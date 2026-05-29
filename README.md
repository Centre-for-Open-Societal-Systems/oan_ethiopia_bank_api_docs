# OAN Ethiopia Bank API Docs

Documentation and tooling for **Open Agri Net (OAN)** registry bank-access APIs, focused on the **Consent Management** flow used in the A2C (Access to Credit) loan integration with the OpenG2P/Odoo registry.

## What's in this repo

| File | Description |
|------|-------------|
| [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c.md) | Full API reference — endpoints, payloads, webhooks, troubleshooting |
| [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) | Postman collection for the end-to-end consent flow |
| [`test_consent_management_apis.sh`](test_consent_management_apis.sh) | Bash script that runs the same flow from the terminal |

## Staging environment

| Item | Value |
|------|-------|
| Registry | [http://registry.oanstaging.com](http://registry.oanstaging.com) |
| Odoo database | `management` |
| OTP webhook bucket | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/) |
| Farmer data webhooks | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

## End-to-end flow

An A2C partner uses these APIs to request farmer consent, verify identity via Fayda OTP, approve the consent, and receive shared farmer data through a WebSub webhook.

1. **Login** — authenticate and obtain an Odoo session cookie
2. **Create consent** — create a pending consent request for a farmer
3. **Request OTP** — trigger Fayda OTP delivery
4. **Fetch OTP** — read the OTP from the public webhook bucket
5. **Verify OTP** — confirm the farmer's identity
6. **Approve consent** — approve the request; registry publishes farmer data
7. **Fetch farmer data** — read the approved payload from the `respone/` webhook folder

See the [detailed documentation](consent_management_postman_registry_a2c.md) for request/response examples, collection variables, and troubleshooting.

## Quick start — Postman

1. Import [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) into Postman.
2. Review or adjust collection variables (`url`, `login`, `password`, `partner_id`, `farmer_db_id`, etc.).
3. Run requests in order: `1. login` → `2. create consent` → `3. request otp` → webhook helpers → `4. verify otp` → `5. approve` → farmer webhook helpers.

The collection includes test scripts that auto-save `consent_id`, `transaction_id`, and `otp_code` between steps.

## Quick start — terminal

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

Override defaults with environment variables:

```bash
BASE_URL=http://registry.oanstaging.com \
LOGIN=your@email.com \
PASSWORD=yourpassword \
PARTNER_ID=7 \
FARMER_DB_ID=10 \
./test_consent_management_apis.sh
```

If OTP auto-detection from S3 fails, pass the code manually:

```bash
OTP_CODE=123456 ./test_consent_management_apis.sh
```

## License

MIT — see [LICENSE](LICENSE).
