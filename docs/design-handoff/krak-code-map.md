# Thamani Dawa web: code map (Krak)

> **Current implementation note (25 Nov 2026):** This is a point-in-time code read, not the current manufacturer contract. The two-step serialization wizard and aggregation-stage SSCC timing supersede the flow notes here. Current behavior is documented in `docs/manual-manufacturer-testing.md` and `docs/mobile/manufacturer-aggregation-api.md`.

Input for Bau's Notion doc on the Thamani Dawa interface. Read it next to Bau's Doop frame inventory (canvas LQFIZlhE35) and `/workspace/thamani/lab-compliance/frame-ledger.md`.

Written 23 Nov 2026, finished 17:21 EAT. Read-only: no repo was changed and nothing was committed.

## 0. Source and method

| Item | Value |
|---|---|
| Branch read | `origin/sean/td-web-design-system` at **368b03f** "Merge origin/master into sean/td-web-design-system" (pushed 23 Nov 17:05 EAT). This is the merged branch, so I used it as the primary source. |
| Master read | `origin/master` at **95abf49** (lkendi, 23 Nov 16:53 EAT). |
| Relationship | 95abf49 is an ancestor of 368b03f, so **the branch contains every master commit**. The branch adds one commit on top of master's history: 933a8a9 (design pass). |
| Worktrees | `/tmp/td-map-branch` and `/tmp/td-map-master`, both detached and removed when this was written. `/workspace/thamani_dawa` was not touched apart from `git fetch` and `git worktree add/remove`. |
| How | I read `router.ex`, every routed LiveView, `layouts.ex`, `td_components.ex`, `core_components.ex` and the `Manufacturing`, `Distributor`, `GoodsReceipts` and `Epcis` contexts. A script listed each LiveView's `handle_event`s, `push_navigate`/`push_patch`/`navigate`/`patch`/`href` targets and components, and cross-checked every route for inbound links. The manufacturer and distributor flows were read line by line. |
| Not done | I ran no tests and no browser session. Everything here comes from reading the code. Test results in §5 come from the suite logs already on the box (`/tmp/base-test.log`, `/tmp/merge-test.log`, `/tmp/s1-test.log`, `/tmp/s1b-test.log`, 17:02–17:10 EAT). Anything marked **(verify)** is my best reading and still needs a click-through. |

**Canon rule (Sean):** master's flow logic is canon, and the branch's design system is canon. On this merged branch the two don't conflict: the branch's only changes to logic files are additions (`Batches.list_site_stock/2` and `Manufacturing.dashboard_summary/2`). Every other branch change is UI.

### Legend

- **UI kit.** **TD** means the page uses only `td_*` components from `components/td_components.ex`. **Legacy** means it uses only the old core components (`.header`, `.button`, `.input`, `.table`, `.modal`, `.blank_state`, `.pagination`) and Tailwind/hero-icon markup. **Mixed** means both.
- **Events** is the number of `handle_event` clauses in the module.
- **Back link** reads **none** for a detail route where I found no back link, back arrow or `back=` attr in the module. Modal routes (`/new`, `/edit`, `/:id/approve` and so on) close with `on_cancel` and aren't flagged.
- **Shells.** Every portal page renders inside `Layouts.<portal>_shell` (`components/layouts.ex`), which wraps `sidebar_shell` and then `td_app_shell`. The shell takes `back`/`back_label` and draws a back link above the content when `back` is a string (layouts.ex ~L676). **Almost no page passes it**: only `site_live/show`, `patient_live/show`, `lab_patient_live/show` and `product_live/show`. The others draw their own back link, or none at all.


## 1. The biggest flow problems (summary)

The details and file references are in §3 (manufacturer) and §4 (distributor).

1. **Pallets can't be built from shippers packed on the serials page or in make-to-order.** Two of the app's three ways to make a shipper immediately record an *approved dispatch shipment* (`Manufacturing.record_dispatch_shipment!/2`) and send an EPCIS Ship event: the "Create shipper SSCC" panel on the serials page (`pack_serials_into_shipper`) and make-to-order in the serial wizard (`generate_order_serials`). The pallet picker (`/manufacturer/aggregations/pallets/new`) only lists shippers that aren't on any shipment yet (`Manufacturing.list_available_ssccs/1`), so shippers made those two ways never appear when you try to build a pallet. Only shippers made through product detail → "Create SSCC" (`Manufacturing.create_sscc`) or the unreachable aggregation wizard can go on a pallet. The test (`manufacturer_pallet_new_live_test.exs`) uses `create_manual_sscc`, so it never covers this. In the domain, shipping before palletising is backwards. **(verify in browser; the code reading is clear)**
2. **Pallet SSCCs aren't real SSCCs.** `create_order_pallet/2` makes a random local code `"PAL-" <> base32`, not an 18-digit GS1 SSCC from the member API. Making a pallet also sends no EPCIS aggregation event and gives no pallet label to print.
3. **There are two shipment systems.** Packing writes `manufacturer_shipments`, through the `Manufacturing` context. The `/manufacturer/shipments` list, form and review read `distributor_shipments` with participant tier "manufacturer", through the `Distributor` context. So shipments created by packing never show in the Shipments list. The dashboard's "Shipped this week" counts `manufacturer_shipments` but links to the list, which reads the other table.
4. **Serial generation now lands on the right page, but the page isn't built for the next step.** Master (aa6aaec, 15:47 EAT) changed the wizard to `push_navigate` to `/manufacturer/products/:gtin/serials?batch=<batch_no>`, so Sean's "don't send me to inventory" is fixed in logic. The landing page has three problems, though: it's fully legacy UI, it prints only one label per serial card (no "print this batch"), and it falls back to the first batch if GS1 hasn't listed the new batch yet. The old "Serials issued" screen, with "Open inventory", "Open aggregation" and "New shipment", is now dead code, and Doop still draws it (kyQHKTVNuw, pu69ruhFa_).
5. **Button labels are unclear.** On `/manufacturer/products`, the SSCC column and the Serials column both have a button labelled "View", and the row action is "Serial". The product detail page uses "Generate serials" and "Create SSCC". The SSCC empty state says SSCCs "are created when stock is shipped", which is wrong: they're created when stock is packed.
6. **Back links are broken or missing.** `/manufacturer/sscc/:id/serials`, `/manufacturer/sscc/:id/label`, `/manufacturer/products/:id`, `/manufacturer/shipments/:id` and `/manufacturer/aggregations/:id` have no back link. They're reached from 3–4 different places, so a fixed back target would be wrong anyway; they need a `return_to` param. The same applies to 9 detail pages in other portals (§2.3).
7. **Half the aggregation feature can't be reached.** `/manufacturer/aggregations/new` (wizard), `/pallets/:pallet_id/ssccs/new`, `/ssccs/:id` (shipper detail with Add GTIN, Upload GTINs, Add batch and Add serials) and `/:id` (aggregation review: approve/reject) have **no inbound links** from any routed page. Only unrouted modules link to them (`ManufacturerAggregationLive.List` and `.Form`). The routed `/manufacturer/aggregations` page only offers "Create pallet SSCC".
8. **Pallet building has no scanning.** Sean's flow is "scan the shippers' SSCCs and make a pallet". `PalletNew` is a searchable checkbox list (`search`, `toggle`, `select_visible`) with no scan input and no GS1 decode. There is also no "ship this pallet" step: pallets aren't linked to a shipment flow.
9. **Distributor: there are no orders, no stock page, and some flows are hidden.** The code has no orders entity; a distributor "order" is a draft shipment with an `order_number`. `/distributor/stock` and `/distributor/expiring` just redirect to `/distributor/products?view=batches`, but Doop draws a full Stock page (zones, Move stock, Change status, Receiving/Picking/Staging/Dispatch). Customer returns (`/distributor/customer-returns`) aren't in the sidebar. Doop also draws "pick list generated" and "pick confirmed" shipment states that the code doesn't have (the `Distributor` moduledoc says: "no picker-facing pick list").
10. **Most manufacturer and distributor pages still use the legacy UI.** Every distributor page except the dashboard is Legacy. On the manufacturer side, the serials page, SSCC list, SSCC serials and the whole aggregation area are Legacy. There are also four separate GLN search implementations: `GlnSearchField`, the serial wizard combobox, the pack panel combobox and the aggregation wizard combobox.


## 2. Cross-cutting: router, shell and nav

### 2.1 Router structure (`lib/thamani_dawa_web/router.ex`, 470 lines, the same on master and branch)

| Scope / live_session | on_mount / plug | Routes |
|---|---|---|
| `/` browser (controllers) | `fetch_current_scope_for_user` | `/`, `/privacy`, `/terms`, `/contact`, `/login` (SessionController), `/logout`, `/reset-password[/:token]`, `/confirm/:token`, `PATCH /switch-site` |
| `:unauthenticated` | `redirect_if_authenticated` | `/signup` |
| `:accept_invite` | `mount_current_scope` | `/invites/:token` |
| `:confirm_email` | `require_admin` | `/confirm-email` |
| `:organization` | `require_admin` + `require_confirmed_email` | `/onboarding` and all `/org/*` |
| `:platform` | `require_superadmin` | `/platform`, `/platform/audit`, `/platform/recalls` |
| `:pharmacy` | `require_pharmacy_access` | `/pharmacy/*` |
| `:lab` | `require_lab_access` | `/lab/*` |
| `:distributor` | `require_distributor_access` | `/distributor/*` operations |
| `:distributor_admin` | `require_distributor_admin_access` (a non-admin is bounced to `/distributor`) | billing, mobile users, api-keys, settings, epcis |
| `:manufacturer` | `require_manufacturer_access` | `/manufacturer/*` operations |
| `:manufacturer_admin` | `require_manufacturer_admin_access` | mobile users, api-keys, settings |
| Controllers | `require_distributor_user` / `require_manufacturer_user` | `GET /distributor/shipments/:id/export`, `GET /manufacturer/sscc/:id/export`, `GET /manufacturer/products/:gtin/batches/:batch_id/serials/export` (CSV), `GET /org/products/import/template` |
| `/api/v1` (JSON) | `ApiAuth` | Pharmacy, lab, org, catalogue and session endpoints for the mobile app. **There are no manufacturer or distributor endpoints on master** (PR #64's packer API isn't merged). |

There are 169 LiveView routes. **Six LiveView modules have no route:**
- `PlatformOrganizationsLive` (99 lines)
- `ManufacturerShipmentLive.Index` and `.Show` (the older `Manufacturing.Shipment` UI)
- `ManufacturerAggregationLive.List` and `.Form` (the older scan-to-aggregate UI)

`ManufacturerProductLive.SerialWizard` is a LiveComponent, not a route.

### 2.2 Sidebar nav (`layouts.ex` `*_item_groups`, ~L790–965)

The nav is built from the current site's activities and the user's roles. Admins in "Manage organization" context (no site picked) also get management groups.

| Portal | Ops groups in code (label → path) | Admin groups in code | Gaps against Doop (NAV-1 / NAV-2) |
|---|---|---|---|
| Manufacturer | Overview: Dashboard. Products: Products, Inventory, Shipments, Aggregation, Mobile users. Compliance: **"EPCIS events"** → `/manufacturer/epcis` | Reference data: Mobile users, Sites. Account: API keys, **"TNT reporting"** → `/manufacturer/epcis`, Org settings | The same route has two labels ("EPCIS events" vs "TNT reporting"). Hero icons. Group names don't match NAV-2 (Manufacturer / Account). |
| Distributor | Overview: Dashboard. Inventory: Receiving, Inventory (→ `/distributor/products`). Sales & distribution: Shipments, Customers, Returns | Reference data: Mobile users, Sites. Account: Billing, API keys, TNT reporting, Org settings | No Stock item (route is a redirect). No Customer returns. NAV-1 wants Distributor / Reference data / Account with Phosphor icons. |
| Pharmacy | Dashboard, Quick sale, Prescriptions, Patients / Stock, Receive stock, Requisitions, Scan / Payments: Transactions | (org groups) | Phosphor icons already used. |
| Lab | Dashboard, Orders, Patients, Tests / Stock, Receive stock, Requisitions, Scan / Payments: Transactions | (org groups) | Phosphor icons already used. |
| Org | Dashboard, Requisitions (multi-site only), Transactions | Organization: Sites, Products, Suppliers, Team, Mobile users. Account: API keys, TNT reporting, Org settings | The `/org/stock-takes` and `/org/disposals` approval queues aren't in the nav, and no page links to them (see §2.4). |
| Platform | Dashboard, Audit activity, Recalls | — | No Organizations route (the file exists, unrouted). |

The account menu (SHELL-ACCOUNT) lives in `td_account_chip` (td_components ~L1000) and is done on the branch. Per Bau's §18 flag, the code has no Account settings LiveView and no in-app password change; only `/reset-password` by email exists.

### 2.3 Detail pages with no back link (static search; verify)

| Route | Module | Reached from |
|---|---|---|
| `/manufacturer/sscc/:id/serials` | `ManufacturerSsccLive.Serials` | Product SSCCs list, product detail SSCC card, pallet detail, after packing a shipper |
| `/manufacturer/sscc/:id/label` | `ManufacturerSsccLive.Label` | Product SSCCs list, product detail SSCC card |
| `/manufacturer/products/:id` | `ManufacturerProductLive.Show` | Inventory "View product", dashboard Recent serial jobs rows |
| `/manufacturer/shipments/:id` | `ManufacturerShipmentLive.Review` | Shipments list "Review", after creating a shipment. Only the packing list has "Back to shipment". |
| `/manufacturer/aggregations/:id` | `ManufacturerAggregationLive.Review` | nothing routed (orphan) |
| `/org/batches/:id` | `BatchLive.Show` | org product pages |
| `/pharmacy/stock-takes/:id`, `/pharmacy/disposals/:id`, `/pharmacy/prescriptions/:id` (+ `/receipt`) | StockTakeLive.Show, DisposalLive.Show, PrescriptionLive.Show | their lists |
| `/lab/stock-takes/:id`, `/lab/disposals/:id` | LabStockTakeLive.Show, LabDisposalLive.Show | their lists |
| `/lab/transactions/:id` (+ `/receipt`) | EarningsLive :lab_show | transactions list (probably a modal over the list: verify) |
| `/distributor/returns/:id` | DistributorDisposalLive.Show | returns list |

Detail pages that do have a back link: org sites/products/requisitions, pharmacy/lab patients, pharmacy/lab stock product and batch (SiteStock "Back to Stock" / "Back to product"), distributor shipments, cases (`history.back`), batches, products, receiving, billing invoice, manufacturer pallets, aggregation wizard, product serials and SSCCs ("← Products").

### 2.4 Routes with no inbound link from any routed page

| Route | Note |
|---|---|
| `/manufacturer/aggregations/new`, `/manufacturer/aggregations/pallets/:pallet_id/ssccs/new` | Aggregation wizard (pallet or standalone shipper). Linked only from the unrouted `List`. |
| `/manufacturer/aggregations/ssccs/:id` | Shipper SSCC detail. Reached only by the wizard's `push_navigate` after saving. |
| `/manufacturer/aggregations/:id` | Aggregation review (approve/reject a scanned aggregation). Linked only from the unrouted `List` and `Form`. |
| `/distributor/stock`, `/distributor/expiring` | Redirect stubs (`DistributorStockLive.Index` → `/distributor/products?view=batches[&expiry=near]`). |
| `/org/stock-takes`, `/org/disposals` (and their `/:id`, `/approve`, `/reject`) | The org approval queues for stock takes and disposals. They link only to each other; nothing in the nav, dashboards or other pages points at the index pages. I didn't check whether emails link to them. |
| `/org/stock-takes/:id/approve`, `/org/disposals/:id/approve` | Modal routes that nothing links to: the lists approve inline with `phx-click` (verify). |


## 3. Manufacturer

### 3.1 Routes

Session `:manufacturer` (`require_manufacturer_access`), plus `:manufacturer_admin` for mobile users, API keys and settings. Shell: `Layouts.manufacturer_shell`.

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/manufacturer` | `ManufacturerDashboardLive` :index | `live/manufacturer_dashboard_live.ex` | manufacturer | TD | td_badge, td_button, td_dash_card, td_dash_row, td_dashboard, td_glance_cell … · td_dashboard | 0 |  |
| `/manufacturer/aggregations` | `ManufacturerAggregationLive.Dashboard` :index | `live/manufacturer_aggregation_live/dashboard.ex` | manufacturer | Legacy |  · legacy: button, header | 1 |  |
| `/manufacturer/aggregations/:id` | `ManufacturerAggregationLive.Review` :show | `live/manufacturer_aggregation_live/review.ex` | manufacturer | TD | td_button, td_empty, td_input, td_modal, td_page_header | 4 | **none** |
| `/manufacturer/aggregations/new` | `ManufacturerAggregationLive.Wizard` :new | `live/manufacturer_aggregation_live/wizard.ex` | manufacturer | Legacy |  · legacy: button, header, input | 5 |  |
| `/manufacturer/aggregations/pallets/:id` | `ManufacturerAggregationLive.PalletShow` :show | `live/manufacturer_aggregation_live/pallet_show.ex` | manufacturer | Legacy |  · legacy: blank_state, button, header | 0 |  |
| `/manufacturer/aggregations/pallets/:pallet_id/ssccs/new` | `ManufacturerAggregationLive.Wizard` :new_on_pallet | `live/manufacturer_aggregation_live/wizard.ex` | manufacturer | Legacy |  · legacy: button, header, input | 5 |  |
| `/manufacturer/aggregations/pallets/new` | `ManufacturerAggregationLive.PalletNew` :new | `live/manufacturer_aggregation_live/pallet_new.ex` | manufacturer | Legacy |  · legacy: button, header | 5 |  |
| `/manufacturer/aggregations/ssccs/:id` | `ManufacturerAggregationLive.SsccShow` :show | `live/manufacturer_aggregation_live/sscc_show.ex` | manufacturer | Legacy |  · legacy: button, header, input, modal | 7 |  |
| `/manufacturer/api-keys` | `ApiKeysLive` :index | `live/api_keys_live.ex` | manufacturer_admin | Mixed | td_page_header · legacy: button | 9 |  |
| `/manufacturer/epcis` | `ManufacturerEpcisLive` :index | `live/manufacturer_epcis_live.ex` | manufacturer | Mixed | td_button, td_page_header · legacy: blank_state, button, modal, search_input | 10 |  |
| `/manufacturer/inventory` | `ManufacturerInventoryLive` :index | `live/manufacturer_inventory_live.ex` | manufacturer | TD | td_button, td_card_header, td_data_table, td_empty, td_list_page | 0 |  |
| `/manufacturer/mobile-users` | `ManufacturerMobileUserLive.Index` :index | `live/manufacturer_mobile_user_live/index.ex` | manufacturer_admin | TD | td_badge, td_button, td_confirm, td_data_table, td_empty, td_input … | 7 |  |
| `/manufacturer/mobile-users/:id/edit` | `ManufacturerMobileUserLive.Index` :edit | `live/manufacturer_mobile_user_live/index.ex` | manufacturer_admin | TD | td_badge, td_button, td_confirm, td_data_table, td_empty, td_input … | 7 |  |
| `/manufacturer/mobile-users/new` | `ManufacturerMobileUserLive.Index` :new | `live/manufacturer_mobile_user_live/index.ex` | manufacturer_admin | TD | td_badge, td_button, td_confirm, td_data_table, td_empty, td_input … | 7 |  |
| `/manufacturer/products` | `ManufacturerProductLive.Index` :index | `live/manufacturer_product_live/index.ex` | manufacturer | Mixed | td_button, td_data_table, td_empty, td_key_value, td_list_page, td_modal … · legacy: pagination · live_component: SerialWizard | 4 |  |
| `/manufacturer/products/:gtin/serials` | `ManufacturerProductLive.Serials` :index | `live/manufacturer_product_live/serials.ex` | manufacturer | Legacy |  · legacy: blank_state, button, header, input, pagination | 12 |  |
| `/manufacturer/products/:gtin/serials/new` | `ManufacturerProductLive.Index` :new_serial | `live/manufacturer_product_live/index.ex` | manufacturer | Mixed | td_button, td_data_table, td_empty, td_key_value, td_list_page, td_modal … · legacy: pagination · live_component: SerialWizard | 4 |  |
| `/manufacturer/products/:gtin/ssccs` | `ManufacturerProductLive.Ssccs` :index | `live/manufacturer_product_live/ssccs.ex` | manufacturer | Legacy |  · legacy: blank_state, button, header, modal | 3 |  |
| `/manufacturer/products/:id` | `ManufacturerProductLive.Show` :show | `live/manufacturer_product_live/show.ex` | manufacturer | TD | td_button, td_card_header, td_data_table, td_detail_page, td_empty, td_input … | 4 | **none** |
| `/manufacturer/products/:id/sscc` | `ManufacturerProductLive.Show` :create_sscc | `live/manufacturer_product_live/show.ex` | manufacturer | TD | td_button, td_card_header, td_data_table, td_detail_page, td_empty, td_input … | 4 |  |
| `/manufacturer/settings` | `OrganizationSettingsLive` :index | `live/organization_settings_live.ex` | manufacturer_admin | Mixed | td_button, td_page_header · legacy: button, input | 6 |  |
| `/manufacturer/shipments` | `ManufacturerShipmentLive.List` :index | `live/manufacturer_shipment_live/list.ex` | manufacturer | Mixed | td_badge, td_button, td_data_table, td_empty, td_key_value, td_list_page … · legacy: pagination | 3 |  |
| `/manufacturer/shipments/:id` | `ManufacturerShipmentLive.Review` :show | `live/manufacturer_shipment_live/review.ex` | manufacturer | TD | td_button, td_data_table, td_empty, td_key_value, td_page_header | 2 |  |
| `/manufacturer/shipments/:id/packing-list` | `ManufacturerShipmentLive.Review` :packing_list | `live/manufacturer_shipment_live/review.ex` | manufacturer | TD | td_button, td_data_table, td_empty, td_key_value, td_page_header | 2 |  |
| `/manufacturer/shipments/new` | `ManufacturerShipmentLive.Form` :new | `live/manufacturer_shipment_live/form.ex` | manufacturer | TD | td_button, td_input, td_page_header, td_select, td_switch · live_component: GlnSearchField | 3 |  |
| `/manufacturer/sscc/:id/label` | `ManufacturerSsccLive.Label` :show | `live/manufacturer_sscc_live/label.ex` | manufacturer | TD | td_button, td_page_header | 0 | **none** |
| `/manufacturer/sscc/:id/serials` | `ManufacturerSsccLive.Serials` :show | `live/manufacturer_sscc_live/serials.ex` | manufacturer | Legacy |  · legacy: button, header | 3 | **none** |

Controllers: `GET /manufacturer/sscc/:id/export` (`ManufacturerSsccExportController`, SSCC CSV) and `GET /manufacturer/products/:gtin/batches/:batch_id/serials/export` (`ManufacturerSerialExportController`, batch serials CSV; `:batch_id` is the **batch number**, not an id).

### 3.2 Data model and where things are stored

| Thing | Where it lives | Notes |
|---|---|---|
| Products | `manufacturer_products` (`Manufacturing.Product`) | Synced from the GS1 member API `GET /HBS/products` (`Manufacturing.sync_products/2`, upsert by GTIN). |
| Batches | `manufacturer_batches` (local) **and** GS1 `getbarcode_batches` (remote) | The Products and Serials pages read GS1. Inventory, product detail and the dashboard read the local table. |
| Primary serials | `manufacturer_serials` (local) **and** GS1 `get_batch_serials` (remote) | The serials page reads GS1 and caches per visit. |
| Shipper SSCCs | `manufacturer_shipper_ssccs` (`packed_serials` array column, `count_of_trade_items`, from/to parties, `order_number`, `manufacturer_pallet_id`) | Minted by GS1 `create_shipper_sscc` or `create_sscc`. Serials inside are read from GS1 `get_sscc_contents`. |
| Pallets | `manufacturer_pallets` | The code is a **local random `PAL-…`**, not a GS1 SSCC. |
| Manufacturer shipments | `manufacturer_shipments` + `manufacturer_shipment_items` | Written automatically when shippers are packed (`record_dispatch_shipment!`). **No routed page lists them.** |
| Portal shipments | `distributor_shipments` (participant tier `"manufacturer"`) | What `/manufacturer/shipments` lists, creates and approves (draft → mobile packs → submitted → approved). |
| Aggregations | `manufacturer_aggregations` + `_items` | Scan-to-aggregate review records. Created only by the unrouted `Form`, approved by the orphan `Review`. |
| Serial jobs | **no table** | The dashboard's "Recent serial jobs" are the latest local batches with their serial counts (`Manufacturing.dashboard_summary/2`, added on our branch). |

Oban: `ThamaniDawa.Manufacturing.ProductSyncWorker` (queue `:gs1`, unique per org for 60 s, 5 attempts) runs `sync_products`. **It's only enqueued when a manufacturing site is created** (`Sites` ~L106). The "Sync from GS1" button calls `sync_products` synchronously in the LiveView process. EPCIS events go to the outbox and are sent by `ThamaniDawa.Epcis.SubmissionWorker`.

### 3.3 Journey: products → serials → print → shipper → pallet → shipment

**Step 1. Products list** (`/manufacturer/products`, `ManufacturerProductLive.Index`)
- `handle_params` → `load_products/1`. This calls `Manufacturing.paginate_products_with_counts` (local) and `Manufacturing.remote_product_counts` (**a live GS1 `list_products` HTTP call on every `handle_params`**, which includes every search keystroke patch and page change), plus `Billing.active_usage` for "Maximum".
- Events:
  - `search` and `set_view` (list/grid) `push_patch` with `?search=&view=`.
  - `reset` → `push_patch /manufacturer/products`.
  - `sync_products` → `Manufacturing.sync_products` (synchronous GS1 call), then a flash "Synced N products from GS1."
- Buttons per row:
  - SSCC column: count + **"View"** → `navigate /manufacturer/products/:gtin/ssccs`.
  - Serials column: count + **"View"** → `navigate /manufacturer/products/:gtin/serials`.
  - Row action **"Serial"** (primary) → `patch /manufacturer/products/:gtin/serials/new`.
  - Grid cards have the same "Serial" button.
- Empty state: "No products found" / "Add or sync a GTIN to start generating primary serials." **There's no Add product button** on this page, although Doop has yWiBLt5W4_ "Add product" and the dashboard frame shows "Add product".
- Friction: two identical "View" labels; "Serial" should read e.g. "Generate serials", with "View serials" and "View SSCCs" on the others (Sean's ask).

**Step 2. Generate serials** (modal `:new_serial`, LiveComponent `ManufacturerProductLive.SerialWizard`, `serial_wizard.ex` 643 lines)
- `apply_action(:new_serial)` loads the product by GTIN, the current site (`Sites.get_site!(org, scope.current_site_id)`) and all facilities.
  - **(verify)** With no current site picked (admin "Manage organization" context), `get_site!` with a nil id would raise.
- Step 1 `choose_mode`: "Make to order" or "Make to stock" (`td_mode_picker`).
- **Make to stock** (2 steps): Batch #, Primary quantity, Production date, Expiry date (Doop date picker) → "Generate serials" → `save` → `Manufacturing.generate_primary_serials/5`. That function does:
  - a GS1 `create_serials` HTTP call
  - then in one transaction: `find_or_create_batch`, persist the serials, and `Epcis.record_manufacturer_commission` (Commission event)
- **Make to order** (3 steps): batch fields + "Units per shipper SSCC" → "Next" → parties step:
  - From facility (select from own sites, autofills company and address)
  - To GLN combobox (`search_to_gln` / `select_to_gln`, backed by `GlnLookup.search_destination`)
  - To company/address (read-only)
  - Order number (required since aa6aaec)
  - → "Generate serials & SSCCs" → `Manufacturing.generate_order_serials/7`. That function makes a GS1 `create_serials` call, then in a transaction:
    1. persists the serials
    2. records Commission
    3. `create_order_pallet` (local PAL code)
    4. mints one shipper per chunk via GS1 `create_shipper_sscc`, with an EPCIS Pack per shipper
    5. `record_dispatch_shipment!` (an **approved** `manufacturer_shipments` row + EPCIS Ship)
  - The guard needs `rem(primary, shipper) == 0`. The error copy ("…positive integer no greater than the primary quantity") doesn't mention that the primary quantity must divide evenly.
- Risk: the GS1 calls happen **before and outside** the DB transaction. If the local transaction fails, GS1 has issued serials the app has no record of.
- **Where it goes after success (master logic, canon):** both modes `push_navigate` to `/manufacturer/products/:gtin/serials?batch=<batch_no>` with a flash. So Sean's "take me to the batch I just made serials for" is now the code's behaviour.
- Dead code left over:
  - the `@issued` "Serials issued" panel (Back to product / **Open inventory** / Open aggregation / New shipment), because `:issued` is never assigned now
  - the four `handle_info({:serials_issued, …})` clauses in `Index`
  - Doop frames kyQHKTVNuw / pu69ruhFa_ still draw this old success screen. **Doop needs updating to the new landing.**
- Errors come back to `Index` as `{:serial_generation_failed, reason}` → flash. The copy covers `:unconfigured`, `:unavailable`, `:not_found` (GTIN not under this GS1 account), `:unauthorized`, `:forbidden` (no SSCC API access) and `:invalid_quantity`.
- Cancel/close: `on_cancel` → `JS.patch /manufacturer/products`.

**Step 3. Batches and serials: view and print** (`/manufacturer/products/:gtin/serials`, `ManufacturerProductLive.Serials`, 958 lines, **Legacy UI**)
- `handle_params`: `ensure_batches` runs once per visit and only when connected. It calls `Manufacturing.fetch_product_batches` (GS1 `getbarcode_batches` merged with local batches). `select_batch` then picks the `?batch=` batch, **falling back to the first batch** if it isn't in GS1's list yet. It loads that batch's serials (GS1 `get_batch_serials`, cached in `serials_cache`) and `Manufacturing.list_batch_shippers` (local).
- Layout: a left rail of batch cards (`patch ?batch=`), and on the right the selected batch with a serials grid, 24 per page. Each serial card has its own **Print** (`phx-hook="LabelPrint"`) and **Download as SVG** (`LabelSvgDownload`) with a DataMatrix (`phx-hook="DataMatrix"`).
- Header actions:
  - "Create shipper SSCC" (`open_pack`), hidden when the batch is fully packed ("All serials packed")
  - **"Export CSV"** → `href /manufacturer/products/:gtin/batches/:batch_no/serials/export`
- **There's no "Print batch" or "Print page" button.** Printing a 1,000-unit batch means 1,000 clicks, or exporting CSV to another tool.
- Back: "← Products" → `navigate /manufacturer/products`.
- Empty: "No serials yet" / "Use + Serial on the Products page to create the first batch." This copy refers to a "+ Serial" button that's actually labelled "Serial".
- Errors: the GS1 batch list failing shows a red box with "Retry" (`retry` → `push_patch` to the same page).

**Step 4. Pack serials into a shipper SSCC** (inline panel on the same page)
- `open_pack` → `Manufacturing.fetch_unpacked_serials` (GS1 `list_unpacked_serials`), with every unpacked serial preselected.
- `toggle_pack_serial`, `pack_select_all`, `pack_clear`; From facility select; To GLN combobox (`search_pack_to_gln` / `select_pack_to_gln`).
- `submit_pack` → `Manufacturing.pack_serials_into_shipper/6`: a GS1 `create_shipper_sscc` call, then a transaction:
  - insert the `ShipperSscc` with `packed_serials`
  - link the local batch and serials
  - EPCIS Pack (`record_manufacturer_serial_pack`)
  - **`record_dispatch_shipment!`** (an approved shipment + EPCIS Ship)
- On success it navigates to `/manufacturer/sscc/:id/serials` (the SSCC serials page, which has **no back link**). The natural next step is the case label, which the user has to find via Products → SSCC "View".

**Step 5. SSCCs for a product** (`/manufacturer/products/:gtin/ssccs`, `ManufacturerProductLive.Ssccs`, Legacy)
- Local `Manufacturing.list_sscc_groups`, grouped by pallet code.
- Per shipper:
  - → `/manufacturer/sscc/:id/serials`
  - → `/manufacturer/sscc/:id/label`
  - `href` `/manufacturer/sscc/:id/export`
- The `show_shippers` modal has shipper/primary tabs and "Print All Shipper" (`PrintAllLabels` hook). Copy: "Print All Shipper" should be "Print all shipper labels".
- Empty copy is wrong: "No SSCCs — these are created when stock is shipped".
- Back: "← Products".

**Step 6. SSCC serials and case label**
- `/manufacturer/sscc/:id/serials` (`ManufacturerSsccLive.Serials`, Legacy): `Manufacturing.fetch_sscc_serials` (GS1 `get_sscc_contents`), with `next_page`, `prev_page` and `retry`, and a per-serial Print. **No back link.**
- `/manufacturer/sscc/:id/label` (`ManufacturerSsccLive.Label`, TD): `ensure_shipper_parties` fills missing from/to parties. "Print" uses the `LabelPrint` hook. **No back link.** The crumb says "Products".

**Step 7. Pallet (aggregation)**
- `/manufacturer/aggregations` (`ManufacturerAggregationLive.Dashboard`, Legacy): `Manufacturing.list_pallets` with a client-side `search` filter. Rows → `/manufacturer/aggregations/pallets/:id`. The only action is **"Create pallet SSCC"** → `/manufacturer/aggregations/pallets/new`.
- `/manufacturer/aggregations/pallets/new` (`PalletNew`, Legacy, added on master 23 Nov): `Manufacturing.list_available_ssccs` (shippers on **no** shipment). Events: `search` (a text filter over SSCC/GTIN/batch/pallet), `toggle`, `select_visible`, `clear`, and `create` → `Manufacturing.create_pallet_from_shippers` (local PAL code, parties copied from the first selected shipper, shippers re-parented). It then navigates to the pallet.
  - **No scanning, no GS1 SSCC, no EPCIS event.**
  - **The shippers from steps 2 (order) and 4 are filtered out**, because they already have a shipment (§1, problem 1).
  - The back link `back=/manufacturer/aggregations` works.
- `/manufacturer/aggregations/pallets/:id` (`PalletShow`, Legacy): read-only shipper cards with links to `/manufacturer/sscc/:id/serials`. No pallet label, no "Add shipper", no "Ship pallet". Back works.
- Orphans (designed in AGG-1, present in code, unreachable):
  - `Wizard` (`/aggregations/new`, `/pallets/:pallet_id/ssccs/new`): `choose_type` pallet|shipper. For a pallet it calls `create_pallet`; for a shipper it calls `mint_empty_shipper_sscc` (GS1 `create_shipper_sscc` with no serials).
  - `SsccShow` (`/aggregations/ssccs/:id`): `verify_gtin` / `save_gtin` (GtinLookup + `create_product`), `verify_bulk_gtins` / `save_bulk_gtins`, `save_batch` (`find_or_create_batch` + `add_batch_to_sscc`), and add a manual serial (`create_manual_serial`).
  - `Review` (`/aggregations/:id`): `approve` → `approve_aggregation` (EPCIS Pack), `reject` with a reason.
  - AGG-1 says to keep `/:id` Review. Bau's §15 notes that "nothing links to them from the new list".

**Step 8. Shipment**
- `/manufacturer/shipments` (`ManufacturerShipmentLive.List`, Mixed): `Distributor.list_shipments(participant_tier: "manufacturer")`, with filters for status and date range (`date_range_picker`) and search. "New shipment" → `/new`; row "Review" → `/:id`.
- `/manufacturer/shipments/new` (`Form`, TD + `GlnSearchField`):
  - Order number, origin site, "Destination is one of your sites" toggle (`toggle_transfer_mode`), destination GLN via `GlnSearchField`
  - `save` → `Distributor.create_shipment(org, user, attrs, "manufacturer")` → navigates to `/manufacturer/shipments/:id`
  - Cancel → list
  - Copy: "The mobile team finds this shipment by its order number, then scans units into shippers."
- `/manufacturer/shipments/:id` (`Review`, TD): `approve` → `Distributor.approve_shipment`. That function checks reservations, issues one SSCC per shipper through GS1 and charges billing, commits the reservations, dispatches batches, and records EPCIS `record_shipment_approval`. `toggle_shipper` expands rows. "View packing list" → `/:id/packing-list` (which has "Back to shipment"). **The show page has no back link to the list.**
- This flow depends on the mobile app packing the draft, and the packer API isn't on master. **On master today, a web-only manufacturer can create a draft but can't get it to "submitted".** (verify against the mobile app)

**Other manufacturer pages**
- `/manufacturer` dashboard (`ManufacturerDashboardLive`, TD, built on our branch to ssU7S65tZF): `dashboard_counts` + `dashboard_summary`.
  - Recent serial jobs rows → `JS.navigate /manufacturer/products/:product_id` (product detail, **not** the serials page with the batch selected).
  - "Open aggregations" counts `manufacturer_aggregations` but links to `/manufacturer/aggregations`, which lists pallets.
  - "Ready to ship" counts shippers not on any `manufacturer_shipments` row and links to the Shipments list, which reads the other table.
  - "Shipped this week" has the same problem.
  - **These three tiles count one model and link to another (our branch's own code; needs fixing).**
- `/manufacturer/products/:id` (`Show`, TD): local batches table + SSCC groups.
  - Actions: "Generate serials" (`patch` to `/manufacturer/products/:gtin/serials/new`, a route owned by **another LiveView**: Phoenix treats this as a full navigation to the Products page with the modal open, **verify**) and "Create SSCC" (`patch /:id/sscc` → modal → `create_sscc` → `Manufacturing.create_sscc`, GS1 + EPCIS Pack, no shipment).
  - It mixes the product id (`/:id`) and the GTIN (`/:gtin`) in sibling URLs.
  - The `save_batch` and `generate_serials` handlers have no form in the template (dead).
  - **No back link.**
- `/manufacturer/inventory` (`ManufacturerInventoryLive`, TD): local batches grouped by product; "View product" → `/manufacturer/products/:id`. No serials or print action.
- `/manufacturer/epcis` (`ManufacturerEpcisLive`, Mixed; TNT-1 queued):
  - Events: `filter_status`, `search`, `inspect_payload` / `close_inspect` / `select_inspection_tab`, `refresh`, `resubmit` (`Outbox.resubmit`), `send_event` / `send_now` (`SubmissionWorker.submit_now` / `enqueue_now`), and `set_submission_mode` (Manual/Automatic, `Organizations.update_epcis_submission_mode`).
  - Master added a migration that makes Automatic the default mode.
  - Links to the API keys path.
- `/manufacturer/mobile-users[/new|/:id/edit]` (TD), `/manufacturer/api-keys` (`ApiKeysLive`, APIKEYS-1 on hold), `/manufacturer/settings` (`OrganizationSettingsLive`).

### 3.4 What Sean's target flow needs (code view; Bau designs first)

| Sean's step | What the code does today | Gap |
|---|---|---|
| Products load from the GS1 JSON API | Sync on site create (Oban) + manual "Sync from GS1" (synchronous) | Clear empty and first-sync states. Avoid the GS1 count call on every keystroke. Add product exists in Doop, not in code. |
| Clear "Generate serials" / "View serials" | "Serial", "View", "View" | Rename and design. |
| After generating, land on the batch to print | Done in logic (`?batch=`) | The landing page is legacy UI, has no batch-level print or preview, and may select the wrong batch if GS1 lags. Doop still shows the old success screen. |
| Print serials | One label per click, plus CSV | Batch print and page print, with label size and copies. |
| Pack units into small shippers (SSCC) | Serials page panel (pick serials) or make-to-order chunks | Packing auto-ships (logic decision for Sean and Lucy). Lands on SSCC serials, not the label. |
| Scan shipper SSCCs to make a pallet | Checkbox picker, local PAL code | Scan input, a real GS1 pallet SSCC, an aggregation EPCIS event, a pallet label, and the auto-ship conflict. |
| Ship the pallet | Portal shipments are mobile-packed; manufacturer shipments are auto-created per shipper | One shipment model; pallet → shipment link. |


## 4. Distributor

### 4.1 Routes

Session `:distributor` (`require_distributor_access`), plus `:distributor_admin` for billing, mobile users, API keys, settings and EPCIS (a non-admin is bounced to `/distributor`). Shell: `Layouts.distributor_shell`. Shipments and mobile users also run `on_mount {DistributorAccess, :require_serialisation_plan}`: with no plan chosen, the user is redirected to `/distributor/billing/options`.

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/distributor` | `DistributorDashboardLive` :index | `live/distributor_dashboard_live.ex` | distributor | TD | td_badge, td_button, td_dash_card, td_dash_row, td_dashboard, td_glance_cell … · td_dashboard | 0 |  |
| `/distributor/api-keys` | `ApiKeysLive` :index | `live/api_keys_live.ex` | distributor_admin | Mixed | td_page_header · legacy: button | 9 |  |
| `/distributor/batches/:id` | `DistributorBatchLive` :show | `live/distributor_batch_live.ex` | distributor | Legacy |  · legacy: button, header, input, status_badge | 7 |  |
| `/distributor/billing` | `DistributorBillingLive.Index` :index | `live/distributor_billing_live/index.ex` | distributor_admin | Legacy |  · legacy: blank_state, button, header, stat_tile, table | 0 |  |
| `/distributor/billing/invoices/:id` | `DistributorBillingLive.Invoice` :show | `live/distributor_billing_live/invoice.ex` | distributor_admin | Legacy |  · legacy: button | 0 |  |
| `/distributor/billing/options` | `DistributorBillingLive.Options` :index | `live/distributor_billing_live/options.ex` | distributor_admin | Legacy |  · legacy: button, header | 2 |  |
| `/distributor/billing/payment` | `DistributorBillingLive.Payment` :prepay | `live/distributor_billing_live/payment.ex` | distributor_admin | Legacy |  · legacy: button, header, input | 3 |  |
| `/distributor/billing/postpay-payment` | `DistributorBillingLive.Payment` :postpay | `live/distributor_billing_live/payment.ex` | distributor_admin | Legacy |  · legacy: button, header, input | 3 |  |
| `/distributor/cases/:id` | `DistributorCaseLive` :show | `live/distributor_case_live.ex` | distributor | Legacy |  · legacy: button, header, input | 4 |  |
| `/distributor/customer-returns` | `DistributorCustomerReturnLive.Index` :index | `live/distributor_customer_return_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 14 |  |
| `/distributor/customer-returns/:id` | `DistributorCustomerReturnLive.Index` :show | `live/distributor_customer_return_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 14 |  |
| `/distributor/customer-returns/new` | `DistributorCustomerReturnLive.Index` :new | `live/distributor_customer_return_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 14 |  |
| `/distributor/customers` | `DistributorCustomerLive.Index` :index | `live/distributor_customer_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, table | 3 |  |
| `/distributor/customers/:id/edit` | `DistributorCustomerLive.Index` :edit | `live/distributor_customer_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, table | 3 |  |
| `/distributor/customers/new` | `DistributorCustomerLive.Index` :new | `live/distributor_customer_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, table | 3 |  |
| `/distributor/epcis` | `DistributorEpcisLive` :index | `live/distributor_epcis_live.ex` | distributor_admin | Legacy |  · legacy: blank_state, button, header, modal, search_input | 10 |  |
| `/distributor/expiring` | `DistributorStockLive.Index` :expiry | `live/distributor_stock_live/index.ex` | distributor | — (redirect) | — | 0 |  |
| `/distributor/mobile-users` | `DistributorMobileUserLive.Index` :index | `live/distributor_mobile_user_live/index.ex` | distributor_admin | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/distributor/mobile-users/:id/edit` | `DistributorMobileUserLive.Index` :edit | `live/distributor_mobile_user_live/index.ex` | distributor_admin | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/distributor/mobile-users/new` | `DistributorMobileUserLive.Index` :new | `live/distributor_mobile_user_live/index.ex` | distributor_admin | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/distributor/products` | `DistributorProductLive.Index` :index | `live/distributor_product_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 6 |  |
| `/distributor/products/:id` | `DistributorProductLive.Show` :show | `live/distributor_product_live/show.ex` | distributor | Legacy |  · legacy: blank_state, button, header, pagination, stat_tile, status_badge, table | 0 |  |
| `/distributor/products/new` | `DistributorProductLive.Index` :new | `live/distributor_product_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 6 |  |
| `/distributor/receiving` | `DistributorReceivingLive` :distributor_index | `live/distributor_receiving_live.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, table | 27 |  |
| `/distributor/receiving/:id` | `DistributorGoodsReceiptLive` :distributor_show | `live/distributor_goods_receipt_live.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal | 2 |  |
| `/distributor/receiving/new` | `DistributorReceivingLive` :distributor_new | `live/distributor_receiving_live.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, table | 27 |  |
| `/distributor/returns` | `DistributorSupplierReturnLive.Index` :index | `live/distributor_supplier_return_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/distributor/returns/:id` | `DistributorDisposalLive.Show` :show | `live/distributor_disposal_live/show.ex` | distributor | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 7 | **none** |
| `/distributor/returns/new` | `DistributorSupplierReturnLive.Index` :new | `live/distributor_supplier_return_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/distributor/settings` | `OrganizationSettingsLive` :index | `live/organization_settings_live.ex` | distributor_admin | Mixed | td_button, td_page_header · legacy: button, input | 6 |  |
| `/distributor/shipments` | `DistributorShipmentLive.Index` :index | `live/distributor_shipment_live/index.ex` | distributor | Legacy |  · legacy: blank_state, button, header, input, pagination, search_input, table | 4 |  |
| `/distributor/shipments/:id` | `DistributorShipmentLive.Show` :show | `live/distributor_shipment_live/show.ex` | distributor | Legacy |  · legacy: button, header, input, modal | 12 |  |
| `/distributor/shipments/:id/delivery-note` | `DistributorShipmentLive.Document` :delivery_note | `live/distributor_shipment_live/document.ex` | distributor | Legacy |  · legacy: button | 0 |  |
| `/distributor/shipments/:id/edit` | `DistributorShipmentLive.Form` :edit | `live/distributor_shipment_live/form.ex` | distributor | Legacy |  · legacy: button, header, input · live_component: GlnSearchField | 3 |  |
| `/distributor/shipments/:id/packing-list` | `DistributorShipmentLive.Document` :packing_list | `live/distributor_shipment_live/document.ex` | distributor | Legacy |  · legacy: button | 0 |  |
| `/distributor/shipments/new` | `DistributorShipmentLive.Form` :new | `live/distributor_shipment_live/form.ex` | distributor | Legacy |  · legacy: button, header, input · live_component: GlnSearchField | 3 |  |
| `/distributor/stock` | `DistributorStockLive.Index` :index | `live/distributor_stock_live/index.ex` | distributor | — (redirect) | — | 0 |  |

Controller: `GET /distributor/shipments/:id/export` (`DistributorShipmentExportController`, CSV).

**UI status:** only `/distributor` (the dashboard, done to 8OjVBGuJw2) is on the TD kit. Every other distributor page is Legacy (`.header`, `.button`, `.input`, `.table`, `.modal`, hero icons).

### 4.2 Journeys

**Orders.** There is no orders entity or route. What Doop and Sean call an order is a **draft shipment** with an `order_number` (`Distributor` moduledoc). "Look at their orders" therefore maps to `/distributor/shipments?status=draft|submitted` today; a real orders page would be new work.

**Shipments: draft → pack (mobile) → submit → approve or reject → dispatch documents**

`ThamaniDawa.Distributor` owns the state machine: `draft → submitted → approved`, `submitted → rejected → (reopen) draft`. Every transition row-locks the shipment, writes a `ShipmentEvent` and broadcasts on PubSub.

1. `/distributor/shipments` (`DistributorShipmentLive.Index`)
   - `Distributor.list_shipments` with status, date range (`date_range_picker`), search and mobile-user filters (`apply_filters`, `clear_filter`, `clear_filters`, `search` → `push_patch`).
   - Subscribes to live updates.
   - Rows are clickable (`JS.navigate /distributor/shipments/:id`); "New shipment" → `/new`.
2. `/distributor/shipments/new` and `/:id/edit` (`Form`)
   - Fields: order number, origin = own site (`GlnLookup.search_origin`), "Destination is one of your sites" (`toggle_transfer_mode`), and destination GLN through the **`GlnSearchField` LiveComponent**, which searches the GS1 all-GLN directory and sends `{:gln_selected, id, party}` to the parent.
   - `save` → `Distributor.create_shipment` / `update_shipment` → navigates to `/distributor/shipments/:id`.
   - A link to `/org/sites/new` when there's no origin site.
   - Two baseline tests are stale against this hidden GLN input (§5).
3. Packing happens in the **mobile app** (`Distributor.list_shipments_for_mobile_user` and friends; no web UI).
4. `/distributor/shipments/:id` (`Show`, 1,050 lines)
   - Back link to the list works.
   - Actions: Edit (draft), Delivery note and Packing list (approved), Export CSV, Print labels (`PrintAllLabels` hook over `Reports.shipper_labels`), Reject (submitted, with a reason modal → `Distributor.reject_shipment`), and Approve (`open_approve` / `approve`).
   - `approve` → `Distributor.approve_shipment/3`:
     1. checks reservations
     2. `issue_ssccs!` (GS1 mints one SSCC per shipper and charges the billing allowance)
     3. commits reservations
     4. depletes batches (a batch reaching 0 moves to `:dispatch`)
     5. records EPCIS `record_shipment_approval`
   - `remove_item` (per unit), plus `open_save_customer` / `save_customer` (saves the destination as a customer, `Customers.create_customer`).
5. `/distributor/shipments/:id/delivery-note` and `/packing-list` (`Document`): printable, each with a back link to the shipment.
- Doop has states the code doesn't: **"pick list generated"** (EU_pnVe8Bz) and **"pick confirmed"** (wWgSbjzUSa). The code has no pick list (the moduledoc says so).

**Receiving**
1. `/distributor/receiving` (`DistributorReceivingLive :distributor_index`, 2,622 lines): the receipts list (`GoodsReceipts.list_receipts`); rows → `/distributor/receiving/:id`; "Receive" → `/new`.
   - `mount` needs a current distribution site. Without one it flashes "Select a distributor warehouse before receiving stock." and `push_navigate`s to `/distributor`.
2. `/distributor/receiving/new` (same LiveView, `:distributor_new`)
   - Origin GLN check (`validate_origin`, `GlnLookup.resolve_party`).
   - Scan or type a GTIN (`scan_gtin`, `GS1Decoder.parse`), or an SSCC (`validate_entry_sscc` → `Distributor.lookup_shipper_by_sscc`, so a delivery from another Thamani shipper pre-fills its items; `confirm_pending_shipper`).
   - Add item (`open_add_item`, `choose_product`, `add_to_delivery`), with inline new product (`save_new_product` → `Products.create_product`) and new supplier (`save_new_supplier`).
   - Received and damaged quantities per group; document uploads (delivery note, invoice, other).
   - A saved draft (`GoodsReceipts.ensure_receiving_draft`).
   - `finish_delivery` → `GoodsReceipts.receive_delivery`, which posts the receipt idempotently by `posting_key` and records EPCIS `record_goods_receipt`. Then it stores attachments, finalises the draft, persists discrepancies and escalates flagged items.
   - After that it **`push_patch`es to the receipts list**, not to the new receipt. **Friction:** after receiving you lose sight of what you just received.
   - Cancel → `patch` back to the list.
3. `/distributor/receiving/:id` (`DistributorGoodsReceiptLive`): the receipt, with `open_resolve` / `close_resolve` for discrepancies (`GoodsReceipts.resolve_discrepancy`). Back → the receiving list.

**Inventory: products, batches, cases**
- `/distributor/products` (`DistributorProductLive.Index`, the "Inventory" nav item): products (`Batches.stock_summary_by_product`) or `?view=batches`, with `filter_expiry`, `filter_hold`, `search` and `set_view`. Modal `/new`: add product (GTIN, names, pack contents, price, reorder level).
- `/distributor/products/:id` (`Show`): the product's batches, a back link, and "Receive" → `/distributor/receiving/new`.
- `/distributor/batches/:id` (`DistributorBatchLive`)
  - Batch detail with links to its goods receipt, case, shipments and child batches.
  - **Split into mini SSCCs** (`open_split`, `add_group`, `remove_group`, `split_evenly`, `break_into_mini_ssccs` → `Batches.break_into_mini_ssccs`, EPCIS `record_mini_sscc_split`).
  - Back → `/distributor/products?view=batches`.
- `/distributor/cases/:id` (`DistributorCaseLive`): **Break case** (`break_case` → `Batches.break_logistic_unit`, EPCIS `record_logistic_unit_break`) and `add_shipper` / `remove_shipper`. Back is `history.back()`.
- `/distributor/stock`, `/distributor/expiring`: redirects to `/distributor/products?view=batches[&expiry=near]`. **Doop's Stock page** (j2u8BBnf6m and others: storage zones, Move stock, Change status, Receiving/Picking/Staging/Dispatch columns) **has no code behind it.** The brief (DIS-50/51) maps it to `/distributor/products (zones)`; the stock-zone version is marked MISSING.

**Returns**
- Supplier returns: `/distributor/returns` (`DistributorSupplierReturnLive.Index`). This is an `InventoryDisposals` list for kind supplier return, filtered to the site; modal `/new` → `InventoryDisposals.create_disposal` → `/distributor/returns/:id`.
- `/distributor/returns/:id` (`DistributorDisposalLive.Show`): `add_batch`, `remove_item`, `submit` (with a confirm modal), and `reopen`. **No back link.** Approval happens in the org queue `/org/disposals`, which has no nav entry (§2.4).
- Customer returns: `/distributor/customer-returns[/new|/:id]` (`DistributorCustomerReturnLive.Index`, 1,444 lines, one LiveView with modals).
  - Pick the source shipment (`search_shipment`, `select_shipment`, `CustomerReturns.customer_for_shipment`) or a customer (`select_customer`); `switch_return_source`; add items with a condition.
  - Status steps: `mark_received` → `mark_inspected` → `complete` (`CustomerReturns.complete_return`, EPCIS `record_customer_return`).
  - **Not in the sidebar.** Doop's "Returns" tabs (supplier / customer, SLxbPI5Z4A and oxNAXRBPCz) imply a tab switch that the code doesn't have between the two routes (verify).

**Customers:** `/distributor/customers[/new|/:id/edit]` (`DistributorCustomerLive.Index`). A list plus modal form; `validate` / `save` → `Customers.create_customer` / `update_customer`, with GLN lookup (`Customers.lookup_gln`) and `skip_gln`.

**Billing (admin):** `/distributor/billing` (usage, payments) → `/billing/options` (`choose_prepay` / `choose_flex`) → `/billing/payment` (`pay` → `Billing.start_prepay_payment`: a manual reference confirms immediately, and M-Pesa STK Push is used only when Daraja is enabled and configured; `cancel_pending`) or `/billing/postpay-payment` → `/billing/invoices/:id` (with a back link). The plan gate (`require_serialisation_plan`) redirects shipments and mobile users here. **(verify)** A *non-admin* distributor user in an org with no plan is sent to `/distributor/billing/options`, which is admin-only and bounces them to `/distributor`: a dead end with no explanation.

**Mobile users (admin):** `/distributor/mobile-users[/new|/:id/edit]`: `save` (create or update), `resend_pin`, `ask_deactivate` / `confirm_deactivate` / `cancel_deactivate`, and `activate`.

**TNT (admin):** `/distributor/epcis` (`DistributorEpcisLive`, shared with `/org/epcis`). It has the same events as the manufacturer page (§3.3); TNT-1 is queued.

**Dashboard** (`/distributor`, TD, done): `Reports.shipment_analytics`, batches and products, billing usage (`SerialUsage.serials_left`). Links: shipments by status (`?status=draft|submitted|…`), new shipment, receiving/new, products (batches, near expiry), billing/options, a recent shipment row → `/distributor/shipments/:id`, and a product row → `/distributor/products/:id`.


## 5. Pharmacy

Session `:pharmacy` (`require_pharmacy_access`). Shell: `Layouts.pharmacy_shell`. The combined pharma-lab site uses the same routes; the nav shows both lab and pharmacy groups.

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/pharmacy` | `PharmacyDashboardLive` :index | `live/pharmacy_dashboard_live.ex` | pharmacy | Legacy |  · legacy: blank_state, button, chart_card, header, stat_tile, status_badge, table | 0 |  |
| `/pharmacy/disposals` | `DisposalLive.Index` :index | `live/disposal_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/pharmacy/disposals/:id` | `DisposalLive.Show` :show | `live/disposal_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 6 | **none** |
| `/pharmacy/disposals/new` | `DisposalLive.Index` :new | `live/disposal_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/pharmacy/patients` | `PatientLive.Index` :index | `live/patient_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, header, pagination, search_input, table | 2 |  |
| `/pharmacy/patients/:id` | `PatientLive.Show` :show | `live/patient_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, header, table | 0 |  |
| `/pharmacy/prescriptions` | `PrescriptionLive.Index` :index | `live/prescription_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 11 |  |
| `/pharmacy/prescriptions/:id` | `PrescriptionLive.Show` :show | `live/prescription_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 3 | **none** |
| `/pharmacy/prescriptions/:id/payments/new` | `PrescriptionLive.Show` :new_payment | `live/prescription_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 3 |  |
| `/pharmacy/prescriptions/:id/receipt` | `PrescriptionLive.Show` :receipt | `live/prescription_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 3 | **none** |
| `/pharmacy/prescriptions/new` | `PrescriptionLive.Index` :new | `live/prescription_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 11 |  |
| `/pharmacy/quick-sale` | `QuickSaleLive` :new | `live/quick_sale_live.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal | 13 |  |
| `/pharmacy/receive-stock` | `ReceiveStockLive` :index | `live/receive_stock_live.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, table | 1 |  |
| `/pharmacy/receive-stock/:id/receive` | `ReceiveStockLive` :receive | `live/receive_stock_live.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, table | 1 |  |
| `/pharmacy/requisitions` | `RequisitionLive.Index` :index | `live/requisition_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 7 |  |
| `/pharmacy/requisitions/:id` | `RequisitionLive.Show` :show | `live/requisition_live/show.ex` | pharmacy | Legacy |  · legacy: button, header, status_badge | 0 |  |
| `/pharmacy/requisitions/new` | `RequisitionLive.Index` :new | `live/requisition_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 7 |  |
| `/pharmacy/scan` | `PharmacyScanLive` :index | `live/pharmacy_scan_live.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input | 1 |  |
| `/pharmacy/stock` | `PharmacyStockLive` :index | `live/pharmacy_stock_live.ex` | pharmacy | TD | td_button · SiteStock | 0 |  |
| `/pharmacy/stock-takes` | `StockTakeLive.Index` :index | `live/stock_take_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/pharmacy/stock-takes/:id` | `StockTakeLive.Show` :show | `live/stock_take_live/show.ex` | pharmacy | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 6 | **none** |
| `/pharmacy/stock-takes/new` | `StockTakeLive.Index` :new | `live/stock_take_live/index.ex` | pharmacy | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/pharmacy/stock/batches/:id` | `PharmacyStockBatchLive` :show | `live/pharmacy_stock_batch_live.ex` | pharmacy | TD (via SiteStock) |  · SiteStock | 2 |  |
| `/pharmacy/stock/products/:id` | `PharmacyStockProductLive` :show | `live/pharmacy_stock_product_live.ex` | pharmacy | TD (via SiteStock) |  · SiteStock | 0 |  |
| `/pharmacy/transactions` | `EarningsLive` :pharmacy | `live/earnings_live.ex` | pharmacy | Mixed | td_badge, td_button, td_icon, td_icon_button, td_orb · legacy: blank_state, header, input, modal, search_input, status_badge, table | 4 |  |

Journeys (logic from master, unchanged on the branch):
- **Quick sale** (`/pharmacy/quick-sale`, `QuickSaleLive`)
  - `scan_submit` / `search_catalog` / `quick_add` → cart (`increment_item`, `decrement_item`, `remove_item`) → `select_payment_type`, `set_cash_tendered` → `complete_sale` / `confirm_payment` → `Sales.create_quick_sale`, which records EPCIS `record_dispense`.
  - The page stays put afterwards (`new_sale` resets).
- **Prescriptions**
  - `/pharmacy/prescriptions/new` (modal): new, existing or no patient (`toggle_patient_mode`), with items (`add-item`, `edit-item`, `remove-item`). `save` → `Prescriptions.create_prescription_*` → `push_navigate /pharmacy/prescriptions/:id`.
  - `/:id`: `verify_item` (`Prescriptions.dispense_scanned_item` / `verify_dispensed_item`, EPCIS dispense).
  - Payment modal `/:id/payments/new` → `Payments.create_payment` / `complete_payment`; `/:id/receipt` shows the receipt. **No back link to the list** on `/:id`.
- **Stock** (`/pharmacy/stock`, `/stock/products/:id`, `/stock/batches/:id`): rebuilt on our branch on `ThamaniDawaWeb.SiteStock` (shared with lab).
  - Read-only, from `Batches.list_site_stock/2`; filtering, paging and CSV in memory (`set_view`, `search`, `set_filter`, `page`, `open_export`, `export_csv`, `export_product`).
  - The batch page has "Print Data Matrix" (`open_print`/`close_print`). **The label size and copies inputs are display-only**: "Print labels" calls `window.print()` once.
  - Back links: "Back to Stock" and "Back to product".
  - Master's version had `apply_filters`, `clear_chip`, `go_to_page` and similar; these were replaced by SiteStock's events. The behaviour is equivalent (verify).
- **Receive stock** (`/pharmacy/receive-stock`, modal `/:id/receive`): `receive` → `Batches.receive_batch` (EPCIS facility receipt) → `push_patch` to the list.
- **Requisitions** (`/pharmacy/requisitions`, modal `/new`, `/:id`): `save` → `Requisitions.create_multi_requisition`. The org admin fulfils them in `/org/requisitions` (multi-site orgs only).
- **Stock takes and disposals** (`/pharmacy/stock-takes`, `/pharmacy/disposals` + `/:id`)
  - Create (modal) → detail: `add_batch`, `record_count`, `submit` with confirm, `reopen`.
  - The org approves in `/org/stock-takes` / `/org/disposals`, which have no nav entry.
  - The detail pages have **no back link**.
- **Scan** (`/pharmacy/scan`): `decode` → `Batches.find_approved_batches_by_gtin`.
- **Patients** (`/pharmacy/patients`, `/:id` with a back link). **Transactions** (`/pharmacy/transactions`, `EarningsLive :pharmacy`).
- **Dashboard** (`/pharmacy`, `PharmacyDashboardLive`): **Legacy**, with `stat_tile`, Chart.js `chart_card` and tables (`Dashboards.dispensed_today`, `dispensed_by_day`, `top_dispensed_products`). The move to `<.td_dashboard>` against q2Wvk4Umn8 is queued.

## 6. Lab

Session `:lab` (`require_lab_access`). Shell: `Layouts.lab_shell`.

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/lab` | `LabDashboardLive` :index | `live/lab_dashboard_live.ex` | lab | TD | td_badge, td_button, td_dash_card, td_dash_row, td_dashboard, td_glance_cell … · td_dashboard | 0 |  |
| `/lab/disposals` | `LabDisposalLive.Index` :index | `live/lab_disposal_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/lab/disposals/:id` | `LabDisposalLive.Show` :show | `live/lab_disposal_live/show.ex` | lab | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 6 | **none** |
| `/lab/disposals/new` | `LabDisposalLive.Index` :new | `live/lab_disposal_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/lab/orders` | `LabOrderLive.Index` :index | `live/lab_order_live/index.ex` | lab | Mixed | td_badge, td_button, td_icon, td_key_value, td_orb, td_page_header · legacy: input, modal, status_badge | 11 |  |
| `/lab/orders/:id` | `LabOrderLive.Show` :show | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/collect` | `LabOrderLive.Show` :collect_specimen | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/consumables/new` | `LabOrderLive.Show` :record_consumable | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/payments/new` | `LabOrderLive.Show` :new_payment | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/report` | `LabOrderLive.Show` :print_report | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/results/:result_id/edit` | `LabOrderLive.Show` :edit_result | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/specimens/:specimen_id/label` | `LabOrderLive.Show` :print_specimen_label | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/:id/tests/new` | `LabOrderLive.Show` :add_test | `live/lab_order_live/show.ex` | lab | Mixed | td_button, td_count, td_icon · legacy: blank_state, button, input, modal, table | 9 |  |
| `/lab/orders/new` | `LabOrderLive.Index` :new | `live/lab_order_live/index.ex` | lab | Mixed | td_badge, td_button, td_icon, td_key_value, td_orb, td_page_header · legacy: input, modal, status_badge | 11 |  |
| `/lab/patients` | `LabPatientLive.Index` :index | `live/lab_patient_live/index.ex` | lab | Legacy |  · legacy: blank_state, header, pagination, search_input, table | 2 |  |
| `/lab/patients/:id` | `LabPatientLive.Show` :show | `live/lab_patient_live/show.ex` | lab | Legacy |  · legacy: blank_state, header, table | 0 |  |
| `/lab/receive-stock` | `LabReceiveStockLive` :index | `live/lab_receive_stock_live.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, table | 6 |  |
| `/lab/receive-stock/:id/receive` | `LabReceiveStockLive` :receive | `live/lab_receive_stock_live.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, table | 6 |  |
| `/lab/requisitions` | `LabRequisitionLive.Index` :index | `live/lab_requisition_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 7 |  |
| `/lab/requisitions/:id` | `LabRequisitionLive.Show` :show | `live/lab_requisition_live/show.ex` | lab | Legacy |  · legacy: button, header, status_badge | 0 |  |
| `/lab/requisitions/new` | `LabRequisitionLive.Index` :new | `live/lab_requisition_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 7 |  |
| `/lab/scan` | `LabScanLive` :index | `live/lab_scan_live.ex` | lab | Legacy |  · legacy: button, header, input | 1 |  |
| `/lab/stock` | `LabStockLive` :index | `live/lab_stock_live.ex` | lab | TD | td_button · SiteStock | 0 |  |
| `/lab/stock-takes` | `LabStockTakeLive.Index` :index | `live/lab_stock_take_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/lab/stock-takes/:id` | `LabStockTakeLive.Show` :show | `live/lab_stock_take_live/show.ex` | lab | Legacy |  · legacy: blank_state, button, input, modal, status_badge | 6 | **none** |
| `/lab/stock-takes/new` | `LabStockTakeLive.Index` :new | `live/lab_stock_take_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 2 |  |
| `/lab/stock/batches/:id` | `LabStockBatchLive` :show | `live/lab_stock_batch_live.ex` | lab | TD (via SiteStock) |  · SiteStock | 2 |  |
| `/lab/stock/products/:id` | `LabStockProductLive` :show | `live/lab_stock_product_live.ex` | lab | TD (via SiteStock) |  · SiteStock | 0 |  |
| `/lab/tests` | `LabTestLive.Index` :index | `live/lab_test_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/lab/tests/:id/edit` | `LabTestLive.Index` :edit | `live/lab_test_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/lab/tests/new` | `LabTestLive.Index` :new | `live/lab_test_live/index.ex` | lab | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/lab/transactions` | `EarningsLive` :lab | `live/earnings_live.ex` | lab | Mixed | td_badge, td_button, td_icon, td_icon_button, td_orb · legacy: blank_state, header, input, modal, search_input, status_badge, table | 4 |  |
| `/lab/transactions/:id` | `EarningsLive` :lab_show | `live/earnings_live.ex` | lab | Mixed | td_badge, td_button, td_icon, td_icon_button, td_orb · legacy: blank_state, header, input, modal, search_input, status_badge, table | 4 | **none** |
| `/lab/transactions/:id/receipt` | `EarningsLive` :lab_receipt | `live/earnings_live.ex` | lab | Mixed | td_badge, td_button, td_icon, td_icon_button, td_orb · legacy: blank_state, header, input, modal, search_input, status_badge, table | 4 | **none** |

Journeys:
- **Lab orders**
  - `/lab/orders` (`LabOrderLive.Index`): list with `search`, `set_filter`, `set_status`, `page`, `clear_filters`.
  - The `/new` modal is a stepped form (`goto_step`): patient (existing or `toggle_new_patient` → `Patients.create_patient`) and tests (`add_test` / `remove_test`). `save` → `LabOrders.create_lab_order_with_results` → **`push_patch /lab/orders` (back to the list, not the new order)**.
- **Order detail** (`/lab/orders/:id`, `LabOrderLive.Show`, 1,416 lines; the dialogs were rebuilt on our branch)
  - `switch_tab`.
  - Modal routes, all `push_patch`ing back to `/lab/orders/:id`:
    - `/tests/new` → `add_result` (`LabOrders.create_lab_order_result`)
    - `/collect` → `collect_specimen` (`LabOrders.collect_specimen`)
    - `/specimens/:sid/label` (print)
    - `/results/:rid/edit` → `save_result` (`LabOrders.record_result`)
    - `/consumables/new` → `search_consumable_products` / `select_consumable_product` → `LabOrders.record_consumable_usage`
    - `/report` (print, `LabReportComponent`)
    - `/payments/new` → `validate_payment` / `save_payment` (`Payments.create_payment` / `complete_payment`)
  - Back: "Back"/arrow to `/lab/orders`.
  - Queued: §5 orders and §6 payment/receipt frames.
- **Transactions**: `/lab/transactions` (`EarningsLive :lab`), `/:id` (`:lab_show`, links to the lab order) and `/:id/receipt` (`:lab_receipt`). Done to MC_1GL3a94 / 45FlJvpVyi / VRY0p3ZE2z.
- **Stock**: the same `SiteStock` pages as pharmacy (done: _VFeE7v1Z3, QxyvdDb1ea, eKD_3r3UqQ, 5MdRlvaDiH, scWNUBy5nv, 6gWHYiELXI).
- **Receive stock** (`/lab/receive-stock`, `/:id/receive`): `receive_batch` → `Batches.receive_batch`; `save_direct_receipt` → `Batches.receive_directly_at_site`.
- **Requisitions**, **stock takes** and **disposals**: same pattern as pharmacy. The detail pages for stock takes and disposals have **no back link**.
- **Tests** (`/lab/tests`, `/new`, `/:id/edit`): the test catalogue builder (`add_field_row`, `add_field_option`, `select_preset`, `toggle_active`, `save` → `LabTests.create_lab_test` / `update_lab_test`).
- **Patients**, **Scan** (`decode`).
- **Dashboard** (`/lab`): TD `<.td_dashboard>`, done on our branch (lDrhCsUsP3).

## 7. Org admin

Session `:organization` (`require_admin` + `require_confirmed_email`). Shell: `Layouts.org_shell`.

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/org/api-keys` | `ApiKeysLive` :index | `live/api_keys_live.ex` | organization | Mixed | td_page_header · legacy: button | 9 |  |
| `/org/batches/:id` | `BatchLive.Show` :show | `live/batch_live/show.ex` | organization | Legacy |  · legacy: blank_state, button, header, table | 0 | **none** |
| `/org/dashboard` | `OrgDashboardLive` :index | `live/org_dashboard_live.ex` | organization | Legacy |  · legacy: button, chart_card, header, stat_tile | 10 |  |
| `/org/disposals` | `InventoryDisposalQueueLive.Index` :index | `live/inventory_disposal_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/disposals/:id` | `InventoryDisposalQueueLive.Show` :show | `live/inventory_disposal_queue_live/show.ex` | organization | Legacy |  · legacy: button, header, status_badge | 1 |  |
| `/org/disposals/:id/approve` | `InventoryDisposalQueueLive.Index` :approve | `live/inventory_disposal_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/disposals/:id/reject` | `InventoryDisposalQueueLive.Index` :reject | `live/inventory_disposal_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/earnings` | `EarningsLive` :index | `live/earnings_live.ex` | organization | Mixed | td_badge, td_button, td_icon, td_icon_button, td_orb · legacy: blank_state, header, input, modal, search_input, status_badge, table | 4 |  |
| `/org/epcis` | `DistributorEpcisLive` :index | `live/distributor_epcis_live.ex` | organization | Legacy |  · legacy: blank_state, button, header, modal, search_input | 10 |  |
| `/org/mobile-users` | `OrgMobileUserLive.Index` :index | `live/org_mobile_user_live/index.ex` | organization | Mixed | td_badge, td_button, td_confirm, td_empty, td_input, td_list_page … · legacy: table | 7 |  |
| `/org/mobile-users/:id/edit` | `OrgMobileUserLive.Index` :edit | `live/org_mobile_user_live/index.ex` | organization | Mixed | td_badge, td_button, td_confirm, td_empty, td_input, td_list_page … · legacy: table | 7 |  |
| `/org/mobile-users/new` | `OrgMobileUserLive.Index` :new | `live/org_mobile_user_live/index.ex` | organization | Mixed | td_badge, td_button, td_confirm, td_empty, td_input, td_list_page … · legacy: table | 7 |  |
| `/org/products` | `ProductLive.Index` :index | `live/product_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 24 |  |
| `/org/products/:id` | `ProductLive.Show` :show | `live/product_live/show.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/org/products/:id/batches/:batch_id/dispatch` | `ProductLive.Show` :dispatch_batch | `live/product_live/show.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/org/products/:id/batches/new` | `ProductLive.Show` :new_batch | `live/product_live/show.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 7 |  |
| `/org/products/:id/edit` | `ProductLive.Index` :edit | `live/product_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 24 |  |
| `/org/products/import` | `ProductLive.Import` :new | `live/product_live/import.ex` | organization | Legacy |  · legacy: button, header | 7 |  |
| `/org/products/new` | `ProductLive.Index` :new | `live/product_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 24 |  |
| `/org/requisitions` | `RequisitionQueueLive.Index` :index | `live/requisition_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 6 |  |
| `/org/requisitions/:id` | `RequisitionQueueLive.Show` :show | `live/requisition_queue_live/show.ex` | organization | Legacy |  · legacy: button, header, status_badge | 0 |  |
| `/org/requisitions/:id/fulfill` | `RequisitionQueueLive.Index` :fulfill | `live/requisition_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 6 |  |
| `/org/requisitions/:id/reject` | `RequisitionQueueLive.Index` :reject | `live/requisition_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 6 |  |
| `/org/requisitions/:id/review` | `RequisitionQueueLive.Index` :review | `live/requisition_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, search_input, status_badge, table | 6 |  |
| `/org/settings` | `OrganizationSettingsLive` :index | `live/organization_settings_live.ex` | organization | Mixed | td_button, td_page_header · legacy: button, input | 6 |  |
| `/org/sites` | `SiteLive.Index` :index | `live/site_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/org/sites/:id` | `SiteLive.Show` :show | `live/site_live/show.ex` | organization | Legacy |  · legacy: blank_state, button, chart_card, header, stat_tile, status_badge, table | 9 |  |
| `/org/sites/:id/edit` | `SiteLive.Index` :edit | `live/site_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/org/sites/new` | `SiteLive.Index` :new | `live/site_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 12 |  |
| `/org/stock-takes` | `StockTakeQueueLive.Index` :index | `live/stock_take_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/stock-takes/:id` | `StockTakeQueueLive.Show` :show | `live/stock_take_queue_live/show.ex` | organization | Legacy |  · legacy: button, header, status_badge | 1 |  |
| `/org/stock-takes/:id/approve` | `StockTakeQueueLive.Index` :approve | `live/stock_take_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/stock-takes/:id/reject` | `StockTakeQueueLive.Index` :reject | `live/stock_take_queue_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, status_badge, table | 3 |  |
| `/org/suppliers` | `SupplierLive.Index` :index | `live/supplier_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 10 |  |
| `/org/suppliers/:id/edit` | `SupplierLive.Index` :edit | `live/supplier_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 10 |  |
| `/org/suppliers/new` | `SupplierLive.Index` :new | `live/supplier_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 10 |  |
| `/org/team` | `TeamLive.Index` :index | `live/team_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 11 |  |
| `/org/team/:id/edit` | `TeamLive.Index` :edit | `live/team_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 11 |  |
| `/org/team/new` | `TeamLive.Index` :new | `live/team_live/index.ex` | organization | Legacy |  · legacy: blank_state, button, header, input, modal, pagination, search_input, status_badge, table | 11 |  |

Journeys:
- **Dashboard** (`/org/dashboard`, `OrgDashboardLive`): Legacy (`stat_tile`, `chart_card`, `range_filter`, `date_range_picker`). It has search and range events and the onboarding checklist (`dismiss_onboarding_checklist`). `?tour=1` starts the product tour.
- **Team** (`/org/team`, `/new`, `/:id/edit`; `TeamLive.Index`, Legacy)
  - Invite: `save` → `Accounts.invite_user` + `deliver_user_invite`. Edit: `save_edit` → `Accounts.update_user`. `toggle_active` → `Accounts.set_user_active`, which uses the browser's `data-confirm`.
  - TEAM-1 (yPDN9VJLDO) is queued: multi-select role cards, sites filtered by role, status/deactivate inside the edit modal, a TD Modal confirm, a seeded orb instead of the letter avatar.
- **Mobile users** (`/org/mobile-users`): this one goes through the **GS1 member API** (`MemberApi.create_mobile_user`, `resend_mobile_user_pin`, `set_mobile_user_active`), not a local table. Mixed UI. Added on master 23 Nov.
- **Sites** (`/org/sites`, `/new`, `/:id`, `/:id/edit`)
  - GLN picker (`pick_gln`, `Grp.verify_gln`) → `Sites.create_site`. Creating a manufacturing site enqueues `ProductSyncWorker`.
  - `/org/sites/:id` (`SiteLive.Show`) is a site dashboard (dispensing, sales by payment method), with a back link.
- **Products**
  - `/org/products` (`ProductLive.Index`, 24 events): catalogue, GTIN scan or search, onboarding import, `toggle_active`.
  - `/org/products/import` (`ProductLive.Import`): CSV upload → map → confirm → `Importer.import_rows`; template at `GET /org/products/import/template`.
  - `/org/products/:id` (`ProductLive.Show`): `/batches/new` → `Batches.receive_into_org_stock` or `receive_directly_at_site`; `/batches/:batch_id/dispatch` → `Batches.dispatch_to_site`; `show_datamatrix`. Back link present.
  - `/org/batches/:id` (`BatchLive.Show`): read-only, **no back link**.
- **Suppliers** (`/org/suppliers`, `/new`, `/:id/edit`): create, update, `toggle_active`.
- **Requisitions queue** (`/org/requisitions` + `/:id/review|reject|fulfill`, `/:id`): `review_lines` / `approve` → `Requisitions.approve_requisition`; `reject`; fulfil → `fulfill_requisition_line(s)`. Shown in nav only for multi-site orgs.
- **Stock-take and disposal queues** (`/org/stock-takes`, `/org/disposals` + `/:id`): `approve` / `reject` (`StockTakes.approve_stock_take`, `InventoryDisposals.approve_disposal`). **Not linked from the nav or any page.**
- **API keys** (`/org/api-keys`, also `/manufacturer/api-keys` and `/distributor/api-keys`; `ApiKeysLive`)
  - EPCIS key per tier: `edit_api_key` / `save_api_key` / `clear_api_key` → `Organizations.set_epcis_api_key` / `clear_epcis_api_key`.
  - GS1 key: `edit_gs1_key` / `save_gs1_key` / `clear_gs1_key` → `Organizations.set_gs1_api_key`.
  - It also appears as an onboarding task step (`continue_onboarding`).
  - APIKEYS-1 is **on hold**.
- **Org settings** (`/org/settings`, also `/manufacturer/settings` and `/distributor/settings`; `OrganizationSettingsLive`): name and address, GS1 prefixes (`add_gs1_prefix`, `delete_gs1_prefix`, `set_primary_gs1_prefix`), GLN verify (`Grp.verify_gln`) and EPCIS submission mode.
- **TNT** (`/org/epcis`): `DistributorEpcisLive` (shared).
- **Transactions** (`/org/earnings`): `EarningsLive :index`.
- **Missing routes** (frames exist, no route): `/org/receiving` (PLA-104), `/org/earnings/:id` transaction detail (PLA-106), and notifications (shell bell, §0.3).

## 8. Platform admin

Session `:platform` (`require_superadmin`). Shell: `Layouts.platform_shell` (fixed nav: Dashboard, Audit activity, Recalls).

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/platform` | `PlatformDashboardLive` :index | `live/platform_dashboard_live.ex` | platform | Legacy |  · legacy: header, stat_tile | 0 |  |
| `/platform/audit` | `PlatformAuditLive` :index | `live/platform_audit_live.ex` | platform | Legacy |  · legacy: blank_state, header, input, pagination, search_input, stat_tile, table | 4 |  |
| `/platform/recalls` | `PlatformRecallLive` :index | `live/platform_recall_live.ex` | platform | Legacy |  · legacy: button, header | 2 |  |

- `/platform`: `PlatformDashboardLive`, Legacy (`stat_tile`), no events.
- `/platform/audit`: `PlatformAuditLive`, with filters and search.
- `/platform/recalls`: `PlatformRecallLive`, `initiate_recall`, `search`.
- **`PlatformOrganizationsLive` exists (99 lines) but has no route.** Doop PLA-102 `/platform/organizations` and the organization detail frames have no route.

## 9. Auth and signup

Controllers (not LiveView):
- `/login` (`SessionController :new/:create`, template `session_html/new.html.heex`)
- `DELETE /logout`
- `/reset-password[/:token]` (`PasswordResetController`)
- `/confirm/:token` (`ConfirmationController`)
- `PATCH /switch-site` (`SiteSwitchController`, the site switcher form in the shell)

| Path | LiveView :action | File (lib/thamani_dawa_web/) | live_session | UI kit | Main components | Events | Back link |
|---|---|---|---|---|---|---|---|
| `/confirm-email` | `ConfirmEmailLive` :index | `live/confirm_email_live.ex` | confirm_email | Custom markup | — | 1 |  |
| `/invites/:token` | `AcceptInviteLive` :edit | `live/accept_invite_live.ex` | accept_invite | Legacy |  · legacy: thamani_btn, thamani_input | 1 |  |
| `/onboarding` | `OnboardingLive` :index | `live/onboarding_live.ex` | organization | Custom markup | — | 3 |  |
| `/signup` | `SignupLive` :new | `live/signup_live.ex` | unauthenticated | Mixed | td_auth_card, td_button, td_input, td_option_card, td_step · legacy: input, thamani_btn, thamani_input | 11 |  |

- **Signup** (`/signup`, `SignupLive`, 1,823 lines, Mixed: `td_auth_card` + `td_option_card` + `td_step` + core `.input`)
  - `@steps [:operating_model, :gs1_key, :main_location, :administrator]`:
    1. **Operating model**: `validate_operating_model` / `continue_operating_model`.
    2. **GS1 key**: `verify_gs1_key` (async `MemberApi.get_company_prefixes` + `MemberApi.list_glns` with the typed key) / `continue_gs1_key`.
    3. **Main location**: `validate_site` / `continue_site`, with the GLN check via `Grp.verify_gln`.
    4. **Administrator**: `validate_administrator`, then `save`, which builds `Organization.signup_changeset`, `Site.default_changeset` and `User.registration_changeset`, then `phx-trigger-action` posts to `/login`.
  - `back` goes one step back; `restore_signup_draft` restores a localStorage draft.
  - **Master already removed the PPB licence collection** (aa6aaec, 15:47 EAT): there's no `ppb` field or event left in `signup_live.ex`.
  - **KMLTTB is still there:** the `maybe_check_kmlttb` gates in `continue_site` and `save` apply when `Site.kmlttb_required?(activities)` (lab activities), there's `select_kmlttb_candidate`, and `Site.default_changeset` still runs `validate_kmlttb_fields`.
  - SIGNUP-1 still needs: KMLTTB removed from signup, the licence fields made optional in `Site.default_changeset`, and the GS1/GLN state screens restyled to the frames.
  - The compiler warns about `step == :administrator` (a comparison between distinct types; seen in the test logs).
- **Accept invite** (`/invites/:token`, `AcceptInviteLive`): `save` → `Accounts.accept_invite`, then a hard `redirect /login`. Uses `thamani_btn` / `thamani_input`, an older kit than both TD and core.
- **Confirm email** (`/confirm-email`): `resend`.
- **Onboarding** (`/onboarding`, `OnboardingLive`): a checklist with `start_setup`, `skip` and `back`, each `push_navigate`ing to the next task path. When finished it goes to `/org/dashboard?tour=1`. TEAM-1 replaces the letter avatar in the invite header here.


## 10. Master vs our branch: flow diff

Compared: `origin/master` 95abf49 against `origin/sean/td-web-design-system` 368b03f (both worktrees), using the router, the list of LiveView modules, and each module's events and navigation targets.

**Routes:** `router.ex` is **identical** (0-line diff), so no flow exists on one side only at the route level. The LiveView module sets differ by one: the branch adds the shared `ThamaniDawaWeb.SiteStock` (a function-component and helper module, not a route).

**Logic files changed on the branch** (all additive; master's logic is untouched):

| File | Branch change |
|---|---|
| `lib/thamani_dawa/batches.ex` | +`list_site_stock/2` (feeds the SiteStock pages) |
| `lib/thamani_dawa/manufacturing.ex` | +`dashboard_summary/2` (feeds the manufacturer dashboard) |

**UI files the branch changed** (26 in `lib/`): `td_components.ex`, `layouts.ex`, `root.html.heex`, the lab report and specimen label components, and these LiveViews:
- distributor dashboard and shipment index
- earnings
- lab dashboard, order show, requisition index, and stock (3 pages)
- manufacturer dashboard and shipment list
- org dashboard
- pharmacy stock (3 pages)
- requisition index and requisition queue index
- site show

**Events and navigation that changed per module:**

| Module | On master only | On branch only | Effect |
|---|---|---|---|
| `LabStockLive`, `PharmacyStockLive` | `apply_filters`, `clear_chip`, `clear_filters`, `go_to_page`, `search`, `set_view` (inline) | handled in `SiteStock.handle_event/3` (`set_view`, `search`, `set_filter`, `page`, `open_export`, `close_export`, `export_csv`, `export_product`); new link to Receive stock | Same capability, new design, plus CSV export (verify filter parity) |
| `LabStockBatchLive`, `PharmacyStockBatchLive` | "Back to product" label in the module | `open_print` / `close_print` (Print Data Matrix dialog); the back link moved into `SiteStock.batch_detail` | Back kept; print added (display-only options) |
| `DistributorDashboardLive` | — | status-filtered shipments links, products, billing | Rebuilt to 8OjVBGuJw2 |
| `ManufacturerDashboardLive` | — | links to inventory, aggregations, shipments | Rebuilt to ssU7S65tZF (see the count/link mismatch in §3.3) |

**What master added recently that the branch has merged** (`6f8c43a..95abf49`, Michael Munavu and lkendi, 23 Nov 15:47–16:53 EAT):
- PPB removed from signup.
- The serial wizard lands on the serials page with `?batch=`, and order number is required.
- `PalletNew` (pallets from shippers) and a reworked `PalletShow` and aggregation dashboard.
- `Ssccs` page (+248 lines).
- SSCC label rework.
- `OrgMobileUserLive` (GS1-backed mobile users).
- Distributor receiving simplified (−218 lines).
- EPCIS default mode set to Automatic (migration).
- `order_number` on shipper SSCCs (migration).
- GS1 `member_api.ex` additions.
- Lab order index and show changes.

**Design-system canon vs master logic:** nothing on master's flows was dropped by the branch. The open risk goes the other way: master keeps adding flows in legacy markup (PalletNew, PalletShow, Ssccs, OrgMobileUser, label), so these need Doop frames and a rebuild. Following Sean's rule, they get listed for Bau first.


## 11. Status against Doop

The frame ledger (`/workspace/thamani/lab-compliance/frame-ledger.md`, 16:58 EAT) lists **482 web frames: 47 done, 5 in progress, 427 to do, 1 on hold, 2 archived**. `ledger/status.json` has the same 52 done or in-progress ids.

### 11.1 Built to Doop on our branch (committed in 933a8a9, merged in 368b03f)

| Area | Frames | Code |
|---|---|---|
| Dashboards: manufacturer, distributor, lab | ssU7S65tZF, 8OjVBGuJw2, lDrhCsUsP3 | `td_dashboard` / `td_dash_row` / `td_dash_card` / `td_glance_*` / `td_tick_row` in `td_components.ex`; `manufacturer_dashboard_live.ex`, `distributor_dashboard_live.ex`, `lab_dashboard_live.ex` |
| Lab stock flow (products, all batches, product detail, batch detail, row actions, Print Data Matrix, filter menus, export) | _VFeE7v1Z3, QxyvdDb1ea, eKD_3r3UqQ, 5MdRlvaDiH, scWNUBy5nv, 6gWHYiELXI | `site_stock.ex` + `lab_stock_*_live.ex` |
| Pharmacy and pharma-lab stock (same flow) | puMtQXqNOq, fO2XgZ8Xir, k6in9fJ2Ub, UlUYBX60A_, YIT-Xr3ym_, 87EK_g6B4h; c3EiqRelu0, fiY29WINlP, MS7rEsXApn, hXPInx920g, KNGUgpK574, NoAAUBFYIM | `site_stock.ex` + `pharmacy_stock_*_live.ex` |
| Lab order dialogs (add test, collect, specimen label, enter and amend result, consumable, print results) | kHgteJkTep, 63lZ570X4e, 5O8udg27kd, zJW8IHMTZV, WEiVx73bYh, ry2wSAtctR, WAOief8IVU | `lab_order_live/show.ex`, `lab_report_component.ex`, `specimen_label_component.ex` |
| Lab transactions (date range, detail, receipt), requisitions and orders date range | MC_1GL3a94, 45FlJvpVyi, VRY0p3ZE2z, 7ikGY9Ebrz, y11_7Bfo8B | `earnings_live.ex`, `lab_requisition_live/index.ex` |
| Date picker (single Doop picker) | TD DatePicker `chdlkoodd2` | `core_components.ex` `date_picker` / `date_range_picker` |
| Account menu (SHELL-ACCOUNT), all portals light and dark | y4OlKMJCvP and 13 per-portal copies | `td_account_chip` |

### 11.2 In progress

- **SHELL-COLLAPSED** (`LToUOeDNer`): collapsed rail and brand mark.
- Shared components: Export CSV (`2E9yucAGjQ`) and the Category/Status/Expiry filter menus (`RBA4UYrkXr`, `TTXzDZPEWP`, `v0UH0bx6L9`), being applied per list page.

### 11.3 Queued (in order)

| Item | Doop | Code it touches | Notes |
|---|---|---|---|
| Lab §5 orders | lab orders frames | `lab_order_live/index.ex` | Creating an order returns to the list (see §6). |
| Lab §6 payment and receipt | lab payment frames | `lab_order_live/show.ex` `:new_payment`, `earnings_live.ex` | |
| DATE-1 range filters | `chdlkoodd2` / gGZGY4la6k | every From/To filter; remove the dead `input[type=date]` CSS; route `datetime-local` to the picker | |
| TNT-1 | manufacturer 6h1jP1RQB5, org ZdiOKCCEg_, distributor brAo4lH0vA | `manufacturer_epcis_live.ex`, `distributor_epcis_live.ex` | Sent/Failed status mapping, EAT times, rename "EPCIS events" → TNT reporting, hide the API-keys hint on org/distributor, segmented control. |
| Pharmacy dashboard | q2Wvk4Umn8 | `pharmacy_dashboard_live.ex` | Move to `td_dashboard`, drop the Chart.js tables, "Recent serial jobs" style per Bau. |
| SIGNUP-1 | CLsksg2sae and others | `signup_live.ex`, `sites/site.ex` | PPB is already gone on master. Still needed: remove KMLTTB and make licences optional in `Site.default_changeset`. |
| AGG-1 | nooman_e0w and others | `manufacturer_aggregation_live/*` | See §3: half the routes are unreachable, and the pallet flow has logic gaps that need Sean/Lucy decisions before a restyle is worth it. |
| TEAM-1 | yPDN9VJLDO and others | `team_live/index.ex`, `onboarding_live.ex` | |
| APIKEYS-1 | dNqZMZIzMf | `api_keys_live.ex` | **On hold** until Bau's frames are ready. |
| NAV-1 / NAV-2 | distributor and manufacturer nav | `layouts.ex` item groups | |
| EMPTY-1 | disposals and returns empty states | pharmacy, lab and distributor disposals/returns | |
| Flagship manufacturer and distributor flows | Bau designing | — | **Paused** by Sean (17:05 EAT) pending this Notion doc. |


## 12. Test baseline and known gaps

### 12.1 Test baseline (from logs on the box; I didn't re-run anything)

| Log (EAT) | Code under test (my reading) | Result |
|---|---|---|
| `/tmp/base-test.log` 17:02 | master | 1,428 tests, 16 failures |
| `/tmp/merge-test.log` 17:03 | merged branch | 1,434 tests, 9 failures |
| `/tmp/s1-test.log` 17:09 | merged branch (another job) | 1,434 tests, 17 failures |
| `/tmp/s1b-test.log` 17:10 | merged branch (another job) | 1,434 tests, 9 failures |

**Six failures show up in every run, on master and on the branch alike.** That makes them the baseline, not regressions:

| Test | File | Why it fails |
|---|---|---|
| creates and dispatches a manufacturer shipment with a manufacturer EPCIS event | `test/thamani_dawa_web/live/manufacturer_shipment_live_test.exs:11` | `hidden "shipment[destination_gln]" must be one of [""]`. The test types into a field that is now the hidden input of `GlnSearchField`, so the test is stale. |
| shipments creating a draft shipment | `test/thamani_dawa_web/live/distributor_routes_test.exs:196` | Same hidden-GLN-input cause. |
| admin configures a brand-new organization end to end | `test/thamani_dawa_web/live/admin_setup_integration_test.exs:14` | Can't find `organization[name]`, because signup no longer has an org-name field (the name comes from GS1). |
| fulfill shows the needs_reorder banner and dispatches stock from the chosen batch | `test/thamani_dawa_web/live/requisition_queue_live_test.exs:74` | `#fulfill-form` not found. |
| approve_disposal/3 fully disposing an already-quarantined batch zeroes it without changing status | `ThamaniDawa.InventoryDisposalsTest` | `Batches` status transition rejects active → quarantined (`cannot move from active to this status`), so the test setup is stale against master's batch state machine. |
| new verifying the GLN reveals activity choices gated by the org's operating models | `test/thamani_dawa_web/live/site_live_test.exs:138` | Expects `#site-name[value='Test Licensee']`. |

These fail in some runs but not others (timing or shared-stub sensitive): the SignupLiveTest group (7), SiteLiveTest GLN picker (2), ManufacturerProductLiveTest (packing, make-to-stock, GS1 counts, eye links), and ManufacturerAggregationWizardTest "builds a pallet hierarchy". Several of them use the GS1 member API stub (`test/support/member_api_stub.ex`), which master changed on 23 Nov.

### 12.2 Known gaps (code)

| Gap | Detail |
|---|---|
| No serial-job record | No schema or table for a serial generation run. "Recent serial jobs" are derived from batches, so there's no record of who generated what, when, how many, or in which mode, and no retry or failure history. |
| Display-only print options | The SiteStock "Print Data Matrix" dialog has Label size (one option, 50×25 mm) and Copies, and neither is wired: "Print labels" runs `window.print()` once. Manufacturer serials print one label per click. There's no batch or bulk print for primary serials. |
| Pallet SSCCs aren't GS1 | `PAL-` + base32 local codes. |
| Auto-shipping on pack | See §1 problem 1 and §3.3 step 4. |
| Two shipment models | `manufacturer_shipments` vs `distributor_shipments` (tier manufacturer). See §1 problem 3. |
| No manufacturer or distributor mobile API on master | Portal shipments depend on mobile packing (PR #64's packer API is unmerged). |
| Missing routes for designed frames | `/org/receiving` (PLA-104), `/platform/organizations` and organization detail (PLA-102; the LiveView file exists, unrouted), notifications (bell, §0.3), `/org/earnings/:id` and `/pharmacy/transactions/:id` transaction detail (PLA-106, PHA-27, PHA-41), title-bar search / ⌘K results (§0.1), Account settings and profile (§18 flag). |
| Distributor stock page | Doop has storage zones, move stock, change status and the picking/staging/dispatch board. Code redirects `/distributor/stock` to products. |
| Distributor pick list | Doop has pick list generated and confirmed; the code has none. |
| Unreachable code | `PlatformOrganizationsLive`, `ManufacturerShipmentLive.Index/Show`, `ManufacturerAggregationLive.List/Form` (unrouted); routed-but-orphaned aggregation Wizard, SsccShow and Review; org stock-take and disposal queues with no entry point. |
| Synchronous GS1 calls in LiveView | "Sync from GS1" and `remote_product_counts` on every Products `handle_params`. |
| GS1 before DB | Serial and SSCC generation calls GS1, then writes locally. A local failure leaves identifiers issued at GS1 with no local record. |
| Times | `TimeFormat` gives EAT ("18 Nov 2026, 10:44"), but 53 `lib/` files still call `Calendar.strftime` directly (e.g. prescriptions, patients, site show, SSCC label and serials, distributor products, receiving and EPCIS, lab disposals and stock takes). Where the value is a raw UTC timestamp, the time shows in UTC and dates can be a day off near midnight. I didn't check each call. |
| Four GLN pickers | `GlnSearchField` (shipment forms) plus inline comboboxes in `serial_wizard.ex`, `serials.ex` (pack panel) and `manufacturer_aggregation_live/wizard.ex`. One shared component would match one Doop control. |
| Ledger / brief mismatch | brief-areas MAN-66 points `/manufacturer/aggregations` at `list.ex`, but the routed module is `dashboard.ex` (`list.ex` is unrouted). |

## 13. Open questions for Sean or Lucy (logic, not design)

1. Should packing a shipper still auto-create an approved shipment and EPCIS Ship event? If pallets come next, shipping probably belongs after the pallet.
2. Should pallet codes be minted as real SSCCs through the GS1 member API (as shippers are)? And should pallet creation send an EPCIS aggregation event?
3. Which shipment model is canon for manufacturers: `Manufacturing.Shipment` (auto, per pack) or the `Distributor.Shipment` portal flow (draft → mobile pack → approve)?
4. Should the scan-to-aggregate review (`/manufacturer/aggregations/:id`) come back, or be deleted along with the unrouted `List` and `Form`?
5. Distributor "orders": a real orders entity, or a filtered draft-shipments view?

## 14. Things I couldn't confirm (verify in a browser)

- The `patch` from `/manufacturer/products/:id` to `/manufacturer/products/:gtin/serials/new` crosses LiveViews (Show → Index). I expect Phoenix to fall back to a full navigation that opens the Products page with the modal, but I haven't seen it happen.
- `Sites.get_site!(org, scope.current_site_id)` in `manufacturer_product_live/index.ex:33` (mount) when no site is selected (admin "Manage organization" context). It may raise.
- That the pallet picker really shows nothing after packing in the app. The code reading says so; no test or browser run backs it up.
- That a non-admin distributor user without a billing plan dead-ends at `/distributor`.
- Whether emails or notifications link to `/org/stock-takes` and `/org/disposals`.
- `/lab/transactions/:id` and `/:id/receipt` render as modals over the list, so their "no back link" may be fine.

