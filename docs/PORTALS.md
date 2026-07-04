# Portals

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

## Development Tools

Enabled only when `config :thamani_dawa, dev_routes: true`.

Routes:

- `/dev/dashboard` -> Phoenix LiveDashboard
- `/dev/mailbox` -> Swoosh mailbox preview

Purpose: local development diagnostics and email preview.

## Not Present Yet

The current router does not include separate reception, radiology, procurement, suppliers, payments, support-staff, or medical-camp portals. Some domain data such as suppliers and payments-adjacent fields exists, but there are no dedicated routes for those portals.
