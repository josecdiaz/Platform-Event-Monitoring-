#!/usr/bin/env bash
# deploy.sh — Deploy Platform Event Monitoring to a Salesforce org
# Usage:
#   ./scripts/deploy.sh                         # interactive web login
#   SF_USERNAME=user@example.com SF_PASSWORD=xxx SF_SECURITY_TOKEN=yyy ./scripts/deploy.sh
#   SFDX_AUTH_URL=force://... ./scripts/deploy.sh

set -euo pipefail

ORG_ALIAS="platform-event-monitor"
SOURCE_DIR="force-app"

log() { echo "[deploy] $*"; }

# ── Authentication ───────────────────────────────────────────────────────────
if [[ -n "${SFDX_AUTH_URL:-}" ]]; then
  log "Authenticating via SFDX auth URL..."
  echo "$SFDX_AUTH_URL" > /tmp/sfdx_auth_url.txt
  sf org login sfdx-url \
    --sfdx-url-file /tmp/sfdx_auth_url.txt \
    --alias "$ORG_ALIAS" \
    --set-default
  rm /tmp/sfdx_auth_url.txt

elif [[ -n "${SF_USERNAME:-}" && -n "${SF_PASSWORD:-}" ]]; then
  log "Authenticating via username/password (SOAP login)..."

  FULL_PASSWORD="${SF_PASSWORD}${SF_SECURITY_TOKEN:-}"

  RESPONSE=$(python3 - <<PYEOF
import urllib.request, sys, re

body = '''<?xml version="1.0" encoding="utf-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"
                  xmlns:urn="urn:partner.soap.sforce.com">
  <soapenv:Body>
    <urn:login>
      <urn:username>${SF_USERNAME}</urn:username>
      <urn:password>${FULL_PASSWORD}</urn:password>
    </urn:login>
  </soapenv:Body>
</soapenv:Envelope>'''

req = urllib.request.Request(
    'https://login.salesforce.com/services/Soap/u/59.0',
    data=body.encode(),
    headers={'Content-Type': 'text/xml', 'SOAPAction': 'login'}
)
try:
    with urllib.request.urlopen(req) as r:
        print(r.read().decode())
except urllib.error.HTTPError as e:
    sys.stderr.write(e.read().decode())
    sys.exit(1)
PYEOF
)

  ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'<sessionId>(.*?)</sessionId>', data)
print(m.group(1) if m else '')
")
  INSTANCE_URL=$(echo "$RESPONSE" | python3 -c "
import sys, re
data = sys.stdin.read()
m = re.search(r'<serverUrl>(.*?)/services/Soap', data)
print(m.group(1) if m else '')
")

  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "ERROR: Authentication failed. Check your username, password, and security token." >&2
    exit 1
  fi

  log "Got access token. Logging into SF CLI..."
  sf org login access-token \
    --instance-url "$INSTANCE_URL" \
    --alias "$ORG_ALIAS" \
    --set-default <<< "$ACCESS_TOKEN"

else
  log "No credentials provided — opening browser for interactive login..."
  sf org login web \
    --instance-url https://login.salesforce.com \
    --alias "$ORG_ALIAS" \
    --set-default
fi

# ── Verify connection ────────────────────────────────────────────────────────
log "Verifying org connection..."
sf org display --target-org "$ORG_ALIAS"

# ── Deploy ───────────────────────────────────────────────────────────────────
log "Deploying source from '$SOURCE_DIR' to org '$ORG_ALIAS'..."
sf project deploy start \
  --source-dir "$SOURCE_DIR" \
  --target-org "$ORG_ALIAS" \
  --wait 30 \
  --test-level RunLocalTests

log "Deployment complete!"
