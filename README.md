# OAN Ethiopia Bank API Docs

Documentation and tooling for **Open Agri Net (OAN)** registry bank-access APIs, focused on the **Consent Management** flow used in the A2C (Access to Credit) loan integration with the OpenG2P/Odoo registry.

## What's in this repo

| File | Description |
|------|-------------|
| [`consent_management_postman_registry_a2c.md`](consent_management_postman_registry_a2c.md) | Full API reference — endpoints, payloads, webhooks, troubleshooting |
| [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) | Postman collection for the end-to-end consent flow |
| [`test_consent_management_apis.sh`](test_consent_management_apis.sh) | Bash script that runs the same flow from the terminal |

## Staging environment

| Item                 | Value                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Registry             | [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et)                                                                 |
| Odoo database        | Please contact the administrator                                                                                                                             |
| Test credentials     | Please contact the administartor                                                                                                    |
| OTP webhook folder   | Given the api is hitting production and connected to fayda, the OTP will be recieved on the mobile         |
| Farmer data webhooks | The resposne will come to kafka and need to subscribed to be delivered to the required application |

## End-to-end flow

An A2C partner uses these APIs to search for a farmer, verify identity via Fayda OTP, attach supporting documents, approve consent, and receive shared farmer data through a WebSub webhook.

1. **Login** — authenticate and obtain an Odoo session cookie
2. **Search farmer** — look up farmer by registration ID
3. **Request OTP** — trigger Fayda OTP delivery
4. **Verify OTP** — Verify the OTO recieved from the Farmer
5. **Fetch Consent Reasons** — Fetch the consent reasons from registry to be displayed in the UI, for initiating the consent request
6. **Fetch Allowed Data Fields** — Fetch the allowed whitelisted fields provisioned for the patrner profile, only the whitlisted fields can be retrived from regsitry as part of consent
7. **Submit Consent** — Submit the request to create the consent artefact, given tgis OTP drive, it will be auto approved and the requseted data will be shared to kafka, the initiatiating application needs to be susbcribe to kafka to retrieve the data.

See the [detailed documentation](consent_management_postman_registry_a2c.md) for request/response examples, collection variables, and troubleshooting and for a detailed workflow  look at [[workflow]]

## Quick start — Postman

1. Import [`Consent Management.postman_collection.json`](Consent%20Management.postman_collection.json) into Postman.
2. Review or adjust collection variables (`base_url`, `db`, `login`, `password`, `partner_id`, `farmer_query`, etc.).
3. Run requests in order: `1. login` → `2. search farmer` → `3. request otp` → webhook helpers → `4. verify otp` → `upload attachment` → `5. create consent` → `6. approve` → farmer webhook helpers.

The collection includes test scripts that auto-save `farmer_db_id`, `consent_id`, `transaction_id`, `otp_code`, and `attachment_id` between steps.

## Quick start — terminal

If you are testing this against our staging env [https://registry.oanstaging.com](https://registry.oanstaging.com) you can use the bewlo code and script files for testing

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
