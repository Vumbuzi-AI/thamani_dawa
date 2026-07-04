# Thamani Dawa — Build TODOs

Derived from `project.md`. Nothing in this repo yet implements Thamani Dawa — this is a fresh
Phoenix project (see [§1](project.md#1-project-setup-proposed)), so Phase 1 starts from
`mix phx.new`. Checklist follows the phases in [§10](project.md#10-roadmap).

Numbering is `Phase.Item` (e.g. `1.4`) — reference these when directing work.

## Phase 0 — Project scaffold

- [ ] **0.1** `mix phx.new thamani_dawa --live`
- [ ] **0.2** Add deps from §1: `bcrypt_elixir`, `ex_gtin`, `scrivener_ecto`, `live_select`, `csv`,
      `swoosh`, plus standard Phoenix/LiveView/Ecto/Postgrex/Tailwind/esbuild/Jason/Credo
- [ ] **0.3** Configure GS1 registry credentials (GS1 Kenya `create_gtin` API or GS1 Global Registry
      Platform) via `config/runtime.exs` + env vars — never hardcoded (§3)

## Phase 1 — MVP (single-site, no requisitions)

### Multi-tenancy foundation (§2)
- [x] **1.1** `organizations` schema (`name`, `slug`, `license_number`, `is_active`)
- [ ] **1.2** `organization_id` + `NOT NULL` + index on every tenant table (see full list in §2.2)
      — done for `users`, `sites`, `products`, `suppliers`, `batches`, `patients`, `prescriptions`,
      `prescription_items`, `dispensed_items`, `pharmacy_logs`, `dangerous_drug_registers`,
      `lab_tests`, `lab_test_categories`, `lab_test_templates`, `lab_orders`, `lab_order_tests`,
      `lab_consumable_usage`, `scan_events`, `quality_assurance_charts`; tick fully once the
      remaining requisition tables (2.1-2.3) land
- [x] **1.3** `on_mount` hook resolving `current_user` → `current_organization_id`; every context
      function takes `organization_id` as first arg and filters on it
- [x] **1.4** Per-organization unique constraints (`products` on `gtin` — done; `lab_test_templates`/
      `lab_test_categories` on `name` — done; `pharmacy_logs` on
      (`organization_id`, `log_type`, `month`, `year`) — done; `dangerous_drug_registers` on
      (`organization_id`, `product_id`, `month`, `year`) — done; `quality_assurance_charts` on
      (`organization_id`, `chart_type`, `month`, `year`) — done) — **not** global uniqueness
- [x] **1.5** Global uniqueness kept only for `sites.gln` and `users.email`

### Signup & accounts (§2.3, §7)
- [x] **1.6** Org signup transaction: `organizations` row + `users` (`role: "admin"`) + default `sites`
      row, all in one transaction — `Organizations.signup/2`
- [x] **1.7** `users` schema: `organization_id`, `site_id` (nullable), `name`, `email`, `hashed_password`,
      `role` (`admin` \| `pharmacist` \| `lab_technician`), `pin`, `invited_by_id`, `is_active`
- [x] **1.8** `user_tokens` schema (`session` \| `invite` \| `reset_password` contexts), reusing the
      Medic `Accounts.UserToken` shape — email-context tokens (`invite`/`reset_password`) are hashed
      before storage; `reset_password` delivery/accept flow itself is left for a future
      forgot-password feature, not part of signup/invite
- [x] **1.9** Team screen: admin invites staff by name/email/role/home site → unconfirmed `users` row +
      invite email with one-time token — `Accounts.invite_user/3` + `UserNotifier`; the actual Team
      LiveView is tracked separately at 1.34
- [x] **1.10** Password + 4-digit PIN secondary auth for counter-side actions — `Accounts.set_user_pin/2`,
      `Accounts.valid_pin?/2`
- [x] **1.11** Role-based access per §7 table (`admin` / `pharmacist` / `lab_technician`) —
      `Accounts.Scope.admin?/1` etc., `UserAuth.on_mount(:require_admin, ...)`

### Catalog & stock (§4.1)
- [x] **1.12** `products` schema
- [x] **1.13** `suppliers` schema
- [x] **1.14** `sites` schema (`site_type`: `pharmacy` \| `lab` \| `warehouse`, globally-unique `gln`)
      — `gln` population itself waits on the GS1 registry work (1.16-1.18)
- [x] **1.15** `batches` schema — one unified table for drug + lab reagent stock, with
      `source_batch_id` self-reference for transfer lineage (even though transfers are Phase 2,
      model the column now)

### GS1 handling (§3)
- [x] **1.16** `GS1Decoder` module: parse AI `01` (GTIN), `10` (batch/lot), `11` (production date), `17`
      (expiry date), `21` (serial number)
- [x] **1.17** Wire up `ex_gtin` for GTIN validate/normalize/generate
- [x] **1.18** GLN-based site lookup: scanning AI-`414` resolves to a `sites` row (§9 "GLN site lookup")


### Patients (§4.2)
- [x] **1.19** `patients` schema, scoped to organization (not site)

### Pharmacy dispensing (§4.3, §9)
- [x] **1.20** `prescriptions` schema
- [x] **1.21** `prescription_items` schema
- [x] **1.22** `dispensed_items` schema — enforce batch must be at the prescription's own `site_id`
      — enforced by `Batches.fefo_batch/3`, which only ever considers batches at that site
- [x] **1.23** Dispense workflow: create prescription → pick batch (FEFO) → record dispensed_items →
      scan-to-verify → `is_verified: true` — `Prescriptions.dispense_item/5` (FEFO pick + stock
      decrement + status rollup, all in one transaction) and
      `Prescriptions.verify_dispensed_item/3` (GS1 scan match)
- [x] **1.24** `pharmacy_logs` schema (site-scoped cold-chain logs)
- [x] **1.25** `dangerous_drug_registers` schema (site-scoped controlled-substance register)

### Laboratory / LIS (§4.4, §9)
- [x] **1.26** `lab_tests` schema — `ThamaniDawa.LabTests`
- [x] **1.27** `lab_test_categories` / `lab_test_templates` schemas (`field_definitions` for templated
      results) — `ThamaniDawa.LabTestTemplates`, `field_definitions` as an `embeds_many` of
      `LabTestTemplates.FieldDefinition` (`key`/`label`/`unit`/`data_type`/`low`/`high`)
- [x] **1.28** `lab_orders` schema — `ThamaniDawa.LabOrders`
- [x] **1.29** `lab_order_tests` schema with auto-flag computation against template reference ranges
      — `LabOrders.record_result/4` + `LabTestTemplates.compute_results/2`
- [x] **1.30** Second-technician verification flow → `lab_orders.status` moves to `verified` —
      `LabOrders.verify_lab_order_test/3` (rejects `:same_technician`, rolls the header status up)
- [x] **1.31** `lab_consumable_usage` schema, drawing from `batches` — `LabOrders.record_consumable_usage/5`

### Traceability (§4.6)
- [x] **1.32** `scan_events` schema (`receipt` \| `dispense` \| `lab_consumption` \| `transfer_out` \|
      `transfer_in`)


### Base LiveViews — Phase 1 scope (§8)
- [x] **1.33** Sign up — `ThamaniDawaWeb.SignupLive` (`/signup`), plus supporting `SessionController`
      (`/login`, `/logout`) and `AcceptInviteLive` (`/invites/:token`), neither itemized in §8 but
      required for signup/invite to be usable end to end
- [x] **1.34** Team — `ThamaniDawaWeb.TeamLive.Index` (`/org/team`)
- [x] **1.35** Sites — `ThamaniDawaWeb.SiteLive.Index` (`/org/sites`)
- [x] **1.36** Pharmacy: Dashboard, Scan, Product catalog, Receive stock, Prescriptions, Dangerous drug
      register, Pharmacy logs — all under `/pharmacy`, gated by `:require_pharmacy_access`
- [x] **1.37** Lab: Dashboard, Scan, Lab orders (worklist), Result entry, Verification queue, Test
      templates & categories, Receive stock/consumables, Quality assurance — all under `/lab`,
      gated by `:require_lab_access`; `quality_assurance_charts` schema/context added (was missing
      despite being in §4.4) and `PharmacyLogs`/`DangerousDrugRegisters` gained `record_daily_entry`/
      `record_entry` to actually append to a month's log/register

## Phase 2 — Multi-site support

- [ ] **2.1** `stock_requisitions` schema (§4.5)
- [ ] **2.2** `stock_requisition_items` schema
- [ ] **2.3** `stock_transfers` schema — decrement source batch, create/top-up destination batch with
      lineage via `source_batch_id`
- [ ] **2.4** Requisitions screen, gated on `count(organization.sites) > 1` (not a feature flag)
- [ ] **2.5** Requisition → transfer workflow end-to-end (§9), including optional scan-verify at both
      ends (`transfer_out` / `transfer_in` scan events)
- [ ] **2.6** Confirm `pharmacy_logs`, `dangerous_drug_registers`, `quality_assurance_charts` are
      site-scoped once multiple sites exist
- [ ] **2.7** Low-stock / near-expiry alerting per site (Swoosh emails)
- [ ] **2.8** Postgres Row-Level Security policies keyed on `organization_id` (defense in depth)

## Phase 3 — Future (not required now)

- [ ] **3.1** AI-assisted lab interpretation
- [ ] **3.2** SSCC-based logistics tracking for larger transfers
- [ ] **3.3** GDSN master-data sync
- [ ] **3.4** Schema-per-tenant migration path (only if a customer requires physical data isolation)
- [ ] **3.5** Platform-level support/ops role across organizations

## Open questions to resolve along the way (§11)

- [ ] **4.1** Does requisition approval need a dedicated role beyond `admin`/`pharmacist`?
- [ ] **4.2** Does `patients` need a stable external identifier, or is name+phone matching enough?
- [ ] **4.3** Do prescriptions/lab orders need a structured internal prescriber (doctor role)?
- [ ] **4.4** Will a user ever need to belong to more than one organization?
- [ ] **4.5** Do Thamani Dawa's own operators need a platform-level cross-org view for support/billing?
