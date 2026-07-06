# Sprint

Name: Complete the full project
Duration: 2026-07-06 to 2026-07-17
Goal: Finish the admin, pharmacy, and lab flows end to end with scoped data, role-based access, polished LiveView screens, and focused tests for every ticket.

## Tasks

### Task: Add combined pharmacy/lab site capability

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Admins need to model real branches where one physical location may operate as a pharmacy, a lab, or both. Update the site domain so downstream screens can ask whether a site supports pharmacy work, lab work, or both without duplicating the site record. Keep existing data migration-friendly so current pharmacy-only and lab-only behavior keeps working.

Acceptance Criteria:

- Site schema and changeset support a combined pharmacy/lab capability.
- Existing pharmacy-only and lab-only sites still validate.
- Context tests cover valid and invalid site capabilities.

Dependencies:

- None

---

### Task: Update site forms for site capabilities

Phase: frontend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
The admin creates and edits sites from the organization portal, and this is where they decide what workflows a branch can use. Update the LiveView form so the capability choice is obvious and maps cleanly to the site model. The UI should prevent confusing choices before they create bad downstream routing or stock assignment problems.

Acceptance Criteria:

- Site create/edit form allows selecting pharmacy, lab, or both.
- Form uses imported `.input` components and stable DOM IDs.
- LiveView tests cover rendering and saving each supported site capability.

Dependencies:

- Add combined pharmacy/lab site capability

---

### Task: Verify signup creates organization admin and default site

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Signup is the first admin flow: an owner creates their organization and immediately gets an admin account plus a default operating site. Treat this as one atomic setup step so a failed user or site insert does not leave orphaned tenant data. This ticket should make the startup path reliable enough for later team, product, and stock tickets to build on.

Acceptance Criteria:

- Failed admin creation rolls back organization and site creation.
- The first user is always role `admin` and belongs to the new organization.
- Tests cover success and rollback behavior.

Dependencies:

- None

---

### Task: Polish signup LiveView validation states

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
The signup screen is the first product experience for a new pharmacy or lab owner. Improve the LiveView states so invalid organization/admin data is easy to correct, flash messages are visible in the app layout, and the success path feels intentional. Keep the scope narrow to form behavior and validation feedback, with tests proving both failure and success paths.

Acceptance Criteria:

- Signup template is wrapped in the app layout with flash handling.
- Required fields show useful validation errors.
- LiveView tests cover invalid submit and successful signup path.

Dependencies:

- Verify signup creates organization admin and default site

---

### Task: Lock admin routes to admin users only

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Organization management is sensitive because it controls staff accounts, sites, and tenant setup. Verify that only admin users can reach `/org/*` screens, while pharmacy and lab staff are kept inside their operational portals. This ticket should exercise the router/live session guard rather than relying on UI links being hidden.

Acceptance Criteria:

- `/org/team` and `/org/sites` are inside the admin live session.
- Pharmacist and lab technician users are redirected away from admin routes.
- Auth tests cover admin allowed and non-admin denied cases.

Dependencies:

- None

---

### Task: Harden staff invite role and site validation

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Admins invite the staff who will run pharmacy and lab operations, so role and home-site assignment must be trusted. Harden `Accounts.invite_user/3` so roles are accepted intentionally and site IDs cannot cross tenant boundaries. The ticket is complete only when the behavior is implemented and documented through focused context tests.

Acceptance Criteria:

- Invites accept admin, pharmacist, and lab technician roles as intended.
- Invites reject a site from another organization.
- Accounts tests cover token creation and validation errors.

Dependencies:

- None

---

### Task: Complete team invite LiveView flow

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
The Team screen is the admin-facing workflow for adding pharmacists and lab technicians after signup. Complete the LiveView interaction so an admin can enter staff details, choose a role, optionally assign a home site, and see the staff list update. The tests should drive the real form so future UI changes do not silently break invitations.

Acceptance Criteria:

- Team form has unique IDs and uses `.input` components.
- Successful invite shows a flash and updates the staff list.
- LiveView tests cover invite success and invalid form errors.

Dependencies:

- Harden staff invite role and site validation

---

### Task: Complete invite acceptance flow

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Invited staff start with no password and must claim their account through a one-time invite link. Finish the acceptance behavior so the token can only be used once, the password is stored securely, and bad links fail safely. This closes the loop between admin invite and operational user login.

Acceptance Criteria:

- Invite token is invalidated after password setup.
- Expired or reused tokens show a safe error state.
- LiveView and context tests cover valid, reused, and invalid tokens.

Dependencies:

- Complete team invite LiveView flow

---

### Task: Add role-based login redirects

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
After authentication, users should land in the portal that matches their day-to-day work. Admins and pharmacists should enter the pharmacy portal first, while lab technicians should enter the lab portal. Keep the redirect behavior explicit so future role changes do not accidentally send users into the wrong workflow.

Acceptance Criteria:

- Admin users land on `/pharmacy`.
- Pharmacist users land on `/pharmacy`.
- Lab technician users land on `/lab`.
- Controller tests cover each redirect.

Dependencies:

- Complete invite acceptance flow

---

### Task: Complete admin site list and edit workflow

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
The site admin screen is the source of truth for branches used by stock, prescriptions, and lab orders. Complete the list, create, and edit behavior so admins can manage only their own organization's sites and persist core branch fields. Include LiveView tests with stable selectors so future UI polish does not break the workflow silently.

Acceptance Criteria:

- Site list only shows sites for the current organization.
- Create and edit actions persist name, address, GLN, and capability.
- LiveView tests use key DOM IDs instead of raw HTML assertions.

Dependencies:

- Update site forms for site capabilities

---

### Task: Harden product catalog organization scoping

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Products are tenant-owned catalog records, and two organizations may stock similar drugs or consumables. Strengthen context-level scoping so every read and write stays inside the current organization, even if a malicious or mistaken ID is passed in. Include tests that prove isolation independently of LiveView route guards.

Acceptance Criteria:

- Product list, get, create, and update functions require organization scope where needed.
- A user cannot fetch or update another organization product.
- Product context tests cover cross-organization isolation.

Dependencies:

- None

---

### Task: Complete product catalog LiveView workflow

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
The product catalog is where admins define drugs, lab consumables, and supplies before batches can be received. Complete the LiveView workflow for creating, editing, searching, and viewing products. Include tests for those interactions so later batch and dispensing work has a stable product foundation.

Acceptance Criteria:

- Create and edit work through LiveView interactions.
- Search filters products by stable table rows or IDs.
- Show page displays product details and batch table presence.
- LiveView tests cover create, edit, search, and show behavior.

Dependencies:

- Harden product catalog organization scoping

---

### Task: Add admin batch creation from product screen

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Admins need a direct way to create stock batches after defining a product, especially during setup or manual inventory entry. Add a batch creation path from the product screen that assigns the batch to a real organization site and captures quantity, expiry, and receiver details. Keep this focused on the admin product workflow, not the pharmacy/lab receive-stock screens.

Acceptance Criteria:

- Product show or modal flow includes an add batch form.
- Batch create sets product, organization, site, quantity, expiry, and receiver.
- LiveView tests cover successful batch creation from the product screen.

Dependencies:

- Complete product catalog LiveView workflow

---

### Task: Validate batch site assignment rules

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Batches represent physical stock at a site, so cross-organization product or site assignment would be a serious tenant isolation bug. Implement backend validation that rejects mismatched product/site IDs before stock is created. Include tests for hostile params, not just normal form submissions.

Acceptance Criteria:

- Batch create rejects cross-organization site IDs.
- Batch create rejects cross-organization product IDs.
- Context tests cover both validation failures.

Dependencies:

- Add combined pharmacy/lab site capability

---

### Task: Harden GS1 decode support for stock receipt

Phase: backend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Both pharmacy and lab receiving flows rely on GS1 barcode data to prefill GTIN, batch number, expiry, manufacture date, and serial fields. Harden the decoder behavior for the supported application identifiers and malformed scans. Include decoder tests so barcode parsing remains stable before LiveViews depend on it.

Acceptance Criteria:

- Decoder extracts GTIN, batch number, expiry, manufacture date, and serial data.
- Invalid payloads return clear errors.
- Tests document supported decoder behavior and error cases.

Dependencies:

- None

---

### Task: Finish pharmacy receive stock flow

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Pharmacists receive drug stock into pharmacy-capable sites before it can be approved and dispensed. Complete the receive-stock workflow for manual entry and GS1-assisted entry, tying together product, supplier, site, and batch creation. The screen should respect organization/site scoping and produce testable form outcomes.

Acceptance Criteria:

- Pharmacist can receive a batch into a pharmacy-capable site.
- GS1 decode can prefill batch form fields.
- LiveView tests cover manual receipt and decoded receipt.

Dependencies:

- Validate batch site assignment rules
- Harden GS1 decode support for stock receipt

---

### Task: Finish lab receive stock flow

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Lab staff receive reagents and consumables into lab-capable sites so later tests can record usage against real inventory. Finish the lab receive-stock flow with the same GS1 and batch discipline as pharmacy stock, while filtering out pharmacy-only sites. The tests should prove lab users cannot accidentally place consumables into the wrong site type.

Acceptance Criteria:

- Lab technician can receive lab consumable stock into a lab-capable site.
- Pharmacy-only sites are not offered for lab receipt.
- LiveView tests cover successful receipt and invalid site selection.

Dependencies:

- Validate batch site assignment rules
- Add combined pharmacy/lab site capability

---

### Task: Complete prescription create with inline patient

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
The pharmacy workflow starts when a pharmacist records a prescription for an existing patient or creates a patient inline. Complete the creation path for prescription header data such as prescriber, payment, and notes while preserving tenant scoping. This ticket should set up a prescription record that later item and dispensing tickets can continue.

Acceptance Criteria:

- Prescription form captures patient, prescriber, payment, and notes.
- Inline patient creation is scoped to the organization.
- Context and LiveView tests cover create with existing and new patient.

Dependencies:

- Finish pharmacy receive stock flow

---

### Task: Complete prescription item entry

Phase: frontend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
A prescription is only useful when it captures the medicines and instructions the patient should receive. Complete entry for multiple prescription items, including product selection, prescribed quantity, dosage, frequency, duration, and route. Include tests that catch invalid quantities and prove multi-item prescriptions persist correctly.

Acceptance Criteria:

- Prescription item fields include product, quantity, dosage, frequency, duration, and route.
- Invalid item quantities show validation errors.
- Tests cover creating a prescription with multiple items.

Dependencies:

- Complete prescription create with inline patient

---

### Task: Implement FEFO dispensing

Phase: backend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Dispensing must follow FEFO so the earliest expiring approved stock is consumed before later batches. Implement or harden the dispensing algorithm for partial fills across batches and insufficient stock. Include backend tests proving dispensing never pulls stock from another site or organization.

Acceptance Criteria:

- Dispensing decrements `remaining_quantity` from the oldest expiry first.
- Dispensing never uses batches from another site or organization.
- Tests cover full, partial, and insufficient stock cases.

Dependencies:

- Complete prescription item entry

---

### Task: Finish prescription dispense LiveView

Phase: frontend
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
The prescription show page is where the pharmacist turns prescribed items into dispensed stock movements. Finish the LiveView action for entering a dispense quantity, applying the backend FEFO behavior, and refreshing item/prescription status. The UI should show errors clearly when there is not enough eligible stock.

Acceptance Criteria:

- Pharmacist can dispense an item from the prescription show page.
- UI updates item status and prescription status after dispense.
- LiveView tests cover successful dispense and insufficient stock error.

Dependencies:

- Implement FEFO dispensing tests

---

### Task: Add dispensed item GS1 verification

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
After dispensing, pharmacists need to verify that the physical pack handed over matches the recorded batch. Add the scan verification flow so matching GTIN and batch data marks the dispensed item verified, while mismatches remain unverified and visible. This closes the pharmacy traceability loop from stock receipt to patient handoff.

Acceptance Criteria:

- Matching GTIN and batch number marks the dispensed item verified.
- Mismatched scan shows an error and leaves verification unchanged.
- Context and LiveView tests cover match and mismatch.

Dependencies:

- Finish prescription dispense LiveView

---

### Task: Add pharmacy batch approval flow

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Newly received pharmacy batches should not automatically become dispensable until a pharmacist approves them. Add a lightweight approval state or equivalent availability flag, then make dispensing and scan lookup respect it. This gives the project a clear control point between receiving stock and using it for prescriptions.

Acceptance Criteria:

- Batch has a pending/approved state or equivalent availability flag.
- Dispensing only uses approved pharmacy batches.
- Tests cover approving a batch and excluding unapproved stock from dispense.

Dependencies:

- Finish pharmacy receive stock flow

---

### Task: Complete lab test catalog management

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Lab orders depend on a maintained catalog of available tests and prices. Complete the management flow so admins or lab staff can create and edit tests, deactivate old tests, and only choose active tests on new orders. Keep this ticket centered on the test catalog, not result templates or order entry.

Acceptance Criteria:

- Admin or lab technician can create and edit active lab tests.
- Inactive tests are hidden from new order selection.
- Context and LiveView tests cover create, edit, and inactive filtering.

Dependencies:

- Finish lab receive stock flow

---

### Task: Complete lab order create with inline patient

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
The lab workflow starts when staff create an order for a patient and select the requested tests. Complete the order creation path for patient details, prescriber, urgency, payment, and initial order status. The flow should support existing patients and inline patient creation without leaking records across organizations.

Acceptance Criteria:

- Lab order form captures patient, prescriber, urgency, payment, and tests.
- Inline patient creation is scoped to the organization.
- Tests cover create with existing and new patient.

Dependencies:

- Complete lab test catalog management

---

### Task: Complete lab order test selection

Phase: frontend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
A lab order may contain one or several tests, and the selected tests drive pricing and later result rows. Complete the selection behavior for multiple active tests and validate that an order cannot be created without tests. Include LiveView tests proving the order setup produces the child records needed for sample collection and result entry.

Acceptance Criteria:

- Lab order form supports selecting multiple active lab tests.
- Total amount is calculated from selected tests.
- LiveView tests cover multiple tests and no-test validation.

Dependencies:

- Complete lab order create with inline patient

---

### Task: Implement sample collection flow

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Once a lab order is created, staff need to record when the sample was collected and any collection notes. Implement the order show action that captures collection date/description and advances the relevant status fields. The tests should prove this transition happens from the real lab order screen.

Acceptance Criteria:

- Sample collection date and description are recorded.
- Order/test status changes after collection.
- Context and LiveView tests cover sample collection.

Dependencies:

- Complete lab order test selection

---

### Task: Complete result entry flow

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
After sample collection, lab staff enter results for each ordered test. Complete the result entry page so it loads the correct order test in the current organization, saves structured result data, and moves the test forward in the workflow. Include access tests so a user cannot submit results against another tenant's order.

Acceptance Criteria:

- Result entry screen loads the selected order test in the current organization.
- Saving results updates test status and result fields.
- Tests cover valid results and cross-organization access denial.

Dependencies:

- Implement sample collection flow

---

### Task: Complete lab verification queue

Phase: integration
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Verification should be a second-person review step for completed lab results. Finish the queue so only tests ready for verification appear, and enforce that the same user who performed the test cannot verify it. This ticket should make the final lab result status trustworthy.

Acceptance Criteria:

- Verification queue lists only tests ready for verification.
- Same user who performed the test cannot verify it.
- Context and LiveView tests cover allowed and rejected verification.

Dependencies:

- Complete result entry flow

---

### Task: Implement lab order status recomputation

Phase: backend
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Backend Developer
Description:
Lab orders summarize the state of their child tests, so parent status must stay accurate across collection, result entry, and verification. Implement or harden recomputation for single-test and multi-test orders. Include context tests to protect dashboards and lists from showing stale order states.

Acceptance Criteria:

- Order status updates after sample collection, result entry, and verification.
- Mixed child statuses produce the expected parent status.
- Context tests cover single-test and multi-test orders.

Dependencies:

- Complete lab verification queue

---

### Task: Add lab consumable usage flow

Phase: integration
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Lab work consumes reagents and supplies from stock, sometimes tied to a specific lab order and sometimes for general use. Complete the usage flow so staff can select a batch, record quantity and purpose, decrement remaining stock, and optionally link it to an order. Include tests that prevent negative inventory and tenant/site leakage.

Acceptance Criteria:

- Usage decrements batch remaining quantity.
- Usage cannot exceed available stock.
- Context and LiveView tests cover successful usage and insufficient stock.

Dependencies:

- Finish lab receive stock flow
- Complete result entry flow

---

### Task: Complete lab scan lookup

Phase: frontend
Priority: medium
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
Lab staff need to scan consumables and quickly confirm what batch they are holding. Complete the scan lookup screen so decoded GS1 data finds matching lab stock and displays product, batch, expiry, site, and remaining quantity. The empty state should help staff distinguish an unknown scan from a real zero-result lookup.

Acceptance Criteria:

- Valid scans show product, batch, expiry, site, and remaining quantity.
- Missing stock shows a clear empty state.
- LiveView tests cover matching and missing scan payloads.

Dependencies:

- Harden GS1 decode support for stock receipt
- Finish lab receive stock flow

---

### Task: Complete pharmacy scan lookup

Phase: frontend
Priority: medium
Estimated Hours: 0.5
Suggested Assignee Role: Frontend Developer
Description:
Pharmacy staff use scan lookup to identify drug stock and support traceability checks. Complete the scan screen so decoded GS1 data finds matching approved pharmacy stock and shows the key product and batch details. Unapproved or missing stock should be clearly unavailable rather than silently looking valid.

Acceptance Criteria:

- Valid scans show product, batch, expiry, site, and remaining quantity.
- Missing or unapproved stock shows a clear empty state.
- LiveView tests cover approved match and unavailable stock.

Dependencies:

- Harden GS1 decode support for stock receipt
- Add pharmacy batch approval flow

---

### Task: Enforce portal access boundaries for pharmacy and lab

Phase: qa
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: QA Engineer
Description:
Before the sprint closes, make the portal boundaries explicit from the user's point of view. Pharmacists should only operate in pharmacy routes, lab technicians should only operate in lab routes, and admins should be able to reach all setup and operational portals. Include access tests that complement the earlier admin-only route checks.

Acceptance Criteria:

- Pharmacist can access pharmacy routes and cannot access lab routes.
- Lab technician can access lab routes and cannot access pharmacy routes.
- Admin can access admin, pharmacy, and lab routes.

Dependencies:

- Add role-based login redirects

---

### Task: Stabilize admin happy path

Phase: qa
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: QA Engineer
Description:
Stabilize the full admin setup path so a new organization can be configured from scratch. The flow should support admin signup, creating a combined-capability site, inviting staff, adding a product, and creating initial stock. Include a high-level test with durable assertions and key DOM IDs so the workflow is verified without freezing the visual design.

Acceptance Criteria:

- Test signs up an organization admin.
- Test creates a combined-capability site, invites staff, creates a product, and creates a batch.
- Assertions use stable DOM IDs and context lookups.

Dependencies:

- Add admin batch creation from product screen
- Complete team invite LiveView flow

---

### Task: Stabilize pharmacy happy path

Phase: qa
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: QA Engineer
Description:
Stabilize the core pharmacy day-to-day workflow from login to verified dispense. The flow should let a pharmacist approve available stock, create a prescription, dispense medication, and verify the dispensed pack by GS1 scan. Include a high-level test that asserts final prescription status and batch quantities so both UI behavior and inventory side effects are covered.

Acceptance Criteria:

- Test logs in as a pharmacist.
- Test approves stock, creates a prescription, dispenses it, and verifies by GS1 scan.
- Prescription and batch quantities are asserted after the flow.

Dependencies:

- Complete pharmacy scan lookup
- Add dispensed item GS1 verification

---

### Task: Stabilize lab happy path

Phase: qa
Priority: high
Estimated Hours: 0.5
Suggested Assignee Role: QA Engineer
Description:
Stabilize the core lab workflow from intake to verified result. The flow should let lab staff create an order, collect a sample, enter results, and verify with a second lab user. Include a high-level test that asserts final lab order and order-test statuses so the workflow is complete, not just screen-rendering.

Acceptance Criteria:

- Test logs in as a lab technician.
- Test creates an order, collects a sample, enters results, and verifies with a second lab user.
- Lab order and lab order test statuses are asserted after the flow.

Dependencies:

- Implement lab order status recomputation
- Complete lab verification queue

---

### Task: Run precommit and fix final issues

Phase: deployment
Priority: urgent
Estimated Hours: 0.5
Suggested Assignee Role: Full-Stack Developer
Description:
Use the project precommit alias as the final sprint gate after all feature tickets land. Fix formatting, compile, lint, and test issues caused by the sprint work, then document any genuinely deferred gaps. This ticket is done only when the project is in a shippable state according to the repo's own checks.

Acceptance Criteria:

- `mix precommit` completes successfully.
- Any failing tests from the sprint are fixed.
- Final notes list remaining known gaps, if any.

Dependencies:

- Stabilize admin happy path
- Stabilize pharmacy happy path
- Stabilize lab happy path

---
