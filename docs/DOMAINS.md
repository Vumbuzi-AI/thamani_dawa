# Domains

Every tenant-owned domain is scoped by `organization_id`. The public functions below are the context API a caller should prefer over direct schema inserts.

## Accounts

Module: `ThamaniDawa.Accounts`

Responsibility: users, login sessions, staff invites, roles, and secondary PINs.

Schemas:

- `ThamaniDawa.Accounts.User`: `admin`, `pharmacist`, and `lab_technician` users.
- `ThamaniDawa.Accounts.UserToken`: session and invite tokens.
- `ThamaniDawa.Accounts.Scope`: runtime scope with `user` and `organization_id`.

Key functions: `get_user_by_email/1`, `get_user_by_email_and_password/2`, `list_users/1`, `register_user/2`, `invite_user/3`, `accept_invite/2`, `set_user_pin/2`, `valid_pin?/2`, session token functions.

Relationships: users belong to an organization and optionally a site; invited users can reference the inviter.

## Organizations

Module: `ThamaniDawa.Organizations`

Responsibility: tenant boundary and signup.

Schema: `ThamaniDawa.Organizations.Organization`.

Key functions: `get_organization!/1`, `create_organization/1`, `signup/2`.

Relationships: `signup/2` creates an organization, a default pharmacy site, and the first admin in one transaction.

## Sites

Module: `ThamaniDawa.Sites`

Responsibility: branches and storage locations.

Schema: `ThamaniDawa.Sites.Site` with site types `:pharmacy`, `:lab`, and `:warehouse`.

Key functions: `list_sites/1`, `get_site!/2`, `get_site_by_gln/2`, `create_default_site/2`, `create_site/2`, `update_site/2`.

Relationships: sites belong to organizations and are referenced by users, stock, prescriptions, lab orders, logs, registers, and QA charts.

## Products

Module: `ThamaniDawa.Products`

Responsibility: tenant-specific catalog for stockable items.

Schema: `ThamaniDawa.Products.Product` with product types `:drug`, `:lab_consumable`, and `:general_supply`.

Key functions: `list_products/1`, `get_product!/2`, `create_product/2`, `update_product/2`.

Relationships: products are referenced by batches, prescription items, dangerous-drug registers, and lab-consumable stock.

## Suppliers

Module: `ThamaniDawa.Suppliers`

Responsibility: vendors that supply stock.

Schema: `ThamaniDawa.Suppliers.Supplier`.

Key functions: `list_suppliers/1`, `get_supplier!/2`, `create_supplier/2`.

Relationships: batches optionally reference a supplier.

## Batches

Module: `ThamaniDawa.Batches`

Responsibility: physical stock lots and FEFO stock selection.

Schema: `ThamaniDawa.Batches.Batch`.

Key functions: `list_batches/1`, `get_batch!/2`, `create_batch/2`, `fefo_batch/3`, `decrement_remaining_quantity/2`.

Relationships: batches belong to organization, product, and site; optional supplier, source batch, and receiver user; dispensing and lab consumption decrement `remaining_quantity`.

## Patients

Module: `ThamaniDawa.Patients`

Responsibility: organization-wide patient records.

Schema: `ThamaniDawa.Patients.Patient`.

Key functions: `list_patients/1`, `get_patient!/2`, `create_patient/2`.

Relationships: patients are referenced by prescriptions and lab orders.

## Prescriptions

Module: `ThamaniDawa.Prescriptions`

Responsibility: pharmacy prescription intake, line items, dispensing, and scan verification.

Schemas:

- `ThamaniDawa.Prescriptions.Prescription`
- `ThamaniDawa.Prescriptions.PrescriptionItem`
- `ThamaniDawa.Prescriptions.DispensedItem`

Key functions: `list_prescriptions/1`, `get_prescription!/2`, `create_prescription/2`, `create_prescription_with_items/3`, `list_prescription_items/2`, `dispense_item/5`, `verify_dispensed_item/3`.

Relationships: prescription dispensing uses `Batches.fefo_batch/3` at the prescription site, decrements stock, records a dispensed item, and recomputes prescription status.

## Lab Tests

Module: `ThamaniDawa.LabTests`

Responsibility: billable lab test catalog.

Schema: `ThamaniDawa.LabTests.LabTest`.

Key functions: `list_lab_tests/1`, `get_lab_test!/2`, `create_lab_test/2`.

Relationships: lab order tests reference lab tests for the ordered procedure and pricing context.

## Lab Test Templates

Module: `ThamaniDawa.LabTestTemplates`

Responsibility: result-entry templates and reference-range flagging.

Schemas:

- `ThamaniDawa.LabTestTemplates.LabTestCategory`
- `ThamaniDawa.LabTestTemplates.LabTestTemplate`
- `ThamaniDawa.LabTestTemplates.FieldDefinition` embedded in templates.

Key functions: category/template list, get, create, update functions, plus `compute_results/2`.

Relationships: lab order tests optionally reference templates. `compute_results/2` stores value/flag maps for result fields.

## Lab Orders

Module: `ThamaniDawa.LabOrders`

Responsibility: lab order intake, sample collection, result entry, verification, and consumable usage.

Schemas:

- `ThamaniDawa.LabOrders.LabOrder`
- `ThamaniDawa.LabOrders.LabOrderTest`
- `ThamaniDawa.LabOrders.LabConsumableUsage`

Key functions: `list_lab_orders/1`, `create_lab_order_with_tests/3`, `mark_sample_collected/3`, `record_result/4`, `verify_lab_order_test/3`, `record_consumable_usage/5`.

Relationships: lab orders belong to patients/sites; tests reference lab tests and optional templates; verification must be done by a different user from the performer.

## Pharmacy Logs

Module: `ThamaniDawa.PharmacyLogs`

Responsibility: site-scoped monthly pharmacy log books.

Schema: `ThamaniDawa.PharmacyLogs.PharmacyLog`.

Key functions: `list_pharmacy_logs/1`, `get_pharmacy_log!/2`, `create_pharmacy_log/2`, `record_daily_entry/7`.

Relationships: logs belong to organization and site and store daily entries in a map.

## Dangerous Drug Registers

Module: `ThamaniDawa.DangerousDrugRegisters`

Responsibility: controlled-drug monthly registers.

Schema: `ThamaniDawa.DangerousDrugRegisters.DangerousDrugRegister`.

Key functions: `list_dangerous_drug_registers/1`, `get_dangerous_drug_register!/2`, `create_dangerous_drug_register/2`, `record_entry/6`.

Relationships: registers belong to site and dangerous-drug product; `record_entry/6` increments `last_entry_number`.

## Quality Assurance Charts

Module: `ThamaniDawa.QualityAssuranceCharts`

Responsibility: site-scoped lab QA/QC charts.

Schema: `ThamaniDawa.QualityAssuranceCharts.QualityAssuranceChart`.

Key functions: `list_quality_assurance_charts/1`, `get_quality_assurance_chart!/2`, `create_quality_assurance_chart/2`, `record_daily_entry/7`.

Relationships: charts belong to organization and site and store daily entries in a map.

## Scan Events

Module: `ThamaniDawa.ScanEvents`

Responsibility: GS1 scan audit trail.

Schema: `ThamaniDawa.ScanEvents.ScanEvent` with event types `:receipt`, `:dispense`, `:lab_consumption`, `:transfer_out`, and `:transfer_in`.

Key functions: `list_scan_events/1`, `get_scan_event!/2`, `create_scan_event/2`, `log_scan_event/5`.

Relationships: scan events store parsed GTIN, batch number, optional GLN, event type, reference id, and user id.
