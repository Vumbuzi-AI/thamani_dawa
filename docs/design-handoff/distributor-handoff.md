# Thamani Dawa · Distributor flagship handoff

Canvas: https://doop.design/c/LQFIZlhE35 · page "Flagship · Distributor" (_mFdqiaAeu). Prototype: https://doop.design/c/LQFIZlhE35/proto (page start = Orders, https://doop.design/c/LQFIZlhE35?frame=BtVvvYcI0u).
Designer: Bau. Updated 23 Nov 2026, EAT. Sources: Krak code map §4 (distributor), dashboard 8OjVBGuJw2 for shell and nav.

## Ground rules used in every frame
- Shell: TD AppShell, same as the dashboard. Sidebar nav is the NEW distributor nav: Dashboard, Orders, Shipments, Receiving, Supplier returns, Customer returns, Stock, Products, Customers · Reference data: Mobile users, Sites · Account: Billing, TNT reporting, Org settings. Active item uses the Phosphor Fill icon. Sidebar links behave the same in every frame, so they are not repeated per frame below.
- Top bar: breadcrumb (site name → Dashboard), global search (click → Search a_9Z4X_p7f, ⌘K → Command menu FUN-ITw_Qj), help → Product tour, bell → Notifications, plus ONE contextual primary (Orders and Shipments: "New order", Customers: "Add customer", Supplier returns: "New supplier return", Customer returns: "New customer return", Receiving: "Receive delivery"). Detail pages have no top-bar primary; their actions sit in the page header.
- Actions happen in place: modals (overlay frames, sized to the modal) and the customer side panel. Approve keeps the same route and re-renders as the approved shipment with a toast. No page bounces.
- Every detail page has a back link at the top ("Back to …") that maps to a `return_to` param; it falls back to the parent list.
- Peeks: dashed-underline IDs (order, shipment, SSCC, customer, GLN) show a TD Peek on hover. In the prototype each peek is a "· Peek" state frame: hover the ID to open it, click outside to go back, the Open button opens the record.
- Mono only for GTIN, SGTIN, GLN, SSCC and batch. Order, shipment, return and receipt numbers are Inter. Times are EAT.
- List search fields filter the list in place (no link). Tabs filter in place (prototype stays on the same frame).
- Date chips (Created, Received, Approved) all open the same TD DatePicker popover frame "Orders · Created date filter" (QtYrmaQO7u); in code it is one shared date-range filter.
- "Prototype states:" text links at the bottom of a frame jump to alternate states of that screen.
- New TD components (Components page): TD Peek cuo1ccz0cc, TD PeekRow c4lmgrekxw, TD GlnResult ch3io2yj80, TD GlnField ckg2o1xqxy.

## Batch 1 · Orders

### Orders
- Frame: https://doop.design/c/LQFIZlhE35?frame=BtVvvYcI0u
- Route: `/distributor/orders (today: /distributor/shipments?status=draft,submitted,rejected)`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: PO-KMC-0412 SH-2026-0090" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Hover ID PO-KMC-0412" · hover → goes to Orders · Peek order (OhBylKZWBL)
  - "Hover ID Kisumu Medical Centre" · hover → goes to Orders · Peek customer (QHhHPf-5-E)
  - "Row: PO-WD-0950 SH-2026-0092" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-MPN-1182 SH-2026-0089" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NCP-0219 SH-2026-0091" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-CD-0331 SH-2026-0085" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NTP-0077 SH-2026-0086" · click → goes to Order · Rejected (vhCc7uhX2D)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · Peek order
- Frame: https://doop.design/c/LQFIZlhE35?frame=OhBylKZWBL
- Route: `/distributor/orders, hover state`
- Back / return_to: Hover state: click outside the peek → base list
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: PO-KMC-0412 SH-2026-0090" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Hover ID PO-KMC-0412" · hover → goes to Orders · Peek order (OhBylKZWBL)
  - "Hover ID Kisumu Medical Centre" · hover → goes to Orders · Peek customer (QHhHPf-5-E)
  - "Row: PO-WD-0950 SH-2026-0092" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-MPN-1182 SH-2026-0089" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NCP-0219 SH-2026-0091" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-CD-0331 SH-2026-0085" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NTP-0077 SH-2026-0086" · click → goes to Order · Rejected (vhCc7uhX2D)
  - "(click outside the peek)" · click → goes to Orders (BtVvvYcI0u)
  - "Open order" · click → goes to Order · Submitted (ubJnNz_20s)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · Peek customer
- Frame: https://doop.design/c/LQFIZlhE35?frame=QHhHPf-5-E
- Route: `/distributor/orders, hover state`
- Back / return_to: Hover state: click outside the peek → base list
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: PO-KMC-0412 SH-2026-0090" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Hover ID PO-KMC-0412" · hover → goes to Orders · Peek order (OhBylKZWBL)
  - "Hover ID Kisumu Medical Centre" · hover → goes to Orders · Peek customer (QHhHPf-5-E)
  - "Row: PO-WD-0950 SH-2026-0092" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-MPN-1182 SH-2026-0089" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NCP-0219 SH-2026-0091" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-CD-0331 SH-2026-0085" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NTP-0077 SH-2026-0086" · click → goes to Order · Rejected (vhCc7uhX2D)
  - "(click outside the peek)" · click → goes to Orders (BtVvvYcI0u)
  - "Open customer" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · Loading
- Frame: https://doop.design/c/LQFIZlhE35?frame=jDK7PezVf6
- Route: `/distributor/orders, loading`
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · No orders yet
- Frame: https://doop.design/c/LQFIZlhE35?frame=BQkZ30kz_9
- Route: `/distributor/orders, empty`
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · Did not load
- Frame: https://doop.design/c/LQFIZlhE35?frame=K9xn-K1Zq1
- Route: `/distributor/orders, load error`
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Try again" · click → goes to Orders (BtVvvYcI0u)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · Created date filter
- Frame: https://doop.design/c/LQFIZlhE35?frame=QtYrmaQO7u
- Route: `/distributor/orders, Created filter popover`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Today" · click → closes, back to the page under it
  - "Last 7 days" · click → closes, back to the page under it
  - "Last 30 days" · click → closes, back to the page under it
  - "This month" · click → closes, back to the page under it
  - "Custom range" · click → closes, back to the page under it
  - "Clear" · click → closes, back to the page under it
  - "Apply" · click → closes, back to the page under it

### New order
- Frame: https://doop.design/c/LQFIZlhE35?frame=oOLJEW6Y9i
- Route: `/distributor/orders, modal (new)`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Ship to" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Searching" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Verified" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Not in GS1" · click → goes to New order · GLN not in GS1 (Xz-QiweZj3)
  - "GS1 unavailable" · click → goes to New order · GS1 unavailable (3DSFdgUXG1)
  - "Cancel" · click → closes, back to the page under it

### New order · Searching GLN
- Frame: https://doop.design/c/LQFIZlhE35?frame=e6HenD0l5o
- Route: `modal state`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Ship to" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Searching" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Verified" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Not in GS1" · click → goes to New order · GLN not in GS1 (Xz-QiweZj3)
  - "GS1 unavailable" · click → goes to New order · GS1 unavailable (3DSFdgUXG1)
  - "Cancel" · click → closes, back to the page under it

### New order · GLN verified
- Frame: https://doop.design/c/LQFIZlhE35?frame=IO_GhePn_L
- Route: `modal state`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Searching" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Verified" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Not in GS1" · click → goes to New order · GLN not in GS1 (Xz-QiweZj3)
  - "GS1 unavailable" · click → goes to New order · GS1 unavailable (3DSFdgUXG1)
  - "Cancel" · click → closes, back to the page under it
  - "Create order" · click → goes to Order · Just created (NWV9zxhi7E)

### New order · GLN not in GS1
- Frame: https://doop.design/c/LQFIZlhE35?frame=Xz-QiweZj3
- Route: `modal state`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Searching" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Verified" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Not in GS1" · click → goes to New order · GLN not in GS1 (Xz-QiweZj3)
  - "GS1 unavailable" · click → goes to New order · GS1 unavailable (3DSFdgUXG1)
  - "Cancel" · click → closes, back to the page under it
  - "Create order" · click → goes to Order · Just created (NWV9zxhi7E)

### New order · GS1 unavailable
- Frame: https://doop.design/c/LQFIZlhE35?frame=3DSFdgUXG1
- Route: `modal state`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Searching" · click → goes to New order · Searching GLN (e6HenD0l5o)
  - "Verified" · click → goes to New order · GLN verified (IO_GhePn_L)
  - "Not in GS1" · click → goes to New order · GLN not in GS1 (Xz-QiweZj3)
  - "GS1 unavailable" · click → goes to New order · GS1 unavailable (3DSFdgUXG1)
  - "Cancel" · click → closes, back to the page under it
  - "Try again" · click → goes to New order · Searching GLN (e6HenD0l5o)

### Order · Draft
- Frame: https://doop.design/c/LQFIZlhE35?frame=iTF4WVAPo5
- Route: `/distributor/shipments/:id (draft)`
- Back / return_to: Back to Orders → Orders
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Edit details" · click → opens modal Edit order details (x-C3WyM0JH)
  - "Add items" · click → opens modal Add items to order (aEXl8NvGyM)
  - "Remove" · click → opens modal Remove item (5mZQ-49VPF)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Orders" · click → goes to Orders (BtVvvYcI0u)

### Order · Just created
- Frame: https://doop.design/c/LQFIZlhE35?frame=NWV9zxhi7E
- Route: `/distributor/shipments/:id (draft, just created, flash)`
- Back / return_to: Back to Orders → Orders
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Edit details" · click → opens modal Edit order details (x-C3WyM0JH)
  - "Add items" · click → opens modal Add items to order (aEXl8NvGyM)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Orders" · click → goes to Orders (BtVvvYcI0u)

### Order · Submitted
- Frame: https://doop.design/c/LQFIZlhE35?frame=ubJnNz_20s
- Route: `/distributor/shipments/:id (status submitted)`
- Back / return_to: Back to Orders → Orders
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Reject" · click → opens modal Reject order (Ii5SM7wFMP)
  - "Approve and issue SSCCs" · click → opens modal Approve order (ZCIIZEHJM7)
  - "Remove" · click → opens modal Remove item (5mZQ-49VPF)
  - "Ready to approve" · click → opens modal Approve order (ZCIIZEHJM7)
  - "Not enough serials" · click → opens modal Approve order · Not enough serials (JpvXFX4Umx)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Orders" · click → goes to Orders (BtVvvYcI0u)

### Order · Rejected
- Frame: https://doop.design/c/LQFIZlhE35?frame=vhCc7uhX2D
- Route: `/distributor/shipments/:id (rejected)`
- Back / return_to: Back to Orders → Orders
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Reopen as draft" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Orders" · click → goes to Orders (BtVvvYcI0u)

### Approve order
- Frame: https://doop.design/c/LQFIZlhE35?frame=ZCIIZEHJM7
- Route: `/distributor/shipments/:id, modal approve`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Approve and issue SSCCs" · click → goes to Shipment · Just approved (M1FGlnKkVy)

### Approve order · Not enough serials
- Frame: https://doop.design/c/LQFIZlhE35?frame=JpvXFX4Umx
- Route: `/distributor/shipments/:id, modal approve error`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Buy serials" · click → goes to Distributor · Billing · prepay (nNSes79vHo)

### Reject order
- Frame: https://doop.design/c/LQFIZlhE35?frame=Ii5SM7wFMP
- Route: `/distributor/shipments/:id, modal reject`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Reject order" · click → goes to Order · Rejected (vhCc7uhX2D)

### Edit order details
- Frame: https://doop.design/c/LQFIZlhE35?frame=x-C3WyM0JH
- Route: `/distributor/shipments/:id, modal edit`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Save changes" · click → closes, back to the page under it

## Batch 1 · Receiving

### Receiving
- Frame: https://doop.design/c/LQFIZlhE35?frame=L2u9fSFZ7S
- Route: `/distributor/receiving`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "Received" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Row: GRN-2026-0148" · click → goes to Receipt · Open discrepancies (wJYopBvolb)
  - "Row: GRN-2026-0147" · click → goes to Receipt · Open discrepancies (wJYopBvolb)
  - "Row: GRN-2026-0146" · click → goes to Receipt · Open discrepancies (wJYopBvolb)
  - "Row: GRN-2026-0145" · click → goes to Receipt · Open discrepancies (wJYopBvolb)
  - "Row: GRN-2026-0144" · click → goes to Receipt · Open discrepancies (wJYopBvolb)
  - "Receive delivery" · click → goes to Receive delivery · Ready to scan (u9cttTYlZ0)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Receiving · Loading
- Frame: https://doop.design/c/LQFIZlhE35?frame=hFyPPEErUh
- Route: `/distributor/receiving, loading`
- Buttons and links (label · trigger → target):
  - "Receive delivery" · click → goes to Receive delivery · Ready to scan (u9cttTYlZ0)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Receiving · No deliveries yet
- Frame: https://doop.design/c/LQFIZlhE35?frame=jubLfnKC7f
- Route: `/distributor/receiving, empty`
- Buttons and links (label · trigger → target):
  - "Receive delivery" · click → goes to Receive delivery · Ready to scan (u9cttTYlZ0)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Receive delivery · Ready to scan
- Frame: https://doop.design/c/LQFIZlhE35?frame=u9cttTYlZ0
- Route: `/distributor/receiving/new`
- Back / return_to: Back to Receiving → Receiving; Cancel → Receiving
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Cancel" · click → goes to Receiving (L2u9fSFZ7S)
  - "Shipper SSCC or product barcode" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "Add item by hand" · click → opens modal Distributor · Add item · product found (ZoTRfv1hsN)
  - "All match" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "With discrepancies" · click → goes to Receive delivery · Discrepancies (4if24EHtRa)
  - "Unknown SSCC" · click → goes to Receive delivery · Unknown SSCC (F767tkSkL8)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Receive delivery · All shippers match
- Frame: https://doop.design/c/LQFIZlhE35?frame=O5RTBc-NkX
- Route: `/distributor/receiving/new (scanned, all match)`
- Back / return_to: Back to Receiving → Receiving
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Cancel" · click → goes to Receiving (L2u9fSFZ7S)
  - "Accept delivery" · click → opens modal Accept delivery (V1bTID3e98)
  - "Add item by hand" · click → opens modal Distributor · Add item · product found (ZoTRfv1hsN)
  - "All match" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "With discrepancies" · click → goes to Receive delivery · Discrepancies (4if24EHtRa)
  - "Unknown SSCC" · click → goes to Receive delivery · Unknown SSCC (F767tkSkL8)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Receive delivery · Unknown SSCC
- Frame: https://doop.design/c/LQFIZlhE35?frame=F767tkSkL8
- Route: `/distributor/receiving/new (unknown SSCC)`
- Back / return_to: Back to Receiving → Receiving
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Cancel" · click → goes to Receiving (L2u9fSFZ7S)
  - "Add item by hand" · click → opens modal Distributor · Add item · product found (ZoTRfv1hsN)
  - "Shipper SSCC or product barcode" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "All match" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "With discrepancies" · click → goes to Receive delivery · Discrepancies (4if24EHtRa)
  - "Unknown SSCC" · click → goes to Receive delivery · Unknown SSCC (F767tkSkL8)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Receive delivery · Discrepancies
- Frame: https://doop.design/c/LQFIZlhE35?frame=4if24EHtRa
- Route: `/distributor/receiving/new (discrepancies)`
- Back / return_to: Back to Receiving → Receiving
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Cancel" · click → goes to Receiving (L2u9fSFZ7S)
  - "Accept delivery" · click → opens modal Accept delivery · With discrepancies (YcbT2XojzC)
  - "Add item by hand" · click → opens modal Distributor · Add item · product found (ZoTRfv1hsN)
  - "All match" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "With discrepancies" · click → goes to Receive delivery · Discrepancies (4if24EHtRa)
  - "Unknown SSCC" · click → goes to Receive delivery · Unknown SSCC (F767tkSkL8)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Accept delivery
- Frame: https://doop.design/c/LQFIZlhE35?frame=V1bTID3e98
- Route: `/distributor/receiving/new, modal finish_delivery`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Keep checking" · click → closes, back to the page under it
  - "Accept delivery" · click → goes to Receipt · Open discrepancies (wJYopBvolb)

### Accept delivery · With discrepancies
- Frame: https://doop.design/c/LQFIZlhE35?frame=YcbT2XojzC
- Route: `/distributor/receiving/new, modal finish_delivery with discrepancies`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Keep checking" · click → closes, back to the page under it
  - "Accept delivery" · click → goes to Receipt · Open discrepancies (wJYopBvolb)

### Receipt · Open discrepancies
- Frame: https://doop.design/c/LQFIZlhE35?frame=wJYopBvolb
- Route: `/distributor/receiving/:id (receipt)`
- Back / return_to: Back to Receiving → Receiving
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Resolve" · click → opens modal Resolve discrepancy (J8fngpiRNP)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Resolve discrepancy
- Frame: https://doop.design/c/LQFIZlhE35?frame=J8fngpiRNP
- Route: `/distributor/receiving/:id, modal resolve_discrepancy`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Mark as resolved" · click → closes, back to the page under it

## Batch 2 · Shipments

### Shipments · Ready to dispatch
- Frame: https://doop.design/c/LQFIZlhE35?frame=3qslZ7MTx3
- Route: `/distributor/shipments (status approved)`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "All shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Approved" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Hover ID SH-2026-0088" · hover → goes to Shipments · Peek shipment (CuinzPru0R)
  - "Row: SH-2026-0087" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0084" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0083" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0081" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Shipments · Peek shipment
- Frame: https://doop.design/c/LQFIZlhE35?frame=CuinzPru0R
- Route: `/distributor/shipments, hover state`
- Back / return_to: Hover state: click outside the peek → base list
- Buttons and links (label · trigger → target):
  - "All shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Approved" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Hover ID SH-2026-0088" · hover → goes to Shipments · Peek shipment (CuinzPru0R)
  - "Row: SH-2026-0087" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0084" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0083" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Row: SH-2026-0081" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "(click outside the peek)" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Open shipment" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Shipments · Nothing ready
- Frame: https://doop.design/c/LQFIZlhE35?frame=hy5MwhOBsm
- Route: `/distributor/shipments, empty`
- Buttons and links (label · trigger → target):
  - "All shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Approved" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Open orders" · click → goes to Orders (BtVvvYcI0u)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Shipment · Just approved
- Frame: https://doop.design/c/LQFIZlhE35?frame=M1FGlnKkVy
- Route: `/distributor/shipments/:id (approved, flash)`
- Back / return_to: Back to Shipments → Shipments
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Print labels" · click → opens modal Distributor · Print SSCC labels (AG21KELEMP)
  - "Packing list" · click → goes to Shipment · Packing list (cz2zJuCU9q)
  - "Delivery note" · click → goes to Distributor · Delivery note (UiVBLpI9Cx)
  - "Hover ID 361640010000004127" · hover → goes to Shipment · Peek SSCC (KVcXAeNLJ-)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)

### Shipment · Approved
- Frame: https://doop.design/c/LQFIZlhE35?frame=-_IWiu3qyJ
- Route: `/distributor/shipments/:id (approved)`
- Back / return_to: Back to Shipments → Shipments
- Buttons and links (label · trigger → target):
  - "Back to Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Print labels" · click → opens modal Distributor · Print SSCC labels (AG21KELEMP)
  - "Packing list" · click → goes to Shipment · Packing list (cz2zJuCU9q)
  - "Delivery note" · click → goes to Distributor · Delivery note (UiVBLpI9Cx)
  - "Hover ID 361640010000004127" · hover → goes to Shipment · Peek SSCC (KVcXAeNLJ-)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)

### Shipment · Peek SSCC
- Frame: https://doop.design/c/LQFIZlhE35?frame=KVcXAeNLJ-
- Route: `/distributor/shipments/:id, hover state`
- Back / return_to: Hover state: click outside the peek → base list
- Buttons and links (label · trigger → target):
  - "Back to Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Print labels" · click → opens modal Distributor · Print SSCC labels (AG21KELEMP)
  - "Packing list" · click → goes to Shipment · Packing list (cz2zJuCU9q)
  - "Delivery note" · click → goes to Distributor · Delivery note (UiVBLpI9Cx)
  - "Hover ID 361640010000004127" · hover → goes to Shipment · Peek SSCC (KVcXAeNLJ-)
  - "(click outside the peek)" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Open SSCC" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)

### Add items to order
- Frame: https://doop.design/c/LQFIZlhE35?frame=aEXl8NvGyM
- Route: `/distributor/shipments/:id, modal add items (NEW)`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Close (x)" · click → opens modal Remove item (5mZQ-49VPF)
  - "Scanned" · click → goes to Add items to order (aEXl8NvGyM)
  - "Already shipped" · click → goes to Add items to order · Already shipped (2FuGWpuQAt)
  - "Cancel" · click → closes, back to the page under it
  - "Add 2 shippers" · click → goes to Order · Draft (iTF4WVAPo5)

### Add items to order · Already shipped
- Frame: https://doop.design/c/LQFIZlhE35?frame=2FuGWpuQAt
- Route: `/distributor/shipments/:id, modal add items error`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Close (x)" · click → opens modal Remove item (5mZQ-49VPF)
  - "Scanned" · click → goes to Add items to order (aEXl8NvGyM)
  - "Already shipped" · click → goes to Add items to order · Already shipped (2FuGWpuQAt)
  - "Cancel" · click → closes, back to the page under it
  - "Add 1 shipper" · click → goes to Order · Draft (iTF4WVAPo5)

### Distributor · Delivery note
- Frame: https://doop.design/c/LQFIZlhE35?frame=UiVBLpI9Cx
- Route: `/distributor/shipments/:id/delivery-note (Document LiveView)`
- Back / return_to: Back to SH-2026-0088 → Shipment
- Buttons and links (label · trigger → target):
  - "Back to SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)

### Shipment · Packing list
- Frame: https://doop.design/c/LQFIZlhE35?frame=cz2zJuCU9q
- Route: `/distributor/shipments/:id/packing-list (Document LiveView)`
- Back / return_to: Back to SH-2026-0088 → Shipment
- Buttons and links (label · trigger → target):
  - "Back to SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "SH-2026-0088" · click → goes to Shipment · Approved (-_IWiu3qyJ)

## Batch 3 · Supplier returns

### Distributor · Returns · supplier returns
- Frame: https://doop.design/c/LQFIZlhE35?frame=SLxbPI5Z4A
- Route: `/distributor/returns`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Awaiting approval" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Approved" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Rejected" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Row: RET-2026-0031" · click → goes to Supplier return · Draft (QaIzcmnIX_)
  - "Row: RET-2026-0030" · click → goes to Supplier return · Awaiting approval (F9KueUZSQP)
  - "Row: RET-2026-0029" · click → goes to Supplier return · Awaiting approval (F9KueUZSQP)
  - "Row: RET-2026-0028" · click → goes to Supplier return · Awaiting approval (F9KueUZSQP)
  - "New supplier return" · click → opens modal New supplier return (k22oREfuiR)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Distributor · Returns · no supplier returns
- Frame: https://doop.design/c/LQFIZlhE35?frame=05gOuYcviW
- Route: `/distributor/returns, empty`
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Awaiting approval" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Approved" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Rejected" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "New supplier return" · click → opens modal New supplier return (k22oREfuiR)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### New supplier return
- Frame: https://doop.design/c/LQFIZlhE35?frame=k22oREfuiR
- Route: `/distributor/returns, modal new`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Create return" · click → goes to Supplier return · Draft (QaIzcmnIX_)

### Supplier return · Draft
- Frame: https://doop.design/c/LQFIZlhE35?frame=QaIzcmnIX_
- Route: `/distributor/returns/:id (draft)`
- Back / return_to: Back to Supplier returns
- Buttons and links (label · trigger → target):
  - "Back to Supplier returns" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Submit for approval" · click → opens modal Submit supplier return (lv6JwlB648)
  - "Close (x)" · click → opens modal Remove item (5mZQ-49VPF)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Supplier returns" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)

### Submit supplier return
- Frame: https://doop.design/c/LQFIZlhE35?frame=lv6JwlB648
- Route: `/distributor/returns/:id, modal submit`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Submit for approval" · click → goes to Supplier return · Awaiting approval (F9KueUZSQP)

### Supplier return · Awaiting approval
- Frame: https://doop.design/c/LQFIZlhE35?frame=F9KueUZSQP
- Route: `/distributor/returns/:id (submitted)`
- Back / return_to: Back to Supplier returns
- Buttons and links (label · trigger → target):
  - "Back to Supplier returns" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)
  - "Reopen as draft" · click → goes to Supplier return · Draft (QaIzcmnIX_)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Supplier returns" · click → goes to Distributor · Returns · supplier returns (SLxbPI5Z4A)

## Batch 3 · Customer returns

### Distributor · Returns · customer returns
- Frame: https://doop.design/c/LQFIZlhE35?frame=oxNAXRBPCz
- Route: `/distributor/customer-returns`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "Received" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Inspected" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Completed" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Row: CR-2026-0041" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0040" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0039" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0038" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "New customer return" · click → goes to Distributor · New customer return (gag0zJMVuV)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Distributor · New customer return
- Frame: https://doop.design/c/LQFIZlhE35?frame=gag0zJMVuV
- Route: `/distributor/customer-returns, modal new (select_shipment / select_customer)`
- Buttons and links (label · trigger → target):
  - "Received" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Inspected" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Completed" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Row: CR-2026-0041" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0040" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0039" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Row: CR-2026-0038" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Cancel" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Create return" · click → goes to Distributor · Customer return detail (2poLrBv3Wq)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Distributor · Customer return detail
- Frame: https://doop.design/c/LQFIZlhE35?frame=2poLrBv3Wq
- Route: `/distributor/customer-returns/:id (received)`
- Back / return_to: Back to Customer returns
- Buttons and links (label · trigger → target):
  - "Back to Customer returns" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Mark as inspected" · click → opens modal Complete customer return (IqmlkmNw_y)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Customer returns" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)

### Complete customer return
- Frame: https://doop.design/c/LQFIZlhE35?frame=IqmlkmNw_y
- Route: `/distributor/customer-returns/:id, modal complete`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Not yet" · click → closes, back to the page under it
  - "Complete return" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)

## Batch 3 · Customers

### Distributor · Customers
- Frame: https://doop.design/c/LQFIZlhE35?frame=tpsqpH3pfq
- Route: `/distributor/customers`
- Back / return_to: Sidebar (top level)
- Buttons and links (label · trigger → target):
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: Kisumu Medical Centre" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Hover ID 6160012300039" · hover → goes to Customers · Peek GLN (xSHiORAF_i)
  - "Row: MedPoint Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nairobi CBD Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Westlands Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Coast Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nakuru Town Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Add customer" · click → opens modal Distributor · Add customer (yfImGybMH4)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Customers · Customer selected
- Frame: https://doop.design/c/LQFIZlhE35?frame=Om1wU20GOb
- Route: `/distributor/customers?selected=:id (side panel)`
- Back / return_to: Close (x) → Customers
- Buttons and links (label · trigger → target):
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: Kisumu Medical Centre" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Hover ID 6160012300039" · hover → goes to Customers · Peek GLN (xSHiORAF_i)
  - "Row: MedPoint Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nairobi CBD Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Westlands Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Coast Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nakuru Town Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Close (x)" · click → goes to Distributor · Customers (tpsqpH3pfq)
  - "List item PO-KMC-0412" · click → goes to Order · Submitted (ubJnNz_20s)
  - "List item PO-KMC-0398" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "List item PO-KMC-0385" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Edit customer" · click → opens modal Distributor · Edit customer (WvABh70bsk)
  - "New order for this customer" · click → opens modal New order · GLN verified (IO_GhePn_L)
  - "Add customer" · click → opens modal Distributor · Add customer (yfImGybMH4)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Customers" · click → goes to Distributor · Customers (tpsqpH3pfq)

### Customers · Peek GLN
- Frame: https://doop.design/c/LQFIZlhE35?frame=xSHiORAF_i
- Route: `/distributor/customers, hover state`
- Back / return_to: Hover state: click outside the peek → base list
- Buttons and links (label · trigger → target):
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: Kisumu Medical Centre" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Hover ID 6160012300039" · hover → goes to Customers · Peek GLN (xSHiORAF_i)
  - "Row: MedPoint Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nairobi CBD Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Westlands Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Coast Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nakuru Town Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "(click outside the peek)" · click → goes to Distributor · Customers (tpsqpH3pfq)
  - "Open customer" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Add customer" · click → opens modal Distributor · Add customer (yfImGybMH4)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Distributor · Customers · none yet
- Frame: https://doop.design/c/LQFIZlhE35?frame=eLeVZImSse
- Route: `/distributor/customers, empty`
- Buttons and links (label · trigger → target):
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Add customer" · click → opens modal Distributor · Add customer (yfImGybMH4)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Distributor · Add customer
- Frame: https://doop.design/c/LQFIZlhE35?frame=yfImGybMH4
- Route: `/distributor/customers, modal add (lookup_gln / skip_gln)`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Add customer" · click → goes to Customers · Customer selected (Om1wU20GOb)

### Distributor · Edit customer
- Frame: https://doop.design/c/LQFIZlhE35?frame=WvABh70bsk
- Route: `/distributor/customers, modal edit`
- Back / return_to: Modal: Cancel / Close (x) closes back to the page under it
- Buttons and links (label · trigger → target):
  - "Close (x)" · click → closes, back to the page under it
  - "Cancel" · click → closes, back to the page under it
  - "Save changes" · click → goes to Customers · Customer selected (Om1wU20GOb)

## Batch 3 · Peeks, GLN field, other upgrades, dark

### TD Peek · Distributor patterns
- Frame: https://doop.design/c/LQFIZlhE35?frame=2zvXQbzJ5G
- Route: `spec board`
- Buttons and links (label · trigger → target):
  - "Open order" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Open shipment" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Open SSCC" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Open customer" · click → goes to Customers · Customer selected (Om1wU20GOb)

### TD GlnField · States
- Frame: https://doop.design/c/LQFIZlhE35?frame=9ZdNOmTsIa
- Route: `spec board`

### Distributor · Break case
- Frame: https://doop.design/c/LQFIZlhE35?frame=9mhLuDdvyF
- Route: `/distributor/stock/batches/:id/break-case (return_to replaces history.back)`
- Back / return_to: Back to batch WH-7688 → batch (return_to)
- Buttons and links (label · trigger → target):
  - "Back to batch WH-7688" · click → goes to Distributor · Batch detail (Yd-me0Se-p)
  - "Cancel" · click → goes to Distributor · Batch detail (Yd-me0Se-p)
  - "Break case" · click → opens modal Distributor · Break case confirm (jDbPbmLbzu)
  - "Close (x)" · click → opens modal Remove item (5mZQ-49VPF)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Stock" · click → goes to Distributor · Stock · storage zone (j2u8BBnf6m)
  - "WH-7688" · click → goes to Distributor · Batch detail (Yd-me0Se-p)

### Distributor · TNT reporting
- Frame: https://doop.design/c/LQFIZlhE35?frame=brAo4lH0vA
- Route: `/distributor/tnt (nav swap only)`
- Buttons and links (label · trigger → target):
  - "API keys" · click → goes to Distributor · API keys (eq1hvM1JAm)
  - "Send pending now" · click → opens modal TNT · Send pending now confirm (0OTimjfTsi)
  - "Refresh" · click → goes to Distributor · TNT reporting (brAo4lH0vA)
  - "View details" · click → opens modal Distributor · TNT event details · Pending (14m9-tXF_w)
  - "Send" · click → opens modal TNT · Send event confirm (m-gTgjUcmi)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Orders · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=lsOTHexE3v
- Route: `dark of Orders`
- Buttons and links (label · trigger → target):
  - "Draft" · click → goes to Orders (BtVvvYcI0u)
  - "Submitted" · click → goes to Orders (BtVvvYcI0u)
  - "Rejected" · click → goes to Orders (BtVvvYcI0u)
  - "Created" · click → opens modal Orders · Created date filter (QtYrmaQO7u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: PO-KMC-0412 SH-2026-0090" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Hover ID PO-KMC-0412" · hover → goes to Orders · Peek order (OhBylKZWBL)
  - "Hover ID Kisumu Medical Centre" · hover → goes to Orders · Peek customer (QHhHPf-5-E)
  - "Row: PO-WD-0950 SH-2026-0092" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-MPN-1182 SH-2026-0089" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NCP-0219 SH-2026-0091" · click → goes to Order · Draft (iTF4WVAPo5)
  - "Row: PO-CD-0331 SH-2026-0085" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Row: PO-NTP-0077 SH-2026-0086" · click → goes to Order · Rejected (vhCc7uhX2D)
  - "New order" · click → opens modal New order (oOLJEW6Y9i)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)

### Order · Submitted · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=_wv810YKEs
- Route: `dark of Order submitted`
- Buttons and links (label · trigger → target):
  - "Back to Orders" · click → goes to Orders (BtVvvYcI0u)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Reject" · click → opens modal Reject order (Ii5SM7wFMP)
  - "Approve and issue SSCCs" · click → opens modal Approve order (ZCIIZEHJM7)
  - "Remove" · click → opens modal Remove item (5mZQ-49VPF)
  - "Ready to approve" · click → opens modal Approve order (ZCIIZEHJM7)
  - "Not enough serials" · click → opens modal Approve order · Not enough serials (JpvXFX4Umx)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Orders" · click → goes to Orders (BtVvvYcI0u)

### Receive delivery · Discrepancies · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=epNjCU0KF8
- Route: `dark of Receive discrepancies`
- Buttons and links (label · trigger → target):
  - "Back to Receiving" · click → goes to Receiving (L2u9fSFZ7S)
  - "Cancel" · click → goes to Receiving (L2u9fSFZ7S)
  - "Accept delivery" · click → opens modal Accept delivery · With discrepancies (YcbT2XojzC)
  - "Add item by hand" · click → opens modal Distributor · Add item · product found (ZoTRfv1hsN)
  - "All match" · click → goes to Receive delivery · All shippers match (O5RTBc-NkX)
  - "With discrepancies" · click → goes to Receive delivery · Discrepancies (4if24EHtRa)
  - "Unknown SSCC" · click → goes to Receive delivery · Unknown SSCC (F767tkSkL8)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Receiving" · click → goes to Receiving (L2u9fSFZ7S)

### Shipment · Approved · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=22wpAvp6KT
- Route: `dark of Shipment approved`
- Buttons and links (label · trigger → target):
  - "Back to Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Print labels" · click → opens modal Distributor · Print SSCC labels (AG21KELEMP)
  - "Packing list" · click → goes to Shipment · Packing list (cz2zJuCU9q)
  - "Delivery note" · click → goes to Distributor · Delivery note (UiVBLpI9Cx)
  - "Hover ID 361640010000004127" · hover → goes to Shipment · Peek SSCC (KVcXAeNLJ-)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Shipments" · click → goes to Shipments · Ready to dispatch (3qslZ7MTx3)

### Customer return · Received · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=zHc-siXtXP
- Route: `dark of Customer return`
- Buttons and links (label · trigger → target):
  - "Back to Customer returns" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)
  - "Mark as inspected" · click → opens modal Complete customer return (IqmlkmNw_y)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Customer returns" · click → goes to Distributor · Returns · customer returns (oxNAXRBPCz)

### Customers · Customer selected · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=36yuq7FZbL
- Route: `dark of Customer panel`
- Buttons and links (label · trigger → target):
  - "Export CSV" · click → opens modal Export CSV (2E9yucAGjQ)
  - "Row: Kisumu Medical Centre" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Hover ID 6160012300039" · hover → goes to Customers · Peek GLN (xSHiORAF_i)
  - "Row: MedPoint Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nairobi CBD Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Westlands Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Coast Diagnostics" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Row: Nakuru Town Pharmacy" · click → goes to Customers · Customer selected (Om1wU20GOb)
  - "Close (x)" · click → goes to Distributor · Customers (tpsqpH3pfq)
  - "List item PO-KMC-0412" · click → goes to Order · Submitted (ubJnNz_20s)
  - "List item PO-KMC-0398" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "List item PO-KMC-0385" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Edit customer" · click → opens modal Distributor · Edit customer (WvABh70bsk)
  - "New order for this customer" · click → opens modal New order · GLN verified (IO_GhePn_L)
  - "Add customer" · click → opens modal Distributor · Add customer (yfImGybMH4)
  - "Embakasi Warehouse" · click → goes to Distributor · Dashboard (8OjVBGuJw2)
  - "Customers" · click → goes to Distributor · Customers (tpsqpH3pfq)

### TD Peek · Distributor patterns · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=j8WEEY48di
- Route: `dark of TD Peek board`
- Buttons and links (label · trigger → target):
  - "Open order" · click → goes to Order · Submitted (ubJnNz_20s)
  - "Open shipment" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Open SSCC" · click → goes to Shipment · Approved (-_IWiu3qyJ)
  - "Open customer" · click → goes to Customers · Customer selected (Om1wU20GOb)

## HOLD (designed or flagged, not to build yet)
1. Web "Add items" (Add items to order aEXl8NvGyM / 2FuGWpuQAt). Today packing only happens in the mobile app. Hold until we decide web scanning into a draft order is allowed. The Draft order still shows "Add items" in the design.
2. Dispatch as its own state. Code has no dispatched state (approved = ready to dispatch). Shipments list is titled "Ready to dispatch". Hold a "Mark as dispatched" action until a status exists.
3. Stock page and pick list. Stock is a redirect today and there is no pick list. Not designed here; sidebar "Stock" still goes to the existing stock frame j2u8BBnf6m.
4. Org disposals approval (/org/disposals) has no nav. Supplier return "Awaiting approval" (F9KueUZSQP) says an org admin approves it; where that admin clicks is held.
5. Creating an order for a GLN that is not in GS1 (New order · GLN not in GS1, Xz-QiweZj3) is shown as allowed and flagged. Confirm the master rules before building.
6. Customer return "Complete" stock effects (m_cr_complete IqmlkmNw_y): resaleable goes back to stock, damaged goes to quarantine. Verify against code before building.
7. Packing list (cz2zJuCU9q) exists in code as a Document LiveView but had no frame; designed now, check copy with ops.
8. Nav change (new Orders item, Customer returns moved into the sidebar) is only applied to the frames on this page plus TNT reporting (brAo4lH0vA). The other canon distributor frames and layouts.ex still use the old nav.

## Backend needs
1. Orders index: `/distributor/orders` as a filtered view of shipments with status in draft, submitted, rejected (DistributorShipmentLive.Index with a status filter). Sidebar badge = submitted count.
2. Shipments index: default filter status = approved, tab "All shipments" removes the filter.
3. `return_to` param on every detail route (shipments/:id, receiving/:id, returns/:id, customer-returns/:id, break case). Back link uses it, falls back to the parent list. Replace `history.back` on cases.
4. Receiving: after `finish_delivery`, push_navigate to the receipt `/distributor/receiving/:id` (not the list) with a flash.
5. Receipt `resolve_discrepancy`: add an outcome field (Supplier is sending the balance, Credit note, Write off) plus note. Verify what exists.
6. One shared `GlnField` LiveComponent replacing GlnSearchField, the serial wizard combobox, the pack panel combobox and the aggregation wizard combobox. Search order: own sites, saved customers, GS1. States: idle, searching/results, verified, not in GS1, GS1 unavailable.
7. Peek data: each peek needs a small payload (order: shipment no, status, shippers/units, products, packed by, submitted at; shipment: order, SSCCs/units, approved at, delivery note printed at, TNT event; SSCC: batch, GTIN, expiry, shipment, packed by/at; customer: GLN, GS1 status, open orders, last shipment, phone; GLN: address, party type, GS1 verified at, saved as, order count). Lists should preload what they already have; one lazy fetch for the rest.
8. Customers list: GS1 verified flag, order count and last order date per customer. Customer panel: recent shipments filtered by destination GLN.
9. Approve: keep the same route and re-render as approved with flash "Approved. 4 SSCCs issued." Serial shortage returns a typed error for the "Not enough serials" modal.
10. Supplier returns: `/distributor/returns/:id` needs a back link; submit/reopen already exist.
11. Customer returns: split the single LiveView into list + detail route `/distributor/customer-returns/:id` (today modals only), keep select_shipment/select_customer in the new modal, mark_received, mark_inspected, complete on the detail.

## Superseded, not deleted
Old frames replaced by this page and left in place on "Web · Distributor flows": XJBYJekyQ3, IiThKMTc0e, ynvC_CLltK, 8SCAEjcIlW, z6VSLXmqsn, pTKmcZsilq, NwX0CruZHC, v-q64497Ft.
