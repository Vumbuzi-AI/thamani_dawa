# Workflows

> **Current-state correction (2026-10-28):** the detailed sections below are retained only
> as a historical snapshot and are superseded by the implementation review in
> [the manual test playbook](MANUAL_TEST_PLAYBOOK.md) and
> [the real-world gap analysis](REAL_WORLD_WORKFLOW_GAP_ANALYSIS.md). In particular, the
> current application now implements central organization stock, partial dispatch, site
> receipt, requisitions, patient visits, quick sales, payments, pooled
> specimens, specimen receipt/rejection, consumable usage, and result amendments. It does
> **not** currently route controlled-drug registers, pharmacy logs, QA charts, test-template
> pages, or a standalone result-verification queue. Use the router and the two linked
> documents as the test baseline.

## Current end-to-end flow map

1. **Onboard:** select organization operating models and the first site → create the
   administrator → add sites → invite/accept staff → assign and switch active sites.
2. **Master data:** suppliers → organization product catalogue/GTIN → laboratory test
   catalogue and dynamic fields.
3. **Supply:** receive supplier lot into organization stock → partial/full dispatch to site
   → pharmacy/lab acknowledgement (including short shipment and GS1 match) → active stock.
4. **Replenishment:** site requisition → admin approve/reject → partial/full fulfilment from
   central lots → site acknowledgement.
5. **Pharmacy:** patient/walk-in visit → prescription or quick sale → transactional FEFO
   allocation → product-scan verification → payment/wallet → receipt; plus stock browse,
   traceability, and scan lookup.
6. **Laboratory:** patient visit/order → tests → combined specimen collection → receipt or
   rejection → result entry/amendment → consumable use → payment. Result entry currently
   completes results without independent authorization.
7. **Oversight:** organization/site/pharmacy/lab dashboards, earnings ledger, batch histories,
   scan events, and repository audit records.

## Historical snapshot (not a test specification)

## Organization Signup

1. A visitor opens `/signup`.
2. Step 1 captures identity, operating models, and first site.
3. Step 2 captures the administrator and requires explicit acceptance of the Terms of
   Service and Privacy Policy. Nothing is persisted between steps.
4. Final submit creates the organization, selected site, and admin in one transaction.
5. The admin can log in and use `/org/team` and `/org/sites`.

Contexts: `Organizations`, `Sites`, `Accounts`.

## Staff Invite

1. An admin opens `/org/team`.
2. `TeamLive.Index` calls `Accounts.invite_user/3`.
3. The invite creates a user without a password and a one-time invite token.
4. The invited staff member opens `/invites/:token`.
5. `AcceptInviteLive` calls `Accounts.accept_invite/2` to set the password.

Contexts: `Accounts`, `Sites`.

## Stock Receipt And GS1 Lookup

1. A pharmacist opens `/pharmacy/receive-stock`; lab staff use `/lab/receive-stock`.
2. The form can decode a GS1 payload and prefill GTIN, batch, expiry, and site data.
3. On save, `Batches.create_batch/2` creates stock at the chosen site.
4. `/pharmacy/scan` and `/lab/scan` decode GS1 data and look up the matching batch/product/site.

Contexts: `Batches`, `Products`, `Suppliers`, `Sites`, `GS1Decoder`.

## Prescription Dispensing

1. A pharmacist creates a prescription at `/pharmacy/prescriptions/new`, optionally creating a patient inline.
2. `Prescriptions.create_prescription_with_items/3` stores the header and items.
3. The pharmacist opens `/pharmacy/prescriptions/:id` and dispenses a quantity for an item.
4. `Prescriptions.dispense_item/5` picks FEFO stock from the prescription site, decrements `batches.remaining_quantity`, creates a `dispensed_items` row, and recomputes status.
5. The pharmacist scans the dispensed pack. `Prescriptions.verify_dispensed_item/3` checks the scanned GTIN and batch number against the recorded batch and marks the dispense verified.

Contexts: `Patients`, `Prescriptions`, `Batches`, `GS1Decoder`.

## Controlled-Drug Register

1. A pharmacist opens `/pharmacy/dangerous-drug-register`.
2. The screen filters by site, product, month, and year.
3. `DangerousDrugRegisters.record_entry/6` gets or creates the monthly register, increments the entry number, and stores the entry map.

Contexts: `Products`, `Sites`, `DangerousDrugRegisters`.

## Pharmacy Log

1. A pharmacist opens `/pharmacy/pharmacy-logs`.
2. The screen filters by site, log type, month, and year.
3. `PharmacyLogs.record_daily_entry/7` gets or creates the monthly log and stores the day entry.

Contexts: `Sites`, `PharmacyLogs`.

## Lab Order To Verified Result

1. Lab staff create an order at `/lab/orders/new`, optionally creating a patient inline.
2. `LabOrders.create_lab_order_with_tests/3` creates the order and its test rows.
3. Staff collect the sample from `/lab/orders/:id` with `LabOrders.mark_sample_collected/3`.
4. Staff enter results at `/lab/orders/:lab_order_id/tests/:id/results`.
5. `LabOrders.record_result/4` stores structured results; when a template exists, `LabTestTemplates.compute_results/2` flags low/normal/high values.
6. A different user verifies from `/lab/verification-queue`.
7. `LabOrders.verify_lab_order_test/3` rejects same-technician verification, marks the test verified, and recomputes the parent order status.

Contexts: `Patients`, `LabTests`, `LabTestTemplates`, `LabOrders`.

## Lab Consumable Usage And QA

1. Lab staff receive consumable batches through `/lab/receive-stock`.
2. The same screen can record usage against a batch.
3. `LabOrders.record_consumable_usage/5` decrements stock and records `lab_consumable_usage`.
4. QA readings are entered at `/lab/quality-assurance`.
5. `QualityAssuranceCharts.record_daily_entry/7` stores daily chart entries.

Contexts: `Batches`, `LabOrders`, `QualityAssuranceCharts`.

## Medical Camps

There is no medical-camp route, context, schema, or migration in the current repo.
