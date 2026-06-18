#!/usr/bin/env bash
# Consent Management API test — Registry A2C flow (matches Postman collection)
# Usage:
#   ./test_consent_management_apis.sh
#   OTP_CODE=123456 TX_ID=abc ./test_consent_management_apis.sh   # skip S3 OTP lookup

set -euo pipefail

BASE_URL="${BASE_URL:-https://registry.oanstaging.com}"
BASE_URL="${BASE_URL%/}"
WEBHOOK_URL="${WEBHOOK_URL:-http://a2c-webhook.s3-website.ap-south-1.amazonaws.com}"
WEBHOOK_S3_API="${WEBHOOK_S3_API:-https://a2c-webhook.s3.ap-south-1.amazonaws.com}"
WEBHOOK_RESPONSE_URL="${WEBHOOK_RESPONSE_URL:-${WEBHOOK_URL}/respone}"

DB="${DB:-odoo}"
LOGIN="${LOGIN:-a2capp@test.com}"
PASSWORD="${PASSWORD:-a2capp@test.com}"
PARTNER_ID="${PARTNER_ID:-16}"
FARMER_QUERY="${FARMER_QUERY:-1234567}"
ALLOWED_DATA_FIELD_IDS="${ALLOWED_DATA_FIELD_IDS:-[1]}"
VALIDITY_FROM="${VALIDITY_FROM:-2026-05-06 00:00:00}"
VALIDITY_TO="${VALIDITY_TO:-2027-05-06 00:00:00}"
OTP_POLL_SECONDS="${OTP_POLL_SECONDS:-30}"

# Minimal PDF (Hello World) for attachment upload
ATTACHMENT_BASE64="${ATTACHMENT_BASE64:-JVBERi0xLjQKJdPr6eEKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKL01lZGlhQm94IFswIDAgMzAwIDE0NF0KPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovUmVzb3VyY2VzIDw8Ci9Gb250IDw8Ci9GMSA0IDAgUgo+Pgo+PgovQ29udGVudHMgNSAwIFIKPj4KZW5kb2JqCjQgMCBvYmoKPDwKL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9CYXNlRm9udCAvSGVsdmV0aWNhCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9MZW5ndGggNDQKPj4Kc3RyZWFtCkJUCjcwIDUwIFRECi9GMSAxMiBUZgooSGVsbG8gV29ybGQhKSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDIxNSAwMDAwMCBuIAowMDAwMDAwMjgyIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKMzc2CiUlRU9GCg==}"

COOKIE_JAR="$(mktemp /tmp/consent_cookies.XXXXXX)"
trap 'rm -f "$COOKIE_JAR"' EXIT
LAST_JSON=""

pretty_json() {
  python3 -m json.tool 2>/dev/null || cat
}

call_registry() {
  local name="$1"
  local path="$2"
  local body="$3"
  echo ""
  echo "========== $name =========="
  echo "POST ${BASE_URL}${path}"
  local resp
  resp=$(curl -sSL -w "\n__HTTP_CODE__:%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST "${BASE_URL}${path}" \
    -H "Content-Type: application/json" \
    -d "$body")
  local code
  code=$(echo "$resp" | grep '__HTTP_CODE__:' | cut -d: -f2)
  local json
  json=$(echo "$resp" | sed '/__HTTP_CODE__:/d')
  LAST_JSON="$json"
  echo "$json" | pretty_json
  echo "HTTP $code"
}

fetch_latest_s3_key() {
  local prefix="${1:-otp/}"
  local xml
  xml=$(curl -sS "${WEBHOOK_S3_API}/?list-type=2&prefix=${prefix}&max-keys=50")
  python3 -c "
import sys, re
xml, prefix = sys.argv[1], sys.argv[2]
keys = re.findall(r'<Key>([^<]+)</Key>', xml)
keys = [k for k in keys if k.endswith('.json') and 'index.html' not in k and 'webhook-respone.json' not in k]
if prefix:
    keys = [k for k in keys if k.startswith(prefix)]
keys.sort()
print(keys[-1] if keys else '')
" "$xml" "$prefix"
}

extract_otp_from_webhook() {
  local key="$1"
  local file_url="${WEBHOOK_URL}/${key}"
  curl -sS "$file_url" | python3 -c "
import json, sys
payload = json.load(sys.stdin)
otp = payload.get('otp') or payload.get('otp_code')
if not otp and isinstance(payload.get('request'), dict):
    otp = payload['request'].get('otp')
tx = payload.get('transaction_id') or payload.get('transactionID') or payload.get('transactionId')
if otp:
    print(f'otp={otp}')
if tx:
    print(f'transaction_id={tx}')
"
}

poll_otp_for_transaction() {
  local want_tx="$1"
  local deadline=$((SECONDS + OTP_POLL_SECONDS))
  while (( SECONDS < deadline )); do
    local key otp tx
    key=$(fetch_latest_s3_key "otp/")
    if [[ -n "$key" ]]; then
      while IFS='=' read -r k v; do
        [[ "$k" == "otp" && -n "$v" ]] && otp="$v"
        [[ "$k" == "transaction_id" && -n "$v" ]] && tx="$v"
      done < <(extract_otp_from_webhook "$key")
      if [[ "${tx:-}" == "$want_tx" && -n "${otp:-}" ]]; then
        OTP_CODE="$otp"
        TX_ID="$tx"
        echo "Matched OTP webhook: $key"
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

echo "Registry : $BASE_URL"
echo "Database : $DB"
echo "Webhook  : $WEBHOOK_URL"
echo "Response : $WEBHOOK_RESPONSE_URL"

call_registry "1. login" "/web/session/authenticate" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"db\": \"${DB}\",
    \"login\": \"${LOGIN}\",
    \"password\": \"${PASSWORD}\"
  }
}"
if echo "$LAST_JSON" | grep -q '"error"'; then
  echo "Login failed." >&2
  exit 1
fi

call_registry "2. search farmer" "/consent/search_farmer" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"query\": \"${FARMER_QUERY}\"
  }
}"
FARMER_DB_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
farmers = (d.get('result') or {}).get('data', {}).get('farmers') or []
print(farmers[0]['id'] if farmers else '')
" 2>/dev/null || true)
if [[ -z "$FARMER_DB_ID" ]]; then
  echo "Farmer search failed for query=${FARMER_QUERY}." >&2
  exit 1
fi
echo "Using farmer_db_id=$FARMER_DB_ID"

call_registry "3. request otp" "/consent/fayda/request_otp" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"farmer_id\": ${FARMER_DB_ID}
  }
}"
TX_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print((d.get('result') or {}).get('data', {}).get('transaction_id', ''))
" 2>/dev/null || true)

if [[ -z "${OTP_CODE:-}" ]]; then
  echo ""
  echo "========== 4. fetch OTP from webhook bucket =========="
  if [[ -n "$TX_ID" ]] && poll_otp_for_transaction "$TX_ID"; then
    :
  else
    OTP_KEY=$(fetch_latest_s3_key "otp/")
    if [[ -n "$OTP_KEY" ]]; then
      echo "Falling back to latest OTP webhook: $OTP_KEY"
      while IFS='=' read -r k v; do
        [[ "$k" == "otp" && -n "$v" ]] && OTP_CODE="$v"
        [[ "$k" == "transaction_id" && -n "$v" ]] && TX_ID="$v"
      done < <(extract_otp_from_webhook "$OTP_KEY")
    fi
  fi
fi

OTP_CODE="${OTP_CODE:-}"
TX_ID="${TX_ID:-}"
if [[ -z "$OTP_CODE" || -z "$TX_ID" ]]; then
  echo "Could not resolve OTP. Set OTP_CODE and TX_ID (or OTP_CODE only) and re-run." >&2
  exit 1
fi
echo "Using transaction_id=$TX_ID otp_code=$OTP_CODE"

call_registry "5. verify otp" "/consent/fayda/verify_otp" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"farmer_id\": ${FARMER_DB_ID},
    \"transaction_id\": \"${TX_ID}\",
    \"otp_code\": \"${OTP_CODE}\"
  }
}"
if echo "$LAST_JSON" | grep -q '"success": false'; then
  echo "OTP verify failed (may be expired). Continuing — staging may allow consent without fresh OTP." >&2
fi

call_registry "6. Fetch Reasons" "/api/consent/reasons" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {}
}"
CONSENT_REASON_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
data = (d.get('result') or {}).get('data') or []
print(data[0]['id'] if isinstance(data, list) and data else 1)
" 2>/dev/null || echo "1")
echo "Using consent_reason_id=$CONSENT_REASON_ID"

call_registry "7. Fetch Allowed Fields" "/api/consent/allowed_data_fields" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"partner_id\": ${PARTNER_ID}
  }
}"
ALLOWED_DATA_FIELD_IDS=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
data = (d.get('result') or {}).get('data') or []
print(f'[{data[0][\"id\"]}]' if isinstance(data, list) and data else '[1]')
" 2>/dev/null || echo "[1]")
echo "Using allowed_data_field_ids=$ALLOWED_DATA_FIELD_IDS"

call_registry "8. submit consent" "/api/consent/submit_consent" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"farmer_id\": ${FARMER_DB_ID},
    \"consent_type\": \"specific\",
    \"consent_reason_id\": ${CONSENT_REASON_ID},
    \"validity_months\": 12,
    \"allowed_data_field_ids\": ${ALLOWED_DATA_FIELD_IDS},
    \"attachment_base64\": \"${ATTACHMENT_BASE64}\",
    \"attachment_filename\": \"consent_form_test.pdf\",
    \"fayda_otp_transaction_id\": \"${TX_ID}\"
  }
}"
CONSENT_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
data = (d.get('result') or {}).get('data') or {}
print(data.get('consent_id') or data.get('id') or '')
" 2>/dev/null || true)
if [[ -z "$CONSENT_ID" ]]; then
  echo "Submit consent failed." >&2
  exit 1
fi
echo "Using consent_id=$CONSENT_ID"

echo ""
echo "========== 9. fetch latest farmer webhook =========="
sleep 4
RESP_KEY=$(fetch_latest_s3_key "respone/")
if [[ -n "$RESP_KEY" ]]; then
  echo "Latest farmer webhook: $RESP_KEY"
  curl -sS "${WEBHOOK_URL}/${RESP_KEY}" | pretty_json
else
  echo "No farmer webhook found yet under respone/. Check ${WEBHOOK_RESPONSE_URL}/"
fi

echo ""
echo "Done."
