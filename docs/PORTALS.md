# Portals

> **Documentation note (2026-10-28):** this page is an older route summary. The router now
> also contains organization dashboard/earnings/products/batches/suppliers/requisitions;
> pharmacy stock/requisitions/patients/quick-sale/payment/receipt; and laboratory
> patients/requisitions/stock/tests/specimen/result-amendment/payment routes. Conversely,
> dangerous-drug register, pharmacy-log, QA-chart, test-template/category, result-entry, and
> verification-queue routes listed below no longer exist. See
> [WORKFLOWS.md](WORKFLOWS.md) and [MANUAL_TEST_PLAYBOOK.md](MANUAL_TEST_PLAYBOOK.md) for the
> reviewed current-state baseline.

Routes are defined in `lib/thamani_dawa_web/router.ex`.

## Public And Session Pages

Who: unauthenticated visitors and signed-out users.

Routes:

- `GET /` -> `ThamaniDawaWeb.PageController.home`
- `GET /login` -> `ThamaniDawaWeb.SessionController.new`
- `POST /login` -> `ThamaniDawaWeb.SessionController.create`
- `DELETE /logout` -> `ThamaniDawaWeb.SessionController.delete`

Purpose: home page and email/password session handling.

## Signup And Invite Acceptance

Who: unauthenticated organization owners and invited staff.

Live session: `:unauthenticated`, `on_mount {ThamaniDawaWeb.UserAuth, :mount_current_scope}`.

Routes:

- `/signup` -> `ThamaniDawaWeb.SignupLive`
- `/invites/:token` -> `ThamaniDawaWeb.AcceptInviteLive`

Purpose: create a new organization/admin/default site, or accept an invite and set a password.

## Organization Admin

Who: `admin` users only.

Live session: `:organization`, `on_mount {ThamaniDawaWeb.UserAuth, :require_admin}`.

Routes:

- `/org/team` and `/org/team/new` -> `ThamaniDawaWeb.TeamLive.Index`
- `/org/sites`, `/org/sites/new`, `/org/sites/:id/edit` -> `ThamaniDawaWeb.SiteLive.Index`

Purpose: invite/manage team members and create/edit pharmacy, lab, and warehouse sites.

## Pharmacy Portal

Who: `admin` and `pharmacist` users.

Live session: `:pharmacy`, `on_mount {ThamaniDawaWeb.UserAuth, :require_pharmacy_access}`.

Routes:

- `/pharmacy` -> `ThamaniDawaWeb.PharmacyDashboardLive`
- `/pharmacy/scan` -> `ThamaniDawaWeb.PharmacyScanLive`
- `/pharmacy/products*` -> `ThamaniDawaWeb.ProductLive.Index` and `Show`
- `/pharmacy/receive-stock` -> `ThamaniDawaWeb.ReceiveStockLive`
- `/pharmacy/prescriptions*` -> `ThamaniDawaWeb.PrescriptionLive.Index` and `Show`
- `/pharmacy/dangerous-drug-register` -> `ThamaniDawaWeb.DangerousDrugRegisterLive.Index`
- `/pharmacy/pharmacy-logs` -> `ThamaniDawaWeb.PharmacyLogLive.Index`

Purpose: track stock, receive batches, manage products, enter prescriptions, dispense against FEFO stock, verify dispensed items by GS1 scan, and keep pharmacy registers/logs.

## Lab Portal

Who: `admin` and `lab_technician` users.

Live session: `:lab`, `on_mount {ThamaniDawaWeb.UserAuth, :require_lab_access}`.

Routes:

- `/lab` -> `ThamaniDawaWeb.LabDashboardLive`
- `/lab/scan` -> `ThamaniDawaWeb.LabScanLive`
- `/lab/orders*` -> `ThamaniDawaWeb.LabOrderLive.Index` and `Show`
- `/lab/orders/:lab_order_id/tests/:id/results` -> `ThamaniDawaWeb.ResultEntryLive`
- `/lab/verification-queue` -> `ThamaniDawaWeb.VerificationQueueLive`
- `/lab/test-templates*` -> `ThamaniDawaWeb.TestTemplateLive.Index`
- `/lab/test-categories*` -> `ThamaniDawaWeb.TestCategoryLive.Index`
- `/lab/receive-stock` -> `ThamaniDawaWeb.LabReceiveStockLive`
- `/lab/quality-assurance` -> `ThamaniDawaWeb.QualityAssuranceLive.Index`

Purpose: create lab orders, collect samples, enter structured results, verify completed tests, manage test templates/categories, receive lab consumables, record consumable usage, and maintain QA charts.

## Distributor Portal

Who: active `distributor` users in an organization whose operating models include `distributor` (the equivalent of ErpLive's "Healthcare Distributor" sector). Removing the distributor model locks out both portal users and mobile app users.

Live session: `:distributor`, `on_mount {ThamaniDawaWeb.UserAuth, :require_distributor_access}`. Shipment and mobile-user screens additionally use `on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}`, which sends the user to `/distributor/billing/options` until a serialisation plan is chosen.

Routes:

- `/distributor` -> shipment pipeline, SSCC and allowance stats, and inventory health
- `/distributor/shipments` -> shipment list with status tabs, search, mobile-user/date filters, live refresh
- `/distributor/shipments/new`, `/distributor/shipments/:id/edit` -> create or edit a draft (order number, origin GLN, destination GLN)
- `/distributor/shipments/:id` -> review, approve (issue SSCCs) or reject, remove units, print SSCC shipper labels
- `GET /distributor/shipments/:id/export` -> CSV of scanned units (`DistributorShipmentExportController`)
- `/distributor/mobile-users*` -> mobile scanning-app users: add, edit, resend PIN, activate/deactivate
- `/distributor/billing/options` -> prepay vs flex plan chooser
- `/distributor/billing/payment`, `/distributor/billing/postpay-payment` -> prepay bundle checkout, flex cycle settlement (M-Pesa STK Push or manual reference)
- `/distributor/billing`, `/distributor/billing/invoices/:id` -> allowance usage, payment history, printable invoices
- `/distributor/products*`, `/distributor/batches/:id`, `/distributor/receiving*` -> catalog, received batches, goods receipts
- `/distributor/suppliers*`, `/distributor/customers*`, `/distributor/warehouses*` -> trading partners and sites; customers carry an auto-generated GLN used as the shipment destination
- `/distributor/settings` -> GS1 Company Prefix used for SSCCs

Purpose: run the distributor shipment workflow — portal admins create draft shipments, the mobile team packs and scans them into shippers, and admins approve (one SSCC per shipper, charged to the serialisation allowance) or reject them.

## Development Tools

Enabled only when `config :thamani_dawa, dev_routes: true`.

Routes:

- `/dev/dashboard` -> Phoenix LiveDashboard
- `/dev/mailbox` -> Swoosh mailbox preview

Purpose: local development diagnostics and email preview.

## Not Present Yet

The current router does not include separate reception, radiology, procurement, suppliers, payments, support-staff, or medical-camp portals. Some domain data such as suppliers and payments-adjacent fields exists, but there are no dedicated routes for those portals.

## Future Consideration: Add An Operating Model After Onboarding

Organizations currently choose their operating models during onboarding. Consider allowing an
administrator to add another model later—for example, enabling laboratory operations after a
pharmacy opens a laboratory division.

This should not be implemented as an ordinary editable select in organization settings. Adding an
operating model enables a new operational workspace and may require coordinated setup across:

- sites and the activities each location offers;
- licences and other regulatory information;
- staff roles and permissions;
- model-specific catalogues, inventory, and receiving workflows;
- billing or subscription entitlements; and
- navigation and portal access.

The preferred future design is an **Add operating model** action followed by a guided enablement
flow. At minimum, the flow should select participating sites, collect required regulatory details,
assign appropriate staff, show incomplete prerequisites, and enable the new workspace only when
its minimum setup is complete.

For an initial version, models may be added but should not be removable from the general settings
screen. Removing or deactivating a model is materially riskier because historical transactions,
stock movements, reports, staff assignments, and regulatory records must remain available. Treat
deactivation as a separate, guarded workflow or a support-assisted operation.

This is intentionally deferred; the current organization settings page should continue to display
operating models as read-only information.
