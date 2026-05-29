#!/usr/bin/env bash
# Consent Management API test — Registry A2C flow
# Usage:
#   BASE_URL=http://registry.oanstaging.com ./test_consent_management_apis.sh
#   OTP_CODE=123456 ./test_consent_management_apis.sh   # skip S3 OTP lookup

set -euo pipefail

BASE_URL="${BASE_URL:-http://registry.oanstaging.com}"
BASE_URL="${BASE_URL%/}"
WEBHOOK_URL="${WEBHOOK_URL:-http://a2c-webhook.s3-website.ap-south-1.amazonaws.com}"
WEBHOOK_S3_API="${WEBHOOK_S3_API:-https://a2c-webhook.s3.ap-south-1.amazonaws.com}"
WEBHOOK_RESPONSE_URL="${WEBHOOK_RESPONSE_URL:-${WEBHOOK_URL}/respone}"

DB="${DB:-management}"
LOGIN="${LOGIN:-messi@gmail.com}"
PASSWORD="${PASSWORD:-messi@gmail.com}"
PARTNER_ID="${PARTNER_ID:-7}"
FARMER_DB_ID="${FARMER_DB_ID:-10}"
ALLOWED_DATA_FIELD_IDS="${ALLOWED_DATA_FIELD_IDS:-[3]}"
VALIDITY_FROM="${VALIDITY_FROM:-2026-05-29 00:00:00}"
VALIDITY_TO="${VALIDITY_TO:-2027-05-29 00:00:00}"

COOKIE_JAR="$(mktemp /tmp/consent_cookies.XXXXXX)"
trap 'rm -f "$COOKIE_JAR"' EXIT

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
  resp=$(curl -sS -w "\n__HTTP_CODE__:%{http_code}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST "${BASE_URL}${path}" \
    -H "Content-Type: application/json" \
    -d "$body")
  local code
  code=$(echo "$resp" | grep '__HTTP_CODE__:' | cut -d: -f2)
  local json
  json=$(echo "$resp" | sed '/__HTTP_CODE__:/d')
  echo "$json" | pretty_json
  echo "HTTP $code"
  echo "$json"
}

fetch_latest_s3_key() {
  local prefix="${1:-}"
  local xml
  xml=$(curl -sS "${WEBHOOK_S3_API}/?list-type=2&prefix=${prefix}&max-keys=50")
  python3 - <<'PY' "$xml" "$prefix"
import sys, re
xml, prefix = sys.argv[1], sys.argv[2]
keys = re.findall(r"<Key>([^<]+)</Key>", xml)
keys = [k for k in keys if k.endswith(".json")]
if prefix:
    keys = [k for k in keys if k.startswith(prefix)]
else:
    keys = [k for k in keys if not k.startswith("respone/")]
keys.sort()
print(keys[-1] if keys else "")
PY
}

extract_otp_from_webhook() {
  local key="$1"
  local file_url
  if [[ "$key" == respone/* ]]; then
    file_url="${WEBHOOK_RESPONSE_URL}/${key#respone/}"
  else
    file_url="${WEBHOOK_URL}/${key}"
  fi
  curl -sS "$file_url" | python3 - <<'PY'
import json, sys
payload = json.load(sys.stdin)
otp = payload.get("otp") or payload.get("otp_code")
if not otp and isinstance(payload.get("request"), dict):
    otp = payload["request"].get("otp")
tx = payload.get("transaction_id") or payload.get("transactionID") or payload.get("transactionId")
if otp:
    print(f"otp={otp}")
if tx:
    print(f"transaction_id={tx}")
PY
}

echo "Registry : $BASE_URL"
echo "Webhook  : $WEBHOOK_URL"
echo "Response : $WEBHOOK_RESPONSE_URL"

LOGIN_JSON=$(call_registry "1. login" "/web/session/authenticate" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"db\": \"${DB}\",
    \"login\": \"${LOGIN}\",
    \"password\": \"${PASSWORD}\"
  }
}")
if echo "$LOGIN_JSON" | grep -q '"error"'; then
  echo "Login failed." >&2
  exit 1
fi

CREATE_JSON=$(call_registry "2. create consent" "/api/consent/request/create" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"partner_id\": ${PARTNER_ID},
    \"farmer_db_id\": ${FARMER_DB_ID},
    \"consent_type\": \"specific\",
    \"purpose\": \"A2C data sharing for agricultural services\",
    \"validity_from\": \"${VALIDITY_FROM}\",
    \"validity_to\": \"${VALIDITY_TO}\",
    \"allowed_data_field_ids\": ${ALLOWED_DATA_FIELD_IDS},
    \"originated_from\": \"partner\"
  }
}")
CONSENT_ID=$(echo "$CREATE_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('result') or {}
data=r.get('data') or {}
print(data.get('id',''))
" 2>/dev/null || true)
CONSENT_ID="${CONSENT_ID:-1}"
echo "Using consent_id=$CONSENT_ID"

OTP_JSON=$(call_registry "3. request otp" "/consent/fayda/request_otp" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"farmer_id\": ${FARMER_DB_ID}
  }
}")
TX_ID=$(echo "$OTP_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d.get('result') or {}
data=r.get('data') or {}
print(data.get('transaction_id',''))
" 2>/dev/null || true)

if [[ -z "${OTP_CODE:-}" ]]; then
  echo ""
  echo "========== 4. fetch OTP from webhook bucket =========="
  OTP_KEY=$(fetch_latest_s3_key "")
  if [[ -n "$OTP_KEY" ]]; then
    echo "Latest OTP webhook: $OTP_KEY"
    while IFS='=' read -r k v; do
      [[ "$k" == "otp" && -n "$v" ]] && OTP_CODE="$v"
      [[ "$k" == "transaction_id" && -n "$v" ]] && TX_ID="$v"
    done < <(extract_otp_from_webhook "$OTP_KEY")
  fi
fi

OTP_CODE="${OTP_CODE:-}"
TX_ID="${TX_ID:-}"
if [[ -z "$OTP_CODE" || -z "$TX_ID" ]]; then
  echo "Could not resolve OTP automatically. Set OTP_CODE (and optionally TX_ID) and re-run." >&2
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

call_registry "6. approve" "/api/consent/request/approve" "{
  \"jsonrpc\": \"2.0\",
  \"method\": \"call\",
  \"params\": {
    \"consent_id\": ${CONSENT_ID}
  }
}"

echo ""
echo "========== 7. fetch latest farmer webhook =========="
sleep 3
RESP_KEY=$(fetch_latest_s3_key "respone/")
if [[ -n "$RESP_KEY" ]]; then
  echo "Latest farmer webhook: $RESP_KEY"
  curl -sS "${WEBHOOK_RESPONSE_URL}/${RESP_KEY#respone/}" | pretty_json
else
  echo "No farmer webhook found yet under respone/. Check ${WEBHOOK_RESPONSE_URL}/"
fi

echo ""
echo "Done."
