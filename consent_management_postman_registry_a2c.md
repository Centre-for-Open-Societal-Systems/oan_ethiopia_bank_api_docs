# Consent Management API — Registry A2C

Documentation for the **Consent Management** Postman collection used in the A2C (Access to Credit) loan flow against the OpenG2P/Odoo registry.

| Item | Value |
|------|-------|
| Registry base URL | [https://registry.oanstaging.com](https://registry.oanstaging.com) |
| Odoo database | `odoo` |
| Postman collection | `Consent Management.postman_collection.json` |
| OTP webhook folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) |
| Farmer data webhook folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

> **Note:** HTTP requests to `http://registry.oanstaging.com` are redirected (301). Use **HTTPS** for all API calls.

---

## Purpose

These APIs let an A2C partner:

1. Authenticate to the registry
2. Search for a farmer by registration ID
3. Request and verify a Fayda OTP
4. Upload a consent attachment (PDF)
5. Create and approve a consent request
6. Receive the farmer’s shared data via a WebSub webhook payload stored in the public S3 bucket

---

## End-to-end flow

```mermaid
sequenceDiagram
    participant Partner as A2C Partner (Postman)
    participant Registry as registry.oanstaging.com
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

    Partner->>Registry: 6. POST /api/consent/attachment/upload
    Registry-->>Partner: attachment_id

    Partner->>Registry: 7. POST /api/consent/request/create
    Registry-->>Partner: consent_id (pending)

    Partner->>Registry: 8. POST /api/consent/request/approve
    Registry->>RespBucket: WebSub farmer payload
    Registry-->>Partner: status approved

    Partner->>RespBucket: 9. Read latest respone/*.json
    RespBucket-->>Partner: farmer + selected_data
```

### Recommended request order (Postman)

| Step | Request | Notes |
|------|---------|-------|
| 1 | `1. login` | Saves session cookie automatically |
| 2 | `2. search farmer` | Sets `farmer_db_id` from search results |
| 3 | `3. request otp` | Sets `transaction_id` collection variable |
| 4 | `A. list OTP webhooks (S3)` | Lists files under `otp/` |
| 5 | `B. fetch latest OTP webhook` | Sets `otp_code` from webhook JSON |
| 6 | `4. verify otp` | Uses `transaction_id` + `otp_code` |
| 7 | `upload attachment` | Sets `attachment_id` for create consent |
| 8 | `5. create consent` | Sets `consent_id` collection variable |
| 9 | `6. approve` | Publishes farmer data webhook |
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
  "method": "call",
  "params": {
    "db": "odoo",
    "login": "a2capp@test.com",
    "password": "a2capp@test.com"
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
    "username": "a2capp@test.com",
    "name": "a2capp@test.com",
    "db": "odoo"
  }
}
```

Postman stores the session cookie when **Send cookies** is enabled (default). Run login before any other registry request.

---

## Registry API endpoints

All registry calls use:

- **Method:** `POST`
- **Header:** `Content-Type: application/json`
- **Body format:** JSON-RPC 2.0 with Odoo `type="json"` routes (`method: "call"`, parameters in `params`)

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

Look up a farmer by registration ID, national ID, or other configured identifier before starting the consent flow.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | Yes | Search string (e.g. Fayda UID `1234567`) |

**Example:**

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "query": "1234567"
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
  "method": "call",
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

The OTP itself is **not** returned in this response. It is written to the `otp/` folder in the webhook bucket configured for the Fayda/staging integration.

### Verify OTP

**POST** `/consent/fayda/verify_otp`

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "farmer_id": 30,
    "transaction_id": "4886E1A5AD5042FDB49DFFC2EE502E5F",
    "otp_code": "965332"
  }
}
```

OTP codes expire quickly. Always use the value from the latest `otp/` webhook file that matches the `transaction_id` returned by request OTP.

### Upload attachment

**POST** `/api/consent/attachment/upload`

Upload a PDF (or other supported document) as base64 before creating the consent request.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `attachment_base64` | Yes | Base64-encoded file content |
| `attachment_filename` | Yes | Original filename (e.g. `test.pdf`) |

**Example:**

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "attachment_base64": "<base64-encoded-pdf>",
    "attachment_filename": "test.pdf"
  }
}
```

**Success `data`:**

```json
{
  "attachment_id": 566,
  "attachment_name": "test.pdf"
}
```

### Create consent

**POST** `/api/consent/request/create`

| Parameter | Required | Description |
|-----------|----------|-------------|
| `partner_id` | Yes | Consent parent partner record ID (e.g. `16` for user `a2capp@test.com`) |
| `farmer_db_id` | Yes* | Registry `res.partner` ID of the approved farmer |
| `consent_type` | No | Default `specific` |
| `purpose` | No | Free-text purpose |
| `validity_from` / `validity_to` | No | Datetime strings `YYYY-MM-DD HH:MM:SS` |
| `allowed_data_field_ids` | Yes | Array of data-field IDs allowed for this partner |
| `originated_from` | No | e.g. `partner` |
| `attachment_ids` | No | Attachment ID from upload step |

\*Alternatively: `farmer_id` or `national_id`.

**Example:**

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "partner_id": 16,
    "farmer_db_id": 30,
    "consent_type": "specific",
    "purpose": "A2C data sharing for agricultural services",
    "validity_from": "2026-05-06 00:00:00",
    "validity_to": "2027-05-06 00:00:00",
    "allowed_data_field_ids": [1],
    "originated_from": "partner",
    "attachment_ids": 566
  }
}
```

**Success `data`:**

```json
{
  "id": 96,
  "consent_creation_request_id": "8e3ce997-dce5-42cc-a6a4-ae3db05b6542",
  "status": "pending"
}
```

### Approve consent

**POST** `/api/consent/request/approve`

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "consent_id": 96
  }
}
```

Alternatively use `consent_creation_request_id` instead of `consent_id`.

**Prerequisites for approval:**

- Partner must have an active **External** WebSub configuration with event `WEBSUB_INDIVIDUAL_UPDATED`
- WebSub hub must deliver to the S3 `respone/` webhook URL
- `allowed_data_field_ids` must resolve to publishable farmer data

On approval the registry enqueues a WebSub publish job. The farmer payload appears in the response webhook folder shortly after.

---

## Webhook bucket

The staging environment uses a public S3 website bucket as a webhook sink for testing.

| Location | URL | Purpose |
|----------|-----|---------|
| OTP folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) | Fayda OTP callback JSON files |
| Response folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) | Farmer data after consent approval |

### Retrieving OTP

**Option A — Browser**

Open the [OTP folder](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/), open the newest JSON file, and copy the OTP value into the Postman `otp_code` variable.

**Option B — S3 list API (used by Postman helpers)**

```bash
curl -s "https://a2c-webhook.s3.ap-south-1.amazonaws.com/?list-type=2&prefix=otp/&max-keys=20"
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
curl -s "https://a2c-webhook.s3.ap-south-1.amazonaws.com/?list-type=2&prefix=respone/&max-keys=20"
```

Fetch the newest payload (ignore `webhook-respone.json` and `index.html`):

```bash
curl -s "http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/2026-06-06T10-40-35_a4014132.json"
```

---

## Sample farmer webhook payload

After approval, a file similar to this appears under `respone/`:

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
    "name": "a2capp@test.com",
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
| `base_url` | `https://registry.oanstaging.com` | Registry base URL (HTTPS) |
| `db` | `odoo` | Odoo database |
| `login` / `password` | `a2capp@test.com` | Test partner credentials |
| `partner_id` | `16` | Consent parent partner for `a2capp@test.com` |
| `farmer_db_id` | `30` | Test farmer (set automatically by search) |
| `farmer_query` | `1234567` | Search query for `2. search farmer` |
| `allowed_data_field_ids` | `[1]` | Must match partner-allowed fields |
| `transaction_id` | *(auto)* | From request OTP |
| `otp_code` | *(auto)* | From OTP webhook |
| `consent_id` | *(auto)* | From create consent |
| `attachment_id` | *(auto)* | From upload attachment |
| `webhook_url` | S3 website root | OTP bucket browser/API |
| `webhook_response_url` | S3 `respone/` path | Farmer payload folder |

---

## Terminal test script

A shell script is available at `test_consent_management_apis.sh`:

```bash
chmod +x test_consent_management_apis.sh
./test_consent_management_apis.sh
```

The script runs the full Postman flow: login → search farmer → request OTP → verify OTP → upload attachment → create consent → approve → fetch farmer webhook.

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

If OTP auto-detection from S3 fails (webhook delivery delay), pass the code manually:

```bash
OTP_CODE=965332 TX_ID=C67AC60C2FF541BBB0150F0E425C4783 ./test_consent_management_apis.sh
```

**Verified on staging (2026-06-06):** login, search farmer, request OTP, upload attachment, create consent, and approve all returned HTTP 200. Farmer webhook `respone/2026-06-06T10-40-35_a4014132.json` was published after approval. OTP webhook delivery to `otp/` was stale during testing; verify OTP may fail with expired codes but the remaining flow still succeeds on staging.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `301 Moved Permanently` or `Invalid JSON data` | Using HTTP instead of HTTPS |
| `Database not found` | Wrong `db` value — staging uses `odoo`, not `management` |
| `Access denied` on OTP endpoints | User is not linked to a consent parent partner |
| `No valid allowed_data_field_ids` | Field IDs not configured on the partner |
| `WebSub configuration is not selected` on approve | Partner missing active External WebSub config |
| OTP verify fails (`OTP session expired`) | Expired OTP, stale webhook file, or `transaction_id` mismatch |
| No new file in `otp/` | Fayda callback not reaching the bucket; use manual `OTP_CODE` |
| No file in `respone/` | Approval failed, WebSub not configured, or job still queued |
| Empty `selected_data` in webhook | WebSub config has no publishable fields for this farmer |

---

## Related resources

- Registry login UI: [https://registry.oanstaging.com](https://registry.oanstaging.com)
- OTP webhook browser: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/)
- Farmer webhook browser: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/)
