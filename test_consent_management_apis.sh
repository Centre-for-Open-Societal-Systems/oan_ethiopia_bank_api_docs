#!/usr/bin/env bash
# Consent Management API test — Registry A2C flow
#
# Defaults to STAGING (S3 webhooks, registry.oanstaging.com).
# Set ENV=production to match the Postman collection (ATI Farmer prod).
#
# Usage:
#   ./test_consent_management_apis.sh
#   ENV=production OTP_CODE=123456 TX_ID=abc ./test_consent_management_apis.sh

set -euo pipefail

ENV="${ENV:-staging}"

if [[ "$ENV" == "production" ]]; then
  BASE_URL="${BASE_URL:-https://farmer-profile.ati.gov.et}"
  DB="${DB:-socialregistrydb}"
  LOGIN="${LOGIN:-test@user.com}"
  PASSWORD="${PASSWORD:-pass}"
else
  BASE_URL="${BASE_URL:-https://registry.oanstaging.com}"
  DB="${DB:-odoo}"
  LOGIN="${LOGIN:-a2capp@test.com}"
  PASSWORD="${PASSWORD:-a2capp@test.com}"
fi

BASE_URL="${BASE_URL%/}"
WEBHOOK_URL="${WEBHOOK_URL:-http://a2c-webhook.s3-website.ap-south-1.amazonaws.com}"
WEBHOOK_S3_API="${WEBHOOK_S3_API:-https://a2c-webhook.s3.ap-south-1.amazonaws.com}"
WEBHOOK_RESPONSE_URL="${WEBHOOK_RESPONSE_URL:-${WEBHOOK_URL}/respone}"

PARTNER_ID="${PARTNER_ID:-16}"
LAND_ID="${LAND_ID:-${FARMER_QUERY_ID:-${FARMER_QUERY:-1234567}}}"
CONSENT_TYPE="${CONSENT_TYPE:-specific}"
VALIDITY_MONTHS="${VALIDITY_MONTHS:-12}"
ALLOWED_DATA_FIELD_IDS="${ALLOWED_DATA_FIELD_IDS:-[1]}"
CONSENT_REASON_ID="${CONSENT_REASON_ID:-}"
OTP_POLL_SECONDS="${OTP_POLL_SECONDS:-30}"

ATTACHMENT_BASE64="${ATTACHMENT_BASE64:-JVBERi0xLjQKJdPr6eEKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKL01lZGlhQm94IFswIDAgMzAwIDE0NF0KPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovUmVzb3VyY2VzIDw8Ci9Gb250IDw8Ci9GMSA0IDAgUgo+Pgo+PgovQ29udGVudHMgNSAwIFIKPj4KZW5kb2JqCjQgMCBvYmoKPDwKL1R5cGUgL0ZvbnQKL1N1YnR5cGUgL1R5cGUxCi9CYXNlRm9udCAvSGVsdmV0aWNhCj4+CmVuZG9iago1IDAgb2JqCjw8Ci9MZW5ndGggNDQKPj4Kc3RyZWFtCkJUCjcwIDUwIFRECi9GMSAxMiBUZgooSGVsbG8gV29ybGQhKSBUagpFVAplbmRzdHJlYW0KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDIxNSAwMDAwMCBuIAowMDAwMDAwMjgyIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKMzc2CiUlRU9GCg==}"
ATTACHMENT_FILENAME="${ATTACHMENT_FILENAME:-consent_form_test.pdf}"

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

call_registry_get() {
  local name="$1"
  local path="$2"
  local body="${3:-{\"jsonrpc\": \"2.0\", \"params\": {}}}"
  echo ""
  echo "========== $name =========="
  echo "GET ${BASE_URL}${path}"
  local resp
  resp=$(curl -sSL -w "\n__HTTP_CODE__:%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X GET "${BASE_URL}${path}" \
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

echo "Environment : $ENV"
echo "Registry    : $BASE_URL"
echo "Database    : $DB"

# --- Login ---
if [[ "$ENV" == "production" ]]; then
  LOGIN_BODY="{
    \"jsonrpc\": \"2.0\",
    \"params\": {
      \"db\": \"${DB}\",
      \"login\": \"${LOGIN}\",
      \"password\": \"${PASSWORD}\"
    }
  }"
else
  LOGIN_BODY="{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"db\": \"${DB}\",
      \"login\": \"${LOGIN}\",
      \"password\": \"${PASSWORD}\"
    }
  }"
fi

call_registry "1. login" "/web/session/authenticate" "$LOGIN_BODY"
if echo "$LAST_JSON" | grep -q '"error"'; then
  echo "Login failed." >&2
  exit 1
fi

# --- Search farmer ---
if [[ "$ENV" == "production" ]]; then
  SEARCH_BODY="{
    \"jsonrpc\": \"2.0\",
    \"params\": {
      \"query\": \"${LAND_ID}\"
    }
  }"
else
  SEARCH_BODY="{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"query\": \"${LAND_ID}\"
    },
    \"id\": 1
  }"
fi

call_registry "2. search farmer" "/consent/search_farmer" "$SEARCH_BODY"
FARMER_DB_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
farmers = (d.get('result') or {}).get('data', {}).get('farmers') or []
print(farmers[0]['id'] if farmers else '')
" 2>/dev/null || true)
if [[ -z "$FARMER_DB_ID" ]]; then
  echo "Farmer search failed for query (land_id)=${LAND_ID}." >&2
  exit 1
fi
echo "Using farmer_db_id=$FARMER_DB_ID"

# --- Request OTP ---
if [[ "$ENV" == "production" ]]; then
  OTP_REQUEST_BODY="{
    \"jsonrpc\": \"2.0\",
    \"params\": {
      \"farmer_id\": ${FARMER_DB_ID}
    }
  }"
else
  OTP_REQUEST_BODY="{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"farmer_id\": ${FARMER_DB_ID}
    }
  }"
fi

call_registry "3. request otp" "/consent/fayda/request_otp" "$OTP_REQUEST_BODY"
TX_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print((d.get('result') or {}).get('data', {}).get('transaction_id', ''))
" 2>/dev/null || true)

# --- Obtain OTP ---
if [[ -z "${OTP_CODE:-}" ]]; then
  if [[ "$ENV" == "production" ]]; then
    echo ""
    echo "Production: OTP is sent to the farmer's mobile. Set OTP_CODE (and TX_ID if needed)." >&2
  else
    echo ""
    echo "========== fetch OTP from S3 webhook bucket =========="
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
fi

OTP_CODE="${OTP_CODE:-}"
TX_ID="${TX_ID:-}"
if [[ -z "$OTP_CODE" || -z "$TX_ID" ]]; then
  echo "Could not resolve OTP. Set OTP_CODE and TX_ID and re-run." >&2
  exit 1
fi
echo "Using transaction_id=$TX_ID otp=$OTP_CODE"

# --- Verify OTP ---
if [[ "$ENV" == "production" ]]; then
  VERIFY_BODY="{
    \"jsonrpc\": \"2.0\",
    \"params\": {
      \"transaction_id\": \"${TX_ID}\",
      \"otp\": \"${OTP_CODE}\",
      \"farmer_id\": ${FARMER_DB_ID}
    }
  }"
else
  VERIFY_BODY="{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"farmer_id\": ${FARMER_DB_ID},
      \"transaction_id\": \"${TX_ID}\",
      \"otp_code\": \"${OTP_CODE}\"
    }
  }"
fi

call_registry "4. verify otp" "/consent/fayda/verify_otp" "$VERIFY_BODY"
if echo "$LAST_JSON" | grep -q '"success": false'; then
  echo "OTP verify failed." >&2
  [[ "$ENV" == "production" ]] && exit 1
  echo "Continuing on staging..." >&2
fi

# --- Fetch consent reasons ---
if [[ "$ENV" == "production" ]]; then
  call_registry_get "5. fetch consent reasons" "/api/consent/reasons"
else
  call_registry "5. fetch consent reasons" "/api/consent/reasons" "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {}
  }"
fi

if [[ -z "$CONSENT_REASON_ID" ]]; then
  CONSENT_REASON_ID=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
data = (d.get('result') or {}).get('data') or []
if isinstance(data, list) and data:
    print(data[0].get('id', ''))
elif isinstance(data, dict):
    reasons = data.get('reasons') or []
    if reasons:
        print(reasons[0].get('id', ''))
" 2>/dev/null || true)
fi
CONSENT_REASON_ID="${CONSENT_REASON_ID:-1}"
echo "Using consent_reason_id=$CONSENT_REASON_ID"

# --- Fetch allowed data fields ---
if [[ "$ENV" == "production" ]]; then
  call_registry_get "6. fetch allowed data fields" "/api/consent/allowed_data_fields"
else
  call_registry "6. fetch allowed data fields" "/api/consent/allowed_data_fields" "{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"partner_id\": ${PARTNER_ID}
    }
  }"
fi

ALLOWED_FROM_API=$(echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
data = (d.get('result') or {}).get('data') or []
ids = []
if isinstance(data, list) and data:
    ids = [data[0].get('id')]
elif isinstance(data, dict):
    fields = data.get('allowed_data_fields') or []
    if fields:
        ids = [fields[0].get('id')]
if ids and ids[0]:
    print(json.dumps(ids))
" 2>/dev/null || true)
if [[ -n "$ALLOWED_FROM_API" ]]; then
  ALLOWED_DATA_FIELD_IDS="$ALLOWED_FROM_API"
fi
echo "Using allowed_data_field_ids=$ALLOWED_DATA_FIELD_IDS"

# --- Submit consent ---
if [[ "$ENV" == "production" ]]; then
  SUBMIT_BODY="{
    \"jsonrpc\": \"2.0\",
    \"params\": {
      \"farmer_id\": ${FARMER_DB_ID},
      \"consent_type\": \"${CONSENT_TYPE}\",
      \"consent_reason_id\": ${CONSENT_REASON_ID},
      \"validity_months\": ${VALIDITY_MONTHS},
      \"allowed_data_field_ids\": ${ALLOWED_DATA_FIELD_IDS},
      \"attachment_base64\": \"${ATTACHMENT_BASE64}\",
      \"attachment_filename\": \"${ATTACHMENT_FILENAME}\",
      \"fayda_otp_transaction_id\": \"${TX_ID}\"
    }
  }"
else
  SUBMIT_BODY="{
    \"jsonrpc\": \"2.0\",
    \"method\": \"call\",
    \"params\": {
      \"farmer_id\": ${FARMER_DB_ID},
      \"consent_type\": \"${CONSENT_TYPE}\",
      \"consent_reason_id\": ${CONSENT_REASON_ID},
      \"validity_months\": ${VALIDITY_MONTHS},
      \"allowed_data_field_ids\": ${ALLOWED_DATA_FIELD_IDS},
      \"attachment_base64\": \"${ATTACHMENT_BASE64}\",
      \"attachment_filename\": \"${ATTACHMENT_FILENAME}\",
      \"fayda_otp_transaction_id\": \"${TX_ID}\"
    }
  }"
fi

call_registry "7. submit consent" "/api/consent/submit_consent" "$SUBMIT_BODY"
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

if [[ "$ENV" == "production" ]]; then
  echo ""
  echo "========== farmer data (production response_data) =========="
  echo "$LAST_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
response_data = ((d.get('result') or {}).get('data') or {}).get('response_data')
if response_data:
    print(json.dumps(response_data, indent=2))
else:
    print('No response_data in submit consent response.', file=sys.stderr)
    sys.exit(1)
" | pretty_json
fi

# --- Farmer data (staging only) ---
if [[ "$ENV" == "staging" ]]; then
  echo ""
  echo "========== 8. fetch latest farmer webhook (staging) =========="
  sleep 4
  RESP_KEY=$(fetch_latest_s3_key "respone/")
  if [[ -n "$RESP_KEY" ]]; then
    echo "Latest farmer webhook: $RESP_KEY"
    curl -sS "${WEBHOOK_URL}/${RESP_KEY}" | pretty_json
  else
    echo "No farmer webhook found yet under respone/. Check ${WEBHOOK_RESPONSE_URL}/"
  fi
fi

echo ""
echo "Done."
