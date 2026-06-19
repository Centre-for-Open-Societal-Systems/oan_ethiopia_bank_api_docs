# Consent Management API — Registry A2C

Documentation for the **Consent Management** Postman collection used in the A2C (Access to Credit) loan flow against the ATI Farmer registry (OpenG2P/Odoo).

| Item | Value |
|------|-------|
| Registry base URL | [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et) |
| Odoo database | `socialregistrydb` |
| Postman collection | `Consent Management - Registry A2C Prod.postman_collection` |
| OTP webhook folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) |
| Farmer data webhook folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

---

## Purpose

These APIs let an A2C partner:

1. Authenticate to the registry
2. Search for a farmer by registration ID
3. Request and verify a Fayda OTP
4. Fetch consent reasons and allowed data fields for the partner
5. Submit a consent request (with inline PDF attachment) — the registry auto-creates and auto-approves the request
6. Receive the farmer's shared data via a WebSub webhook payload stored in the public S3 bucket

---

## End-to-end flow

```mermaid
sequenceDiagram
    participant Partner as A2C Partner (Postman)
    participant Registry as farmer-profile.ati.gov.et
    participant Fayda as Fayda OTP service
    participant OTPBucket as S3 otp/ folder
    participant RespBucket as S3 respone/ folder

    Partner->>Registry: 1. POST /web/session/authenticate
    Registry-->>Partner: session cookie

    Partner->>Registry: 2. POST /consent/search_farmer
    Registry-->>Partner: farmer_db_id

    Partner->>Registry: 3. POST /consent/fayda/request_otp
    Registry->>Fayda: request OTP
    Fayda-->>OTPBucket: OTP callback JSON
    Registry-->>Partner: transaction_id

    Partner->>OTPBucket: 4. Read latest otp/*.json
    OTPBucket-->>Partner: otp_code

    Partner->>Registry: 5. POST /consent/fayda/verify_otp
    Registry-->>Partner: OTP verified

    Partner->>Registry: 6. GET /api/consent/reasons
    Registry-->>Partner: consent_reason_id

    Partner->>Registry: 7. GET /api/consent/allowed_data_fields
    Registry-->>Partner: allowed_data_field_ids

    Partner->>Registry: 8. POST /api/consent/submit_consent
    Registry->>RespBucket: WebSub farmer payload (auto-approved)
    Registry-->>Partner: consent_id

    Partner->>RespBucket: 9. Read latest respone/*.json
    RespBucket-->>Partner: farmer + selected_data
```

### Recommended request order (Postman)

| Step | Request | Notes |
|------|---------|-------|
| 1 | `1. login` | Saves session cookie and `partner_id` automatically |
| 2 | `2. search farmer` | Sets `farmer_db_id` from search results |
| 3 | `3. request otp` | Sets `transaction_id` collection variable |
| 4 | `A. list OTP webhooks (S3)` | Lists files under `otp/` |
| 5 | `B. fetch latest OTP webhook` | Sets `otp_code` from webhook JSON |
| 6 | `4. verify otp` | Uses `transaction_id` + `otp_code` |
| 7 | `5. Fetch Consent Reasons` | Sets `consent_reason_id` |
| 8 | `6. Fetch Allowed Data Fields` | Sets `allowed_data_field_ids` |
| 9 | `7. Submit Consent` | Inline attachment; auto-creates and auto-approves |
| 10 | `C. list farmer webhooks (S3)` | Finds newest file under `respone/` |
| 11 | `D. fetch latest farmer webhook` | Returns farmer details payload |

---

## Authentication

All registry endpoints except login require an authenticated Odoo session cookie.

### Login

**POST** `/web/session/authenticate`

```json
{
  "jsonrpc": "2.0",
  "params": {
    "db": "socialregistrydb",
    "login": "test@user.com",
    "password": "pass"
  }
}
```

**Success response (abbreviated):**

```json
{
  "jsonrpc": "2.0",
  "id": null,
  "result": {
    "uid": 6,
    "username": "test@user.com",
    "name": "test@user.com",
    "partner_id": 16,
    "db": "socialregistrydb"
  }
}
```

Postman stores the session cookie when **Send cookies** is enabled (default). Run login before any other registry request.

---

## Registry API endpoints

Registry calls use JSON-RPC 2.0 with Odoo `type="json"` routes (parameters in `params`).

Successful business responses are wrapped as:

```json
{
  "jsonrpc": "2.0",
  "id": null,
  "result": {
    "success": true,
    "message": "OK",
    "data": { }
  }
}
```

Errors:

```json
{
  "result": {
    "success": false,
    "code": 400,
    "message": "Human-readable error"
  }
}
```

### Search farmer

**POST** `/consent/search_farmer`

Look up a farmer by registration ID before starting the consent flow.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `farmer_id` | Yes | Farmer registration ID (e.g. Fayda UID `1234567`) |

**Example:**

```json
{
  "jsonrpc": "2.0",
  "params": {
    "farmer_id": "1234567"
  }
}
```

**Success `data`:**

```json
{
  "farmers": [
    {
      "id": 30,
      "name": "ABEBE BEKELE TESFAYE BEKELE TEFAYA",
      "farmer_id": "",
      "phone": "",
      "reg_ids": ["1234567"],
      "profile_image_url": "",
      "otp_identifier": "1234567",
      "otp_identifier_type": "FIN",
      "otp_identifier_source": "UID",
      "otp_available": true
    }
  ]
}
```

Use the returned `id` as `farmer_db_id` in subsequent requests.

### Request OTP

**POST** `/consent/fayda/request_otp`

```json
{
  "jsonrpc": "2.0",
  "params": {
    "farmer_id": 30
  }
}
```

**Success `data`:**

```json
{
  "transaction_id": "4886E1A5AD5042FDB49DFFC2EE502E5F",
  "masked_mobile": "09xxxxxx55",
  "masked_email": "",
  "identifier_type": "FIN",
  "identifier_source": "UID"
}
```

The OTP itself is **not** returned in this response. It is written to the `otp/` folder in the webhook bucket configured for the Fayda integration.

### Verify OTP

**POST** `/consent/fayda/verify_otp`

```json
{
  "jsonrpc": "2.0",
  "params": {
    "transaction_id": "4886E1A5AD5042FDB49DFFC2EE502E5F",
    "otp": "965332",
    "farmer_id": 30
  }
}
```

> **Note:** The verify endpoint expects the OTP in the `otp` field (not `otp_code`). The Postman collection variable is still named `otp_code`.

OTP codes expire quickly. Always use the value from the latest `otp/` webhook file that matches the `transaction_id` returned by request OTP.

### Fetch consent reasons

**GET** `/api/consent/reasons`

Retrieves active consent reasons for the authenticated partner.

```json
{
  "jsonrpc": "2.0",
  "params": {}
}
```

**Success `data` (array or object with `reasons`):**

```json
[
  {
    "id": 1,
    "name": "A2C loan application",
    "active": true
  }
]
```

Use the returned `id` as `consent_reason_id` in submit consent.

### Fetch allowed data fields

**GET** `/api/consent/allowed_data_fields`

Retrieves data fields the partner is permitted to request.

```json
{
  "jsonrpc": "2.0",
  "params": {}
}
```

**Success `data` (array or object with `allowed_data_fields`):**

```json
[
  {
    "id": 1,
    "code": "farmer_basic",
    "name": "Farmer basic information"
  }
]
```

Use the returned IDs in `allowed_data_field_ids` when submitting consent.

### Submit consent

**POST** `/api/consent/submit_consent`

Submits a consent request with an inline PDF attachment. The registry **automatically creates and auto-approves** the consent request — there is no separate create/approve step.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `farmer_id` | Yes | Registry `res.partner` ID of the farmer |
| `consent_type` | Yes | e.g. `specific` |
| `consent_reason_id` | Yes | ID from fetch consent reasons |
| `validity_months` | Yes | Consent validity period in months (e.g. `12`) |
| `allowed_data_field_ids` | Yes | Array of data-field IDs from fetch allowed data fields |
| `attachment_base64` | Yes | Base64-encoded PDF content |
| `attachment_filename` | Yes | Original filename (e.g. `consent_form.pdf`) |
| `fayda_otp_transaction_id` | Yes | `transaction_id` from the verified OTP step |

**Example:**

```json
{
  "jsonrpc": "2.0",
  "params": {
    "farmer_id": 30,
    "consent_type": "specific",
    "consent_reason_id": 1,
    "validity_months": 12,
    "allowed_data_field_ids": [1],
    "attachment_base64": "<base64-encoded-pdf>",
    "attachment_filename": "consent_form_test.pdf",
    "fayda_otp_transaction_id": "4886E1A5AD5042FDB49DFFC2EE502E5F"
  }
}
```

**Success `data`:**

```json
{
  "consent_id": 96,
  "status": "approved"
}
```

On success the registry enqueues a WebSub publish job. The farmer payload appears in the response webhook folder shortly after.

---

## Webhook bucket

The integration uses a public S3 website bucket as a webhook sink.

| Location | URL | Purpose |
|----------|-----|---------|
| OTP folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) | Fayda OTP callback JSON files |
| Response folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) | Farmer data after consent approval |

### Retrieving OTP

**Option A — Browser**

Open the [OTP folder](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/), open the newest JSON file, and copy the OTP value into the Postman `otp_code` variable.

**Option B — S3 list API (used by Postman helpers)**

```bash
curl -s "https://a2c-webhook.s3.ap-south-1.amazonaws.com/?list-type=2&prefix=otp/&max-keys=50"
```

Fetch the newest OTP payload:

```bash
curl -s "http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/2026-06-01T17-47-13_5ac7f1fa.json"
```

**Sample OTP webhook:**

```json
{
  "transactionID": "C67AC60C2FF541BBB0150F0E425C4783",
  "otp": "965332",
  "individualId": "12345",
  "individualIdType": "FIN",
  "timestamp": "2026-06-01T17:47:13.643488"
}
```

Common fields the collection test script checks:

- `otp` / `otp_code`
- `transaction_id` / `transactionID`

### Retrieving farmer data after approval

List files under `respone/`:

```bash
curl -s "https://a2c-webhook.s3.ap-south-1.amazonaws.com/?list-type=2&prefix=respone/&max-keys=50"
```

Fetch the newest payload (ignore `webhook-respone.json` and `index.html`):

```bash
curl -s "http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/2026-06-06T10-40-35_a4014132.json"
```

---

## Sample farmer webhook payload

After submit consent (auto-approval), a file similar to this appears under `respone/`:

```json
{
  "source": "g2p_ati_consent_mgt",
  "event_type": "WEBSUB_INDIVIDUAL_UPDATED",
  "published_at": "2026-06-06 10:40:35",
  "consent": {
    "id": 95,
    "consent_creation_request_id": "57782a91-bbd7-4764-98c7-b1b136401aec",
    "consent_type": "specific",
    "status": "approved",
    "approved_at": "2026-06-06 10:40:35",
    "validity_from": "2026-05-06 00:00:00",
    "validity_to": "2027-05-06 00:00:00",
    "requested_field_codes": ["farmer_basic"],
    "published_field_codes": ["farmer_basic"],
    "data_field_mode": "dynamic"
  },
  "consent_partner": {
    "id": 16,
    "name": "test@user.com",
    "ref": false,
    "websub_config_id": 2,
    "websub_config_name": "Local Test WebSub (Mock)1"
  },
  "farmer": {
    "id": 30,
    "farmer_id": false,
    "name": "ABEBE BEKELE TESFAYE BEKELE TEFAYA"
  },
  "selected_data": {
    "farmer": {
      "First Name(English)": false,
      "Father Name": false,
      "Email": false,
      "Region": {
        "id": 1,
        "name": "Addis Ababa",
        "code": "ET14"
      },
      "Zone": {
        "id": 1,
        "name": "Gulele Subcity",
        "code": "ET1401"
      },
      "Woreda": {
        "id": 1,
        "name": "Wereda 01",
        "code": "140101"
      }
    }
  }
}
```

| Field | Meaning |
|-------|---------|
| `consent` | Approved consent metadata |
| `consent_partner` | Partner that requested data |
| `farmer` | Farmer registry record |
| `selected_data` | Published field values per WebSub configuration |

---

## Collection variables

| Variable | Default | Description |
|----------|---------|-------------|
| `base_url` | `https://farmer-profile.ati.gov.et` | Registry base URL |
| `db` | `socialregistrydb` | Odoo database |
| `login` / `password` | `test@user.com` / `pass` | Test partner credentials |
| `partner_id` | `16` | Consent parent partner (set by login) |
| `farmer_query_id` | `1234567` | Registration ID for `2. search farmer` |
| `farmer_db_id` | `30` | Registry farmer ID (set automatically by search) |
| `consent_type` | `specific` | Consent type for submit |
| `consent_reason_id` | `1` | From fetch consent reasons (auto-set) |
| `validity_months` | `12` | Consent validity in months |
| `allowed_data_field_ids` | `[1]` | From fetch allowed data fields (auto-set) |
| `attachment_base64` | *(sample PDF)* | Inline PDF for submit consent |
| `attachment_filename` | `consent_form_test_megha1.pdf` | Filename for inline attachment |
| `transaction_id` | *(auto)* | From request OTP |
| `otp_code` | *(auto)* | From OTP webhook |
| `consent_id` | *(auto)* | From submit consent |
| `webhook_url` | S3 website root | OTP bucket browser/API |
| `webhook_response_url` | S3 `respone/` path | Farmer payload folder |
| `webhook_s3_api` | `https://a2c-webhook.s3.ap-south-1.amazonaws.com` | S3 list API for webhook helpers |

---

## Terminal test script

A shell script is available at `test_consent_management_apis.sh`:

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

The script runs the full Postman flow: login → search farmer → request OTP → verify OTP → fetch consent reasons → fetch allowed data fields → submit consent → fetch farmer webhook.

Override defaults with environment variables:

```bash
BASE_URL=https://farmer-profile.ati.gov.et \
DB=socialregistrydb \
LOGIN=test@user.com \
PASSWORD=pass \
FARMER_QUERY_ID=1234567 \
./test_consent_management_apis.sh
```

If OTP auto-detection from S3 fails (webhook delivery delay), pass the code manually:

```bash
OTP_CODE=965332 TX_ID=C67AC60C2FF541BBB0150F0E425C4783 ./test_consent_management_apis.sh
```

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `Database not found` | Wrong `db` value — production uses `socialregistrydb` |
| `Access denied` on OTP endpoints | User is not linked to a consent parent partner |
| `No valid allowed_data_field_ids` | Field IDs not configured on the partner |
| OTP verify fails (`OTP session expired`) | Expired OTP, stale webhook file, or `transaction_id` mismatch |
| OTP verify fails with field error | Using `otp_code` instead of `otp` in verify request body |
| No new file in `otp/` | Fayda callback not reaching the bucket; use manual `OTP_CODE` |
| No file in `respone/` | Submit consent failed, WebSub not configured, or job still queued |
| Empty `selected_data` in webhook | WebSub config has no publishable fields for this farmer |
| Farmer search returns no results | Wrong `farmer_query_id` or farmer not registered |

---

## Related resources

- Registry: [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et)
- OTP webhook browser: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/)
- Farmer webhook browser: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/)
