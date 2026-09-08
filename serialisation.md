# Serialisation Module — Standalone Member System (SSCC + Serialised Data Matrix)

A build spec for lifting the **Healthcare Traceability** feature out of `gs1_admin`
into its own member-facing system, with its **own UI and its own database**, that
**calls the GS1 (gs1_admin) APIs** to actually mint SSCCs and serials instead of
generating them locally.

This document is the source of truth for whoever builds the new module. It
describes what exists today, what moves, what stays, and the contract between
the two systems.

---

## 1. Why a separate system

Today serialisation lives inside the admin monolith (`gs1_admin`, Phoenix +
LiveView, `ErpLive*` namespace). Members reach it through the member portal
routes under `/healthcare/:id/...`. That couples a member-facing, high-write
workload (millions of serial rows) to the admin app's release cycle and
database.

The new system:

- owns the **member experience** (product list, generation forms, artwork,
  exports, billing screens),
- owns its **own DB** for shipments, serials, SSCCs, batches, usage/billing,
- treats GS1 as the **authority for identifier issuance**: every SSCC and every
  serialised GTIN comes back from a GS1 API call, never from local arithmetic.

Working name used below: **Serials** (`serials_web` / `Serials.*`). Rename freely.

---

## 2. What exists today (the thing being ported)

### 2.1 Entry flow

| Route (current)                                  | Module                                       | Purpose                                                                                        |
| ------------------------------------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `/healthcare/:id/options`                        | `CompanyPortalLive.HealthcareOptions`        | Choose **prepay** (buy a block of serials) or **flex/postpay** (generate now, billed on usage) |
| `/healthcare/:id/payment`                        | `CompanyPortalLive.HealthcarePayment`        | Prepay checkout (M-Pesa)                                                                       |
| `/healthcare/:id/postpay-payment`                | `CompanyPortalLive.HealthcarePostpayPayment` | Settle a postpay cycle                                                                         |
| `/healthcare/:id/billing`                        | `CompanyPortalLive.HealthcareBilling`        | Plan status + full cycle history                                                               |
| `/healthcare/:id/dashboard`                      | `CompanyPortalLive.HealthcareDashboard`      | Usage/summary dashboard                                                                        |
| `/healthcare/:id`                                | `CompanyPortalLive.Healthcare` `:index`      | Product listing with per-GTIN SSCC + serialised counts, search/sort/paginate                   |
| `/healthcare/:id/generate`                       | `Healthcare` `:generate`                     | Distributor multi-GTIN SSCC generation                                                         |
| `/healthcare/:id/add/tdh/:barcode`               | `Healthcare` `:dt`                           | SSCC (logistics) generation for one GTIN                                                       |
| `/healthcare/:id/add/serialised/:barcode`        | `Healthcare` `:sdt`                          | Serialised Data Matrix generation for one GTIN                                                 |
| `/healthcare/:id/datamatrix/:barcode`            | `CompanyPortalLive.Datamatrix`               | View/print generated SSCC labels                                                               |
| `/healthcare/:id/serialised/datamatrix/:barcode` | `CompanyPortalLive.Serialised`               | View/print serialised labels                                                                   |
| `/healthcare/:id/export/list/:barcode`           | `CsvController.serialised`                   | CSV export of generated codes                                                                  |

Heavy lifting lives in two LiveComponents:
`datamatrix_component.ex` (~1.3k lines, SSCC generation) and
`serialised_component.ex` (~900 lines, serialised Data Matrix generation).

### 2.2 Domain contexts

| Context                       | File                                        | Role                                                                                                                                                  |
| ----------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ErpLive.Barcodes`            | `lib/erp_live/barcodes/barcodes.ex`         | GTIN lookup + `verify_gtin/1`, `create_tdhcodes/1`, `create_shipper/1`, `log_serialization/1`, per-member counts                                      |
| `ErpLive.SerialBarcodes`      | `lib/erp_live/serial_barcodes.ex`           | A **distributor's** own working catalog of GTINs they don't own — `lookup/2` (no write), `find_or_verify/3`, `ensure_for_member/3`                    |
| `ErpLive.Ssccs`               | `lib/erp_live/ssccs/ssccs.ex`               | SSCC records created via the public API path                                                                                                          |
| `ErpLive.SerialUsage`         | `lib/erp_live/serial_usage/serial_usage.ex` | Allowance enforcement: `get_active_usage/1`, `authorize_generation/2`, `exhausted?/1`, `overdue?/1`, `ensure_first_postpay_cycle/1`, `list_history/1` |
| `ErpLive.SerialUsage.Pricing` | `.../pricing.ex`                            | Tiered pricing bands + VAT                                                                                                                            |

### 2.3 Schemas to carry over

- **`tdhcode`** (`Barcodes.Tdhcodes`) — one row per SSCC ↔ GTIN pairing.
  Fields: `barcode` (GTIN), `sscc`, `serial`, `type` (`"dt"`/`"sdt"`), `batch`,
  `production`, `expiry` (dates), `count` (cases), `items`, `pallete`, `image`,
  `material_description`, `order_number`, `customer_part_number`,
  `from_address`, `to_address`, `gln_id`, `to_gln_id`, `from_po_box`,
  `from_company_name`, `to_po_box`, `to_company_name`, `member_id`, `user_id`.
- **`shipper`** (`Barcodes.Shipper`) — shipper/case units: `barcode`, `gtin`,
  `gtins`, `sscc`, `pallet_sscc`, `serial`, batch/production/expiry, addresses,
  `member_id`, `user_id`.
- **`ssccs`** (`Ssccs.Sscc`) — API-created SSCCs: `code`, `gtin`, `batch`,
  `production_date`, `expiry_date`, `from_address`, `to_address`,
  `count_of_trade_items`, `material_description`, `order_number`,
  `customer_part_number`, `facility_gln`.
- **`serial_barcodes`** (`SerialBarcodes.SerialBarcode`) — distributor catalog:
  `code`, `name`, `description`, `weight`, `uom`, `classification`,
  `target_market`, `comp_name`, `image`, `source` (`"local"`/`"external"`),
  unique on `[code, member_id]`.
- **`serialization_logs`** (`Barcodes.SerializationLog`) — audit of each
  generation event: `type` (`"dt"`/`"sdt"`), `barcode`, `batch`, `count`.
- **`serial_usages`** (`SerialUsage.Usage`) — one row per prepay purchase or
  postpay cycle, linked 1:1 to an `mpesa` payment row: `type`
  (`prepay`/`postpay`), `quantity_limit`, `buffer_limit` (default 10,000,000),
  `running_quantity`, `running_buffer`. Append-only; latest row is active.

### 2.4 Business rules that MUST survive the port

1. **Prefix required.** SSCC generation is blocked with an explicit message when
   the member has no GS1 company prefix. Same for serialised generation, which
   also requires a `bank`.
2. **SSCC prefix ownership.** The SSCC always carries the _distributor's_ own
   prefix, regardless of who owns the product GTIN.
3. **Extension digits.** Pallet SSCCs use extension `1` + prefix; case SSCCs use
   `2` + prefix. Check digit computed via `ActivateApis.checkdigit/1`.
4. **Mixed pallet counting.** More than one GTIN on a pallet ⇒ exactly one
   pallet. Each _distinct SSCC_ is one billable serial; extra per-GTIN rows on a
   mixed pallet are **not** counted twice.
   `requested = pallets + total_cases`.
5. **Authorize before writing.** `SerialUsage.authorize_generation/2` runs inside
   a transaction with a row lock **before** any code rows are created. Three
   distinct rejection messages: insufficient capacity (shows the remaining
   count), allocation exhausted (renew), no active usage (go to billing).
6. **Prepay capacity** = `running_quantity + (buffer_limit - running_buffer)`;
   draw from quantity first, spill into buffer.
7. **Postpay** is unbounded until overdue (`next_billing_date` reached and
   unpaid), then only the buffer remains.
8. **Viewing is always allowed.** Only entering a _generation_ form redirects an
   exhausted member to the plans page.
9. **No dirty catalog rows.** GTIN search only _previews_ (`SerialBarcodes.lookup/2`
   returns an unsaved struct); rows are persisted at save time via
   `ensure_for_member/3`.
10. **Pricing is flat-rate-by-total, not graduated** — see `Pricing`. Bands are
    cliffs by design; keep the docstring.
11. **Every generation event is logged** to `serialization_logs`.

### 2.5 Data Matrix payload formats

Serialised primary item:

```
␝010<GTIN>17<YYMMDD expiry>10<batch>␝21<serial>␝11<YYMMDD production>
```

Shipper:

```
␝02<GTIN>17<YYMMDD expiry>10<batch>␝21<serial>␝11<YYMMDD production>
```

Dates are `YYMMDD` (`format_date/1`: strip `-`, slice `2..8`). Serials are
`SecureRandom.urlsafe_base64(9)` with `=` stripped — **in the new system these
come from GS1, not from local randomness** (§4).

---

## 3. Target architecture

```
┌──────────────────────────────┐        HTTPS + Bearer token        ┌────────────────────────┐
│  Serials (new member system) │ ─────────────────────────────────> │  gs1_admin GS1 API     │
│  Phoenix + LiveView          │                                     │  /api/create_sscc      │
│  Own Postgres/MySQL DB       │ <───────────────────────────────── │  /api/get_sscc         │
│  UI, artwork, CSV, billing   │        issued codes + payload      │  /api/create_serialised│
└──────────────────────────────┘                                     │        _datamatrix     │
                                                                     │  /api/getbarcode_v2    │
                                                                     └────────────────────────┘
```

**Split of responsibility**

| Concern                                                   | Owner                                          |
| --------------------------------------------------------- | ---------------------------------------------- |
| Member identity, prefix, bank, standards entitlements     | gs1_admin (source of truth)                    |
| GTIN registry + verification                              | gs1_admin                                      |
| Issuing SSCC codes and serials                            | gs1_admin API                                  |
| Shipment/consignment modelling, batches, lines            | **Serials**                                    |
| Local mirror of issued codes (for listing, print, export) | **Serials**                                    |
| Label/artwork rendering, CSV export, print sheets         | **Serials**                                    |
| Allowance + billing UI                                    | **Serials** UI, gs1_admin enforcement (see §6) |

### 3.1 Suggested app layout

```
lib/serials/
  accounts/           # member session, links to gs1 member_id
  catalog/            # local GTIN catalog mirror (was serial_barcodes)
  shipments/          # shipment, shipment_line, pallet, case
  codes/              # sscc, serialised_code, shipper_code, serialization_log
  usage/              # usage cycles, pricing (mirror of SerialUsage + Pricing)
  gs1/                # ← the API client
    client.ex         # Req/Finch wrapper, auth, retries, telemetry
    sscc.ex           # create_sscc/1, get_sscc/1
    serialised.ex     # create_serialised_datamatrix/1
    gtin.ex           # getbarcode_v2/1 for verification
    error.ex
lib/serials_web/live/
  onboarding_live/    # options / prepay / postpay
  billing_live/
  dashboard_live/
  catalog_live/       # product listing (was Healthcare :index)
  sscc_live/          # generation form (was datamatrix_component)
  serialised_live/    # generation form (was serialised_component)
  labels_live/        # print/preview
```

---

## 4. GS1 API contract

Base: `POST https://<gs1-admin-host>/api/...`
Auth: `Authorization: Bearer <api_token>` (the member's API token; resolves
server-side to `user_id` → `member_id` → prefix/bank/entitlements).

All endpoints return JSON. Non-2xx bodies are `{"result": "<human message>"}`.

### 4.1 `POST /api/create_sscc`

Request:

```json
{
  "batch_info": [
    {
      "gtin": "6161100000015",
      "batch": "B12",
      "production_date": "2026-01-10",
      "expiry_date": "2027-01-10"
    }
  ],
  "address": { "from_address": "...", "to_address": "..." },
  "count_of_trade_items": 24,
  "material_description": "...",
  "order_number": "...",
  "customer_part_number": "...",
  "facility_gln": "..."
}
```

- `batch_info` accepts an object or a list; a **single SSCC code is shared
  across all batch entries** (one `ssccs` row per batch entry).
- Every field is required except `customer_part_number`.
- Response includes the issued `sscc.sscc` code, human-readable text,
  application identifiers, and a Data Matrix image path.

Failure modes to handle in the client: `400` missing params, `401` invalid
token, `404` member not found, `403`-style "standard access denied" when the
member is not entitled to SSCC, `422` no prefix configured.

### 4.2 `POST /api/get_sscc`

```json
{ "sscc": "100000000000000018" }
```

Returns the SSCC with its batch entries, AIs, human-readable text and image.

### 4.3 `POST /api/create_serialised_datamatrix`

```json
{
  "barcode": "6161100000015",
  "batch": "B12",
  "production": "2026-01-10",
  "expiry": "2027-01-10",
  "trade_item_qty": "1000",
  "shipper_qty": "20",
  "order_number": "...",
  "customer_part_number": "..."
}
```

- `barcode` must be exactly 13 digits and exist on the platform with a member.
- `shipper_count = trunc(trade_item_qty / shipper_qty)`; the call authorizes
  `trade_item_qty + shipper_count` serials against the member's plan.
- Response: the SSCC, ITF-14, the list of primary serials, and per-shipper
  `{"sscc": ..., "primary_serials": [...]}` groupings.

### 4.4 `POST /api/getbarcode_v2`

Used for GTIN verification/preview in the catalog screen (replaces the direct
`Barcodes.verify_gtin/1` call). Cache the result locally as a `catalog` row only
on save, per rule 2.4.9.

### 4.5 Client requirements

- **Idempotency.** Generation is not naturally idempotent — a retried
  `create_sscc` mints a _new_ code. Send a client-generated `request_id` per
  attempt, persist it locally _before_ the call in a `gs1_requests` table with
  status `pending → succeeded/failed`, and never auto-retry a `pending` request
  without an operator-visible reconciliation step. (This requires adding
  `request_id` support on the gs1_admin side — see §8.)
- **Timeouts** generous (serialised generation of 100k+ serials is slow);
  prefer an async job (Oban) per generation request with progress in the UI
  rather than a blocking LiveView handle_event.
- **Bulk.** Large runs should be chunked; the current API returns the full serial
  list in one response, which will not scale past a few hundred thousand.
  Either paginate the response or have GS1 return a job id + download URL.
- Log every request/response (redacting the token) — the current controller
  already writes an api-log row per call; mirror that locally.

---

## 5. Data model for the new system

Normalise what is currently a wide, denormalised `tdhcode` table.

```
members_mirror   id, gs1_member_id, name, prefix, bank, api_token_ref, entitlements
catalog_items    id, member_id, gtin, name, description, weight, uom,
                 classification, target_market, comp_name, image, source,
                 unique (member_id, gtin)
shipments        id, member_id, user_id, type ("sscc"|"serialised"),
                 batch, production_date, expiry_date,
                 order_number, customer_part_number, material_description,
                 from_gln_id, to_gln_id, from_address, to_address,
                 from_po_box, from_company_name, to_po_box, to_company_name,
                 status, gs1_request_id, inserted_at
shipment_lines   id, shipment_id, gtin, cases, items_per_case
ssccs            id, shipment_id, code, level ("pallet"|"case"),
                 parent_sscc_id, image, issued_at
sscc_items       id, sscc_id, gtin, count, items      # mixed-pallet contents
serialised_codes id, shipment_id, gtin, serial, image, sscc_id (nullable),
                 unique (member_id, serial)
serialization_logs id, member_id, user_id, type, gtin, batch, count
usage_cycles     id, member_id, payment_id, type, quantity_limit, buffer_limit,
                 running_quantity, running_buffer
gs1_requests     id, member_id, endpoint, request_id, payload_digest,
                 status, response_summary, inserted_at
```

Indexes that matter at volume: `serialised_codes(member_id, gtin)`,
`serialised_codes(serial)`, `ssccs(code)`, `shipments(member_id, inserted_at)`.

**Migration from the monolith:** backfill `tdhcode` rows where `type = "dt"`
into `shipments` + `ssccs` + `sscc_items` (group by `member_id, batch,
production, expiry, order_number` to reconstitute a shipment), `type = "sdt"`
rows into `serialised_codes`, and `shipper` rows into case-level `ssccs`. Keep a
`legacy_tdhcode_id` column on the new rows for one release so exports can be
diffed against the old system.

---

## 6. Allowance, billing, and the double-enforcement problem

The GS1 API **already** calls `SerialUsage.authorize_generation/2` inside
`create_serialised_datamatrix`. If the new system also decrements a local copy,
counts will drift.

**Decision: GS1 remains the single enforcer.** The new system:

- reads plan state from GS1 (add a `GET /api/serial_usage` endpoint — §8),
- shows the plan, remaining balance, band and pricing UI locally,
- does an **optimistic pre-check** for UX only (so the user sees "you have N
  left" before submitting), never as the authority,
- surfaces the API's rejection messages verbatim — they are already
  member-appropriate and distinguish the three cases in 2.4.5.

Payment (M-Pesa prepay/postpay) stays in gs1_admin, since usage rows are 1:1
with `mpesa` rows. The new system deep-links to the existing payment screens, or
GS1 exposes a payment-initiation endpoint. Port `Pricing` verbatim into the new
app for display only, and add a test asserting the two copies agree.

---

## 7. UI to build (feature parity checklist)

- [ ] **Plan chooser** — prepay vs flex, with the pricing-bands popup; skip
      straight to the app when an active non-exhausted plan exists.
- [ ] **Billing** — current cycle, remaining balance, overdue banner, full
      history table.
- [ ] **Dashboard** — generated counts by type, recent activity.
- [ ] **Catalog listing** — search, sort (`@sortable_fields`), paginate
      (default 10/page), per-GTIN SSCC and serialised counts, distributor mode
      showing `catalog_items` instead of owned GTINs.
- [ ] **SSCC generation (single GTIN)** — cases, items per case, pallets, batch,
      production, expiry, order no., customer part no., material description,
      from/to GLN pickers (search local GLNs, fall back to the Activate lookup).
- [ ] **SSCC generation (distributor, multi-GTIN)** — add/remove GTIN lines,
      per-line cases and items, GTIN search with preview-not-save, mixed-pallet
      rule.
- [ ] **Serialised Data Matrix generation** — trade item qty, shipper qty,
      derived shipper count, per-shipper serial grouping.
- [ ] **Label view/print** — Data Matrix images, human-readable AI text, print
      sheets, per-batch/expiry/production/serial deep links.
- [ ] **CSV export** of generated codes per GTIN.
- [ ] All prefix/bank/entitlement guard messages from 2.4.1.

Keep the existing copy for error and guard messages — it has been through
support already.

---

## 8. Changes needed on the gs1_admin side

1. `GET /api/serial_usage` — active cycle, type, remaining quantity, buffer,
   overdue flag, next billing date. (Needed for §6.)
2. `request_id` / idempotency key on `create_sscc` and
   `create_serialised_datamatrix`; return the original result on replay.
3. Async mode for large serialised runs: return `{job_id}` + a poll/download
   endpoint instead of the full serial list inline.
4. `POST /api/create_sscc` currently mints **one** SSCC per call; the UI needs
   _n_ pallets and _m_ cases per shipment. Either add a `quantity` +
   `extension_digit` parameter, or accept that the new system loops (slow, and
   defeats idempotency). Prefer the parameter.
5. Expose member profile (`prefix`, `bank`, standards entitlements) so the new
   system can render guards without guessing.
6. Return the check-digit/extension logic decisions in the response (which
   extension digit was used) so local records stay faithful.

Until (4) lands, the new system cannot fully replace local generation for
multi-pallet shipments — flag this as the critical path item.

---

## 9. Build order

1. GS1 API client + `gs1_requests` audit table, with a sandbox token and
   contract tests against a recorded fixture set.
2. Schema + migrations for §5; backfill script from the monolith (read-only).
3. Catalog listing + GTIN preview/verify (read-only slice, ships early).
4. SSCC generation end-to-end for a single GTIN, single pallet.
5. Multi-GTIN / mixed pallet, once §8.4 exists.
6. Serialised Data Matrix generation (async job).
7. Labels, print, CSV export.
8. Plan chooser, billing, dashboard.
9. Cutover: run both systems against the same member in read-only diff mode,
   then flip the `/healthcare/*` routes to redirect.

---

## 10. Open questions

- Does the new system authenticate members with its own accounts, or SSO from
  gs1_admin? (Affects §5 `members_mirror` and token storage.)
- Where do Data Matrix images live — regenerated locally, or fetched from the
  GS1 response path? Local generation is cheaper and avoids a round trip per
  label; the AI payload is deterministic once the serial is known.
- Uganda / Rwanda / GHCE member tables also reference SSCC — is this module
  Kenya-only at launch, or multi-country from day one?
- Retention: serialised runs of millions of rows — is there an archival policy?

---

## 11. Implementation status (in `thamani_dawa`)

Decision taken at build time: the module lives **inside `thamani_dawa`** rather
than in a separate app, so it reuses the existing accounts, org scoping,
`Layouts`, and `core_components`. Two consequences for everything below:

- **`member_id` becomes `organization_id`.** Every table and context function is
  organization-scoped the way the rest of the app is, and `members_mirror` (§5)
  is not needed — the organization *is* the member.
- **Table names are `serial_`-prefixed** (`serial_catalog_items`,
  `serial_shipments`, `serial_ssccs`, …) so a future pharmacy "shipments"
  feature can't collide. `serialised_codes`, `serialization_logs` and
  `gs1_requests` keep their spec names.

### Landed (build order steps 1–3)

| Piece                                   | Where                                                                                    |
| --------------------------------------- | ---------------------------------------------------------------------------------------- |
| GS1 API client, error mapping           | `lib/thamani_dawa/gs1_api/{client,error}.ex`                                             |
| Idempotency + audit (`gs1_requests`)    | `lib/thamani_dawa/gs1_api.ex`, `.../gs1_api/request.ex`                                  |
| Data model for §5                       | `priv/repo/migrations/20260908*`, `lib/thamani_dawa/serialisation/*.ex`                  |
| Catalog + GTIN preview-not-save (2.4.9) | `lib/thamani_dawa/serial_catalog.ex`, `lib/thamani_dawa_web/live/serial_catalog_live/`   |
| Config                                  | `GS1_ADMIN_BASE_URL`, `GS1_ADMIN_API_TOKEN`; unset ⇒ every call fails `:not_configured`  |

Writes (`create_sscc`, `create_serialised_datamatrix`) are audited and never
auto-retried; reads (`get_sscc`, `getbarcode_v2`) retry on transient failures
and are not written to `gs1_requests` — GTIN preview runs on every search and
would swamp the table.

`ThamaniDawa.Gtin.to_gtin13/1` bridges the mismatch between the canonical
GTIN-14 stored locally and the 13 digits the GS1 API demands (§4.3).

### Not yet built

Steps 4–9: SSCC and serialised generation, labels/print, CSV export, plan
chooser, billing, dashboard, cutover. `serial_usage_cycles` exists as a
**display-only mirror** — GS1 stays the single enforcer (§6), and nothing local
may treat those counters as permission to generate.

Still blocked on gs1_admin (§8): the `quantity`/`extension_digit` parameter on
`create_sscc` (§8.4) is the critical path for multi-pallet shipments, and
`GET /api/serial_usage` (§8.1) is needed before the billing screens can show
anything real.

### Tenancy: distributors/manufacturers only see this module

`organizations` gained a `kind` column (`:healthcare` default, or
`:distributor`), chosen at signup (`SignupLive`, a toggle above the org
fields). A distributor's default site is `:warehouse` instead of `:pharmacy`
(`Sites.create_default_site/3`).

- `ThamaniDawa.Organizations.distributor?/1` / `healthcare?/1` are the
  building blocks; nothing caches the kind, each check is a fresh lookup —
  consistent with how `Sites.get_site!/2` is already called per-request
  elsewhere in `user_auth.ex`.
- Router: `/org/products`, `/org/products/*`, `/org/batches/:id`,
  `/org/suppliers*` moved to a `:organization_healthcare` live_session
  (`on_mount: :require_healthcare_org`); `/org/serialisation*` moved to
  `:organization_distributor` (`on_mount: :require_distributor_org`). Both
  wrong-kind hits redirect to the other tenant's home screen with a flash,
  not a raw 404.
- `Layouts.org_shell` picks the sidebar nav by kind — a distributor never
  sees "Products"/"Suppliers"; a healthcare org never sees "Serialisation".
- Login (`SessionController`) sends a distributor admin straight to
  `/org/serialisation` instead of `/org/sites`.
- **Known gap:** `/org/dashboard` and the team invite role list
  (admin/pharmacist/lab_technician/pharma_lab) are still shared across both
  kinds — the dashboard's stats (patients, prescriptions, lab tests) will
  just read as zero for a distributor rather than being hidden, and staff
  roles don't yet have a distributor-appropriate vocabulary. Neither is
  reachable from the distributor nav, but both are reachable by URL.


