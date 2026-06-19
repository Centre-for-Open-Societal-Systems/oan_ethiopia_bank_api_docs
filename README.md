# OAN Ethiopia Bank API Docs

Documentation and tooling for **Open Agri Net (OAN)** registry bank-access APIs, focused on the **Consent Management** flow used in the A2C (Access to Credit) loan integration with the ATI Farmer registry (OpenG2P/Odoo).

## What's in this repo

| File | Description |
|------|-------------|
| [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c.md) | Full API reference — endpoints, payloads, webhooks, troubleshooting |
| [`Consent Management - Registry A2C Prod.postman_collection`](Consent%20Management%20-%20Registry%20A2C%20Prod.postman_collection) | Postman collection for the end-to-end consent flow |
| [`test_consent_management_apis.sh`](test_consent_management_apis.sh) | Bash script that runs the same flow from the terminal |

## Production environment (ATI Farmer)

| Item | Value |
|------|-------|
| Registry | [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et) |
| Odoo database | `socialregistrydb` |
| Test credentials | `test@user.com` / `pass` |
| OTP webhook folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) |
| Farmer data webhooks | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

## End-to-end flow

An A2C partner uses these APIs to search for a farmer, verify identity via Fayda OTP, submit consent (with inline PDF attachment), and receive shared farmer data through a WebSub webhook.

1. **Login** — authenticate and obtain an Odoo session cookie
2. **Search farmer** — look up farmer by registration ID
3. **Request OTP** — trigger Fayda OTP delivery
4. **Fetch OTP** — read the OTP from the `otp/` webhook folder
5. **Verify OTP** — confirm the farmer's identity
6. **Fetch consent reasons** — retrieve active consent reasons
7. **Fetch allowed data fields** — retrieve fields the partner may request
8. **Submit consent** — submit consent with attachment; registry auto-creates and auto-approves
9. **Fetch farmer data** — read the approved payload from the `respone/` webhook folder

See the [detailed documentation](consent_management_postman_registry_a2c.md) for request/response examples, collection variables, and troubleshooting.

## Quick start — Postman

1. Import [`Consent Management - Registry A2C Prod.postman_collection`](Consent%20Management%20-%20Registry%20A2C%20Prod.postman_collection) into Postman.
2. Review or adjust collection variables (`base_url`, `db`, `login`, `password`, `farmer_query_id`, etc.).
3. Run requests in order: `1. login` → `2. search farmer` → `3. request otp` → webhook helpers → `4. verify otp` → `5. Fetch Consent Reasons` → `6. Fetch Allowed Data Fields` → `7. Submit Consent` → farmer webhook helpers.

The collection includes test scripts that auto-save `farmer_db_id`, `consent_reason_id`, `allowed_data_field_ids`, `transaction_id`, `otp_code`, and `consent_id` between steps.

## Quick start — terminal

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

Override defaults with environment variables:

```bash
BASE_URL=https://farmer-profile.ati.gov.et \
DB=socialregistrydb \
LOGIN=test@user.com \
PASSWORD=pass \
FARMER_QUERY_ID=1234567 \
./test_consent_management_apis.sh
```

If OTP auto-detection from S3 fails, pass the code manually:

```bash
OTP_CODE=965332 TX_ID=C67AC60C2FF541BBB0150F0E425C4783 ./test_consent_management_apis.sh
```

## License

MIT — see [LICENSE](LICENSE).
