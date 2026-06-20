# OAN Ethiopia Bank API Docs

Documentation and tooling for **Open Agri Net (OAN)** registry bank-access APIs, focused on the **Consent Management** flow used in the A2C (Access to Credit) loan integration with the ATI Farmer registry (OpenG2P/Odoo).

## What's in this repo

| File | Description |
|------|-------------|
| [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c.md) | API reference — endpoints, payloads, environment config, troubleshooting |
| [`consent_management_postman_registry_a2c_workflow.md`](consent_management_postman_registry_a2c_workflow.md) | Production workflow guide with UI screenshots and per-step variable tables |
| [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) | Postman collection configured for **production** |
| [`test_consent_management_apis.sh`](test_consent_management_apis.sh) | Bash script — defaults to **staging**; supports production via `ENV=production` |

## Environments

The same API flow applies in both environments. Differences are mainly registry URL, credentials, OTP delivery, and how approved farmer data is received.

### Staging (integration testing)

Use staging for end-to-end testing without real Fayda SMS. OTP callbacks and farmer payloads are written to a public S3 webhook bucket.

| Item | Value |
|------|-------|
| Registry | [https://registry.oanstaging.com](https://registry.oanstaging.com) |
| Odoo database | `odoo` |
| Test credentials | `a2capp@test.com` / `a2capp@test.com` |
| OTP delivery | S3 bucket — [otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) |
| Farmer data delivery | S3 bucket — [respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |
| Recommended tooling | `test_consent_management_apis.sh` (default) |

### Production (ATI Farmer)

The Postman collection ships with production defaults. OTP is sent to the farmer's mobile via Fayda; approved farmer data is returned inline in the **Submit Consent** response (`result.data.response_data`).

| Item | Value |
|------|-------|
| Registry | [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et) |
| Odoo database | `socialregistrydb` |
| Credentials | Contact the administrator |
| OTP delivery | Farmer's mobile (Fayda) |
| Farmer data delivery | Inline in `7. Submit Consent` response (`response_data`) |
| Recommended tooling | Postman collection (import as-is) |

> **Note:** Use HTTPS for all API calls. HTTP to `registry.oanstaging.com` returns a 301 redirect.

## End-to-end flow

1. **Login** — authenticate and obtain an Odoo session cookie
2. **Search farmer** — look up farmer by registration ID
3. **Request OTP** — trigger Fayda OTP delivery
4. **Obtain OTP** — read from S3 webhook (staging) or farmer's mobile (production)
5. **Verify OTP** — confirm the farmer's identity
6. **Fetch consent reasons** — retrieve active consent reasons
7. **Fetch allowed data fields** — retrieve fields the partner may request
8. **Submit consent** — submit with inline PDF; registry auto-creates, auto-approves, and returns farmer data in `response_data` (production)
9. **Receive farmer data** — read from S3 `respone/` (staging only; production data is in step 8 response)

See [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c.md) for endpoint details and [`consent_management_postman_registry_a2c_workflow.md`](consent_management_postman_registry_a2c_workflow.md) for the production UI workflow.

## Quick start — Postman (production)

The collection is pre-configured for production (`farmer-profile.ati.gov.et`).

1. Import [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json).
2. Set credentials (`login`, `password`) provided by the administrator.
3. Run in order: `1. login` → `2. search farmer` → `3. request otp` → `4. verify otp` → `5. Fetch Consent Reasons` → `6. Fetch Allowed Data Fields` → `7. Submit Consent`.

For **staging** in Postman, override collection variables:

| Variable | Staging value |
|----------|---------------|
| `base_url` | `https://registry.oanstaging.com` |
| `db` | `odoo` |
| `login` / `password` | `a2capp@test.com` |
| `farmer_query_id` | Your test farmer ID |

Then use the **Webhook Helpers** folder to fetch OTP from S3 before verify.

## Quick start — terminal (staging)

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

Defaults target staging. Override if needed:

```bash
BASE_URL=https://registry.oanstaging.com \
DB=odoo \
LOGIN=a2capp@test.com \
PASSWORD=a2capp@test.com \
FARMER_QUERY_ID=1234567 \
./test_consent_management_apis.sh
```

### Terminal (production)

```bash
ENV=production \
LOGIN=your@user.com \
PASSWORD=yourpass \
FARMER_QUERY_ID=1234567 \
OTP_CODE=123456 \
TX_ID=your-transaction-id \
./test_consent_management_apis.sh
```

Production requires a real OTP from the farmer's mobile — S3 OTP polling is skipped.

## License

MIT — see [LICENSE](LICENSE).
