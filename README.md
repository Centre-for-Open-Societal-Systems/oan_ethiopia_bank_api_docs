# OAN Ethiopia Bank API Docs

Documentation and tooling for **Open Agri Net (OAN)** registry bank-access APIs, focused on the **Consent Management** flow used in the A2C (Access to Credit) loan integration with the OpenG2P/Odoo registry.

## What's in this repo

| File | Description |
|------|-------------|
| [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c_workflow.md) | Full API reference — endpoints, payloads, webhooks |
| [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) | Postman collection for the end-to-end consent flow |
| [`test_consent_management_apis.sh`](test_consent_management_apis.sh) | Bash script that runs the same flow from the terminal |

## Staging environment

| Item                 | Value                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Registry             | [https://registry.oanstaging.com](https://registry.oanstaging.com)                                                                 |
| Odoo database        | `odoo`                                                                                                                             |
| Test credentials     | `a2c@test.com` / `a2c@test.com`                                                                                                    |
| OTP webhook folder   | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/)         |
| Farmer data webhooks | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

## End-to-end flow

An A2C partner uses these APIs to search for a farmer, verify identity via Fayda OTP, attach supporting documents, approve consent, and receive shared farmer data through a WebSub webhook.

1. **Login** — authenticate and obtain an Odoo session cookie
2. **Search farmer** — look up farmer by registration ID
3. **Request OTP** — trigger Fayda OTP delivery
4. **Fetch OTP** — read the OTP from the `otp/` webhook folder
5. **Verify OTP** — confirm the farmer's identity
6. **Upload attachment** — upload a PDF for the consent record
7. **Create consent** — create a pending consent request
8. **Approve consent** — approve the request; registry publishes farmer data
9. **Fetch farmer data** — read the approved payload from the `respone/` webhook folder

See the [detailed documentation](consent_management_postman_registry_a2c_workflow.md) for request/response examples, collection variables, and troubleshooting and for a detailed workflow  look at [[workflow]]

## Quick start — Postman

1. Import [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) into Postman.
2. Review or adjust collection variables (`base_url`, `db`, `login`, `password`, `partner_id`, `farmer_query`, etc.).
3. Run requests in order: `1. login` → `2. search farmer` → `3. request otp` → webhook helpers → `4. verify otp` → `upload attachment` → `5. create consent` → `6. approve` → farmer webhook helpers.

The collection includes test scripts that auto-save `farmer_db_id`, `consent_id`, `transaction_id`, `otp_code`, and `attachment_id` between steps.

## Quick start — terminal

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

Override defaults with environment variables:

```bash
BASE_URL=https://registry.oanstaging.com \
DB=odoo \
LOGIN=a2capp@test.com \
PASSWORD=a2capp@test.com \
PARTNER_ID=16 \
FARMER_QUERY=1234567 \
./test_consent_management_apis.sh
```

If OTP auto-detection from S3 fails, pass the code manually:

```bash
OTP_CODE=965332 TX_ID=C67AC60C2FF541BBB0150F0E425C4783 ./test_consent_management_apis.sh
```

## License

MIT — see [LICENSE](LICENSE).
