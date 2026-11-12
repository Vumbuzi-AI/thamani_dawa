# PPB National Track & Trace Hub — Integration Findings & Implementation Guide

Source spec: *National L5 Track & Trace Hub — EPCIS Event Reporting Standards, v0.3*
(https://trackiq.apeiro-digital.com/partners/docs). A local copy of the full spec lives at
`/home/lkk2/Desktop/ppb.md` (not committed). This document maps that spec onto the current
ThamaniDawa codebase and gives a dev (or agent) everything needed to implement live event
submission correctly, plus manual test steps.

Status: **design/guide only — no EPCIS code exists in this repo yet.** Audited on branch
`kendi/distributor-flow` (2026-11-10).

---

## 1. What PPB requires of us

ThamaniDawa serves two PPB participant tiers, each with its own API key, scope and event set:

| Our portal | PPB tier | Events we must report |
| --- | --- | --- |
| Distributor portal + mobile scan app | Distributor / 3PL | Receiving, Pack, Unpack, Ship, Return Ship/Receive, Status updates (damaged/expired/stolen/lost/export), Stock adjustment, Recall–Destruction |
| Pharmacy / facility portal | Healthcare Facility / Dispenser | Receiving, Dispensing, Return Ship, Status updates |

We are **not** a manufacturer: we never send Commissioning events (a Distributor key is
rejected for them), and we never send the Regulator Approval event (`inspecting` +
`active` is PPB-only; trading partners are forbidden).

**Tier ≠ separate company.** Per spec §2.5 the API key is provisioned *per organisation
and per participant role*, scoped to a GLN prefix and tier. One org that both
distributes and dispenses is still one org — it holds one key per role. Our
`organizations.operating_models` already allows `[:distributor, :pharmacy]` together, so
each outbox event is stamped with its tier and the client picks the key per (org, tier).
Whether PPB onboarding issues both roles under one registration or requires registering
under each org type is unstated — confirm with PPB support (§9), the design works either
way.

Non-negotiable platform rules (from spec §1.2, §2.6.3, §6):

1. **EPCIS 2.0 JSON-LD** is the recommended format — use it exclusively. Plain CBV tokens
   (`shipping`, `in_transit`, `desadv`, `owning_party`) — full `urn:epcglobal:cbv:…` values
   are **rejected** in JSON-LD. No SBDH wrapper. Auth via `X-API-Key` header, HTTPS only.
2. Every event: `eventID` = `urn:uuid:<UUIDv4>` (idempotency key — **retries must reuse it**),
   `eventTime` in UTC ending `Z` (future time > 5 min = hard reject; > 7 days old =
   `STALE_EVENT_TIME` warning), `eventTimeZoneOffset` stated separately (`"+03:00"` for Kenya),
   `bizLocation` mandatory (facility-level SGLN), `bizTransactionList` mandatory on all
   shipment/receiving events (`desadv` → ASN/order number, `recadv` → goods-receipt number).
3. **Chronology:** inbound Receiving must be reported **before** any Pack/Ship of the same
   stock; events in one envelope must be oldest-first; resends must be the whole message,
   never fragments. Do not report intra-warehouse OBSERVE movements.
4. **Immutability:** accepted events can only be voided/corrected with a GS1 Error
   Declaration (§6.4) — same `eventID`, identical content, plus `errorDeclaration` block.
5. Dispensing is **synchronous** (HTTP 201/4xx, ≤ 1 MB). Everything else is async
   (HTTP 202, ≤ 10 MB, ≤ 50,000 EPCs/event). 207 = partial acceptance. 409 = duplicate
   eventID *or* duplicate payload fingerprint. 429 = back off exponentially
   (distributor budget 3,000–5,000 req/min — we will never approach it).
6. Hard rejects (HTTP 400) mean the event was **not stored** — must fix and resubmit with
   the *same* eventID. HTTP 201-with-`warnings[]` means stored but flagged — log the
   warnings, do not resubmit.

---

## 2. Current-state assessment

### What already exists and maps cleanly

| Codebase asset | EPCIS use |
| --- | --- |
| `ThamaniDawa.GS1Decoder` (AIs 01/10/11/17/21/414) | Source of GTIN+batch+serial+dates for every scanned unit → SGTIN EPCs |
| `ThamaniDawa.GS1.Sscc` — SSCC-18 allocation per org (`gs1_company_prefix` + atomic `next_sscc_serial`) | Parent IDs for Packing (AggregationEvent) and epcList for Shipping |
| `ThamaniDawa.Gtin` / `ExGtin` check-digit validation | Pre-validates before the Hub's `INVALID_*_CHECK_DIGIT` hard rejects |
| `Distributor.Shipment` (draft→submitted→approved) with `origin_gln`, `destination_gln`, `order_number`, snapshot addresses | Shipping ObjectEvent: source/destination parties, `desadv` reference |
| `Distributor.Shipper` (one SSCC per case, assigned at approval, contents snapshot) | Packing AggregationEvent: `parentID` = SSCC, `childEPCs` = item SGTINs |
| `Distributor.ShipmentItem` (per-unit scan: `gtin`, `serial`, `batch`, dates, raw DataMatrix) | Child SGTIN EPCs; serials come from the manufacturer's own barcode, i.e. already commissioned upstream |
| `Distributor.SerialReservation` + validation against received batches | Guards the spec's "ship only what you received" rule locally |
| `GoodsReceipts` (`GRN-000123` numbers, idempotent posting key, atomic batch posting) | `recadv` bizTransaction reference for Receiving events |
| `Distributor.ShipmentEvent` append-only audit trail | Natural hook points for emitting EPCIS events |
| `Organization.gs1_company_prefix` | Needed to split GTIN-14/SSCC-18/GLN-13 into EPC URN components |
| `req` ~> 0.5 already a dependency; `ThamaniDawa.VerifyGtin`/`GtinLookup` show the established pattern for an external GS1 API client with runtime env config | Template for the Hub client |

### Gaps (ranked by severity)

1. **No EPCIS code at all.** No event builder, no submission client, no outbox/queue, no
   idempotency store. Everything in §4 below is net-new.
2. **GLNs are self-minted and will not resolve in the national repository.**
   `ThamaniDawa.Gln.generate!/0` fabricates GLNs from a *globally configured* company
   prefix + random digits for sites, suppliers and distributor customers. The Hub
   validates SGLNs against pre-registered GLNs: every event carrying these will draw
   `UNKNOWN_SGLN` warnings, and receiving-side matching (`destinationList` of the prior
   shipping event vs the receiver's GLN) will never line up with what the customer's own
   systems report. **Real, PPB-registered GLNs must be captured for: each org site that
   ships/receives (bizLocation), each customer facility (destination), and each upstream
   supplier (source).** Self-minted GLNs can remain for internal routing, but the
   PPB-registered GLN must be a distinct, verified field.
3. **Inbound receiving is batch/quantity-level, not unit-level.**
   `DistributorReceivingLive` posts GTIN + batch + quantity into `batches`; it does not
   scan inbound SSCCs or per-unit serials (the `batches.serial` column is only populated
   by other paths). A spec-correct Receiving event needs the EPCs that the supplier's
   Shipping event declared — ideally the inbound **SSCC** scanned off the pallet/case
   label. Without it we can only send class-level/LGTIN quantity data, which the
   receiving flow does not support (receiving is EPC-based). → Receiving UI must capture
   at minimum the inbound SSCC(s), or per-unit SGTINs.
4. **Pharmacy dispensing is FEFO batch-quantity, not serialized.** `QuickSaleLive`
   allocates quantities across batches. The spec allows **class-level dispense**
   (`quantityList` with LGTIN + quantity, no epcList) — we can comply without
   serializing the counter, but the LGTIN needs GTIN + lot, which batches do carry.
   Serialized dispense can come later if PPB tightens this.
5. **No background job infrastructure** (no Oban, no custom GenServers). Async submission
   with retry/backoff needs an outbox table + a small worker (see §4.2).
6. **No sensor/cold-chain data captured** — fine; `sensorElementList` is optional and only
   constrains you *if* you include it. Out of scope for v1.

### Prior art check — gs1_admin (ErpLive, GS1 Kenya's ERP)

`~/Dev/projects/vumbuzi/gs1_admin` has **no EPCIS implementation** (EPCIS appears only in
marketing/course HTML) — nothing to reuse for event submission. Its **GLN handling**,
however, is the authoritative model to copy, because that system *is* GS1 Kenya's
member/licence ERP:

- **GLNs are allocated, not invented.** A member holds a GS1-licensed company prefix
  (`members.prefix`, length 7–11). A GLN is built by appending the next free numeric
  code within that prefix's capacity, zero-padded to 12 digits, plus an `ExGtin` check
  digit (`gs1_api_controller.ex: generate_gln/2`, `global.ex: generate_all_gln_codes/2`).
  The code space is **shared** with the member's GTIN barcodes and GSRNs — a code used
  for a barcode is never reissued as a GLN (`generate_gln_code/3` subtracts
  `Barcodes.get_filled_member/1` and existing GLNs; the backfill task skips members with
  "no free code left").
- **A GLN is only issued with real location data.** The backfill refuses members missing
  address, latitude, longitude, county, or country — a GLN row carries description
  (company), address, lat/long, postal, region, country. That metadata is what makes the
  GLN resolvable by other parties.
- **External GLN validation** uses the GS1 Global Registry Platform: unknown destination
  GLNs are POSTed to `https://grp.gs1.org/grp/v3.2/licences/GLN` (`ActivateApis.get_prefix!/2`)
  and the licensee name/address come back from the registry
  (`Global.GlnLookup.fetch_from_registry/1`). Registry outage degrades to "not found",
  never crashes a search.
- **Compliance in its distributor flow** mirrors what we need: shipment **origins** must
  be one of the member's *own* registered GLNs; **destinations** are locally registered
  GLNs first, with the GS1 registry consulted as fallback — the client never supplies
  address data, only a GLN that the server resolves (`Global.GlnLookup`).

**Implication for ThamaniDawa:** `ThamaniDawa.Gln`'s random-extension generation is the
wrong model and must not feed PPB events. Each tenant org needs its own GS1-licensed
prefix (obtained through GS1 Kenya — i.e. through the gs1_admin pipeline), its GLNs
allocated within that prefix's code space with location data, and foreign GLNs
(customers, suppliers) verified against the GS1 GRP registry — the same GRP API this
repo already calls for GTINs (`VerifyGtin`, `POST /grp/v3.2/gtins/verified`), so the
client pattern and API key handling already exist. Whether PPB's national repository
syncs from GS1's registry or requires separate GLN registration with PPB is an open
question (§9).

---

## 3. Identifier construction (the part everyone gets wrong)

All EPC URNs require splitting a digit string into company prefix + reference using the
**owner's actual GS1 Company Prefix length**. Use `organizations.gs1_company_prefix` for
identifiers we minted; for *scanned* manufacturer SGTINs we do not know the brand owner's
prefix length — see the SGTIN note below.

| Identifier | Digit form | EPC URN | Construction |
| --- | --- | --- | --- |
| SGTIN | GTIN-14 `d1 d2…d13 d14` + serial | `urn:epc:id:sgtin:CompanyPrefix.ItemRef.Serial` | ItemRef = indicator digit (GTIN digit 1) **prepended** to the item reference (digits after the company prefix, before the check digit). Check digit (digit 14) dropped. `CompanyPrefix` + `ItemRef` together = 13 digits. Serial is taken verbatim from AI(21). |
| SSCC | 18 digits | `urn:epc:id:sscc:CompanyPrefix.SerialRef` | SerialRef = extension digit (digit 1) prepended to the serial reference. Check digit dropped. Together = 17 digits. Our own SSCCs: prefix = org's `gs1_company_prefix`, extension digit is `0` (see `GS1.Sscc.build_sscc/2`). |
| SGLN | GLN-13 | `urn:epc:id:sgln:CompanyPrefix.LocationRef.0` | Check digit dropped; prefix + location ref = 12 digits; extension `0` for facility-level. |
| LGTIN | GTIN-14 + lot | `urn:epc:class:lgtin:CompanyPrefix.ItemRef.Lot` | Same GTIN split as SGTIN; lot from AI(10). |

**SGTIN prefix-length problem for scanned units:** the correct split of a foreign GTIN
needs the brand owner's prefix length (6–12 digits). Options, in order of preference:
(a) resolve via GS1 GEPIR/Verified-by-GS1 data we already fetch in `GtinLookup` (the GRP
response carries licence info); (b) store a per-product `gs1_prefix_length`
on `products` populated at catalogue time; (c) default to a 7-digit split and accept
`UNKNOWN_SGTIN`-class warnings. Do **not** guess silently — record which strategy
produced each URN. The Hub validates check digits hard (reject) but prefix split only
soft (registry match warnings), so a wrong split is recoverable; a dropped/mangled digit
is not.

Build a dedicated module `ThamaniDawa.Epcis.Urn` with pure functions + doctests:
`sgtin(gtin14, serial, prefix_length)`, `sscc(sscc18, prefix_length)`,
`sgln(gln13, prefix_length)`, `lgtin(gtin14, lot, prefix_length)`.

---

## 4. Target architecture

Follow the existing codebase conventions: contexts own logic, everything transactional,
runtime config from env in `config/runtime.exs` (same pattern as `GtinLookup`).

### 4.1 New modules

```
lib/thamani_dawa/epcis/
  urn.ex            # §3 — pure URN construction, doctested
  event.ex          # builds EPCIS 2.0 JSON-LD event maps (one fun per event type)
  document.ex       # wraps events (oldest-first) into an EPCISDocument envelope
  outbox_event.ex   # Ecto schema — persisted event + submission state
  outbox.ex         # enqueue (inside the business transaction), claim, mark result
  client.ex         # Req-based POST to the Hub; X-API-Key; classifies responses
  worker.ex         # GenServer: drains outbox serially per org, backoff on failure
```

### 4.2 Outbox pattern (mandatory, not optional)

Events must be (a) created atomically with the business write that triggers them,
(b) submitted in chronological order per organization, (c) retried with the **same
eventID**, (d) never lost. That is exactly a transactional outbox:

```
create table epcis_outbox_events (
  id bigserial primary key,
  organization_id references organizations not null,
  event_id uuid not null,                -- the EPCIS eventID (without urn:uuid: prefix)
  event_type text not null,              -- "receiving" | "packing" | "shipping" | "dispensing" | ...
  participant_tier text not null,        -- "distributor" | "facility" → selects API key
  payload jsonb not null,                -- the full event object (not the envelope)
  occurred_at timestamptz not null,      -- eventTime; ordering key within org
  status text not null default 'pending',-- pending | submitted | accepted | warning | rejected | dead
  http_status integer,
  response jsonb,                        -- warnings[] / error body for audit
  attempts integer not null default 0,
  next_attempt_at timestamptz,
  source_type text, source_id bigint,    -- e.g. ("shipment", 42) / ("goods_receipt", 7)
  inserted_at / updated_at
)
unique index on (event_id)
index on (organization_id, status, occurred_at)
```

Worker rules:

- Drain **per organization in `occurred_at` order**; never submit event N+1 while N is
  still `pending`/retrying (preserves the spec's chronological-order rule).
- `202`/`201` → `accepted` (store any `warnings[]` and surface them in an admin view —
  warnings are compliance debt, e.g. `UNKNOWN_SGLN`, `RECEIVING_WITHOUT_SHIPPING`).
- `400` → `rejected`: do **not** auto-retry (payload is wrong); alert, fix, resubmit
  manually with the same eventID.
- `409` → the event already made it (earlier timeout) → mark `accepted`.
- `429`/`5xx`/network → exponential backoff (`next_attempt_at`), attempts capped, then
  `dead` + alert. Backoff never reorders: the org's queue is head-blocked by design.
- Dispensing: same outbox, but the UI may optionally await the synchronous result
  (v1: fire-and-record is acceptable; the Hub's sync validation is their patient-safety
  concern, our sale already completed locally).

**Decision (2026-11-10): use Oban** for the submission worker (first job runner in this
repo — add `{:oban, "~> 2.18"}`, its migration, and the supervisor child). The outbox
table above still exists and remains the source of truth; Oban only *drives* it. Because
Oban does not guarantee cross-job ordering, do **not** enqueue one job per event:
enqueue a single **unique job per organization** (`unique: [keys: [:organization_id]]`)
whose perform drains that org's pending outbox rows in `occurred_at` order and reschedules
itself on retryable failure. This preserves chronology while getting Oban's supervision,
backoff and dashboard for free.

### 4.3 Configuration (runtime.exs)

```elixir
config :thamani_dawa, ThamaniDawa.Epcis.Client,
  base_url: System.get_env("PPB_TNT_BASE_URL"),          # provided later — not a blocker
  capture_path: System.get_env("PPB_TNT_CAPTURE_PATH", "/epcis/v2/capture"), # confirm when URL arrives
  api_key: System.get_env("PPB_TNT_API_KEY"),
  enabled: System.get_env("PPB_TNT_ENABLED", "false") == "true"
```

**Key model (decided 2026-11-10): one platform-level key.** This system is operated by
GS1 (Kenya); events for all tenant orgs are submitted under **GS1's own API key(s)** —
a service-provider model, not per-tenant keys. So: a single `PPB_TNT_API_KEY` env var,
no per-org key storage, regardless of how many orgs onboard. The `participant_tier`
column stays on the outbox (it documents which role an event belongs to and leaves the
door open), but key selection is a constant. One thing to confirm with PPB when the key
arrives: that a GS1 service-provider key is accepted for events whose identifiers sit
under the *tenant orgs'* GLN prefixes (the spec says keys are "scoped to a specific GLN
Prefix" — verify the scoping accommodates submission-on-behalf before bulk go-live;
T0/T2 in §8 will surface it immediately if not).

The capture URL arriving later is **not** an implementation blocker: everything through
§6 step 9 is buildable and testable offline (builders are pure; the client is stubbed in
tests); only §8's live tests need the URL and key.

`enabled: false` must be a complete no-op (enqueue still happens; worker idles) so the
distributor flow keeps working before go-live. Rotate the key annually per spec.

### 4.4 Schema additions & GLN/onboarding model

**GLN division of labour (decided 2026-11-10): gs1_admin generates, ThamaniDawa
verifies.** This system never allocates GLNs. GLNs are issued in gs1_admin (within the
org's licensed prefix, with location data); here they are *entered* and *verified*
against the GS1 GRP registry (`POST /grp/v3.2/licences/GLN`, same call shape as
gs1_admin's `ActivateApis.get_prefix!/2` and this repo's existing `VerifyGtin`).
`ThamaniDawa.Gln.generate!/0` is retired from any PPB-relevant path.

**Onboarding flow (decided 2026-11-10):** at org onboarding the admin enters the
company's **GS1 company prefix**; the system calls the GRP licences API (as gs1_admin's
`ActivateApis` does) to fetch the licensee's verified company details and prefills the
org record. The prefix lands in `organizations.gs1_company_prefix` (already exists) —
per-org, no global config.

Schema changes:

- `sites`, `distributor_customers`, `suppliers`: `gln` becomes an entered, GRP-verified
  value (add `gln_verified_at` + verification source). Event building **refuses** (holds
  the event `blocked` with a visible reason, never fabricates) when a required GLN is
  missing or unverified.
- `products`: `gs1_prefix_length` (nullable; see §3), populated from the GRP licence
  lookup at catalogue time.
- Receiving capture: optional inbound `sscc` per goods-receipt line (SSCC path of D1);
  absent SSCC → class-level fallback, no new capture needed.
- `products.uom` mapping to UNECE Rec 20 codes (`EA` etc.): derive the mapping from the
  distinct values currently in the column (implementation task, not a question).

---

## 5. Event mapping — internal trigger → EPCIS event

All JSON-LD, all with `@context: ["https://ref.gs1.org/standards/epcis/epcis-context.jsonld"]`
at the envelope, `eventTimeZoneOffset: "+03:00"`, `bizLocation` = SGLN URN of our PPB
site GLN, short CBV tokens throughout. "Org prefix" = `organizations.gs1_company_prefix`.

### 5.1 Distributor tier

| # | Trigger in code | EPCIS event | Key fields |
| --- | --- | --- | --- |
| D1 | `GoodsReceipts.receive_delivery/4` success (new receipt posted) | **Receiving** — ObjectEvent, OBSERVE, bizStep `receiving`, disposition `active` | `epcList`: inbound SSCC(s) scanned at the dock when the case label carries one; **fallback (decided 2026-11-10)** when it doesn't: class-level `quantityList` with the LGTIN (GTIN + lot) and received quantity — i.e. exactly the GTIN + batch + qty the receiving form already captures, no per-unit scanning required. `bizTransactionList`: `{type: "recadv", bizTransaction: "urn:epcglobal:cbv:bt:<orgprefix>:GRN-000123"}`. `sourceList`: `owning_party` = supplier's SGLN. `destinationList`: `owning_party` = our org SGLN. `RECEIVING_WITHOUT_SHIPPING` warnings are expected until upstream partners report — accepted, not an error. |
| D2 | `Distributor.approve_shipment/3`, inside `issue_ssccs!/1` (one event **per shipper**, after SSCC assignment) | **Packing** — AggregationEvent, ADD, bizStep `packing`, disposition `active` | `parentID`: shipper SSCC URN. `childEPCs`: SGTIN URNs of the shipper's items. `eventTime` = `sscc_assigned_at`. All children same bizLocation (true by construction — one origin site per shipment). Max depth 3 — we use 2 (item→case), fine. |
| D3 | Same approval transaction, **after** all D2 events (chronology!) | **Shipping** — ObjectEvent, OBSERVE, bizStep `shipping`, disposition `in_transit` | `epcList`: **shipper SSCCs only — never the child SGTINs** (`INVALID_PARENT_CHILD_RELATION` otherwise). `bizTransactionList`: `{type: "desadv", bizTransaction: "urn:epcglobal:cbv:bt:<orgprefix>:<order_number>"}`. `sourceList`: `owning_party` = origin site SGLN. `destinationList`: `owning_party` **and** `location` = customer's PPB SGLN. `eventTime` strictly ≥ every D2 eventTime (use assignment time + 1s or ordered timestamps). |
| D4 | Future: unpack/repack flows (not in current UI) | **Unpack** — AggregationEvent, DELETE, `unpacking`/`active`; partial allowed | Only when we physically break a received SSCC to pick units. Required before shipping loose SGTINs out of a received SSCC, and before unit-level damage reporting inside a case. |
| D5 | Future: returns to supplier | **Return Shipping** — ObjectEvent, OBSERVE, `shipping`/`returned`; then counterpart Return Receiving when we take goods back from customers (`receiving`/`returned` → QA → `active` or damage/destroy chain) | `bizTransactionList`: `desadv` + RMA reference. Source/destination inverted vs forward flow. |
| D6 | Future: write-offs | **Damaged** (`inspecting`/`damaged`), **Expired** (`inspecting`/`expired`), **Lost** (`decommissioning`/`inactive`), **Stolen** (`decommissioning`/`stolen`), **Export** (`decommissioning`/`non_sellable_other`) | Submit only for EPCs in our possession. Damaged SSCC quarantines all children; unit-level damage inside a case requires D4 first. `bizTransactionList` with `cert` + internal quality/incident reference. |
| D7 | Future: periodic stock count | **Stock adjustment** — ObjectEvent, OBSERVE, `stock_taking`/`active` | `bizTransactionList`: `{type: "upevt", bizTransaction: "urn:kenya-tnt:stockcount:<session>"}` — stable session id per count cycle. |

v1 scope = **D1 + D2 + D3**. D4–D7 have no triggering UI yet; build them when those
flows exist, the outbox/builder make each a small addition.

### 5.2 Facility tier (pharmacy portal)

| # | Trigger | EPCIS event | Key fields |
| --- | --- | --- | --- |
| F1 | `ReceiveStockLive` / `Batches.receive_batch` (site receives stock) | **Receiving** — as D1 but facility key, `recadv` = internal receipt ref, bizLocation = site SGLN | Same SSCC-capture gap applies. |
| F2 | `QuickSaleLive` sale completion / prescription dispense | **Dispensing** — ObjectEvent, OBSERVE, `dispensing`/`dispensed`, **synchronous** | Default **class-level**: no `epcList`; `quantityList: [{epcClass: <LGTIN urn from batch gtin+batch_no>, quantity: n, uom: "EA"}]` per FEFO-allocated batch line. When a dispensed unit's serial *is* known (scanned, or the batch row carries one), include its SGTIN in `epcList` and reduce the class-level quantity accordingly (the spec's **mixed dispense**). Serials are **not required** — many products carry no AI(21). Never SSCCs. ≤ 1 MB. |

**Decision (2026-11-10, revised):** both tiers are in scope, phased — build and prove
**D1–D3 (receiving, packing, shipping) first**; facility F1–F2 follow. D4–D6
(returns/damage/destruction) are explicitly deferred. PPB registration is already done;
the API key and capture URL arrive when live testing starts (not a build blocker).

### 5.3 Events we must never send

- **Commissioning** (manufacturer-only; our key would be rejected).
- **Regulator Approval** (`inspecting` + `active` with `cert`): PPB-only, forbidden.
- Intermediate warehouse OBSERVE movements (explicitly disallowed, §1.2).
- Recall **initiation** is regulator-driven; we only ever send the **Destruction
  Completion** (`destroying`/`destroyed`, bizLocation = the *destruction facility's*
  GLN, preceded by the recall/damage/expiry status chain).

### 5.4 Worked example — D3 Shipping for an approved shipment

Org prefix `6291234`, origin site PPB GLN `6291234000017`, customer PPB GLN
`6164000000224` (customer prefix length unknown → their party GLN still formats as SGLN
with *their* split; if unknown, use GS1 Kenya's published licence data — same resolution
strategy as §3, and the same warning-not-reject risk applies):

```json
{
  "type": "ObjectEvent",
  "eventID": "urn:uuid:8b2f91a4-c5d6-43e7-b901-2a3b4c5d6e7f",
  "eventTime": "2026-11-10T08:30:00.000Z",
  "eventTimeZoneOffset": "+03:00",
  "epcList": ["urn:epc:id:sscc:6291234.0000000123"],
  "action": "OBSERVE",
  "bizStep": "shipping",
  "disposition": "in_transit",
  "readPoint": { "id": "urn:epc:id:sgln:6291234.00001.0" },
  "bizLocation": { "id": "urn:epc:id:sgln:6291234.00001.0" },
  "bizTransactionList": [
    { "type": "desadv", "bizTransaction": "urn:epcglobal:cbv:bt:6291234:PO-2026-0144" }
  ],
  "sourceList": [
    { "type": "owning_party", "source": "urn:epc:id:sgln:6291234.00001.0" }
  ],
  "destinationList": [
    { "type": "owning_party", "destination": "urn:epc:id:sgln:6164000.00022.0" },
    { "type": "location",     "destination": "urn:epc:id:sgln:6164000.00022.0" }
  ]
}
```

Envelope: `{"@context": [...], "type": "EPCISDocument", "schemaVersion": "2.0",
"creationDate": "<now UTC Z>", "epcisBody": {"eventList": [ ...oldest first... ]}}`.

---

## 6. Implementation plan (ordered)

1. **`Epcis.Urn`** — pure, doctested (§3). Includes check-digit verification on input
   (reuse `ExGtin` / `GS1.Sscc.mod10_check_digit/1`) so bad identifiers fail at build
   time, not as Hub 400s.
2. **Migration pack** — outbox table (§4.2) + `ppb_gln` columns (§4.4) + inbound SSCC
   capture column. Append-only migrations; never edit applied ones (see
   `.engineering/project_memory.md` for the incident that rule comes from).
3. **`Epcis.Event` / `Epcis.Document`** — builders returning plain maps; unit tests
   assert exact JSON against the spec's samples (tokens not URNs, field order
   irrelevant in JSON, arrays for `@context`/`eventList`, no trailing data).
4. **`Epcis.Outbox`** — `enqueue/2` called *inside* the triggering `Repo.transaction`
   (goods receipt / shipment approval). Enqueue is unconditional; submission is gated
   by config + org onboarding state.
5. **Hook triggers** — D1 in `GoodsReceipts.create_and_post/4`; D2+D3 in
   `Distributor.approve_shipment/3` after `issue_ssccs!/1` (events get monotonically
   increasing `occurred_at`: receipts < packs < ship).
6. **`Epcis.Client`** — Req, `X-API-Key`, JSON, 30 s timeout, response classifier
   returning `{:accepted, warnings} | {:rejected, body} | {:duplicate} | {:retry, reason}`.
7. **`Epcis.Worker`** — supervised GenServer per §4.2; add to `application.ex` children.
8. **Receiving UI change** — inbound SSCC scan field on `DistributorReceivingLive`
   (one per delivery line; optional in UI but its absence blocks D1 from `pending` →
   it sits `blocked` with a visible reason).
9. **Admin visibility** — a distributor-portal LiveView listing outbox rows with
   status/warnings/attempts and a "resubmit" action for `rejected` (same eventID).
   Warnings are regulatory debt; make them impossible to miss.
10. **Facility phase** — F1/F2 after distributor flow is proven in the PPB test env.

Testing conventions: follow existing patterns (`DataCase`/`ConnCase`, fixtures);
`Epcis.Client` behind a behaviour + Mox (or a `Req.Test` stub) so worker tests run
offline. Live validation before review per the pre-review checklist memory.

---

## 7. Error handling decisions

| Hub response | Our action |
| --- | --- |
| 201 no warnings / 202 | mark `accepted` |
| 201 + `warnings[]` | mark `warning`, persist warnings, surface in admin UI. Specific expected ones: `RECEIVING_WITHOUT_SHIPPING` (upstream didn't report — tolerate), `UNKNOWN_SGTIN`/`UNKNOWN_SGLN` (registration gap — chase operationally), `EXPIRING_SOON` (informational) |
| 207 | parse per-event breakdown; accepted events marked, rejected ones → `rejected` individually |
| 400 | `rejected`; no auto-retry; alert. Resubmit (same eventID) only after a code/data fix |
| 401/403 | pause the org's queue, alert — key problem, retrying is pointless |
| 409 | treat as success (duplicate eventID or payload fingerprint ⇒ already stored) |
| 413 | split the envelope (shouldn't occur at our volumes; guard: ≤ 1,000 events/envelope) |
| 429, 5xx, timeout | exponential backoff from 30 s, cap 1 h, max ~50 attempts → `dead` + alert |

Corrections: build a small `Epcis.Event.error_declaration/2` that clones a stored
payload, injects `errorDeclaration` (`declarationTime` > original `eventTime`, reason
`did_not_occur` or `incorrect_data` + `correctiveEventIDs`), and enqueues it. Needed the
first time an approved shipment turns out to be wrong after submission — don't ship v1
without it, immutability makes it the *only* undo.

---

## 8. Manual test plan (PPB test environment)

Prerequisites: onboarding complete via the Partner Portal (register → credentials →
test-execution stage); `PPB_TNT_BASE_URL` + distributor `X-API-Key` for the **test**
environment; at least our org GLN, one warehouse site GLN, one customer facility GLN
registered with PPB; `gs1_company_prefix` set on the org; `PPB_TNT_ENABLED=true` in the
dev/staging env only.

**T0 — connectivity & auth.** `curl` the capture endpoint with an intentionally empty
JSON body and the API key: expect a 400 (`MISSING_EPCIS_BODY`), **not** 401. With a
wrong key: expect 401. With `http://`: expect rejection. This validates key, URL, TLS.

**T1 — URN correctness (offline).** In IEx: build SGTIN/SSCC/SGLN URNs for a known
scanned DataMatrix and the org's own SSCC; manually verify digit counts (13 total for
sgtin prefix+itemref, 17 for sscc, 12 for sgln) and that check digits were dropped.
`mix test` the doctests.

**T2 — Receiving (D1).** In the distributor portal, receive a delivery with an inbound
SSCC scanned. Confirm: one outbox row, `event_type: "receiving"`, payload has
`bizStep: "receiving"`, `disposition: "active"`, `recadv` = the GRN number, epcList =
the scanned SSCC URN. Worker submits → expect 202 (or 201+`RECEIVING_WITHOUT_SHIPPING`
warning if the test env has no upstream shipping event — that warning **is the pass
condition** for an unannounced SSCC). Verify status + stored response in the admin view.

**T3 — Pack + Ship (D2, D3).** Mobile flow: create shipment (origin = GLN-registered
warehouse, destination = GLN-registered test customer), scan ≥ 2 units into each of 2
shippers (units previously received in T2's batch so validation passes), submit,
approve in the portal. Confirm: outbox has 2 packing events + 1 shipping event, in that
`occurred_at` order; packing `parentID`s match the shippers' assigned SSCCs; shipping
`epcList` contains **only** the 2 SSCCs; `desadv` = the order number. Worker submits all
three in order → 202s. In the Hub/partner portal (if the test env exposes a trace view),
confirm the SSCCs show disposition `in_transit`.

**T4 — chronology guard.** Stop the worker, approve a shipment, then also post a goods
receipt. Restart worker: events must go out in `occurred_at` order and the receiving
event of *new* stock must not interleave into the earlier shipment's sequence.

**T5 — idempotency.** Kill the worker mid-submit (after the HTTP request, before the DB
update), restart: the resubmission must reuse the same `eventID` and the 409 must be
treated as success — outbox ends `accepted`, no duplicate event in the Hub.

**T6 — hard-reject handling.** Temporarily corrupt a payload in the outbox (e.g. strip
`bizTransactionList` from a pending shipping event via SQL), let the worker submit:
expect 400 `MISSING_NEEDED_FIELDS`-class rejection, row → `rejected`, queue for that org
halts behind it (verify the *next* pending event did not jump the line), alert visible.
Restore payload, resubmit, confirm recovery.

**T7 — error declaration.** Void T3's shipping event: submit the same payload + eventID
with `errorDeclaration{reason: "did_not_occur"}` → expect 201. Then re-ship with a new
event. Confirm the Hub accepts both (the only legal same-eventID case).

**T8 — dispensing (facility phase only).** Complete a quick sale; confirm the sync 201
and that a class-level `quantityList` dispense with LGTIN of the FEFO batch was sent;
try dispensing a quantity from a lot the Hub knows is recalled/expired in the test env
and record how the 400-level response is surfaced.

Each test: record request/response pairs (the outbox `response` column is the audit
trail) — PPB's test-execution stage will ask for evidence of exactly these scenarios.

---

## 9. Decisions log & open questions

Decided 2026-11-10 (product owner):

- **Oban** is added for async submission (§4.2) — the outbox stays, Oban drives it.
- **v1 scope = both tiers**: distributor (D1–D3) *and* facility (F1–F2). One org can be
  both; one API key per role (§1).
- **PPB registration already done**; API keys will be issued when testing starts.
- **Dispensing is class-level by default**; SGTINs included only when a serial happens
  to be known (mixed dispense). Serials never required — many products lack AI(21).
- **GLN model follows gs1_admin**: licensed-prefix allocation with location data +
  GRP registry verification, not random generation (see §2 prior-art section).
- **PPB ingests GS1-registered GLNs/GTINs automatically** — no separate PPB master-data
  registration step; GS1-side registration is what clears `UNKNOWN_SGLN`/`UNKNOWN_SGTIN`.
- **Every org holds its own GS1 Kenya licence; company prefix is per-org.**
  Consequence: `ThamaniDawa.Gln`'s single global `company_prefix` app-config is wrong
  and must be replaced by per-org allocation off `organizations.gs1_company_prefix`
  (gs1_admin-style: sequential code in the prefix space, shared with GTIN/SSCC
  allocations, location data required, check digit via ExGtin).
- **Inbound receiving supports both scenarios**: SSCC scan when the label has one;
  SGTIN-scan or class-level LGTIN fallback when it doesn't (see D1).

Further decisions 2026-11-10 (second round, product owner):

- **One API key** (GS1's own — service-provider model, §4.3); per-role keys dropped.
- **Capture URL arrives later** — not a blocker; config-only.
- **v1 events = Receiving, Packing, Shipping** (D1–D3). Returns, damage and destruction
  (D4–D6) explicitly deferred. Facility events (F1–F2) follow once D1–D3 are proven.
- **No-SSCC receiving = GTIN + batch + quantity** (class-level LGTIN) — exactly what the
  receiving form captures today.
- **Testing runs locally.** Several orgs may onboard; all submit under GS1's key.
- **UoM mapping**: derive from current `products.uom` values — implementation task.
- **Onboarding**: org enters its GS1 company prefix → company details prefetched from
  Verified by GS1 (GRP licences API, as in gs1_admin's `ActivateApis`) — §4.4.
- **GLNs generated in gs1_admin only; this system verifies** (GRP lookup) — §4.4.

Still open (none block the build):

1. **Capture endpoint URL** — pending from PPB; blocks only §8 live tests.
2. **Service-provider key scoping** — confirm GS1's key is accepted for events under
   tenant orgs' GLN prefixes (spec ties keys to a GLN prefix). T0/T2 surface this on
   day one of live testing.
3. **Partner GLN data entry** — operational: who backfills real GLNs for existing
   suppliers/customers before go-live (events for partners without verified GLNs sit
   `blocked`).
