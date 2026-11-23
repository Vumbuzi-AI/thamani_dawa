# Thamani Dawa · Doop coverage brief, all areas (phase 2)

Companion to `brief.md` (phase 1 lab, sections 1-9). Canon: Doop **LQFIZlhE35**, link `https://doop.design/c/LQFIZlhE35?frame=<id>`. Matrix: `coverage.md`. Snapshot of the working tree at 23 Nov 13:50 EAT; render line numbers are where each screen starts, so they may drift as Krak edits.

**Every screen item has the same base fix, called R1-R6 below, plus its own notes:**
- R1 Shell: `td_list_page` / `td_detail_page` inside the TD shell; header 68, back row 40, toolbar 12 16, table flush, no `.td-page` 24px padding (brief.md §4.9).
- R2 Kit only: replace `.header`, `.table`, `.button`, `.modal`, `.input`, `.tab_group`, `.status_badge`, `.filter_drawer`, `.form_block`, `.blank_state` with `td_*` (or the core wrappers once brief.md §2 makes them delegate).
- R3 Icons: Phosphor names only, no `hero-*`; 16px; ink-3 in rows, ink-2 in buttons.
- R4 Colour: TD tokens only, legacy classes per brief.md §1A, no `shadow*`, no `bg-white`, no `slate/zinc/gray`.
- R5 Type: Inter 12/14/16 at 400/500; no `font-semibold/bold`, `text-xl+`, `uppercase`, `tracking-*`; mono only for codes.
- R6 Overlays: every dialog is `td_modal` (form 560 / confirm 480) with title, subtitle and footer; every destructive action opens a confirm; filter chips open the shared filter menus.

**Acceptance for every screen item:** (a) at 1440×900, light and dark, the page matches the listed frames side by side (layout, copy, spacing, tokens); (b) `rg -n "hero-|shadow|thamani-(forest|lime|snow|stone|pewter)|font-semibold|font-bold|uppercase|text-2xl" <file>` returns nothing; (c) every clickable element in the frame does the same thing in the app (prototype links); (d) `mix compile --warnings-as-errors` passes.

## 0. Cross-cutting features that are missing everywhere (build once, use in every portal)

### 0.1 Title-bar search, results and Cmd-K command menu
- Frames: Lab A-NSb15zZW, NEa-OK75GL, SObwoLbfus · Pharmacy hfzoIrlQm2, xmBPwSy8U7, oEEi6oe1SM · Pharma-lab LDU1m5zU_D, DaHpKXC8VZ, pBbtVnD7n2 · Distributor a_9Z4X_p7f, OzaMqDsP6e, FUN-ITw_Qj · Org p_lyQcEmhk, RhKDiFO6f_, 07-8zNav0v · Platform 5RcyWy41dg, H2ErF6VkIY, 6kqmSrYrj0.
- Where: `td_app_shell` title bar (`td_components.ex` L565-592, tools slot L583) and each portal shell in `layouts.ex` (tools slots L100, L132, L199, L228, L269, L303, L346).
- Build: new `td_search_palette` LiveComponent mounted once in the shell. Title-bar field 304×30 opens it on click, `/` or Cmd/Ctrl-K. Palette 560 wide, top 12vh, surface, 1px border, radius 12, no shadow; input row 48; results grouped (Patients, Orders, Products, Batches, Pages) with 12/500 ink-3 group labels and 36px rows; empty query shows Command menu actions (New order, Receive stock, Toggle dark mode, Go to …). Arrow keys + Enter, Esc closes. Search is scoped to the current site and portal.
- Acceptance: Cmd-K from any page opens the palette; typing "grace" lists the patient and her orders; Enter navigates; Esc returns focus to the page; matches the frames for each portal.

### 0.2 Transaction detail, actions, refund (UI only), receipt, refunded state
- Frames: Pharmacy m_jp8035Ug, 4EBIQw1oOJ, AVv0nB0ws7, McK_NH1FTW, lQNYAcVoz_ · Pharma-lab O6qBL6WmLK, 5_jH3LQdKe, g0AWNx5smP, XhrkUGbBw-, wyJQ6GLU2P · Org tvMYqHud3S, 3DKqAH3VB8, fi0pTx-1f7, Oh4IwFJvUg, gTIcNKn1Ie (lab in brief.md §6).
- Where: `live/earnings_live.ex` (render L138); `router.ex` L167 (`/org/earnings`), L220 (`/pharmacy/transactions`).
- Build: routes `/pharmacy/transactions/:id` (`:pharmacy_show`), `/pharmacy/transactions/:id/receipt`, `/org/earnings/:id`, `/org/earnings/:id/receipt`; one shared `TransactionComponents.detail_modal/1` and `receipt/1` used by lab, pharmacy and org. Actions menu: Print receipt, Refund (danger). Refund is UI states only (decision 3): dialog renders, submit disabled with hint "Refunds are not live yet." The refunded list state renders from a `refunded` status if present, else is hidden.
- Acceptance: a Transactions row opens the modal over the list in every portal; Print receipt opens the receipt print view; refund dialog opens from actions and cannot submit.

### 0.3 Notifications
- Frame: TzQlEuhO6H (Shared).
- Where: title-bar `bell` icon button in `td_app_shell` tools.
- Build: popover 360 wide anchored to the bell, surface, 1px border, radius 12; header "Notifications" 14/500 + "Mark all read" text button; rows 56 (tone icon tile 28, title 14, meta 12 ink-2, unread dot accent); empty state. Feed source: existing events (low stock, expiring batches, requisition status, stock take/disposal approvals). If no backend feed exists, render the empty state and flag to Sean.
- Acceptance: bell shows a count pill when unread; popover matches TzQlEuhO6H; clicking a row navigates.

### 0.4 Export CSV and Download ready
- Frames: 2E9yucAGjQ Export CSV, zkycQlzsjO Download ready.
- Where: every list header that shows "Export CSV" on Doop (Stock products/batches, Transactions, Requisitions, Products, Shipments, Receiving). Existing controllers to reuse: `controllers/distributor_shipment_export_controller.ex`, `manufacturer_serial_export_controller.ex`, `manufacturer_sscc_export_controller.ex`.
- Build: secondary "Export CSV" button opens a confirm-size dialog (columns summary, current filters, date range) → GET a CSV controller with the same filter params → toast "Download ready" with a Download link. One generic `CsvExportController` keyed by list type.
- Acceptance: exported rows equal the filtered list; filename `<list>-<site>-<yyyy-mm-dd>.csv`.

### 0.5 Shared overlays not built
- Log out confirm cwUKNlhijG: account menu Log out opens a 480 confirm (`td_confirm`), Cancel / Log out (danger-confirm). Where: `td_account_chip` L650 menu.
- Remove item 5mZQ-49VPF: every line-item remove (requisitions, receiving, shipments, disposals, stock takes) opens this confirm.
- Item details gCMI-5oDzE: line-item details overlay from receiving and requisition lines.
- Get the mobile app _AkYsfMrBW: account menu item → dialog with store links + QR.
- Period menu 5I9pJoGa6G and Calendar view menu UwAiusb5oG: dashboard period chip (Today / 7 days / 30 days / This month / custom) used by lab, pharmacy, org dashboards.
- Print d687xWcrBC: before any print (labels, receipts, reports), show this dialog (printer, copies, paper) then `window.print()`; today label hooks print directly.
- Filter menus (19 frames: GNR8ZG0WQa Activity, RBA4UYrkXr Category, Q6s3o1UKRS Created, 2trt8GDgl8 Date, v0UH0bx6L9 Expiry, hsTdh4fT_Z Flags, flG9lx1Pxp Gender, gYpvtPDu1v Method, xse0VhnCxA Mobile user, ntkXbBL-C6 Organization, lC7VMdCEri Paid, U6QCMLJ8LN Payment, X42vxHfarW Received, 5uprTqJznQ Role, M733hm_3tb Site, TTXzDZPEWP Status, feg9yL0s8X Urgency, HZvoVe9Hug Visited, qtRoKxMMu1 Warehouse): replace `filter_drawer` (core_components.ex L2464) everywhere with `td_filter_chip` + one `td_filter_menu` popover (options list with check, date presets + range calendar for date chips). Acceptance: no `filter_drawer` call left (`rg "filter_drawer" lib` = 0).

## 1. Shell

- 1.0 Shell items from brief.md §4 apply to every portal: nav groups and Phosphor fill, site switcher, sidebar bottom, title bar tools, product tour, back row. Pharmacy groups: Pharmacy (Dashboard `squares-four`, Quick sale `lightning`, Prescriptions `prescription`, Patients `users`), Inventory (Stock `package`, Receive stock `tray-arrow-down`, Requisitions `clipboard-text`, Scan `barcode`), Payments (Transactions `money`). Distributor, manufacturer, org, platform: map every `hero-*` in layouts.ex L245-247, L701-824, L871, L910-914, L981 to the Phosphor names used on each portal's Doop shell frames.
- Acceptance: `rg "hero-" lib/thamani_dawa_web/components/layouts.ex` = 0; each portal shell matches its Doop dashboard frame in light and dark.

### SHE-1  (sidebar)
- Frames: l3PRkMH9kA Site switcher open · pharmacy, IJAc4XSYTP Site switcher open · lab, QwOww6J_-C Site switcher open · combined, CUy1Ue75h- Site switcher open · dist, xKjyrzVPWd Site switcher open · org, pRWh641rg7 Product tour · step 1, sHEmCo_9oR Product tour · step 2, F-mzfB-j8y Product tour · step 3
- Where: `components/layouts.ex` L40
- Gaps now: layouts.ex: 66 hero icons, 42 legacy colour classes, 3 shadows, 20 heavy/uppercase type
- Notes: Site switcher popover still Tailwind legacy: shadow-xl, rounded-xl, bg-white, uppercase 10px labels, hero icons (layouts.ex L408-454, L932-954); Tour popover is forest fill, shadow-2xl, rounded-2xl, uppercase lime label, text-xl semibold (layouts.ex L1220-1260). Doop: surface popover, 16/500 title, secondary/primary buttons
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SHE-2  (sidebar)
- Frames: hB-Q2itaVG Account menu
- Where: `components/td_components.ex` L17
- Notes: td_account_chip menu: check 32px menu items, radius 6, danger Log out opens confirm
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SHE-3  (sidebar)  · **MISSING**
- Frames: cwUKNlhijG Log out confirm
- Where: (new)
- Notes: Log out has no confirm dialog; Doop opens a 480 confirm
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-4 title bar bell  · **MISSING**
- Frames: TzQlEuhO6H Notifications
- Where: (new)
- Notes: No notifications panel or bell in title bar
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-5 filter chips
- Frames: GNR8ZG0WQa Filter menu · Activity, RBA4UYrkXr Filter menu · Category, Q6s3o1UKRS Filter menu · Created, 2trt8GDgl8 Filter menu · Date, v0UH0bx6L9 Filter menu · Expiry, hsTdh4fT_Z Filter menu · Flags, flG9lx1Pxp Filter menu · Gender, gYpvtPDu1v Filter menu · Method, xse0VhnCxA Filter menu · Mobile user, ntkXbBL-C6 Filter menu · Organization, lC7VMdCEri Filter menu · Paid, U6QCMLJ8LN Filter menu · Payment, X42vxHfarW Filter menu · Received, 5uprTqJznQ Filter menu · Role, M733hm_3tb Filter menu · Site, TTXzDZPEWP Filter menu · Status, feg9yL0s8X Filter menu · Urgency, HZvoVe9Hug Filter menu · Visited, qtRoKxMMu1 Filter menu · Warehouse
- Where: `components/core_components.ex` L63
- Gaps now: core_components.ex: 20 hero icons, 188 legacy colour classes, 10 shadows, 26 legacy core components, 18 heavy/uppercase type, no TD components
- Notes: Code uses filter_drawer with selects (core_components L2464). Doop: TD FilterChip "Label · Value" that opens a menu popover
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SHE-6 list headers  · **MISSING**
- Frames: 2E9yucAGjQ Export CSV, zkycQlzsjO Download ready
- Where: (new)
- Notes: Export CSV dialog + download toast only exist as links on manufacturer serial/SSCC pages
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-7 print dialog
- Frames: d687xWcrBC Print
- Where: `components/core_components.ex` L63
- Gaps now: core_components.ex: 20 hero icons, 188 legacy colour classes, 10 shadows, 26 legacy core components, 18 heavy/uppercase type, no TD components
- Notes: Print goes straight to window.print via label hooks; Doop shows a Print dialog (printer, copies)
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SHE-8 confirm  · **MISSING**
- Frames: 5mZQ-49VPF Remove item
- Where: (new)
- Notes: Remove line items without confirm; Doop uses 480 confirm
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-9 overlay  · **MISSING**
- Frames: gCMI-5oDzE Item details
- Where: (new)
- Notes: Not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-10 account menu  · **MISSING**
- Frames: _AkYsfMrBW Get the mobile app
- Where: (new)
- Notes: Not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### SHE-11 dashboards  · **MISSING**
- Frames: 5I9pJoGa6G Period menu, UwAiusb5oG Calendar view menu
- Where: (new)
- Notes: Dashboard period and calendar view menus not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

## 2. Pharmacy (and shared pharmacy+lab frames)

### PHA-12 /pharmacy
- Frames: q2Wvk4Umn8 Pharmacy · Dashboard
- Where: `live/pharmacy_dashboard_live.ex` L172
- Gaps now: pharmacy_dashboard_live.ex: 8 hero icons, 16 legacy core components, 1 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-13 /pharmacy/quick-sale
- Frames: WjL-tNN_VO Pharmacy · Quick sale · items in sale, N461d8znxS Pharmacy · Quick sale · confirm payment, nIkqRsQnw0 Pharmacy · Quick sale · empty, pZUoyG0NbM Pharmacy · Quick sale · sale complete receipt
- Where: `live/quick_sale_live.ex` L635
- Gaps now: quick_sale_live.ex: 18 hero icons, 110 legacy colour classes, 1 shadows, 12 legacy core components, 32 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-14 /pharmacy/prescriptions
- Frames: mGgl_Tv3Ej Pharmacy · Prescriptions, Mpn9ChDfzN Pharmacy · Prescriptions · no results, V57ys398o_ Pharmacy · New prescription · existing patient, 50yafn4tfg Pharmacy · New prescription · new patient, h1ctG5HEZ0 Pharmacy · Prescriptions · Pending, fR7za4TcRy Pharmacy · Prescriptions · Partially dispensed, PP6AFx7PEM Pharmacy · Prescriptions · Completed
- Where: `live/prescription_live/index.ex` L346
- Gaps now: index.ex: 12 hero icons, 22 legacy colour classes, 1 shadows, 43 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-15 /pharmacy/prescriptions/:id
- Frames: oBlQhsWTT7 Pharmacy · Prescription detail, kk8xYfpH6O Pharmacy · Prescription detail · just created, D-QWKUeNkj Pharmacy · Dispense item, EnmtwPsOaU Pharmacy · Dispense item · role blocked, I3I6tP8uFj Pharmacy · Record payment, 2GZ7SeAWi0 Pharmacy · Prescription receipt
- Where: `live/prescription_live/show.ex` L292
- Gaps now: show.ex: 10 hero icons, 81 legacy colour classes, 2 shadows, 16 legacy core components, 39 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-16 /pharmacy/patients
- Frames: fysrRIVfjl Pharmacy · Patients, PzFZTh8Hqw Pharmacy · Patients · visits
- Where: `live/patient_live/index.ex` L80
- Gaps now: index.ex: 3 hero icons, 8 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-17 /pharmacy/patients/:id
- Frames: Vc5-hRnH8E Pharmacy · Patient detail
- Where: `live/patient_live/show.ex` L19
- Gaps now: show.ex: 2 hero icons, 5 legacy colour classes, 3 legacy core components, 5 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-18 /pharmacy/stock
- Frames: puMtQXqNOq Pharmacy · Stock · products, fO2XgZ8Xir Pharmacy · Stock · all batches, YIT-Xr3ym_ Pharmacy · Stock row actions
- Where: `live/pharmacy_stock_live.ex` L323
- Gaps now: pharmacy_stock_live.ex: 7 hero icons, 12 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-19 /pharmacy/stock/products/:id
- Frames: k6in9fJ2Ub Pharmacy · Stock product detail
- Where: `live/pharmacy_stock_product_live.ex` L33
- Gaps now: pharmacy_stock_product_live.ex: 2 hero icons, 4 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-20 /pharmacy/stock/batches/:id
- Frames: UlUYBX60A_ Pharmacy · Stock batch detail, 87EK_g6B4h Pharmacy · Print Data Matrix
- Where: `live/pharmacy_stock_batch_live.ex` L67
- Gaps now: pharmacy_stock_batch_live.ex: 3 hero icons, 5 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-21 /pharmacy/receive-stock
- Frames: VpVCkmNrin Pharmacy · Receive stock, kuH9a_Hlb4 Pharmacy · Receive stock · received, cdW-D3F-WD Pharmacy · Receive stock · nothing pending, W4rtCphTmP Pharmacy · Receive batch
- Where: `live/receive_stock_live.ex` L139
- Gaps now: receive_stock_live.ex: 3 hero icons, 4 legacy colour classes, 7 legacy core components, 14 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-22 /pharmacy/requisitions
- Frames: R0-3QT_OPy Pharmacy · Requisitions, dVFTApB_-o Pharmacy · Requisitions · sent, 8jIK-HzR1_ Pharmacy · New requisition, YK8WeJ4D9U Pharmacy · Requested between · date range
- Where: `live/requisition_live/index.ex` L291
- Gaps now: index.ex: 3 hero icons, 13 legacy colour classes, 17 legacy core components, 10 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-23 /pharmacy/requisitions/:id
- Frames: qAAuZfHK88 Pharmacy · Requisition detail
- Where: `live/requisition_live/show.ex` L42
- Gaps now: show.ex: 2 hero icons, 12 legacy colour classes, 4 legacy core components, 20 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-24 /pharmacy/scan
- Frames: WDnObl1yFI Pharmacy · Scan lookup · ready, t2AQmt0try Pharmacy · Scan lookup · approved stock found, oEYztKz59R Pharmacy · Scan lookup · not at your site
- Where: `live/pharmacy_scan_live.ex` L136
- Gaps now: pharmacy_scan_live.ex: 7 hero icons, 19 legacy colour classes, 4 legacy core components, 11 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-25 /pharmacy/transactions
- Frames: 8SwyrgWmlD Pharmacy · Transactions, iXgHWN9Wlx Pharmacy · Transactions · date range
- Where: `live/earnings_live.ex` L300
- Gaps now: earnings_live.ex: 2 hero icons, 11 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-26 title bar search  · **MISSING**
- Frames: hfzoIrlQm2 Pharmacy · Search, xmBPwSy8U7 Pharmacy · Search · results, oEEi6oe1SM Pharmacy · Command menu
- Where: (new)
- Notes: Title-bar search and ⌘K not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PHA-27 /pharmacy/transactions/:id  · **MISSING**
- Frames: m_jp8035Ug Pharmacy · Transaction detail, 4EBIQw1oOJ Pharmacy · Transaction actions, AVv0nB0ws7 Pharmacy · Refund payment, McK_NH1FTW Pharmacy · Payment receipt
- Where: (new)
- Notes: No transaction detail, actions, refund or receipt
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PHA-28 /pharmacy/transactions  · **MISSING**
- Frames: lQNYAcVoz_ Pharmacy · Transactions · refunded
- Where: (new)
- Notes: Refund state not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PHA-29 /pharmacy, /lab
- Frames: 0xQtYRdBP7 Pharma-lab · Site dashboard
- Where: `live/pharmacy_dashboard_live.ex` L172, `live/lab_dashboard_live.ex` L169
- Gaps now: pharmacy_dashboard_live.ex: 8 hero icons, 16 legacy core components, 1 heavy/uppercase type, no TD components
- Notes: Combined pharmacy+lab site dashboard
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-30 /…/stock
- Frames: c3EiqRelu0 Pharma-lab · Stock · products, fiY29WINlP Pharma-lab · Stock · all batches, KNGUgpK574 Pharma-lab · Stock row actions
- Where: `live/pharmacy_stock_live.ex` L323, `live/lab_stock_live.ex` L269
- Gaps now: pharmacy_stock_live.ex: 7 hero icons, 12 legacy core components, no TD components; lab_stock_live.ex: 3 hero icons, 12 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-31 /…/stock/products/:id
- Frames: MS7rEsXApn Pharma-lab · Stock product detail
- Where: `live/pharmacy_stock_product_live.ex` L33, `live/lab_stock_product_live.ex` L37
- Gaps now: pharmacy_stock_product_live.ex: 2 hero icons, 4 legacy core components, no TD components; lab_stock_product_live.ex: 2 hero icons, 4 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-32 /…/stock/batches/:id
- Frames: hXPInx920g Pharma-lab · Stock batch detail, NoAAUBFYIM Pharma-lab · Print Data Matrix
- Where: `live/pharmacy_stock_batch_live.ex` L67, `live/lab_stock_batch_live.ex` L66
- Gaps now: pharmacy_stock_batch_live.ex: 3 hero icons, 5 legacy core components, 8 heavy/uppercase type, no TD components; lab_stock_batch_live.ex: 3 hero icons, 5 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-33 /…/receive-stock
- Frames: 8iVW7r9PTq Pharma-lab · Receive stock, zbldFTPOl8 Pharma-lab · Receive stock · received, 2i2uC75baP Pharma-lab · Receive batch
- Where: `live/receive_stock_live.ex` L139, `live/lab_receive_stock_live.ex` L381
- Gaps now: receive_stock_live.ex: 3 hero icons, 4 legacy colour classes, 7 legacy core components, 14 heavy/uppercase type, no TD components; lab_receive_stock_live.ex: 3 hero icons, 19 legacy colour classes, 19 legacy core components, 35 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-34 /…/requisitions
- Frames: D4seM_mRUZ Pharma-lab · Requisitions, XzIaUb-TRg Pharma-lab · Requisitions · sent, m0G-EwG5xI Pharma-lab · New requisition, N-VnSYQtSj Pharma-lab · Requested between
- Where: `live/requisition_live/index.ex` L291, `live/lab_requisition_live/index.ex` L291
- Gaps now: index.ex: 3 hero icons, 13 legacy colour classes, 17 legacy core components, 10 heavy/uppercase type, no TD components; index.ex: 3 hero icons, 13 legacy colour classes, 17 legacy core components, 10 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-35 /…/requisitions/:id
- Frames: tHrj71_Sgx Pharma-lab · Requisition detail
- Where: `live/requisition_live/show.ex` L42, `live/lab_requisition_live/show.ex` L42
- Gaps now: show.ex: 2 hero icons, 12 legacy colour classes, 4 legacy core components, 20 heavy/uppercase type, no TD components; show.ex: 2 hero icons, 12 legacy colour classes, 4 legacy core components, 20 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-36 /…/patients
- Frames: bqOkfOEJid Pharma-lab · Patients, ZHDa9azVGo Pharma-lab · Patients · visits
- Where: `live/patient_live/index.ex` L80, `live/lab_patient_live/index.ex` L81
- Gaps now: index.ex: 3 hero icons, 8 legacy core components, no TD components; index.ex: 3 hero icons, 8 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-37 /…/patients/:id
- Frames: HKuQgCEMDo Pharma-lab · Patient detail
- Where: `live/patient_live/show.ex` L19, `live/lab_patient_live/show.ex` L19
- Gaps now: show.ex: 2 hero icons, 5 legacy colour classes, 3 legacy core components, 5 heavy/uppercase type, no TD components; show.ex: 2 hero icons, 5 legacy colour classes, 3 legacy core components, 5 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-38 /…/scan
- Frames: AtpiHFUFn_ Pharma-lab · Scan lookup · ready, nUtvlhnxmd Pharma-lab · Scan lookup · found, 8Dk9fCPTKi Pharma-lab · Scan lookup · not found
- Where: `live/pharmacy_scan_live.ex` L136, `live/lab_scan_live.ex` L55
- Gaps now: pharmacy_scan_live.ex: 7 hero icons, 19 legacy colour classes, 4 legacy core components, 11 heavy/uppercase type, no TD components; lab_scan_live.ex: 2 hero icons, 6 legacy colour classes, 6 legacy core components, 3 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-39 /…/transactions
- Frames: 7wrWcmujxW Pharma-lab · Transactions, UGem41P4cJ Pharma-lab · Transactions · date range, wyJQ6GLU2P Pharma-lab · Transactions · refunded
- Where: `live/earnings_live.ex` L300
- Gaps now: earnings_live.ex: 2 hero icons, 11 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PHA-40 title bar search  · **MISSING**
- Frames: LDU1m5zU_D Pharma-lab · Search, DaHpKXC8VZ Pharma-lab · Search · results, pBbtVnD7n2 Pharma-lab · Command menu
- Where: (new)
- Notes: Title-bar search, results and ⌘K command menu not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PHA-41 /…/transactions/:id  · **MISSING**
- Frames: O6qBL6WmLK Pharma-lab · Transaction detail, 5_jH3LQdKe Pharma-lab · Transaction actions, g0AWNx5smP Pharma-lab · Refund payment, XhrkUGbBw- Pharma-lab · Payment receipt
- Where: (new)
- Notes: No transaction detail, actions, refund or receipt route
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

## 3. Distributor

- 3.A **Pick list (missing):** frames EU_pnVe8Bz (pick list generated), wWgSbjzUSa (pick confirmed). Where: `live/distributor_shipment_live/show.ex` (render L301). Build: on a draft shipment, "Generate pick list" (secondary) produces a table of SSCC/batch, zone, qty to pick; "Confirm pick" (primary) marks lines picked and moves stock to Staging. Needs a backend action if none exists (flag). Acceptance: draft → pick list generated → pick confirmed → submit, matching the 4 frames in order.
- 3.B **Move stock and Change status (missing):** frames 9JOOh3G1S8 Move stock, hRt_Ys_3Bg Change status, c7Hoa67z3h moved, swbFp29AJY status updated; zone tabs UKUgQMR4Jy Receiving, sVU0g3wEAw Picking, 7zytGb6V4h Staging, FvnY7JCNQz Dispatch, j2u8BBnf6m storage zone, 3fqhLARkKR empty zone, S0calaqsas pick a warehouse. Where: `live/distributor_product_live/index.ex` (render L305), which now hosts the warehouse board (`distributor_stock_live/index.ex` only redirects). Build: zone tabs with counts, row actions Move stock (zone/location select, qty) and Change status (Available / Quarantine / Damaged), toasts. Backend for zone moves may be missing (flag). Acceptance: matches frames; moving updates the zone counts.

### DIS-42 /distributor
- Frames: 8OjVBGuJw2 Distributor · Dashboard
- Where: `live/distributor_dashboard_live.ex` L179
- Gaps now: distributor_dashboard_live.ex: 11 hero icons, 19 legacy colour classes, 3 legacy core components, 4 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-43 /distributor/billing/options
- Frames: Eu3T4LB1bO Distributor · Choose a serialisation plan
- Where: `live/distributor_billing_live/options.ex` L52
- Gaps now: options.ex: 3 hero icons, 13 legacy colour classes, 4 shadows, 3 legacy core components, 6 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-44 /distributor/shipments
- Frames: XJBYJekyQ3 Distributor · Shipments, 4WJVAyBAlz Distributor · Shipments · nothing matches, kzJGEKhPLK Distributor · Shipments · rejected, 4C-4iO5AGv Distributor · Shipments · created between, z6VSLXmqsn Distributor · New shipment · GLN verified, 8WcwnQK6TA Distributor · New shipment · GLN not verified, b-sThvfHQD Distributor · Shipments · Draft, _L9q82a0i8 Distributor · Shipments · Submitted, Lb1ooUthfE Distributor · Shipments · Approved
- Where: `live/distributor_shipment_live/index.ex` L168, `live/distributor_shipment_live/form.ex` L187
- Gaps now: index.ex: 3 hero icons, 3 legacy colour classes, 11 legacy core components, no TD components; form.ex: 6 hero icons, 29 legacy colour classes, 8 legacy core components, 6 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-45 /distributor/shipments/:id
- Frames: ynvC_CLltK Distributor · Shipment · draft, n3E_4eHtB7 Distributor · Shipment · draft saved, IiThKMTc0e Distributor · Shipment · submitted, KfQfsgpVkN Distributor · Shipment · can't approve yet, 8SCAEjcIlW Distributor · Shipment · approved, lQVs5LkQSv Distributor · Shipment · just approved, EA9ystUKuK Distributor · Approve shipment, rQCrmvANKH Distributor · Reject shipment, AG21KELEMP Distributor · Print SSCC labels
- Where: `live/distributor_shipment_live/show.ex` L378
- Gaps now: show.ex: 27 hero icons, 86 legacy colour classes, 26 legacy core components, 43 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-46 /distributor/shipments/:id  · **MISSING**
- Frames: EU_pnVe8Bz Distributor · Shipment · pick list generated, wWgSbjzUSa Distributor · Shipment · pick confirmed
- Where: (new)
- Notes: Pick list generate/confirm not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### DIS-47 /distributor/receiving
- Frames: pTKmcZsilq Distributor · Receiving, L7MPRjX9Qe Distributor · Receiving · no receipts, JoswSNZBZB Distributor · Receiving · delivery received
- Where: `live/distributor_receiving_live.ex` L1989
- Gaps now: distributor_receiving_live.ex: 26 hero icons, 147 legacy colour classes, 38 legacy core components, 67 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-48 /distributor/receiving/new
- Frames: R3EZTr4ePq Distributor · Receive inventory · start, NwX0CruZHC Distributor · Receive inventory · items added, ZoTRfv1hsN Distributor · Add item · product found, cuTiC1b_gF Distributor · Add item · new product, G02PxKZRth Distributor · Add item · new supplier
- Where: `live/distributor_receiving_live.ex` L1989
- Gaps now: distributor_receiving_live.ex: 26 hero icons, 147 legacy colour classes, 38 legacy core components, 67 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-49 /distributor/receiving/:id
- Frames: v-q64497Ft Distributor · Goods receipt
- Where: `live/distributor_goods_receipt_live.ex` L380
- Gaps now: distributor_goods_receipt_live.ex: 9 hero icons, 72 legacy colour classes, 3 shadows, 7 legacy core components, 26 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-50 /distributor/products (zones)
- Frames: j2u8BBnf6m Distributor · Stock · storage zone, 3fqhLARkKR Distributor · Stock · empty zone, S0calaqsas Distributor · Stock · pick a warehouse, UKUgQMR4Jy Distributor · Stock · Receiving, sVU0g3wEAw Distributor · Stock · Picking, 7zytGb6V4h Distributor · Stock · Staging, FvnY7JCNQz Distributor · Stock · Dispatch
- Where: `live/distributor_product_live/index.ex` L305
- Gaps now: index.ex: 5 hero icons, 25 legacy colour classes, 22 legacy core components, 3 heavy/uppercase type, no TD components
- Notes: Doop has zone tabs Receiving/Picking/Staging/Dispatch
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-51 /distributor/products (stock zones)  · **MISSING**
- Frames: c7Hoa67z3h Distributor · Stock · moved, swbFp29AJY Distributor · Stock · status updated, 9JOOh3G1S8 Distributor · Move stock, hRt_Ys_3Bg Distributor · Change status
- Where: (new)
- Notes: Move stock and status change not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### DIS-52 /distributor/products
- Frames: GbcOmL7hjr Distributor · Products, 4JRxjqsjai Distributor · Products · all batches, -h8zVFSeZ0 Distributor · Products · added, qHoPkYGnpt Distributor · Add product
- Where: `live/distributor_product_live/index.ex` L305
- Gaps now: index.ex: 5 hero icons, 25 legacy colour classes, 22 legacy core components, 3 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-53 /distributor/products/:id
- Frames: lqrh3ko8nX Distributor · Product detail
- Where: `live/distributor_product_live/show.ex` L53
- Gaps now: show.ex: 8 hero icons, 7 legacy colour classes, 8 legacy core components, 20 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-54 /distributor/batches/:id
- Frames: Yd-me0Se-p Distributor · Batch detail
- Where: `live/distributor_batch_live.ex` L415
- Gaps now: distributor_batch_live.ex: 10 hero icons, 66 legacy colour classes, 8 legacy core components, 41 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-55 /distributor/billing
- Frames: nNSes79vHo Distributor · Billing · prepay, onc1mah2wo Distributor · Billing · flex, vi5a6Pe3nV Distributor · Billing · payment received, jFNgzgD5q1 Distributor · Settle usage
- Where: `live/distributor_billing_live/index.ex` L61, `live/distributor_billing_live/payment.ex` L152
- Gaps now: index.ex: 12 hero icons, 3 legacy colour classes, 6 legacy core components, 5 heavy/uppercase type, no TD components; payment.ex: 5 hero icons, 19 legacy colour classes, 6 legacy core components, 5 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-56 /distributor/billing/payment
- Frames: 5dblYmDL3P Distributor · Buy serials, yqxtyU599f Distributor · Buy serials · check your phone
- Where: `live/distributor_billing_live/payment.ex` L152
- Gaps now: payment.ex: 5 hero icons, 19 legacy colour classes, 6 legacy core components, 5 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-57 /distributor/billing/invoices/:id
- Frames: tmGVB7EA_h Distributor · Invoice
- Where: `live/distributor_billing_live/invoice.ex` L54
- Gaps now: invoice.ex: 2 hero icons, 31 legacy colour classes, 1 shadows, 1 legacy core components, 25 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-58 /distributor/mobile-users
- Frames: uNq45yZlSw Distributor · Mobile users, FUYV1G6_oq Distributor · Mobile users · added, eZdGCDlHbo Distributor · Mobile users · PIN resent, SgbVcf0GcK Distributor · Mobile users · deactivated, FBYkmZgLdp Distributor · Mobile users · none yet, _8R2f0HWVA Distributor · Add mobile user, h5-N5tqIvS Distributor · Edit mobile user, z9vglBIUjs Distributor · Deactivate mobile user, 2m66wHWWE7 Distributor · Mobile user row actions
- Where: `live/distributor_mobile_user_live/index.ex` L149
- Gaps now: index.ex: 4 hero icons, 6 legacy colour classes, 20 legacy core components, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-59 /distributor/epcis
- Frames: brAo4lH0vA Distributor · TNT reporting, 14m9-tXF_w Distributor · Event payload
- Where: `live/distributor_epcis_live.ex` L301
- Gaps now: distributor_epcis_live.ex: 16 hero icons, 71 legacy colour classes, 10 legacy core components, 11 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-60 /org/sites
- Frames: iwqRqWwzqP Distributor · Sites, VtFnWKWwhA Distributor · Sites · created, hcfdn9XxbD Distributor · Site row actions, zPFVqJpCoT Distributor · Add site
- Where: `live/site_live/index.ex` L685
- Gaps now: index.ex: 23 hero icons, 71 legacy colour classes, 4 shadows, 26 legacy core components, 15 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### DIS-61 title bar search  · **MISSING**
- Frames: a_9Z4X_p7f Distributor · Search, OzaMqDsP6e Distributor · Search · results, FUN-ITw_Qj Distributor · Command menu
- Where: (new)
- Notes: Not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

## 4. Manufacturer

### MAN-62 /manufacturer
- Frames: ssU7S65tZF Manufacturer · Dashboard
- Where: `live/manufacturer_dashboard_live.ex` L16
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-63 /manufacturer/products
- Frames: nOHadNSnnW Manufacturer · Products, yWiBLt5W4_ Manufacturer · Add product
- Where: `live/manufacturer_product_live/index.ex` L209
- Gaps now: index.ex: 1 legacy core components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-64 /manufacturer/inventory
- Frames: PSRp5BYBqa Manufacturer · Inventory
- Where: `live/manufacturer_inventory_live.ex` L28
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-65 /manufacturer/shipments
- Frames: dD_f7mT7VA Manufacturer · Shipments
- Where: `live/manufacturer_shipment_live/list.ex` L90
- Gaps now: list.ex: 1 legacy core components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-66 /manufacturer/aggregations
- Frames: nooman_e0w Manufacturer · Aggregation
- Where: `live/manufacturer_aggregation_live/list.ex` L80
- Gaps now: list.ex: 1 legacy core components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-67 /manufacturer/products/:id
- Frames: vGTuM5LTeA Manufacturer · Product detail
- Where: `live/manufacturer_product_live/show.ex` L179
- Gaps now: show.ex: 7 legacy colour classes, 1 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-68 /manufacturer/epcis
- Frames: 6h1jP1RQB5 Manufacturer · TNT reporting
- Where: `live/manufacturer_epcis_live.ex` L301
- Gaps now: manufacturer_epcis_live.ex: 14 hero icons, 71 legacy colour classes, 8 legacy core components, 11 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-69 /manufacturer/shipments/new
- Frames: fR48lnlLFS Manufacturer · New shipment
- Where: `live/manufacturer_shipment_live/form.ex` L97
- Gaps now: form.ex: 4 hero icons, 15 legacy colour classes, 5 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-70 /manufacturer/products/:gtin/serials/new
- Frames: K4RLF5VaaL Manufacturer · Generate serials · Mode, qFO1qTLxuX Manufacturer · Generate serials · Stock, KmXWmRHQdm Manufacturer · Generate serials · Order batch, 9OowcBjmWP Manufacturer · Generate serials · Order parties
- Where: `live/manufacturer_product_live/serial_wizard.ex` L316
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-71 /manufacturer/products/:gtin/serials
- Frames: kyQHKTVNuw Manufacturer · Serials issued · Stock, pu69ruhFa_ Manufacturer · Serials issued · Order
- Where: `live/manufacturer_product_live/serials.ex` L72
- Gaps now: serials.ex: 6 hero icons, 21 legacy colour classes, 1 shadows, 8 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-72 /manufacturer/mobile-users
- Frames: ePbnW2fsM1 Manufacturer · Mobile users, PHuUbfzLYd Manufacturer · Add mobile user, k4McyoV5Ze Manufacturer · Deactivate mobile user
- Where: `live/manufacturer_mobile_user_live/index.ex` L137
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-73 /manufacturer/shipments/:id
- Frames: zlgzwWEFqF Manufacturer · Shipment review, _5mVCvDB4- Manufacturer · Packing list
- Where: `live/manufacturer_shipment_live/review.ex` L67
- Gaps now: review.ex: 4 hero icons, 35 legacy colour classes, 15 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-74 /manufacturer/aggregations/:id
- Frames: gqkhVbK6z_ Manufacturer · Aggregation review, LjYz-aVJzL Manufacturer · Reject aggregation
- Where: `live/manufacturer_aggregation_live/review.ex` L110
- Gaps now: review.ex: 2 hero icons, 28 legacy colour classes, 13 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-75 /manufacturer/aggregations/new
- Frames: R2MvAEcBgQ Manufacturer · New aggregation
- Where: `live/manufacturer_aggregation_live/form.ex` L108
- Gaps now: form.ex: 2 hero icons, 19 legacy colour classes, 9 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### MAN-76 /manufacturer/sscc/:id/label
- Frames: iqCZv_AYnf Manufacturer · Case label
- Where: `live/manufacturer_sscc_live/label.ex` L24
- Gaps now: label.ex: 7 legacy colour classes, 6 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

## 5. Auth, sign up, onboarding

### AUT-77 /login
- Frames: oYsDYjktDQ Auth · Log in, zq-cSnBhZm Auth · Log in error
- Where: `controllers/session_html/new.html.heex` L1
- Gaps now: new.html.heex: 2 legacy core components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-78 /password-reset
- Frames: GvVnAtQkik Auth · Reset password, tRNixmPXUk Auth · Reset link sent
- Where: `controllers/password_reset_html/new.html.heex` L1
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-79 /password-reset/:token
- Frames: SmQvGu5eAA Auth · Choose a new password
- Where: `controllers/password_reset_html/edit.html.heex` L1
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-80 /signup
- Frames: CLsksg2sae Sign up · Organization, _DHaSIu5T5 Sign up · Main location, NKlXWNuz3M Sign up · multiple PPB matches, 1P50qYkBt1 Sign up · Administrator
- Where: `live/signup_live.ex` L1092
- Gaps now: signup_live.ex: 33 hero icons, 92 legacy colour classes, 4 shadows, 25 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-81 /confirm
- Frames: HILJpytHOT Auth · Confirm your email, 2_xpgW-wlF Auth · Confirmation resent
- Where: `live/confirm_email_live.ex` L69
- Gaps now: confirm_email_live.ex: 1 hero icons, 12 legacy colour classes, 1 shadows, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-82 /invite/:token
- Frames: fbPy5QWJp3 Auth · Accept invite, fVLfnbTWpZ Auth · Invalid invite
- Where: `live/accept_invite_live.ex` L42
- Gaps now: accept_invite_live.ex: 14 legacy colour classes, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-83 /onboarding
- Frames: v1kqSDbicp Onboarding · Workspace ready, uVN_MBMLkT Onboarding · Primary site, DgQOClHH9A Onboarding · Products, BiJ52LwtJR Onboarding · Suppliers, PCwYGGREAA Onboarding · Team
- Where: `live/onboarding_live.ex` L155
- Gaps now: onboarding_live.ex: 11 hero icons, 60 legacy colour classes, 10 shadows, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### AUT-84 /sites/switch
- Frames: pG6LqCfcwP Auth · Choose a site
- Where: `controllers/site_switch_controller.ex` L1
- Gaps now: site_switch_controller.ex: no TD components
- Notes: Verify a post-login site chooser exists; only the sidebar switcher was found
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

## 6. Settings (org settings, API keys)

### SET-85 /org/settings
- Frames: su8eaSdNu- Org · Organization settings, wvo1WwnBJ0 Org · Organization settings · saved
- Where: `live/organization_settings_live.ex` L307
- Gaps now: organization_settings_live.ex: 2 hero icons, 31 legacy colour classes, 1 shadows, 7 legacy core components, 4 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SET-86 /distributor/settings
- Frames: X1yBg1glDy Distributor · Org settings · saved, 6c3WqEKBCP Distributor · Org settings
- Where: `live/organization_settings_live.ex` L307
- Gaps now: organization_settings_live.ex: 2 hero icons, 31 legacy colour classes, 1 shadows, 7 legacy core components, 4 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SET-87 /manufacturer/settings
- Frames: a5BIYP5fvv Manufacturer · Org settings
- Where: `live/organization_settings_live.ex` L307
- Gaps now: organization_settings_live.ex: 2 hero icons, 31 legacy colour classes, 1 shadows, 7 legacy core components, 4 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### SET-88 /manufacturer/api-keys
- Frames: dNqZMZIzMf Manufacturer · API keys
- Where: `live/api_keys_live.ex` L277
- Gaps now: api_keys_live.ex: 4 hero icons, 33 legacy colour classes, 1 shadows, 12 legacy core components, 7 heavy/uppercase type
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

## 7. Org admin and platform

- 7.A **Platform organizations route (missing):** frames OPeL_8IxLl Organizations, 5o7nNuRzYl Organization detail. `live/platform_organizations_live.ex` exists without a route. Add in `router.ex` live_session :platform (L212-216): `live "/platform/organizations", PlatformOrganizationsLive, :index` and `/platform/organizations/:id` (:show), and a nav item "Organizations" (`buildings`) in layouts.ex L245-247. Acceptance: list + detail match frames; filter chips Organization type, Status.
- 7.B **Org receiving (missing):** frames 2CQZtx0m1X Receiving, pCRl3tBxpV received, C2qqpiyP9- Receive inventory, aTuOrvCy4u Goods receipt, zlnJOqaCJ2 Add item, 5mYf4LJWPD new product, -ihp-A1mBi new supplier. Where: reuse `live/distributor_receiving_live.ex` and `distributor_goods_receipt_live.ex`, which already have `:distributor_*` actions; add `:org_index`, `:org_new`, `:org_show` and routes `/org/receiving`, `/org/receiving/new`, `/org/receiving/:id` in live_session :organization (router L159-210), plus the nav item. Acceptance: same flow as distributor, org shell, matches frames.

### PLA-89 /org/dashboard
- Frames: voIG90Ocbf Org · Admin dashboard, ZZmLwye-Ku Org · Filters and date range
- Where: `live/org_dashboard_live.ex` L356
- Gaps now: org_dashboard_live.ex: 18 hero icons, 85 legacy colour classes, 8 shadows, 4 legacy core components, 23 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-90 /org/sites
- Frames: _YkjLU_zT_ Org · Sites, sAWzRq9qay Org · Sites · created, 3Sc9KGsLbu Org · Add site · GLN verified, VNh-f2-P62 Org · Add site · GLN not found, 2eBvlpe3ly Org · Site row actions
- Where: `live/site_live/index.ex` L685
- Gaps now: index.ex: 23 hero icons, 71 legacy colour classes, 4 shadows, 26 legacy core components, 15 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-91 /org/sites/:id
- Frames: wMZFC8udDO Org · Site dashboard
- Where: `live/site_live/show.ex` L432
- Gaps now: show.ex: 25 hero icons, 52 legacy colour classes, 25 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-92 /org/products
- Frames: U90FoygrHh Org · Products, 1bDRkfghe0 Org · Products · first product, 7T5Ej-s71E Org · Products · created, PFWPVocsJO Org · Products · imported, ebFMw2ujwl Org · Add product · GTIN lookup, P1YyR3c2zD Org · Add product · details, tuBuNxEu2S Org · Product row actions, 8Y5PKREa6b Org · Import products · upload, y0ei0hPW3l Org · Import products · map columns, YjpcXimA0V Org · Import products · review
- Where: `live/product_live/index.ex` L716, `live/product_live/import.ex` L244
- Gaps now: index.ex: 27 hero icons, 189 legacy colour classes, 4 shadows, 38 legacy core components, 36 heavy/uppercase type, no TD components; import.ex: 10 hero icons, 109 legacy colour classes, 9 legacy core components, 21 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-93 /org/products/:id
- Frames: a8lUVVHA5V Org · Product detail, G_OlReyO_J Org · Product detail · stock added, a4VMCbMZQJ Org · Product detail · dispatched, PlITdIuONs Org · Add to stock, G2_gAudVRD Org · Dispatch batch to site
- Where: `live/product_live/show.ex` L254
- Gaps now: show.ex: 10 hero icons, 47 legacy colour classes, 3 shadows, 29 legacy core components, 6 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-94 /org/batches/:id
- Frames: 8Q1WL7sVvp Org · Batch detail, kHfilJh18d Org · Print Data Matrix
- Where: `live/batch_live/show.ex` L68
- Gaps now: show.ex: 2 hero icons, 5 legacy core components, 16 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-95 /org/suppliers
- Frames: OzelvYK3yA Org · Suppliers, 1Q0pdnYpNX Org · Suppliers · created, GExUc2gMoK Org · Add supplier, YE-Ck_dDLy Org · Supplier row actions
- Where: `live/supplier_live/index.ex` L248
- Gaps now: index.ex: 8 hero icons, 34 legacy colour classes, 3 shadows, 23 legacy core components, 8 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-96 /org/team
- Frames: lrsiMDnvg9 Org · Team, oxV_PIz1td Org · Team · invite sent, Z3khDQ-YI3 Org · Team · updated, F1AjINQBbP Org · Team · deactivated, DQNLz1gSP4 Org · Invite staff, yPDN9VJLDO Org · Edit team member, 2SgnW5Uol9 Org · Deactivate confirm, iZtnCpcAK5 Org · Team row actions
- Where: `live/team_live/index.ex` L511
- Gaps now: index.ex: 14 hero icons, 89 legacy colour classes, 4 shadows, 23 legacy core components, 21 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-97 /org/requisitions
- Frames: 9M_rqF3EVx Org · Requisition queue, igIKdkIMxW Org · Requisitions · reviewed, Z2-QOnLxHN Org · Requisitions · rejected, hLNbpWQx_q Org · Requisitions · dispatched, vMFVABkZbL Org · Review requisition, WIRHaj6N90 Org · Reject requisition, muEbyHxoXB Org · Fulfill requisition, Sjnr9gxKcg Org · Requisition row actions, dIPT7cCITO Org · Requested between, zBzFGblRnK Org · Requisitions · Pending, 0TOJ-OerfR Org · Requisitions · Approved, LHl7qlHyR_ Org · Requisitions · Fulfilled, xYILh6bLB1 Org · Requisitions · Rejected
- Where: `live/requisition_queue_live/index.ex` L460
- Gaps now: index.ex: 4 hero icons, 16 legacy colour classes, 30 legacy core components, 9 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-98 /org/requisitions/:id
- Frames: nzi5p4-AI5 Org · Requisition detail
- Where: `live/requisition_queue_live/show.ex` L47
- Gaps now: show.ex: 2 hero icons, 13 legacy colour classes, 6 legacy core components, 24 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-99 /org/earnings
- Frames: DSjQ_Epu5w Org · Transactions, 53BedS4v4m Org · Transactions date range
- Where: `live/earnings_live.ex` L300
- Gaps now: earnings_live.ex: 2 hero icons, 11 legacy core components, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-100 /org/epcis
- Frames: ZdiOKCCEg_ Org · TNT reporting, duj3-u6uPd Org · Event payload
- Where: `live/distributor_epcis_live.ex` L301
- Gaps now: distributor_epcis_live.ex: 16 hero icons, 71 legacy colour classes, 10 legacy core components, 11 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-101 /platform
- Frames: 1SYxbLx8Fm Platform · Dashboard
- Where: `live/platform_dashboard_live.ex` L14
- Gaps now: platform_dashboard_live.ex: 11 hero icons, 11 legacy colour classes, 3 legacy core components, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-102 /platform/organizations  · **MISSING**
- Frames: OPeL_8IxLl Platform · Organizations, 5o7nNuRzYl Platform · Organization detail
- Where: (new)
- Notes: platform_organizations_live.ex exists but has no route
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PLA-103 /platform/audit
- Frames: 2MEScH0sKV Platform · Audit activity
- Where: `live/platform_audit_live.ex` L142
- Gaps now: platform_audit_live.ex: 10 hero icons, 8 legacy colour classes, 9 legacy core components, 1 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-104 /org/receiving  · **MISSING**
- Frames: 2CQZtx0m1X Org · Receiving, pCRl3tBxpV Org · Receiving · received, C2qqpiyP9- Org · Receive inventory, aTuOrvCy4u Org · Goods receipt, zlnJOqaCJ2 Org · Add item, 5mYf4LJWPD Org · Add item · new product, -ihp-A1mBi Org · Add item · new supplier
- Where: (new)
- Notes: No org receiving route; distributor_receiving_live only mounts under /distributor
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PLA-105 title bar search  · **MISSING**
- Frames: p_lyQcEmhk Org · Search, RhKDiFO6f_ Org · Search · results, 07-8zNav0v Org · Command menu, 5RcyWy41dg Platform · Search, H2ErF6VkIY Platform · Search · results, 6kqmSrYrj0 Platform · Command menu
- Where: (new)
- Notes: Not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PLA-106 /org/earnings/:id  · **MISSING**
- Frames: tvMYqHud3S Org · Transaction detail, 3DKqAH3VB8 Org · Transaction actions, fi0pTx-1f7 Org · Refund payment, Oh4IwFJvUg Org · Payment receipt
- Where: (new)
- Notes: Not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PLA-107 /org/earnings  · **MISSING**
- Frames: gTIcNKn1Ie Org · Transactions · refunded
- Where: (new)
- Notes: Refund state not built
- Build: see section 0 or the area notes above for spec; until built, the Doop frames are the spec.
- Accept: base acceptance (a)-(d).

### PLA-108 /platform/recalls
- Frames: FSi8DNwuSY Platform · Recalls
- Where: `live/platform_recall_live.ex` L76
- Gaps now: platform_recall_live.ex: 1 hero icons, 26 legacy colour classes, 5 legacy core components, 12 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-109 /org/stock-takes
- Frames: Fe0oA1BIfd Org · Stock takes
- Where: `live/stock_take_queue_live/index.ex` L151
- Gaps now: index.ex: 2 hero icons, 6 legacy colour classes, 9 legacy core components, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

### PLA-110 /org/disposals
- Frames: O2D6yB49p7 Org · Disposals
- Where: `live/inventory_disposal_queue_live/index.ex` L153
- Gaps now: index.ex: 2 hero icons, 6 legacy colour classes, 9 legacy core components, 2 heavy/uppercase type, no TD components
- Fix: R1-R6.
- Accept: base acceptance (a)-(d).

## 8. Missing frame index (61)

| Frame | Name | Covered by |
|---|---|---|
| hfzoIrlQm2 | Pharmacy · Search | 0.1 |
| xmBPwSy8U7 | Pharmacy · Search · results | 0.1 |
| oEEi6oe1SM | Pharmacy · Command menu | 0.1 |
| m_jp8035Ug | Pharmacy · Transaction detail | 0.2 |
| 4EBIQw1oOJ | Pharmacy · Transaction actions | 0.2 |
| AVv0nB0ws7 | Pharmacy · Refund payment | 0.2 |
| McK_NH1FTW | Pharmacy · Payment receipt | 0.2 |
| lQNYAcVoz_ | Pharmacy · Transactions · refunded | 0.2 |
| A-NSb15zZW | Lab · Search | 0.1 |
| NEa-OK75GL | Lab · Search · results | 0.1 |
| SObwoLbfus | Lab · Command menu | 0.1 |
| 45FlJvpVyi | Lab · Transaction detail | brief.md §6 |
| 00v8gxaGGq | Lab · Transaction actions | brief.md §6 |
| 5kI8h3aBwo | Lab · Refund payment | brief.md §6 |
| VRY0p3ZE2z | Lab · Payment receipt | brief.md §6 |
| DnuQVVOIuE | Lab · Transactions · refunded | brief.md §6 |
| OPeL_8IxLl | Platform · Organizations | 7.A |
| 2CQZtx0m1X | Org · Receiving | 7.B |
| pCRl3tBxpV | Org · Receiving · received | 7.B |
| C2qqpiyP9- | Org · Receive inventory | 7.B |
| aTuOrvCy4u | Org · Goods receipt | 0.2 |
| zlnJOqaCJ2 | Org · Add item | 7.B |
| 5mYf4LJWPD | Org · Add item · new product | 7.B |
| -ihp-A1mBi | Org · Add item · new supplier | 7.B |
| p_lyQcEmhk | Org · Search | 0.1 |
| RhKDiFO6f_ | Org · Search · results | 0.1 |
| 07-8zNav0v | Org · Command menu | 0.1 |
| 5RcyWy41dg | Platform · Search | 0.1 |
| H2ErF6VkIY | Platform · Search · results | 0.1 |
| 6kqmSrYrj0 | Platform · Command menu | 0.1 |
| tvMYqHud3S | Org · Transaction detail | 0.2 |
| 3DKqAH3VB8 | Org · Transaction actions | 0.2 |
| fi0pTx-1f7 | Org · Refund payment | 0.2 |
| Oh4IwFJvUg | Org · Payment receipt | 0.2 |
| gTIcNKn1Ie | Org · Transactions · refunded | 0.2 |
| 5o7nNuRzYl | Platform · Organization detail | 7.A |
| EU_pnVe8Bz | Distributor · Shipment · pick list generated | 3.A |
| wWgSbjzUSa | Distributor · Shipment · pick confirmed | 3.A |
| c7Hoa67z3h | Distributor · Stock · moved | 3.B |
| swbFp29AJY | Distributor · Stock · status updated | 3.B |
| 9JOOh3G1S8 | Distributor · Move stock | 3.B |
| hRt_Ys_3Bg | Distributor · Change status | 3.B |
| a_9Z4X_p7f | Distributor · Search | 0.1 |
| OzaMqDsP6e | Distributor · Search · results | 0.1 |
| FUN-ITw_Qj | Distributor · Command menu | 0.1 |
| cwUKNlhijG | Log out confirm | 0.5 |
| TzQlEuhO6H | Notifications | 0.3 |
| LDU1m5zU_D | Pharma-lab · Search | 0.1 |
| DaHpKXC8VZ | Pharma-lab · Search · results | 0.1 |
| pBbtVnD7n2 | Pharma-lab · Command menu | 0.1 |
| O6qBL6WmLK | Pharma-lab · Transaction detail | 0.2 |
| 5_jH3LQdKe | Pharma-lab · Transaction actions | 0.2 |
| g0AWNx5smP | Pharma-lab · Refund payment | 0.2 |
| XhrkUGbBw- | Pharma-lab · Payment receipt | 0.2 |
| 2E9yucAGjQ | Export CSV | 0.4 |
| zkycQlzsjO | Download ready | 0.4 |
| 5mZQ-49VPF | Remove item | 0.5 |
| gCMI-5oDzE | Item details | 0.5 |
| _AkYsfMrBW | Get the mobile app | 0.5 |
| 5I9pJoGa6G | Period menu | 0.5 |
| UwAiusb5oG | Calendar view menu | 0.5 |


## 9. Old flows designed in pass 2 (23 Nov 2026, 14:25 EAT)

These Phoenix flows had no Doop frame. They are now designed and wired on LQFIZlhE35; build each to match. Do not delete any of these flows.

### OLD-1 Pharmacy stock takes
- Route: `/pharmacy/stock-takes, /pharmacy/stock-takes/:id`
- Files: `live/stock_take_live/*`
- Frames: fO4InWJM_1, eTe6yFWa7P, FxJu0mMXnB, KYYC_z9FD_, jA5FCpOM3b
- Build: Entry: "Stock takes" header button on Stock (puMtQXqNOq, fO2XgZ8Xir). Start is a 560 td_modal with Site + Notes. Draft: KV card, add-batch row, Count cell, Save count, Variance coloured. Submit opens 480 confirm. Pending: read-only with Reopen for counting.
- Acceptance: Same layout as lab stock takes; no `<.modal>`/`<.table>`/hero icons left in stock_take_live; status badges neutral/warning/success/danger.

### OLD-2 Pharmacy disposals (expiry write-off + supplier return)
- Route: `/pharmacy/disposals, /new, /:id`
- Files: `live/disposal_live/*`
- Frames: tYEXxq_6Bv, tULjmgrTnG, GUbfteruTM, jsbe4tiSoH, rfdJAC7blZ, Oxk8_GkQ7m, hHPVIKVxvx, PWA0gFjF5G, -Y9ypf1BqR, gwRHfpWdbQ
- Build: Entry: "Disposals" header button on Stock. Underline tabs Expiry write-off / Supplier return, both linked. Write-off takes the whole remaining quantity (no qty input). Supplier return draft has Batch + Quantity and columns Product, Supplier, On hand, To return. Remove opens 5mZQ-49VPF.
- Acceptance: Tabs switch via patch, not pills; every remove goes through confirm; submit goes through 480 confirm; copy matches frames (no em dashes).

### OLD-3 Lab supplier return
- Route: `/lab/disposals?tab=supplier_return`
- Files: `live/lab_disposal_live/*`
- Frames: y0FY06NVXy, M_aJhSQSjt, Wx7_TyNlII, 8pBS5RcfYF, BNVMha_eAs
- Build: Lab Disposals Supplier return tab (OsoDOCNQ8G now links here). Same flow as OLD-2 with lab products.
- Acceptance: Tab active state + counts match; Start dialog is td_modal form size.

### OLD-4 Lab printed report and specimen label
- Route: `/lab/orders/:id/report, /lab/orders/:id/specimens/:sid/label`
- Files: `components/lab_report_component.ex, components/specimen_label_component.ex`
- Frames: -0cH-9CyjR, N-RxCNzKsm
- Build: A4 report: logo + site line, "Laboratory report", 3x2 field grid (Patient, Lab order LO ref mono, Gender / Age, Requested on, Prescriber, Urgency), Test / Result / Performed by table, Lab technologist signature line, footer. Label 4x6: DataMatrix, GS1 string mono, Specimen, DOB, Patient, Age / Gender, Tests, LO ref + collected time. Print buttons in WAOief8IVU / 5O8udg27kd open these.
- Acceptance: Print CSS: white page, Inter, no app chrome, no shadows; LO ref via LabOrders.reference/1.

### OLD-5 Distributor customers
- Route: `/distributor/customers, /new, /:id/edit`
- Files: `live/distributor_customer_live/*`
- Frames: tpsqpH3pfq, eLeVZImSse, yfImGybMH4, WvABh70bsk
- Build: Table: Customer (+type), GLN mono, Contact (+phone), Email, Address, Edit. Empty state with Add customer. Add/Edit are 560 td_modal, 2-col grid: Name, Type, GLN, Contact person, Contact phone, Contact email, Address. Subtitle without em dash.
- Acceptance: Nav: Customers sits in the Distributor group with Phosphor address-book (see decision below).

### OLD-6 Distributor supplier returns
- Route: `/distributor/returns, /new, /:id`
- Files: `live/distributor_supplier_return_live/*, live/distributor_disposal_live/show`
- Frames: SLxbPI5Z4A, Nv4Cfb715M, zo7Me6_9Ya, Atyo7QvDVx, DE6Mpnt79E
- Build: Returns page with underline tabs Supplier returns / Customer returns. Columns Warehouse, Started, Status, Notes. Start dialog has Warehouse select + Notes. Draft: Batch + Quantity, Available / Requested.
- Acceptance: Same confirm pattern as disposals.

### OLD-7 Distributor customer returns
- Route: `/distributor/customer-returns, /new, /:id`
- Files: `live/distributor_customer_return_live/*`
- Frames: oxNAXRBPCz, gag0zJMVuV, 2poLrBv3Wq
- Build: List columns Return, Customer (orb), Warehouse, Reason, Items, Status (draft neutral, received info, inspected warning, completed success), Updated. New: two columns; left "Where this return comes from" (Find the shipment) + Customer card (Customer, GLN, Warehouse, Reason, Notes); right Items table (trash icon remove) + Related documents dropzone. Detail: KV card, items with condition badges (sellable/damaged/quarantine), documents, primary Mark inspected.
- Acceptance: Customer returns live under the Returns tabs, not a separate nav item.

### OLD-8 Break case
- Route: `distributor case route (distributor_case_live.ex)`
- Files: `live/distributor_case_live.ex`
- Frames: 9mhLuDdvyF, jDbPbmLbzu
- Build: Entry: Break case action on the distributor stock row (j2u8BBnf6m). Left: Batches and serials; right: Build sub-shippers with per-sub-shipper card (Batch select, Quantity), Add sub-shipper. Break case opens 480 confirm "Makes N sub-shippers, then closes this case."
- Acceptance: Destructive, so confirm is mandatory.

### OLD-9 Delivery note
- Route: `/distributor/shipments/:id/delivery-note`
- Files: `live/distributor_shipment_live/document.ex`
- Frames: UiVBLpI9Cx
- Build: A4: logo, "Delivery note" + shipment ref mono, Ship from / Ship to boxes with GLN, Warehouse / Order / Dispatch date / Packages, Product / Batch / Expiry / Units / Serials table with total, three signature lines. Entry: Delivery note button on approved shipment (8SCAEjcIlW).
- Acceptance: Only offered once approved.

### OLD-10 Manufacturer SSCC list and SSCC serials
- Route: `/manufacturer/products/:id/ssccs (+ serials)`
- Files: `live/manufacturer_product_live/ssccs.ex`
- Frames: C22opce6ED, TcfVwKaNOZ
- Build: SSCC list: back to product, Serials list / Shippers list (Export CSV overlay), Pallet label primary, chips Batch / Produced, columns Shipper SSCC, Batch, Produced, Expires, Primary serials, Pallet ("Not assigned to a pallet" muted). Serials: KV card + #, Serial, GTIN, Batch, Status, Previous/Next pager. Entry: View SSCCs on product detail Batches card (vGTuM5LTeA).
- Acceptance: All codes mono; nothing else mono.

### OLD-11 Error pages
- Route: `403 / 404 / 500`
- Files: `controllers/error_html/*.html.heex`
- Frames: OQFyEOkUDz, S17bRTza4-, BPT3jcEdcm
- Build: Auth layout (as Login oYsDYjktDQ): logo, "Error 4xx" muted, title, one line, Back to home primary lg; 403 adds "Log in as someone else", 500 adds support email.
- Acceptance: No Tailwind heavy type; Inter; no em dashes.

### Decision for Sean
- Distributor nav: Phoenix already has Customers and Returns (hero icons, groups Overview / Inventory / Sales & distribution). Doop distributor shell lacks both. New frames add Returns (arrow-u-up-left) after Receiving and Customers (address-book) after Products inside Doop groups Distributor / Reference data / Account. Resolved 23 Nov (pass 3): all 55 existing distributor desktop frames on LQFIZlhE35 now carry the same nav. See NAV-1.


## §10 Nav and empty states (pass 3, 23 Nov 2026)

### NAV-1 Distributor sidebar nav
- Doop source: every distributor desktop frame on page L1k6rZuWUm (for example 8OjVBGuJw2, XJBYJekyQ3, SLxbPI5Z4A, tpsqpH3pfq)
- Files: `layouts.ex` (`distributor_item_groups`), `td_components` nav item
- Build: Three groups, matching Doop exactly.
  - Distributor: Dashboard (squares-four), Shipments (truck, count), Receiving, Returns (arrow-u-up-left), Stock (package), Products, Customers (address-book)
  - Reference data: Mobile users, Sites
  - Account: Billing, TNT reporting, Org settings
- Phosphor icons only; drop the hero icons. Drop the Phoenix groups Overview / Inventory / Sales & distribution.
- Returns opens the supplier returns tab; Customers opens the customers list.
- Acceptance: Order, group labels and icons match Doop on every distributor page; one active item.

### NAV-2 Manufacturer sidebar nav
- Doop source: ssU7S65tZF (dashboard) and all 13 manufacturer desktop frames on page UZTuVHXtoW
- Files: `layouts.ex` manufacturer item groups
- Build: Two groups, every item with a Phosphor icon.
  - Manufacturer: Dashboard, Products, Inventory, Shipments (count), Aggregation, Mobile users
  - Account: TNT reporting, API keys, Org settings (gear)
- Sidebar footer: Dark mode row, then a hairline, then the user row with a seeded orb.
- Acceptance: No nav item without an icon. TNT reporting, API keys and Org settings show on every manufacturer page, not only the dashboard.

### EMPTY-1 Disposals and Returns empty states
- Doop source:
  - Pharmacy: 99LzqIZcf_ (no expiry write-offs) and rsjJ9t28Zj (no supplier returns)
  - Lab: SRcJwOLocx (no expiry write-offs) and Gk7InyRKVS (no supplier returns)
  - Distributor: 05gOuYcviW (no supplier returns)
- Files: pharmacy and lab disposals LiveViews (expiry and supplier tabs); distributor returns LiveView (supplier tab)
- Build:
  - Keep the tabs, with a count of 0.
  - Centred block: a 24px Phosphor icon in ink-3, a 16/500 title, one muted line, and one primary button that opens the start dialog.
  - No header CTA while the list is empty. No illustration.
- Copy:
  - "No expiry write-offs yet" / "Start one when a batch has passed its date."
  - "No supplier returns yet" / "Start one when stock is going back to the supplier."
- Acceptance: Shown when the tab has no rows. The button opens the same modal as the header button on the filled list.


## §11 Date picker and TNT reporting (23 Nov 2026)

### DATE-1 TD DatePicker (existing component, no new design)
- Doop source: component **TD DatePicker** `chdlkoodd2`, main frame gGZGY4la6k (DS · Components). Used in 11 frames: YK8WeJ4D9U, iXgHWN9Wlx, y11_7Bfo8B, 7ikGY9Ebrz, MC_1GL3a94, ZZmLwye-Ku, dIPT7cCITO, 53BedS4v4m, 4C-4iO5AGv, N-VnSYQtSj, UGem41P4cJ (all date-range filters).
- Code: `<.date_picker>` in `core_components.ex` (hook `.DatePicker`, styles from `--td-dp-*` in `app.css`). `<.input type="date">` and `<.td_input type="date">` already route to it.
- What the Doop component covers: month header with prev/next (26px filled buttons), weekday row, outside-month days (ink-3), range fill (accent tint) and range ends (solid accent, radius 8). One prop: `month`.
- Not drawn in Doop yet, but already in code: today marker, single selected day, disabled days (min/max), Clear and Today text actions. Match the code; do not add new visuals. Month/year quick switch exists in neither; out of scope.
- Sizes: field 32px, radius 8, 1px border, raised surface, Inter 14, calendar-blank icon right. Popover 280px wide, 12px padding, radius 12, 1px border on the surface token, no shadow. Weekday row 28px (12/500, ink-3). Day cells 32px (14, tabular figures).
- Field states: empty (placeholder "Choose a date" in ink-3), filled ("29 Jul 2026", Inter, never mono), focus/open (accent border and focus ring), error (danger border and message), disabled.
- Popover: opens below the field, flips above when there is no room, and sits above modal content (never clipped by a modal).
- Keyboard (already in the hook, keep it): Enter, Space or ArrowDown on the field opens; arrows move by a day or a week; Home/End jump to the start or end of the week; PageUp/PageDown change the month (Shift for a year); Enter or Space selects; Escape closes and returns focus to the field.
- Native date inputs left in Phoenix (read-only grep, branch sean/td-web-design-system):
  - No call site renders `type="date"` or `datetime-local` natively. All 16 LiveViews with date fields use `<.date_picker>`: distributor_customer_return_live/index, distributor_receiving_live, distributor_shipment_live/index, earnings_live, lab_order_live/index, lab_order_live/show, lab_receive_stock_live, lab_requisition_live/index, manufacturer_product_live/serial_wizard (Production and Expiry, lines 417-418), manufacturer_shipment_live/list, org_dashboard_live, prescription_live/index, product_live/show, requisition_live/index, requisition_queue_live/index, site_live/show.
  - Leftovers to clean: `assets/css/app.css:754` still styles `input[type="date"]` (dead selector). `core_components.ex:231` still lists `date` and `datetime-local` as allowed `input` types; `date` is redirected (line 262), but `datetime-local` would fall through to the generic native input (line 726). Remove `datetime-local` from the allowed list, or route it to the picker, so it cannot come back.
- Acceptance: No native browser calendar anywhere in Thamani web. Dates always display as "29 Jul 2026".

### TNT-1 TNT reporting (EPCIS events) in D5
- Doop source (canvas LQFIZlhE35):
  - Manufacturer: 6h1jP1RQB5 (Manual, 5 waiting, Hub off), IUuHyR8EK6 (Automatic), Ey__g8H971 (No events yet), ccaGTlWZk8 (dark)
  - Org: ZdiOKCCEg_ (Manual), IXtDUwcf_S (Automatic)
  - Distributor: brAo4lH0vA (Manual), wKLi2KlP3Q (Automatic)
  - Event details modal: 0zmvdMTWIE (Pending), 8B4C8tDPqC (Sent), G1_T8lFZ2b (dark); org duj3-u6uPd / 34PdLETg5c; distributor 14m9-tXF_w / xbhMUOwlrl
  - Confirms: m-gTgjUcmi (Send one event), 0OTimjfTsi (Send pending now)
- Routes and files (read-only grep):
  - `/manufacturer/epcis` → `lib/thamani_dawa_web/live/manufacturer_epcis_live.ex` (also serves admins as the org portal through `epcis_portal`)
  - `/org/epcis` and `/distributor/epcis` → `lib/thamani_dawa_web/live/distributor_epcis_live.ex` (router.ex lines 208 and 363; manufacturer at line 394)
  - Nav: `layouts.ex` lines 769 ("EPCIS events", hero-signal, manufacturer), 812, 829 and 847 ("TNT reporting", hero-globe-alt). Use "TNT reporting" with a Phosphor icon everywhere and drop the "EPCIS events" label.
  - Data: `lib/thamani_dawa/epcis/outbox.ex`, `outbox_event.ex`, `submission_worker.ex`, `client.ex` (`Client.enabled?`), `urn.ex`; mode in `Organizations.update_epcis_submission_mode/2`
  - API keys: `/manufacturer/api-keys`, `/org/api-keys`, `/distributor/api-keys` → `api_keys_live.ex`
- Build:
  - Page: `td_page_header` "TNT reporting" / "Report supply-chain events to the PPB National Track and Trace Hub.", then the 16px padded stack (`.pad`) of cards. No header actions.
  - Notice (only when `Client.enabled?` is false): bordered surface block, Phosphor info icon, "PPB submission is not active yet. Events are safely recorded here, but will not be sent until your system administrator enables the Hub connection." No tint, no shadow.
  - Hint (only when `tnt_keys_missing?`): key icon + "Add your TNT API key on API keys before you send events.", with "API keys" as an underlined link to the portal's API keys page.
  - Card "How events are sent": TD CardHeader; subtitle switches between "Events go to PPB as soon as they are queued." and "Events wait here until you send them." Row: Automatic / Manual segmented control (TD Segment items in the control track, not pills, no hero icons), then "N events waiting" (N in 500 weight, tabular), then primary "Send pending now" with a paper-plane icon. The button is disabled when mode is Automatic or N is 0; it opens the confirm.
  - Card "Events": TD CardHeader "Events" / "What has been queued or sent for this organization." with Refresh as the bordered secondary TD Button (arrows-clockwise). Toolbar: the "All events" filter menu trigger (funnel icon, caret, bordered) and TD Search "Search by action or event ID". Keep the existing filter menu items and counts, restyled as TD MenuItems with Phosphor icons.
  - Table columns: Event (business step in 500 weight, event type below in 12), Time (EAT) as "18 Nov 2026, 10:44", Event ID (mono, the short id), Status badge, Location (site name from the GLN), actions. Actions: "View details" (secondary) on every row, plus "Send" (primary) on Pending rows.
  - Status mapping: Pending = pending (warning tone); Sent = accepted or warning (success tone); Failed = rejected or dead (danger tone). Blocked shows as Failed with the reason in details. Keep Resubmit on failed rows as a primary button if Sean wants it (not drawn).
  - Times: the LiveView formats UTC ("%d %b %Y, %H:%M UTC"). Convert to Africa/Nairobi and show EAT.
  - Empty: "No events yet" / "Generate serials or create an SSCC and its events will appear here." Type only, no icon block or illustration. Send pending now is disabled (0 waiting).
  - Event details modal (TD Modal, replaces the raw JSON tabs as the first view): title "<Business step> event", subtitle "<Event type> · <short id>". Sections What (SGTIN or SSCC in mono, batch in mono), Where (location name, GLN in mono), When (event time and recorded time in EAT), Why (business step, disposition), Payload (status, Hub response). Footer: Close (secondary), Send (primary, Pending only). Keep the Request / Response JSON behind a secondary link if needed for support.
  - Send confirm: "Send this event now?" / "It goes to the PPB Hub ahead of its place in the queue, with its original event ID." Cancel + Send. Send pending confirm: "Send N pending events now?" / "They go to the PPB Hub in the order they were recorded." Cancel + "Send N events". Replace the `data-confirm` browser dialogs with these modals.
- Light and dark: all colours from TD tokens; dark is drawn on ccaGTlWZk8 and G1_T8lFZ2b.
- Open for Sean: org and distributor API keys pages are not designed in Doop yet, so the hint link is unwired on those two portals.
- Acceptance: No hero icons, legacy colour classes or uppercase type on the page; mode change, Send, Send pending now and View details all work as in Doop.

## §12 Shell account menu (23 Nov 2026)

### SHELL-ACCOUNT TD AccountMenu on the sidebar account chip
- Doop source (canvas LQFIZlhE35):
  - Component: TD AccountMenu `cgzlu47zzw`, main frame PCaEZ11y_v (Components page).
  - Open frames (light, dark): pharmacy y4OlKMJCvP / jYraWHiZ8A, lab hWFPMYtHfw / dmDflEXJzh, pharma-lab bXky4oNIZD / pTsV2tO6pN, distributor jHrWur7OeT / 5tAJJwmXEA, manufacturer xn2gfMFpoN / fbkMkuqkko, org mCPsIZVgxf / 9WU5fkjygR, platform 8Aov3K8OB_ / m3L9wqE8ed.
  - DS: uIcR89jDrO / lL8zAqkM0p (Site switcher and account menu). The old menu hB-Q2itaVG is renamed "old, replaced" and no longer linked; kept, not deleted.
  - All 238 shell frames: the chip opens the portal's open frame; the Dark mode and Product tour rows are gone from the sidebar.
- Code (read-only): `layouts.ex` lines 524-578 (sidebar footer: `#dark-mode-switch`, `#start-product-tour`, `td_account_chip` with the `:menu` slot holding `#sidebar-logout` / `#sidebar-logout-confirm`). The chip is `td_components.ex:772` (`#sidebar-account-card` aria-haspopup="menu", `#sidebar-account-dropdown` `.td-account-menu`). Put the menu in the chip's `:menu` slot; delete the two sidebar rows above the chip.
- Spec:
  - Anchored to the chip, opens upward, sidebar width less 12px each side (216px). Radius 12, 4px padding, 1px `--color-td-border`, `--color-td-surface`, no shadow.
  - Header: seeded gradient orb (same seed as the chip), name 14/500, role 12 ink-2, then "Org · Site" 12 ink-2 (wraps, never truncates).
  - Rows 32px, radius 8, 14/400, Phosphor 16px icon, hover `--color-td-hover`. Order: Account settings; Org settings (org, distributor and manufacturer admins only); divider; Help & docs, Product tour (starts the existing tour), Get the mobile app, Keyboard shortcuts with "⌘K" in 12 ink-3 (opens the command menu); divider; "Appearance" label 12 ink-3, then System / Light / Dark with a check on the active one; divider; Log out in danger, opening the existing Log out confirm.
  - No Switch site row: TD SiteSwitcher at the top of the sidebar already does it.
- Keyboard: Enter or Space on the chip opens and focuses the first row; ArrowUp/ArrowDown move (wrap), Home/End jump; Enter/Space activates; Escape closes and returns focus to the chip; Tab or outside click closes. role="menu" with role="menuitem" rows and role="menuitemradio" + aria-checked on the theme rows.
- Theme: use the existing script in `root.html.heex` lines 32-66 (`phx:set-theme`, localStorage "phx:theme", values system/light/dark). The rows dispatch `phx:set-theme` with `data-phx-theme`; the check follows the stored value. Remove `theme_toggle` from the sidebar (`layouts.ex` 1376 can stay if used elsewhere).
- Log out keeps `#sidebar-logout` and `#sidebar-logout-confirm` so tests still pass.
- Unwired in Doop: Account settings and Help & docs (no frames yet); Keyboard shortcuts on manufacturer (no command menu frame).
- Acceptance: No Dark mode or Product tour rows in any sidebar; the menu works by mouse and keyboard on all 7 portals in light and dark.

## §13 Sign up (23 Nov 2026)

### SIGNUP-1 Sign up with a GS1 API key only (no PPB)
- Doop source (canvas LQFIZlhE35, page Web · Shared, row y 1100), centred auth variant B:
  - 1 Organization: CLsksg2sae (dark 4Z4YHM7Y_Y)
  - 2 GS1 account: VwxTOORndK (empty), OV5Tdr9ydZ (checking, auto-advances), 2XUobNcrNt (verified with company name; dark O8kLNYf3Fk), 4F6aZWhPLl (key not accepted), G_PnFvidFs (registry unavailable), HSXX62zpxA (verified, no company name)
  - 3 Main location: 2N_Kzpr0VC (choose GLN), _DHaSIu5T5 (GLN verified + what happens here), niHaE_gCEX (GLN already registered), 2VMo4rHr0a (registry unavailable)
  - 4 Administrator: 1P50qYkBt1, Create account goes to Onboarding · Workspace ready v1kqSDbicp
  - Archived on Old · Archive (y 12000): copies DTvi4B5QP8, r_mJHlKTRh, o8Ghn-FKi- of the old three steps; moved pcEk276aX8, UQkSsnRqBF, NKlXWNuz3M. Nothing deleted.
- Code (read-only): `lib/thamani_dawa_web/live/signup_live.ex` (`@steps [:operating_model, :gs1_key, :main_location, :administrator]`), GS1 calls `ThamaniDawa.GS1.MemberApi.get_company_prefixes/1` and `list_glns/1`, GLN check via `lib/thamani_dawa/gs1/grp.ex` + `grp/licence.ex`, post-login checklist `onboarding_live.ex`. Routes `/signup`, `/onboarding`.
- Steps and fields:
  1. Organization: services multi-select (Retail pharmacy, Diagnostic laboratory, Pharmaceutical distributor, Pharmaceutical manufacturer) as TD OptionCards in 2 columns, "N selected" count. No organization name field: the name comes from GS1.
  2. GS1 account: TD Input "GS1 API key" (masked). States map to `@gs1_key_check`: `:idle` hint + "Not sure what this is?" box with "Get one from GS1 Kenya"; `:checking` TD Verify checking "Verifying with GS1", button disabled; `{:verified, name, ...}` TD Verify verified + "Verified organization" block (buildings icon, company name), Continue; `:invalid` input error + "This key was not accepted by GS1. Check it and try again."; `:unavailable` warning "We could not reach GS1. Try again in a moment."; `:name_not_found` warning + "Check the company details on your GS1 Kenya account, then verify again."
  3. Main location: TD Select "Location GLN" listing the GLNs from the GS1 account (name, address, GLN in mono). `@gln_check` states: checking, matched (TD Verify "Verified · name · address"), inactive, taken ("This GLN is already registered to another location on Thamani Dawa. Choose another GLN."), not_found, invalid_check_digit, unavailable. When verified and the org has more than one service, "What happens at this location?" radio cards from `site_activity_choices/1`.
  4. Administrator: first and last name, email, password ("At least 12 characters"), Terms and Privacy checkbox, Back + Create account.
- Remove from Phoenix: the PPB facility license block (`ppb_facility_name`, `license_number`, `@ppb_check`, `select_ppb_candidate`, `Ppb.verify_license`) and the KMLTTB block (`@kmlttb_check`) from the Main location step, the matching gates in `continue_site` and the Continue `disabled` rule, the PPB/KMLTTB keys in the `.SignupDraft` hook, and the PPB wording in `signup_subtitle(:main_location)` (use "Choose this location from your GS1 account, then say what happens here."). This lets manufacturers, distributors and other members join with only a GS1 key. Flag for Krak: this is code removal, not a restyle.
- Copy: no em dashes; "We use your GS1 member account to set up your organization and locations."
- Buttons: Back is the bordered secondary TD Button; primary fills the rest of the row. Hero icons become Phosphor (info, arrow-up-right, buildings, check-circle).
- Acceptance: No PPB or KMLTTB text or field anywhere in /signup; each GS1 and GLN state above renders as drawn.

## §14 Collapsed sidebar and brand mark (23 Nov 2026)

### SHELL-COLLAPSED
- Brand mark, why it looked missing: Doop shells were fine (every TD AppShell instance shows the canon wordmark /a/skIQnijggz.png, byte-identical to `priv/static/images/logo-transparent.png`; no instance overrides it). In Phoenix, commit 3cfbe41 (23 Nov 15:14 EAT, "align design system with Doop canon") removed the old `#sidebar-brand-row` and moved the logo to `.td-br` in `td_app_shell` (`td_components.ex` ~line 771). In the collapsed state `.td-shl.is-collapsed` shrinks that cell to 72px, but `.td-br` still holds the full 2628x411 wordmark at 15px high (~96px wide) plus the 30px toggle and 28px padding. With the global `img {max-width:100%}` from `landing.css` the wordmark gets squeezed to almost nothing, so the mark disappears when collapsed. The old collapsed rules in `app.css` 389-500 (`#sidebar-aside.sidebar-collapsed #sidebar-brand-row` and friends) target IDs that no longer exist, so they are dead CSS.
- Fix in Phoenix: add a compact mark to `.td-br` (`<img class="td-br-mark" src="/images/logo-mark.png">`, the red T cropped from the canon wordmark; Doop asset https://doop.design/a/jku0C1e2TG.png, 128x128 PNG) and in `.td-shl.is-collapsed` hide the wordmark, show the mark at 20x20, set `.td-br` padding to `0 14px 0 16px`. Delete the dead `#sidebar-aside.sidebar-collapsed #sidebar-brand-*` rules.
- Doop: TD AppShell (cufyq5cgue) rev 2 adds `sidebar: expanded|collapsed` (default expanded, so the 252 existing instances are unchanged). Collapsed = 72px rail + 1368px content, compact T mark + toggle in the brand cell.
- Frames (Light / Dark / Account menu open): pharmacy z-_Z3Rv4qH / yVco6_I9AL / -lOBfXJD2F; lab wDPDmgntHD / vHqhV0Iw7I / QN8jY331nC; pharma-lab uph54TOXbd / w8LaQy0Qdg / Y9Oy43oHk9; distributor l-R4s4jvz6 / 4ei1VPTckH / sDY1vtG1_v; manufacturer LToUOeDNer / a5DbXnpQwK / 40_pwuNQzC; org scM_EYqIrM / yr3ahvmXCi / gWKEKhjgay; platform CUuSnDv903 / xQ8gu75RDf / x6rOztF1f8.
- Rail spec: 56px column centred in the 72px sidebar (8px side padding). Site switcher as a 40x40 bordered tile with the site-type icon (opens the existing switcher). Nav items 40x32, radius 8, Phosphor 16px in ink-3; hover `--color-td-hover` + ink-2; active `--color-td-selected` with the filled Phosphor icon in accent. Count badges become a 6px accent dot. Groups are separated by a 24px hairline instead of labels. Tooltip on hover: label to the right (12/500, ink on surface inverted, radius 8, no shadow, 48px from the rail edge). Bottom: the account orb (40x40 hit area) opens TD AccountMenu upward.
- Toggle: `#sidebar-toggle` (sidebar-simple icon) collapses and expands; Doop wires the 7 dashboards to their collapsed frame and back. Keep `localStorage["sidebar-collapsed"]` and `aria-expanded` / `aria-label` ("Collapse sidebar" / "Expand sidebar"). Tooltips need `aria-label` on each link and show on keyboard focus too.
- Fixed layout: the title bar and content keep their positions; only the sidebar column changes (240 → 72) and content widens (1200 → 1368). Nothing else moves.

## §15 Manufacturer aggregation (23 Nov 2026)

### AGG-1 Aggregation on brand (pallet and shipper SSCCs)
- Sean (16:11): "i need this page on brand http://localhost:5780/manufacturer/aggregations".
- Code (read-only), `lib/thamani_dawa_web/live/manufacturer_aggregation_live/`: `dashboard.ex` (list), `wizard.ex` (add SSCC, also `:new_on_pallet`), `pallet_show.ex`, `sscc_show.ex` (contents + 4 modals), `review.ex`, `form.ex`, `list.ex`. Routes (router.ex 388-403): `/manufacturer/aggregations`, `/new`, `/pallets/:pallet_id/ssccs/new`, `/pallets/:id`, `/ssccs/:id`, `/:id` (Review).
- What was wrong: Doop had the older "pack serials into a shipper, Open/Labeled" list (nooman_e0w) that no longer matches the code. The code uses hero icons, ghost buttons and its own card styles.
- Doop (canvas LQFIZlhE35, page UZTuVHXtoW, row y 7800 and modals y 8800):
  - List: nooman_e0w (rewritten in place; nav "Aggregation" already points here). Empty GcfERrqXwb. Dark 9eVZhuE_oo.
  - Add SSCC: choose type lHqj6ZUNd9, pallet SynBwMYmxH (To GLN search open with results), standalone shipper dFl7bLVBCX (To party picked, "generated by the GS1 member API" note).
  - Pallet detail rDvQtkfRwC. Add shipper to pallet qGit1zj1rm (parent pallet block, inherited parties).
  - Shipper SSCC detail 6s_cVMiQkS, no contents rYXMrp0LxV, dark tY878a4EFK.
  - Modals: Add a GTIN lR-QAyMqkU, verified 0Bgaf217sX; Upload GTINs fVih9AULeV, review NS4itJFiPZ; Add a batch N6mJklIrFy; Add serials CSIvAn03cl.
  - Archived: copy of the old list _1h-hwz542 (Old · Archive, y 12000). The old review flow frames gqkhVbK6z_, R2MvAEcBgQ, LjYz-aVJzL stay where they are because `/:id` Review still exists in code; nothing links to them from the new list.
- Layout: TD PageHeader title + subtitle from the code. Title bar primary action: "Add SSCC" (list), "Add shipper SSCC" (pallet), "Upload GTINs" (bordered secondary) + "Add GTIN" (shipper). List = two cards with TD CardHeader ("Pallet SSCCs", "Standalone shipper SSCCs") holding tables: SSCC (mono 12), From → To company, count (tabular, right), caret. Rows open the detail.
- Forms: one 720px card centred in the content; type picker as two TD OptionCards; From fieldset = TD Select "From facility" (name · GLN) + read-only Company name and Address; To fieldset = TD Input "To GLN" with a result menu (company, GLN mono, address; check on the selected row). Search states use the code's copy: "Type at least 2 characters…", "Searching GS1 GLNs…", "No GS1 GLNs match this search.", "The GS1 GLN directory is unavailable. Try again in a moment." Footer: Cancel (secondary) + "Save pallet SSCC" / "Save shipper SSCC" (primary). Shipper error state copy: "Configure the organization's GS1 API key before generating a shipper SSCC."
- Detail: From / To party cards (icon + label 12/500 ink-3, company 16/500, GLN mono 12, address 14 ink-2) side by side, then the contents card. Batch table: Product (name + GTIN mono sub), Batch (mono), Production, Expiry, Serials. Pallet table: Shipper SSCC (mono), Product + GTIN, Batches, caret.
- Modals: TD Modal. Bulk review rows show GTIN (mono), product, and a status dot + label ("Owned GTIN" ink-2, "Verified" success, "Not ready" danger); footer Back + "Save ready GTINs". Batch dates use TD DatePicker (DATE-1) on the Production and Expiry inputs.
- Replace in Phoenix: hero icons with Phosphor (plus, upload-simple, caret-right, arrow-right, factory, warehouse, stack, info, check); ghost buttons with TD Button secondary; the custom cards with the td card + header pattern; codes in `font-mono` 12px only for SSCC, GTIN, GLN, batch numbers.
- Acceptance: each route above renders like its frame in light and dark; no ghost buttons; no hero icons; SSCC/GTIN/GLN/batch values are mono, everything else Inter.

## §16 Org team (23 Nov 2026)

### TEAM-1 Team on brand (list, invite, edit, deactivate, invited)
- Sean (16:24): "this needs to be on brand http://localhost:5780/org/team/5/edit".
- Code (read-only): `lib/thamani_dawa_web/live/team_live/index.ex` (one LiveView, `:index` / `:new` / `:edit`). Routes `/org/team`, `/org/team/new`, `/org/team/:id/edit` (router.ex 169-171). Status from `status/1`: Active, Invited (no password yet), Inactive. Roles are a multi-select (`role_checkboxes`), sites are filtered by role (`compatible_sites/2`); admins get all sites.
- Doop (page DUlCvlObu4):
  - List lrsiMDnvg9 (status label Pending → Invited, Faith's role → "Pharmacist, Lab technician", rows open the right edit modal as an overlay, inactive rows open the inactive row menu). Same fixes on oxV_PIz1td (invite sent), Z3khDQ-YI3 (updated), F1AjINQBbP (deactivated; Amina now shows Inactive). Dark hJ1Mh7LATb. No matches rt7EciPgt1.
  - Edit member yPDN9VJLDO (rewritten in place; /org/team/5/edit), invited NedbrC0gje, admin editing self WKjqxreB-S, inactive BoCBydTazK, dark wuYjejg5y0.
  - Invite staff DQNLz1gSP4 (rewritten in place), no role yet bCEk08BuY1, admin selected P_17R-JE3z.
  - Deactivate confirm 2SgnW5Uol9 (existing, kept). Row actions iZtnCpcAK5 (Edit, Deactivate), inactive _WNIkxsMWh (Edit, Reactivate).
  - Archived copies: kS9WXG6QX_ (old edit with Home site), gitgTFvqqH (old single-role invite), Old · Archive y 12000.
- Edit modal: TD Modal "Edit team member" / "Change roles and site access." Header row: orb (seed per user), name 14/500, email 12 ink-2, status dot + label on the right (Active success, Invited warning, Inactive ink-2). Name and email are read-only, as in the code. Roles = 3 check cards (TD Checkbox + 12px description; selected card has accent border + accent tint). Sites = search ("Search compatible sites") + TD Checkbox list of compatible sites; with Admin selected, show the note "Admins automatically have organization-wide access across all sites."; with no role, "Select a role above to view and assign compatible sites." Access row under a hairline: Active → "Deactivate account" + danger Deactivate (opens 2SgnW5Uol9); Invited → "Invite sent <date>" + "Not accepted yet. Deactivate to stop them joining." + Deactivate; Inactive → "Account deactivated" + secondary Reactivate; self → "This is your account. You cannot deactivate your own account." (no button). Footer Cancel + Save changes.
- List: keep the table (Name with orb, Email, Role, Sites, Status badge, ⋯ menu). Replace the inline ghost "Edit" / "Deactivate" / "Reactivate" buttons with the ⋯ row menu (TD MenuItem) and the row click to edit. Replace the browser `data-confirm` with the TD Modal confirm 2SgnW5Uol9. Flash errors stay as toasts: "You cannot deactivate your own account.", "Assign another active admin before deactivating this account."
- Replace in Phoenix: `hero-users` header icon and the blank state icon (Phosphor users-three), `ghost-edit` / `ghost-delete` / `ghost` button variants, the letter avatar in the onboarding invite header (`String.first(@current_scope.user.name)`) with the seeded orb, status badge label "Invited" (not Pending).
- New in design, flag for Krak: status/deactivate lives inside the edit modal too (code only has it inline on the row).
- Acceptance: /org/team and /org/team/:id/edit render like the frames in light and dark; no ghost buttons; no letter avatars; roles multi-select; site list follows the selected roles.

## §17 API keys (23 Nov 2026)

### APIKEYS-1 API keys on brand (org, distributor, manufacturer)
- Sean (16:23): API keys page on brand, built from the LiveView.
- Code (read-only): `lib/thamani_dawa_web/live/api_keys_live.ex`. Routes `/org/api-keys`, `/distributor/api-keys`, `/manufacturer/api-keys`. Nav: "API keys" sits in the Account group for org, distributor and manufacturer (layouts.ex 823-875).
- Important: the code does not issue keys. There is no create, reveal-once, copy or revoke. The page stores external keys this organization uses: one PPB Track & Trace key per tier (distributor "Receiving, packing, and shipping", facility "Receiving and dispensing", manufacturer "Commissioning, packing, and shipping") and one GS1 member API key. Saved keys show only "Key ending <last4>". The design follows the code: list = tier rows, empty = no keys saved, add/replace = inline form, revoke = Clear confirm. No reveal-once or copy, because the full key is never shown again. If Sean wants issued keys (Thamani's own API), that is new backend work, not this page.
- Doop:
  - Org (page DUlCvlObu4, y 22600): keys saved Wymc1OcGAx, no keys yet ZkVNOumC9w, adding a TNT key Kt5nPKwiu2, replacing the GS1 key naaWbccXBO, saved toast 28Gy0LUyw-, dark ldt0X9c853.
  - Clear confirm 9a056M-Yir, dark 2oBHtPAwc_ (y 23600).
  - Distributor (page L1k6rZuWUm, y 26000): eq1hvM1JAm, dark fOIbHB-8_d.
  - Manufacturer dNqZMZIzMf rewritten to match the code (archive copy vwnD8zZGTK of the old "issued keys / Create key" design).
  - The TNT "API keys" hint now links to the page: org ZdiOKCCEg_ and IXtDUwcf_S → Wymc1OcGAx; distributor brAo4lH0vA and wKLi2KlP3Q → eq1hvM1JAm.
- Layout: TD PageHeader "API keys" / "Credentials this organization uses with PPB Track & Trace and GS1." TNT card: title "TNT API key", or "Add your TNT API key" with an accent border when a needed tier has no key; Partner Portal link. One row per tier: tier name 14/500, scope 12 ink-2, then "Key ending 7f3a" (mono 12 for the last4 only) or "No key saved" (ink-3). Row actions: Replace (secondary) + Clear (secondary) when saved; Add key (primary) when empty. GS1 card: "GS1 API key" / "Bearer token for the GS1 member API…", row "Member API" / "SSCC creation and case contents".
- Add / replace: the row expands in place to a TD Input type password (label "<Tier> API key", placeholder "trk_live_…") with Cancel + Save. Saved → toast "<Tier> key saved." Clear → TD Modal confirm "Clear this key?" / "<Tier> key ending 7f3a" / "Reporting falls back to the platform-wide key until you add a new one." with Cancel + danger "Clear key"; toast "<Tier> key cleared. Reporting falls back to the platform key." GS1 copy: "GS1 key saved.", "GS1 key cleared. SSCC calls fall back to the platform token."
- Replace in Phoenix: ghost Replace / Clear buttons with TD Button secondary; `data-confirm` with the TD Modal confirm; hero-key with Phosphor key; custom cards with the td card + header pattern.
- Doop nav gap, flag: the existing org and distributor sidebars (about 108 frames) have no "API keys" item, though the code has one. The new API keys frames include it (active, before TNT reporting). Adding it to every other org and distributor frame is a separate sweep.
- Acceptance: all three routes render like the frames in light and dark; no ghost buttons; no browser confirm; only the last4 is mono.

## §18 Gaps closed after AGG-1 and TEAM-1 (23 Nov 2026)
- AGG-1 dark: modals Add a GTIN _z_kvN4J3u, verified 0ICDRrcaQm, Upload GTINs YkH8thqsrO, review -lU-wxAX4p, Add a batch k7yr3odkh-, Add serials z6oVqrpt2g (page UZTuVHXtoW, y 9500). Dark pallet XEj-QF2bKn. Dark list 9eVZhuE_oo and dark shipper tY878a4EFK now open the dark frames, dark dashboard and dark menu.
- AGG-1 bulk verifying state (code `bulk_status == :verifying`, "Checking each GTIN against GS1…", button "Verifying..."): rhHZl42YEh, dark Kcw3QZqZg3. Upload GTINs → verifying → review.
- AGG-1 GS1 key missing (wizard.ex `sscc_error(:unconfigured)`): standalone shipper form with an inline danger notice "GS1 API key missing" / "Configure the organization's GS1 API key before generating a shipper SSCC." and "Open API keys" → dNqZMZIzMf. c9jkythg4W, dark q-15ZUmjys. In code this is a flash; recommend the inline notice in the form card.
- TEAM-1 dark: deactivate confirm M0u047G0_t, edit invited atutxIdxzw, self waSN0oUASt, inactive P6mOUHvaAl, invite pjA5e3tWBR, row menus usg46YuulW / 9QS4GQVnnG, deactivated list h1QyV_djKg. Dark list hJ1Mh7LATb and dark edit wuYjejg5y0 now stay in dark.
- Dark dashboards (new, one per portal): pharmacy wUsA9ZdXrU, lab DK81R55zDL, pharma-lab WhDXvN7qc-, distributor bmmS6NYoqO, manufacturer xhJU95ZpT2, org 2t7LNnigQz, platform Rar-eyv7TH. Collapsed dark frames expand to these; their orb opens the new collapsed dark menu frames (pharmacy q5YtnjeAk4, lab K_zJSzulr0, pharma-lab ReN19tB_Wa, distributor zcgPDZ0lF2, manufacturer FiDFXnh49i, org kpyKO06T6e, platform SuGcOyYIM3). Dark expanded menu frames close to the dark dashboard.
- Account menu rows wired in all 28 menu-open frames: Account settings → per-portal Account settings modal (light/dark: pharmacy eMFocxEJET / e6armdDuB1, lab Wtq7havOxU / Zl8tmTC33I, pharma-lab GmWj7_y4-0 / vr-sx-p7kp, distributor LtxAOEjPME / rC46cFt9Bv, manufacturer tAYE2C0tWh / e_aY6bJVmi, org aXl83lItyb / 2z7Os_uWCz, platform fqgpDjTirx / moUzWWEaIH). Help & docs → product tour (the code's title bar help_path). Keyboard shortcuts → command menu (code focuses global search); manufacturer gets a new command menu MvYOMauO8O.
- Flag for Krak: the code's account menu has no Account settings or Help & docs rows, and there is no profile page or in-app password change (only /reset-password by email). The Account settings modal (name, email, "Send reset link") is design-ahead and needs a LiveView, or the two rows come out of TD AccountMenu.
