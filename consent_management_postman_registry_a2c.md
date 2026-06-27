# Consent Management API — Registry A2C

API reference for the **Consent Management** Postman collection used in the A2C (Access to Credit) loan flow.

| Item | Value |
|------|-------|
| Postman collection | `Consent Management.postman_collection.json` (production defaults) |
| Production registry | [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et) |
| Staging registry | [https://registry.oanstaging.com](https://registry.oanstaging.com) |
| Workflow guide (production UI) | [`consent_management_postman_registry_a2c_workflow.md`](consent_management_postman_registry_a2c_workflow.md) |

---

## Purpose

These APIs let an A2C partner:

1. Authenticate to the registry
2. Search for a farmer by land ID
3. Request and verify a Fayda OTP
4. Fetch consent reasons and allowed data fields
5. Submit a consent request (inline PDF) — auto-created and auto-approved
6. Receive shared farmer data — inline in the submit consent response on production (`response_data`); S3 webhooks on staging

---

## Environments

### Staging

For integration testing with mock webhook delivery via S3.

| Item | Value |
|------|-------|
| Registry | `https://registry.oanstaging.com` |
| Database | `odoo` |
| Credentials | `a2capp@test.com` / `a2capp@test.com` |
| Search parameter | `query` (land ID value) |
| Verify OTP field | `otp_code` |
| Fetch reasons / allowed fields | `POST` |
| OTP source | [S3 otp/ folder](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) |
| Farmer data sink | [S3 respone/ folder](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) |

### Production (ATI Farmer)

The Postman collection defaults to this environment.

| Item | Value |
|------|-------|
| Registry | `https://farmer-profile.ati.gov.et` |
| Database | `socialregistrydb` |
| Credentials | Contact the administrator |
| Search parameter | `query` (land ID value) |
| Verify OTP field | `otp` |
| Fetch reasons / allowed fields | `GET` |
| OTP source | Farmer's mobile (Fayda) |
| Farmer data sink | Inline in submit consent `response_data` |

### Environment differences at a glance

| Setting | Staging | Production |
|---------|---------|------------|
| `base_url` | `https://registry.oanstaging.com` | `https://farmer-profile.ati.gov.et` |
| `db` | `odoo` | `socialregistrydb` |
| Search body key | `query` | `query` |
| Verify OTP key | `otp_code` | `otp` |
| Reasons endpoint method | `POST` | `GET` |
| Allowed fields method | `POST` | `GET` |
| JSON body | includes `method: "call"` (staging) | `jsonrpc` + `params` only |
| Farmer data delivery | S3 `respone/` folder | Inline `response_data` in submit consent |

---

## End-to-end flow

```mermaid
sequenceDiagram
    participant Partner as A2C Partner
    participant Registry as Registry API
    participant Fayda as Fayda OTP
    participant Staging as S3 webhooks (staging)

    Partner->>Registry: 1. POST /web/session/authenticate
    Registry-->>Partner: session cookie

    Partner->>Registry: 2. POST /consent/search_farmer
    Registry-->>Partner: farmer_db_id

    Partner->>Registry: 3. POST /consent/fayda/request_otp
    Registry->>Fayda: request OTP
    Registry-->>Partner: transaction_id

    Partner->>Registry: 5. POST /consent/fayda/verify_otp
    Registry-->>Partner: OTP verified

    Partner->>Registry: 6. GET or POST /api/consent/reasons
    Partner->>Registry: 7. GET or POST /api/consent/allowed_data_fields
    Partner->>Registry: 8. POST /api/consent/submit_consent
    Registry-->>Partner: consent_id + response_data (production)

    alt Staging
        Fayda-->>Staging: OTP to S3 otp/
        Registry->>Staging: farmer payload to respone/
        Partner->>Staging: read respone/ webhook
    else Production
        Fayda-->>Partner: OTP to farmer mobile
        Note over Partner,Registry: Farmer data in submit_consent response_data
    end
```

### Recommended request order (Postman)

| Step | Request | Notes |
|------|---------|-------|
| 1 | `1. login` | Saves session cookie and `partner_id` |
| 2 | `2. search farmer` | Sets `farmer_db_id` |
| 3 | `3. request otp` | Sets `transaction_id` |
| 4a | `A–B. OTP webhook helpers` | **Staging only** — fetch OTP from S3 |
| 4b | Enter OTP manually | **Production** — from farmer's mobile |
| 5 | `4. verify otp` | Uses `transaction_id` + OTP |
| 6 | `5. Fetch Consent Reasons` | Sets `consent_reason_id` |
| 7 | `6. Fetch Allowed Data Fields` | Sets `allowed_data_field_ids` |
| 8 | `7. Submit Consent` | Auto-approves; returns `response_data` with farmer payload (production) |
| 9 | `C–D. Farmer webhook helpers` | **Staging only** — read `respone/` payload |

---

## Authentication

**POST** `/web/session/authenticate`

Production example (matches collection):

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

Staging example:

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

All other endpoints require the session cookie from this response.

---

## Registry API endpoints

Requests use JSON-RPC 2.0 (`jsonrpc`, `params`). Staging may also include `"method": "call"`.

Successful responses:

```json
{
  "jsonrpc": "2.0",
  "id": null,
  "result": {
    "success": true,
    "message": "OK",
    "data": {}
  }
}
```

### Search farmer

**POST** `/consent/search_farmer`

Search for an approved farmer by **land ID**. Pass the land parcel ID via `query` — this matches the consent portal UI (`callJsonRoute('/consent/search_farmer', { query: singleQuery })`).

The backend matches the supplied value against `g2p.land.information.land_id` (and other registry identifiers).

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | Yes | Land parcel ID to search (recommended; same as portal) |
| `farmer_id` | No | Alternative — pass the land ID as the value |
| `national_id` | No | Alternative — pass the land ID as the value |
| `uid` | No | Alternative — pass the land ID as the value |

Recommended request (matches portal):

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "query": "1234567"
  },
  "id": 1
}
```

Production Postman collection (omits `method` and `id`; `query` is the important field):

```json
{
  "jsonrpc": "2.0",
  "params": {
    "query": "1234567"
  }
}
```

These alternatives also work (use the land ID as the value):

```json
{ "params": { "farmer_id": "1234567" } }
{ "params": { "national_id": "1234567" } }
{ "params": { "uid": "1234567" } }
```

Use the returned `farmers[0].id` as `farmer_db_id`.

**Empty `"farmers": []` response**

If the request succeeds but returns no farmers:

- The land ID does not exist in `g2p.land.information`
- The linked farmer is not in the approved-farmer domain (`_approved_farmer_domain()` filters results)
- The land record has no `partner_id`
- Wrong parameter name (e.g. `land_id` in params — not accepted; use `query` instead)

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

Returns `transaction_id`. The OTP itself is not in the response — obtain it from S3 (staging) or the farmer's phone (production).

### Verify OTP

**POST** `/consent/fayda/verify_otp`

Production (collection uses `otp`):

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

Staging (uses `otp_code`):

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

> The Postman collection variable is named `otp_code` in both environments; production maps it to the `otp` request field.

### Fetch consent reasons

**Production:** `GET` `/api/consent/reasons`

```json
{
  "jsonrpc": "2.0",
  "params": {}
}
```

**Staging:** `POST` `/api/consent/reasons` with `"method": "call"` and empty `params`.

### Fetch allowed data fields

**Production:** `GET` `/api/consent/allowed_data_fields`

```json
{
  "jsonrpc": "2.0",
  "params": {}
}
```

**Staging:** `POST` `/api/consent/allowed_data_fields` — may include `partner_id` in `params`.

### Submit consent

**POST** `/api/consent/submit_consent`

Submits consent with inline PDF attachment. Auto-creates and auto-approves — no separate create/approve step.

| Parameter | Required | Description |
|-----------|----------|-------------|
| `farmer_id` | Yes | Registry `res.partner` ID |
| `consent_type` | No | Default `specific` |
| `consent_reason_id` | Yes | From fetch consent reasons |
| `validity_months` | No | Default `12` |
| `allowed_data_field_ids` | Yes | Array of field IDs |
| `attachment_base64` | Yes | Base64-encoded PDF |
| `attachment_filename` | Yes | PDF filename |
| `fayda_otp_transaction_id` | Yes | Verified OTP `transaction_id` |

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

**Success `data` (production):**

On success the response includes consent metadata and the full farmer payload in `response_data`:

```json
{
  "consent_id": 9,
  "status": "approved",
  "auto_approved": true,
  "auto_approval_failed": false,
  "auto_approve_method": "otp",
  "error_details": null,
  "response_data": {
    "source": "g2p_ati_consent_mgt",
    "event_type": "WEBSUB_INDIVIDUAL_UPDATED",
    "published_at": "2026-06-20 13:27:07",
    "consent": {
      "id": 10,
      "consent_creation_request_id": "9cd96a35-f9b4-457c-98f9-d49080972380",
      "consent_type": "specific",
      "status": "approved",
      "approved_at": "2026-06-20 13:27:07",
      "validity_from": "2026-06-20 13:27:07",
      "validity_to": "2027-06-15 13:27:07",
      "requested_field_codes": ["NAME", "GENDER", "DOB-GC", "Email", "REGION", "ZONE", "woreda", "KEBELE"],
      "published_field_codes": ["NAME", "GENDER", "DOB-GC", "Email", "REGION", "ZONE", "woreda", "KEBELE"],
      "data_field_mode": "dynamic"
    },
    "consent_partner": {
      "id": 264515,
      "name": "COOP BANK",
      "ref": false,
      "websub_config_id": 4,
      "websub_config_name": "COOP"
    },
    "farmer": {
      "id": 612961,
      "farmer_id": "FR-9075201458",
      "name": "TEST TEST TEST"
    },
    "selected_data": {
      "NAME": { "name": "TEST TEST TEST" },
      "GENDER": { "gender": "male" },
      "DOB-GC": { "date_of_birth_gc": "1985-06-12" },
      "REGION": {
        "region": { "id": 24, "name": "Oromiya", "code": "ET04" }
      }
    }
  }
}
```

| Field | Meaning |
|-------|---------|
| `consent_id` | Approved consent record ID |
| `status` | `approved` when auto-approval succeeds |
| `response_data` | Full farmer payload — same structure as the staging S3 webhook |
| `response_data.consent` | Consent metadata and requested/published field codes |
| `response_data.farmer` | Farmer registry record |
| `response_data.selected_data` | Published field values keyed by field code |

> **Production:** no separate Kafka subscription or webhook poll is required — read `result.data.response_data` from this response.
>
> **Staging:** may return the same shape inline, or farmer data may appear asynchronously in the S3 `respone/` folder.

---

## Staging webhook bucket

Used only for staging integration testing.

| Location | URL | Purpose |
|----------|-----|---------|
| OTP folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/) | Fayda OTP callback JSON |
| Response folder | [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/) | Farmer data after approval |

List OTP files:

```bash
curl -s "https://a2c-webhook.s3.ap-south-1.amazonaws.com/?list-type=2&prefix=otp/&max-keys=50"
```

Sample OTP webhook:

```json
{
  "transactionID": "C67AC60C2FF541BBB0150F0E425C4783",
  "otp": "965332",
  "individualId": "12345",
  "individualIdType": "FIN",
  "timestamp": "2026-06-01T17:47:13.643488"
}
```

---

## Collection variables (production defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `base_url` | `https://farmer-profile.ati.gov.et` | Production registry |
| `db` | `socialregistrydb` | Odoo database |
| `login` / `password` | `test@user.com` / `pass` | Replace with admin-provided credentials |
| `land_id` | `1234567` | Land parcel ID — sent as `query` in step 2 |
| `farmer_db_id` | `30` | Set automatically by search |
| `consent_type` | `specific` | Consent type |
| `consent_reason_id` | `1` | Set by fetch reasons |
| `validity_months` | `12` | Consent validity |
| `allowed_data_field_ids` | `[1]` | Set by fetch allowed fields |
| `transaction_id` | *(auto)* | From request OTP |
| `otp_code` | *(manual)* | OTP value (maps to `otp` field in production) |
| `attachment_base64` | *(sample PDF)* | Inline consent PDF |
| `attachment_filename` | `consent_form_test_megha1.pdf` | PDF filename |
| `webhook_url` | S3 website root | Staging OTP bucket |
| `webhook_response_url` | S3 `respone/` path | Staging farmer payload folder |
| `webhook_s3_api` | `https://a2c-webhook.s3.ap-south-1.amazonaws.com` | S3 list API |

Override these variables when pointing Postman at staging (see [Environments](#environments)).

---

## Terminal test script

`test_consent_management_apis.sh` defaults to **staging**. Set `ENV=production` for production.

**Staging:**

```bash
./test_consent_management_apis.sh
```

**Production:**

```bash
ENV=production LOGIN=your@user.com PASSWORD=pass \
LAND_ID=1234567 OTP_CODE=123456 TX_ID=abc... \
./test_consent_management_apis.sh
```

---

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| `301 Moved Permanently` | Using HTTP instead of HTTPS |
| `Database not found` | Wrong `db` — staging uses `odoo`, production uses `socialregistrydb` |
| OTP verify field error (production) | Using `otp_code` instead of `otp` in request body |
| OTP verify field error (staging) | Using `otp` instead of `otp_code` |
| No OTP in S3 (staging) | Fayda callback delay; pass `OTP_CODE` manually |
| No file in `respone/` (staging) | Submit failed or WebSub job still queued |
| Empty `response_data` (production) | Submit succeeded but no publishable fields for this farmer |
| Missing `response_data` in submit response | Check `auto_approval_failed` and `error_details` |
| Farmer search returns empty | Wrong `query` value, land ID not in registry, land has no `partner_id`, or farmer not in approved domain |
| Farmer search error: missing parameter | Use `query` (not `land_id`) — backend does not accept `land_id` as a param yet |

---

## Related resources

- Staging registry: [https://registry.oanstaging.com](https://registry.oanstaging.com)
- Production registry: [https://farmer-profile.ati.gov.et](https://farmer-profile.ati.gov.et)
- Staging OTP bucket: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/otp/)
- Staging farmer bucket: [http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/](http://a2c-webhook.s3-website.ap-south-1.amazonaws.com/respone/)
