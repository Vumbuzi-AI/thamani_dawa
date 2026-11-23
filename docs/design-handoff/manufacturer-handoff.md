# Thamani Dawa · Manufacturer flagship flow · Handoff

Canvas: https://doop.design/c/LQFIZlhE35 · page "Flagship · Manufacturer" (GCvBvFLYxw). Prototype start: Products (rOKtmxrk0b).
Built by Bau on 23 Nov 2026 (EAT). Code reference: Krak's code map, box clone at 6c38d46. Repo not touched.

Rules applied: TD components and tokens only, native editable frames, Phosphor icons, Inter for labels, mono only for GTIN, SGTIN, GLN, SSCC and batch, no ghost secondary buttons, no shadows or blur, whites #F9F9FA / #EFEFF0 / #FFFFFF (label paper), Orb avatars, times in EAT, TD DatePicker chdlkoodd2, desktop fixed 1440 x 900, light first then dark.

Every detail page has a 40px back row ("Back to X") that reads `?return_to=` and falls back to the parent shown under "Back". Modals are separate frames opened as overlays; Close (x) and Cancel return to the page underneath.

Sample data: Thamani Pharma Limited (GLN 6164001000017) ships to Kilimo Distributors Ltd (GLN 6164003000024). Hero product Ceftriaxone 1g injection, GTIN 06289001005678, batch CFX-2411-01, 500 units, order PO-24117.

## Batch 1 · Steps 1 to 3 (Products, Generate serials, Batches, View serials)

Flow: Products → "Generate serials" (row action when a product has 0 serials) → Mode → Batch → Generating → lands on Batches `?batch=CFX-2411-01` with the new batch selected, a serial preview and the primary "Print labels" (bulk). "View serials" (row action when a product has serials) → Batches for that product → "View all serials" → View serials with search, state filter and shipper filter, packed and unpacked from packed_serials, "Create shipper SSCC" and the "All serials packed" state.

Superseded: kyQHKTVNuw and pu69ruhFa_ (old "Serials issued" modals on page UZTuVHXtoW) are renamed "Superseded · …" and point to 4KdsxCd1Xj.

### Step 1 · Products
#### Products
- Frame: https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b
- Route: `/manufacturer/products`
- Back: None (sidebar page)
- Buttons and links (from this frame):
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
  - "Sync from GS1" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Hover GTIN (peek)" → [Products · GTIN peek](https://doop.design/c/LQFIZlhE35?frame=vvYOSDxcqf)
  - "Row: Amoxicillin 500mg capsules" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
#### Products · Syncing from GS1
- Frame: https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_
- Route: `/manufacturer/products (sync running)`
- Back: None (sidebar page)
- Note: Auto-advances to Products after 2s in the prototype.
- Buttons and links (from this frame):
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
  - "Syncing" → disabled in this state
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Row: Amoxicillin 500mg capsules" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Auto: sync finished" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Products · Sync failed
- Frame: https://doop.design/c/LQFIZlhE35?frame=jEHjO102Ab
- Route: `/manufacturer/products (sync failed)`
- Back: None (sidebar page)
- Buttons and links (from this frame):
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
  - "Sync from GS1" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "Retry sync" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Row: Amoxicillin 500mg capsules" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
#### Products · Empty
- Frame: https://doop.design/c/LQFIZlhE35?frame=AywKWZYjJ5
- Route: `/manufacturer/products (no products)`
- Back: None (sidebar page)
- Buttons and links (from this frame):
  - "Sync from GS1" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
#### Product detail
- Frame: https://doop.design/c/LQFIZlhE35?frame=oR30_7au26
- Route: `/manufacturer/products/:id?return_to=…`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Buttons and links (from this frame):
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Hover batch (peek)" → [Product detail · Batch peek](https://doop.design/c/LQFIZlhE35?frame=1G5npcrtDv)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Products · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL
- Route: `/manufacturer/products`
- Back: None (sidebar page)
- Buttons and links (from this frame):
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
  - "Sync from GS1" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Hover GTIN (peek)" → [Products · GTIN peek](https://doop.design/c/LQFIZlhE35?frame=vvYOSDxcqf)
  - "Row: Amoxicillin 500mg capsules" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
### Step 2 · Generate serials wizard and landing
#### Generate serials · Mode
- Frame: https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF
- Route: `/manufacturer/products/:gtin/serials/new`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Make to stock" → [Generate serials · Batch (stock)](https://doop.design/c/LQFIZlhE35?frame=60lAgEf28c) (opens as modal)
  - "Make to order" → [Generate serials · Batch (order)](https://doop.design/c/LQFIZlhE35?frame=QTcjh85AAT) (opens as modal)
  - "Cancel" → closes the modal (back to the page underneath)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · Batch (stock)
- Frame: https://doop.design/c/LQFIZlhE35?frame=60lAgEf28c
- Route: `/manufacturer/products/:gtin/serials/new · Batch (stock)`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Expiry date field (opens TD DatePicker)" → [Generate serials · Expiry date picker](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) (opens as modal)
  - "Back" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Generate serials" → [Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · Expiry date picker
- Frame: https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr
- Route: `/manufacturer/products/:gtin/serials/new · expiry picker open`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Pick a day (22 Nov 2028)" → [Generate serials · Batch (stock)](https://doop.design/c/LQFIZlhE35?frame=60lAgEf28c) (opens as modal)
  - "Expiry date field (opens TD DatePicker)" → [Generate serials · Expiry date picker](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) (opens as modal)
  - "Back" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Generate serials" → [Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · Batch (order)
- Frame: https://doop.design/c/LQFIZlhE35?frame=QTcjh85AAT
- Route: `/manufacturer/products/:gtin/serials/new · Batch (order)`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Back" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Next" → [Generate serials · From and To](https://doop.design/c/LQFIZlhE35?frame=EAR8n3VwU-) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · From and To
- Frame: https://doop.design/c/LQFIZlhE35?frame=EAR8n3VwU-
- Route: `/manufacturer/products/:gtin/serials/new · From and To (order)`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Back" → [Generate serials · Batch (order)](https://doop.design/c/LQFIZlhE35?frame=QTcjh85AAT) (opens as modal)
  - "Generate serials & SSCCs" → [Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · Generating
- Frame: https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp
- Route: `/manufacturer/products/:gtin/serials/new · generating`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Note: Auto-advances to Batches with CFX-2411-01 selected after 1.8s.
- Buttons and links (from this frame):
  - "Back" → disabled in this state
  - "Generating" → disabled in this state
  - "Close (x)" → closes the modal (back to the page underneath)
  - "Auto: GS1 returned serials, land on Batches ?batch=CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Generate serials · GS1 unavailable
- Frame: https://doop.design/c/LQFIZlhE35?frame=w0jvpBd9vY
- Route: `/manufacturer/products/:gtin/serials/new · GS1 unavailable`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Expiry date field (opens TD DatePicker)" → [Generate serials · Expiry date picker](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) (opens as modal)
  - "Back" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Try again" → [Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Generate serials · Batch (stock) · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=JjktwwOHSf
- Route: `/manufacturer/products/:gtin/serials/new · Batch (stock)`
- Back: Modal over Products (or Batches / Product detail). Close and Cancel return to the page it opened on.
- Buttons and links (from this frame):
  - "Expiry date field (opens TD DatePicker)" → [Generate serials · Expiry date picker](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) (opens as modal)
  - "Back" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Generate serials" → [Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) (opens as modal)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Batches · New batch selected
- Frame: https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&return_to=/manufacturer/products`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Note: Landing after Generate serials (both modes). No inventory hop.
- Buttons and links (from this frame):
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "View all serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Batches · New batch selected · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=y3QHt6WcP5
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&return_to=/manufacturer/products`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Note: Landing after Generate serials (both modes). No inventory hop.
- Buttons and links (from this frame):
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "Back: Back to Products" → [Products · dark](https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials · dark](https://doop.design/c/LQFIZlhE35?frame=skkXuR1UiM)
  - "View all serials" → [View serials · All unpacked · dark](https://doop.design/c/LQFIZlhE35?frame=a-cMCe7l9k)
  - "Crumb: Products" → [Products · dark](https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL)
#### Print labels
- Frame: https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM
- Route: `/manufacturer/products/:gtin/serials?batch=… · Print labels (modal)`
- Back: Modal. Cancel and Close return to the page underneath.
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Print 500 labels" → closes the modal (back to the page underneath)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Batches · Batch with shippers
- Frame: https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT
- Route: `/manufacturer/products/:gtin/serials?batch=AMX-2409-11`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Buttons and links (from this frame):
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Shipper row" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "View all serials" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "Rail: batch AMX-2410-03" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Rail: batch AMX-2408-02" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Rail: batch AMX-2407-05" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Rail: batch AMX-2406-09" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Batches · Waiting for GS1
- Frame: https://doop.design/c/LQFIZlhE35?frame=Zl3Kuvvy9I
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01 (GS1 still listing the batch)`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Note: Keep ?batch= selected and poll. Never fall back to another batch. Auto-advances after 2s.
- Buttons and links (from this frame):
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Print labels" → disabled in this state
  - "Auto: GS1 listed the batch" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Batches · GS1 error
- Frame: https://doop.design/c/LQFIZlhE35?frame=lbP-59bxKH
- Route: `/manufacturer/products/:gtin/serials (GS1 batch list failed)`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Buttons and links (from this frame):
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Retry" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Print labels" → disabled in this state
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Batches · No serials yet
- Frame: https://doop.design/c/LQFIZlhE35?frame=s-Y7-4zrCb
- Route: `/manufacturer/products/:gtin/serials (no batches)`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Buttons and links (from this frame):
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Print labels" → disabled in this state
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
### Step 3 · View serials
#### View serials · All unpacked
- Frame: https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials&return_to=…`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Note: State "Create shipper SSCC": unpacked serials exist.
- Buttons and links (from this frame):
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### View serials · Packed filter
- Frame: https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials&state=packed`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Buttons and links (from this frame):
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### View serials · No matches
- Frame: https://doop.design/c/LQFIZlhE35?frame=N47kkIH5F7
- Route: `/manufacturer/products/:gtin/serials?…&view=serials&q=X7K2ZZ`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Buttons and links (from this frame):
  - "Clear search" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### View serials · GS1 error
- Frame: https://doop.design/c/LQFIZlhE35?frame=RWCTScqFsc
- Route: `/manufacturer/products/:gtin/serials?…&view=serials (GS1 error)`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Buttons and links (from this frame):
  - "Retry" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Create shipper SSCC" → disabled in this state
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### View serials · All serials packed
- Frame: https://doop.design/c/LQFIZlhE35?frame=MMpEnojxuU
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials (all packed)`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Note: State "All serials packed": Create shipper SSCC is hidden; the next step is Build a pallet.
- Buttons and links (from this frame):
  - "View shipper SSCCs" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Build a pallet" → [Build a pallet · Scan shippers](https://doop.design/c/LQFIZlhE35?frame=InMakqK959)
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### View serials · All unpacked · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=a-cMCe7l9k
- Route: `/manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials&return_to=…`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Note: State "Create shipper SSCC": unpacked serials exist.
- Buttons and links (from this frame):
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials · dark](https://doop.design/c/LQFIZlhE35?frame=skkXuR1UiM)
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected · dark](https://doop.design/c/LQFIZlhE35?frame=y3QHt6WcP5)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Print labels" → [Print labels](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) (opens as modal)
  - "State chip" → [View serials · Packed filter](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products · dark](https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected · dark](https://doop.design/c/LQFIZlhE35?frame=y3QHt6WcP5)
## Batch 2 · Steps 4 and 5 (Pack into shipper, Build a pallet)

Flow: View serials "Create shipper SSCC" (or Batches) → Pack shipper: 1 Select serials → 2 Parties → 3 Review → "Create shipper SSCC" → Shipper SSCC detail (toast, back via return_to) → titlebar "Print label" opens the single full-size Shipper label modal. That modal replaces "Print SSCC labels" and "Case label" (old modal iqCZv_AYnf). Shipper detail → "Build a pallet" → scan shipper SSCCs (clean, then errors: duplicate, on shipment, empty shipper, different destination) → "Create pallet SSCC" modal → Pallet SSCC detail → "Print label" (Pallet label modal) and primary "Ship this pallet" (step 6).

Empty-state copy fix: Product SSCCs now says "Shipper SSCCs are created when you pack serials into a shipper." (was "created when stock is shipped").

Renamed reused frames: ijOdE3IvVJ "Pack shipper · 1 Select serials", fbgqW4GxfP "Pack shipper · 1 Scan error", IQ2oV6Y6Gn "Pack shipper · 2 Parties".

### Step 4 · Pack into shipper
#### Pack shipper · 1 Select serials
- Frame: https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01&return_to=…`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: New live_action. Only unpacked serials are listed. Step 1 of 3.
- Buttons and links (from this frame):
  - "Scan field (scan a serial)" → [Pack shipper · 1 Scan error](https://doop.design/c/LQFIZlhE35?frame=fbgqW4GxfP)
  - "Cancel" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Next" → [Pack shipper · 2 Parties](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Pack shipper · 1 Scan error
- Frame: https://doop.design/c/LQFIZlhE35?frame=fbgqW4GxfP
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01 (scan error)`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Buttons and links (from this frame):
  - "Scan field (clear the error)" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Cancel" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Next" → [Pack shipper · 2 Parties](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Pack shipper · 2 Parties
- Frame: https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01&step=parties`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: Step 2 of 3. Packing never creates a shipment.
- Buttons and links (from this frame):
  - "Back" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Next" → [Pack shipper · 3 Review](https://doop.design/c/LQFIZlhE35?frame=Og6REur2VF)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Pack shipper · 3 Review
- Frame: https://doop.design/c/LQFIZlhE35?frame=Og6REur2VF
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01&step=review`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: Step 3 of 3.
- Buttons and links (from this frame):
  - "Back" → [Pack shipper · 2 Parties](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn)
  - "Create shipper SSCC" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Pack shipper · 3 GS1 error
- Frame: https://doop.design/c/LQFIZlhE35?frame=ETttYSzslq
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01&step=review (GS1 error)`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: Error state of Review. Not on the happy path; Try again goes on to the created shipper.
- Buttons and links (from this frame):
  - "Back" → [Pack shipper · 2 Parties](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn)
  - "Try again" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Shipper SSCC · Created
- Frame: https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU
- Route: `/manufacturer/sscc/:id/serials?return_to=/manufacturer/products/:gtin/serials?batch=CFX-2411-01`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: Shipper detail. Today this page has no back link; it gets one here.
- Buttons and links (from this frame):
  - "Print label" → [Shipper label](https://doop.design/c/LQFIZlhE35?frame=NlxXvWnCVy) (opens as modal)
  - "Back: Back to serials" → [View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2)
  - "Pack another shipper" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Build a pallet" → [Build a pallet · Scan shippers](https://doop.design/c/LQFIZlhE35?frame=InMakqK959)
  - "View serials" → [View serials · All serials packed](https://doop.design/c/LQFIZlhE35?frame=MMpEnojxuU)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Shipper label
- Frame: https://doop.design/c/LQFIZlhE35?frame=NlxXvWnCVy
- Route: `/manufacturer/sscc/:id/serials · Shipper label (modal)`
- Back: Modal over the shipper. Cancel and Close return to it.
- Note: Single full-size label. Replaces "Print SSCC labels" and "Case label".
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Print label" → closes the modal (back to the page underneath)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Product SSCCs · Empty
- Frame: https://doop.design/c/LQFIZlhE35?frame=xMKTsiTgSt
- Route: `/manufacturer/products/:gtin/sscc (no shippers)`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01 ("Back to batch CFX-2411-01")
- Note: Copy fix: SSCCs are created when stock is packed, not when it ships.
- Buttons and links (from this frame):
  - "Back: Back to batch CFX-2411-01" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
  - "Pack a shipper" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Create shipper SSCC" → [Pack shipper · 1 Select serials](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj)
#### Pack shipper · 1 Select serials · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=skkXuR1UiM
- Route: `/manufacturer/products/:gtin/serials/pack?batch=CFX-2411-01&return_to=…`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: New live_action. Only unpacked serials are listed. Step 1 of 3.
- Buttons and links (from this frame):
  - "Scan field (scan a serial)" → [Pack shipper · 1 Scan error](https://doop.design/c/LQFIZlhE35?frame=fbgqW4GxfP)
  - "Cancel" → [View serials · All unpacked · dark](https://doop.design/c/LQFIZlhE35?frame=a-cMCe7l9k)
  - "Next" → [Pack shipper · 2 Parties](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn)
  - "Back: Back to serials" → [View serials · All unpacked · dark](https://doop.design/c/LQFIZlhE35?frame=a-cMCe7l9k)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Crumb: Products" → [Products · dark](https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected · dark](https://doop.design/c/LQFIZlhE35?frame=y3QHt6WcP5)
#### Shipper SSCC · Created · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=rnN1USyC0E
- Route: `/manufacturer/sscc/:id/serials?return_to=/manufacturer/products/:gtin/serials?batch=CFX-2411-01`
- Back: return_to, default /manufacturer/products/:gtin/serials?batch=CFX-2411-01&view=serials ("Back to serials")
- Note: Shipper detail. Today this page has no back link; it gets one here.
- Buttons and links (from this frame):
  - "Print label" → [Shipper label · dark](https://doop.design/c/LQFIZlhE35?frame=yev3IBhxHQ) (opens as modal)
  - "Back: Back to serials" → [View serials · All unpacked · dark](https://doop.design/c/LQFIZlhE35?frame=a-cMCe7l9k)
  - "Pack another shipper" → [Pack shipper · 1 Select serials · dark](https://doop.design/c/LQFIZlhE35?frame=skkXuR1UiM)
  - "Build a pallet" → [Build a pallet · Scan shippers](https://doop.design/c/LQFIZlhE35?frame=InMakqK959)
  - "View serials" → [View serials · All serials packed](https://doop.design/c/LQFIZlhE35?frame=MMpEnojxuU)
  - "Crumb: Products" → [Products · dark](https://doop.design/c/LQFIZlhE35?frame=K-dOqwMXhL)
  - "Crumb: Ceftriaxone 1g injection" → [Batches · New batch selected · dark](https://doop.design/c/LQFIZlhE35?frame=y3QHt6WcP5)
#### Shipper label · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=yev3IBhxHQ
- Route: `/manufacturer/sscc/:id/serials · Shipper label (modal)`
- Back: Modal over the shipper. Cancel and Close return to it.
- Note: Single full-size label. Replaces "Print SSCC labels" and "Case label".
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Print label" → closes the modal (back to the page underneath)
  - "Close (x)" → closes the modal (back to the page underneath)
### Step 5 · Build a pallet
#### Build a pallet · Scan shippers
- Frame: https://doop.design/c/LQFIZlhE35?frame=InMakqK959
- Route: `/manufacturer/pallets/new?return_to=/manufacturer/sscc/:id/serials`
- Back: return_to, default /manufacturer/aggregation ("Back to shipper 361640010000000276" when opened from the shipper)
- Note: Replaces the PalletNew checkbox list with scanning.
- Buttons and links (from this frame):
  - "Back: Back to shipper 361640010000000276" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Scan field (scan shippers)" → [Build a pallet · Scanned](https://doop.design/c/LQFIZlhE35?frame=pzbEX96qkr)
  - "Cancel" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Create pallet SSCC" → disabled in this state
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Build a pallet · Scanned
- Frame: https://doop.design/c/LQFIZlhE35?frame=pzbEX96qkr
- Route: `/manufacturer/pallets/new (6 scanned)`
- Back: return_to, default /manufacturer/aggregation ("Back to shipper 361640010000000276" when opened from the shipper)
- Buttons and links (from this frame):
  - "Back: Back to shipper 361640010000000276" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Scan field (scan more shippers)" → [Build a pallet · Scan errors](https://doop.design/c/LQFIZlhE35?frame=Vwv8gSu322)
  - "Remove 361640010000000276" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000283" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000290" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000306" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000313" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000320" → no navigation (action stays on this page: download, print or row control)
  - "Cancel" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Create pallet SSCC" → [Build a pallet · Create pallet SSCC](https://doop.design/c/LQFIZlhE35?frame=Df97I34rKN) (opens as modal)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Build a pallet · Scan errors
- Frame: https://doop.design/c/LQFIZlhE35?frame=Vwv8gSu322
- Route: `/manufacturer/pallets/new (scan errors)`
- Back: return_to, default /manufacturer/aggregation ("Back to shipper 361640010000000276" when opened from the shipper)
- Note: Errors: duplicate, already on a shipment, wrong state (empty), different destination.
- Buttons and links (from this frame):
  - "Back: Back to shipper 361640010000000276" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Scan field (clear the error)" → [Build a pallet · Scanned](https://doop.design/c/LQFIZlhE35?frame=pzbEX96qkr)
  - "Dismiss 361640010000000306" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000191" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000412" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000429" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000276" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000283" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000290" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000306" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000313" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000320" → no navigation (action stays on this page: download, print or row control)
  - "Cancel" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Create pallet SSCC" → [Build a pallet · Create pallet SSCC](https://doop.design/c/LQFIZlhE35?frame=Df97I34rKN) (opens as modal)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Build a pallet · Create pallet SSCC
- Frame: https://doop.design/c/LQFIZlhE35?frame=Df97I34rKN
- Route: `/manufacturer/pallets/new · Create pallet SSCC (modal)`
- Back: Modal over Build a pallet. Cancel and Close return to it.
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Create pallet SSCC" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Pallet SSCC · Created
- Frame: https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8
- Route: `/manufacturer/pallets/:id?return_to=…`
- Back: return_to, default /manufacturer/aggregation ("Back to Aggregation")
- Note: Pallet detail. Next step is Ship this pallet.
- Buttons and links (from this frame):
  - "Ship this pallet" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Back: Back to Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
  - "Print label" → [Pallet label](https://doop.design/c/LQFIZlhE35?frame=Wamzg3_MVh) (opens as modal)
  - "Hover shipper SSCC (peek)" → [Pallet SSCC · SSCC peek](https://doop.design/c/LQFIZlhE35?frame=Ey4b5ZGx9X)
  - "Shipper row" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Pallet label
- Frame: https://doop.design/c/LQFIZlhE35?frame=Wamzg3_MVh
- Route: `/manufacturer/pallets/:id · Pallet label (modal)`
- Back: Modal over the pallet. Cancel and Close return to it.
- Note: Same label design as the shipper label.
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Print 2 labels" → closes the modal (back to the page underneath)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Build a pallet · Scan errors · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=UD5E8zd0_X
- Route: `/manufacturer/pallets/new (scan errors)`
- Back: return_to, default /manufacturer/aggregation ("Back to shipper 361640010000000276" when opened from the shipper)
- Note: Errors: duplicate, already on a shipment, wrong state (empty), different destination.
- Buttons and links (from this frame):
  - "Back: Back to shipper 361640010000000276" → [Shipper SSCC · Created · dark](https://doop.design/c/LQFIZlhE35?frame=rnN1USyC0E)
  - "Scan field (clear the error)" → [Build a pallet · Scanned](https://doop.design/c/LQFIZlhE35?frame=pzbEX96qkr)
  - "Dismiss 361640010000000306" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000191" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000412" → no navigation (action stays on this page: download, print or row control)
  - "Dismiss 361640010000000429" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000276" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000283" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000290" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000306" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000313" → no navigation (action stays on this page: download, print or row control)
  - "Remove 361640010000000320" → no navigation (action stays on this page: download, print or row control)
  - "Cancel" → [Shipper SSCC · Created · dark](https://doop.design/c/LQFIZlhE35?frame=rnN1USyC0E)
  - "Create pallet SSCC" → [Build a pallet · Create pallet SSCC](https://doop.design/c/LQFIZlhE35?frame=Df97I34rKN) (opens as modal)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Pallet SSCC · Created · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=BVwbmqz3Re
- Route: `/manufacturer/pallets/:id?return_to=…`
- Back: return_to, default /manufacturer/aggregation ("Back to Aggregation")
- Note: Pallet detail. Next step is Ship this pallet.
- Buttons and links (from this frame):
  - "Ship this pallet" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Back: Back to Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
  - "Print label" → [Pallet label](https://doop.design/c/LQFIZlhE35?frame=Wamzg3_MVh) (opens as modal)
  - "Hover shipper SSCC (peek)" → [Pallet SSCC · SSCC peek](https://doop.design/c/LQFIZlhE35?frame=Ey4b5ZGx9X)
  - "Shipper row" → [Shipper SSCC · Created · dark](https://doop.design/c/LQFIZlhE35?frame=rnN1USyC0E)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
## Batch 3 · Step 6 (Ship this pallet) and hover peeks

Flow: Pallet SSCC detail "Ship this pallet" → New shipment prefilled from the pallet (route, order, carrier, contents) → "Review shipment" → Shipment ready to dispatch → "Dispatch shipment" (confirm modal) → Shipment dispatched (toast, activity in EAT). Shipments is one list for web and mobile packing, with a "Packed by" column (orb + channel + person) and state tabs. Sidebar "Shipments" in every flagship frame opens this list.

Peeks: hovering a peekable ID (dashed underline) opens the TD Peek state frame. In the prototype, hover on the first GTIN on Products, batch AMX-2409-11 on Product detail, the first shipper SSCC on Pallet detail and order PO-24109 on Shipments. Click away returns to the page; the action opens the record. TD Peek is component cuo1ccz0cc (rev 2, adds a `mono` prop), rows are TD PeekRow c4lmgrekxw.

### Step 6 · Ship this pallet
#### New shipment · From pallet
- Frame: https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr
- Route: `/manufacturer/shipments/new?pallet=361640010000000405&return_to=/manufacturer/pallets/:id`
- Back: return_to, default /manufacturer/pallets/:id ("Back to pallet 361640010000000405")
- Note: Prefilled from the pallet. Creates a draft shipment linked to the pallet.
- Buttons and links (from this frame):
  - "Back: Back to pallet 361640010000000405" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Add pallet" → no navigation (action stays on this page: download, print or row control)
  - "Cancel" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Review shipment" → [Shipment · Ready to dispatch](https://doop.design/c/LQFIZlhE35?frame=6aSnzLJdDd)
  - "Crumb: Shipments" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
#### Shipment · Ready to dispatch
- Frame: https://doop.design/c/LQFIZlhE35?frame=6aSnzLJdDd
- Route: `/manufacturer/shipments/:id?return_to=…`
- Back: return_to, default /manufacturer/shipments ("Back to Shipments")
- Note: Draft shipment, ready to dispatch. One shipment model: the same record the distributor receives.
- Buttons and links (from this frame):
  - "Dispatch shipment" → [Shipment · Dispatch confirm](https://doop.design/c/LQFIZlhE35?frame=SD0KAkE0eF) (opens as modal)
  - "Back: Back to Shipments" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
  - "Packing list" → [Packing list](https://doop.design/c/LQFIZlhE35?frame=_5mVCvDB4-)
  - "Pallet row" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Crumb: Shipments" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
#### Shipment · Dispatch confirm
- Frame: https://doop.design/c/LQFIZlhE35?frame=SD0KAkE0eF
- Route: `/manufacturer/shipments/:id · Dispatch (modal)`
- Back: Modal over the shipment. Cancel and Close return to it.
- Buttons and links (from this frame):
  - "Cancel" → closes the modal (back to the page underneath)
  - "Dispatch shipment" → [Shipment · Dispatched](https://doop.design/c/LQFIZlhE35?frame=ePNim8DFMt)
  - "Close (x)" → closes the modal (back to the page underneath)
#### Shipment · Dispatched
- Frame: https://doop.design/c/LQFIZlhE35?frame=ePNim8DFMt
- Route: `/manufacturer/shipments/:id (dispatched)`
- Back: return_to, default /manufacturer/shipments ("Back to Shipments")
- Buttons and links (from this frame):
  - "Packing list" → [Packing list](https://doop.design/c/LQFIZlhE35?frame=_5mVCvDB4-)
  - "Back: Back to Shipments" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
  - "Pallet row" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Crumb: Shipments" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
#### Shipments
- Frame: https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL
- Route: `/manufacturer/shipments`
- Back: None (sidebar page)
- Note: One list for web and mobile shipments (today manufacturer_shipments never show here).
- Buttons and links (from this frame):
  - "New shipment" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Row: SHP-2611-0042" → [Shipment · Dispatched](https://doop.design/c/LQFIZlhE35?frame=ePNim8DFMt)
  - "Hover order (peek)" → [Shipments · Order peek](https://doop.design/c/LQFIZlhE35?frame=Ilhehcbovo)
  - "Row: SHP-2611-0041" → [Shipment · Ready to dispatch](https://doop.design/c/LQFIZlhE35?frame=6aSnzLJdDd)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
#### Shipment · Ready to dispatch · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=BRrAdoRX_x
- Route: `/manufacturer/shipments/:id?return_to=…`
- Back: return_to, default /manufacturer/shipments ("Back to Shipments")
- Note: Draft shipment, ready to dispatch. One shipment model: the same record the distributor receives.
- Buttons and links (from this frame):
  - "Dispatch shipment" → [Shipment · Dispatch confirm](https://doop.design/c/LQFIZlhE35?frame=SD0KAkE0eF) (opens as modal)
  - "Back: Back to Shipments" → [Shipments · dark](https://doop.design/c/LQFIZlhE35?frame=R13LmBT3qN)
  - "Packing list" → [Packing list](https://doop.design/c/LQFIZlhE35?frame=_5mVCvDB4-)
  - "Pallet row" → [Pallet SSCC · Created · dark](https://doop.design/c/LQFIZlhE35?frame=BVwbmqz3Re)
  - "Crumb: Shipments" → [Shipments · dark](https://doop.design/c/LQFIZlhE35?frame=R13LmBT3qN)
#### Shipments · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=R13LmBT3qN
- Route: `/manufacturer/shipments`
- Back: None (sidebar page)
- Note: One list for web and mobile shipments (today manufacturer_shipments never show here).
- Buttons and links (from this frame):
  - "New shipment" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Row: SHP-2611-0042" → [Shipment · Dispatched](https://doop.design/c/LQFIZlhE35?frame=ePNim8DFMt)
  - "Hover order (peek)" → [Shipments · Order peek](https://doop.design/c/LQFIZlhE35?frame=Ilhehcbovo)
  - "Row: SHP-2611-0041" → [Shipment · Ready to dispatch · dark](https://doop.design/c/LQFIZlhE35?frame=BRrAdoRX_x)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
### Peeks
#### Products · GTIN peek
- Frame: https://doop.design/c/LQFIZlhE35?frame=vvYOSDxcqf
- Route: `/manufacturer/products · GTIN peek`
- Back: None (sidebar page)
- Note: Hover state. Shows after 300ms on hover or keyboard focus; Esc or moving away closes it; clicking the ID opens the record.
- Buttons and links (from this frame):
  - "Open product" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Add product" → [Add product (modal)](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) (opens as modal)
  - "Sync from GS1" → [Products · Syncing from GS1](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Row: Amoxicillin 500mg capsules" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Click away (close peek)" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Product detail · Batch peek
- Frame: https://doop.design/c/LQFIZlhE35?frame=1G5npcrtDv
- Route: `/manufacturer/products/:id · batch peek`
- Back: return_to, default /manufacturer/products ("Back to Products")
- Note: Hover state. Shows after 300ms on hover or keyboard focus; Esc or moving away closes it; clicking the ID opens the record.
- Buttons and links (from this frame):
  - "Open batch" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Generate serials" → [Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) (opens as modal)
  - "Back: Back to Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
  - "View serials" → [Batches · Batch with shippers](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT)
  - "Export CSV" → no navigation (action stays on this page: download, print or row control)
  - "Click away (close peek)" → [Product detail](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26)
  - "Crumb: Products" → [Products](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b)
#### Pallet SSCC · SSCC peek
- Frame: https://doop.design/c/LQFIZlhE35?frame=Ey4b5ZGx9X
- Route: `/manufacturer/pallets/:id · SSCC peek`
- Back: return_to, default /manufacturer/aggregation ("Back to Aggregation")
- Note: Hover state. Shows after 300ms on hover or keyboard focus; Esc or moving away closes it; clicking the ID opens the record.
- Buttons and links (from this frame):
  - "Open shipper" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Ship this pallet" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Back: Back to Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
  - "Print label" → [Pallet label](https://doop.design/c/LQFIZlhE35?frame=Wamzg3_MVh) (opens as modal)
  - "Shipper row" → [Shipper SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=97tWE2wGEU)
  - "Click away (close peek)" → [Pallet SSCC · Created](https://doop.design/c/LQFIZlhE35?frame=kJVstU1vN8)
  - "Crumb: Aggregation" → [Aggregation (AGG-1)](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w)
#### Shipments · Order peek
- Frame: https://doop.design/c/LQFIZlhE35?frame=Ilhehcbovo
- Route: `/manufacturer/shipments · order peek`
- Back: None (sidebar page)
- Note: Hover state. Shows after 300ms on hover or keyboard focus; Esc or moving away closes it; clicking the ID opens the record.
- Buttons and links (from this frame):
  - "Open shipment" → [Shipment · Ready to dispatch](https://doop.design/c/LQFIZlhE35?frame=6aSnzLJdDd)
  - "New shipment" → [New shipment · From pallet](https://doop.design/c/LQFIZlhE35?frame=NSxDs_eqdr)
  - "Row: SHP-2611-0042" → [Shipment · Dispatched](https://doop.design/c/LQFIZlhE35?frame=ePNim8DFMt)
  - "Row: SHP-2611-0041" → [Shipment · Ready to dispatch](https://doop.design/c/LQFIZlhE35?frame=6aSnzLJdDd)
  - "Previous" → disabled in this state
  - "Next" → no navigation (action stays on this page: download, print or row control)
  - "Click away (close peek)" → [Shipments](https://doop.design/c/LQFIZlhE35?frame=RRJbfBqPlL)
#### TD Peek · Component
- Frame: https://doop.design/c/LQFIZlhE35?frame=lUbiG4NO-X
- Route: `Component spec (no route)`
- Back: None
- Note: TD Peek cuo1ccz0cc with TD PeekRow c4lmgrekxw. One component for GTIN, batch, SSCC and order peeks.
- Buttons and links (from this frame):
### State frames not on the happy path
These are reached from the canvas, not by a click in the main flow: Products · Sync failed (jEHjO102Ab), Products · Empty (AywKWZYjJ5), Generate serials · GS1 unavailable (w0jvpBd9vY), Batches · Waiting for GS1 (Zl3Kuvvy9I), Batches · GS1 error (lbP-59bxKH), Batches · No serials yet (s-Y7-4zrCb), View serials · No matches (N47kkIH5F7), View serials · GS1 error (RWCTScqFsc), Pack shipper · 3 GS1 error (ETttYSzslq), Product SSCCs · Empty (xMKTsiTgSt). Each one wires its own recovery (Retry, Try again, Clear search, Generate serials, Pack a shipper).

## HOLD

1. Aggregation review `/manufacturer/aggregation/:id` and the AGG-1 frames (nooman_e0w, rDvQtkfRwC, 6s_cVMiQkS, lHqj6ZUNd9) are untouched. I did not add a "Build a pallet" entry to the AGG-1 list nooman_e0w (that is a canon frame on another page). Recommend adding a secondary "Build a pallet" there once Sean signs off.
2. Unrouted code: the old SerialWizard modal path and SsccShow are unrouted in code; the flagship assumes the new `serials/pack` live_action and `/manufacturer/sscc/:id/serials` with return_to. Confirm the routes with Krak before build.
3. Product SSCCs page C22opce6ED still carries the old "Print SSCC labels" and "Case label" buttons. The flagship replaces both with the single Shipper label modal (NlxXvWnCVy). Only the empty-state copy was redesigned here (xMKTsiTgSt); the full page needs a pass.
4. "Add product" on Products opens the existing Add product modal (yWiBLt5W4_). Krak's map says code has no Add product. Keep or drop is Sean's call; products otherwise come only from the GS1 sync.
5. TD DatePicker (chdlkoodd2) only takes a `month` prop and draws a fixed range (9 to 18). The expiry picker frame (JL8VPDk7sr) therefore shows that range, not 22 Nov 2028. Needs a single-date `selected` prop on the shared component (used in 11 frames), which I did not change.
6. Dark mode covers 11 key frames. Peeks and the remaining modals are light only; hovering in a dark frame lands on the light peek.
7. Superseded: kyQHKTVNuw and pu69ruhFa_ renamed "Superseded · …" (not deleted).
8. Batches · Batch with shippers (aDfQMYP8sT) uses Amoxicillin; its "Generate serials" opens the Ceftriaxone wizard frames (sample-data shortcut).

## Backend needs

1. Products sync: run the GS1 sync in an Oban ProductSyncWorker, store `last_synced_at` and sync status per org, and stop calling the GS1 count on every handle_params. Products shows "Synced from GS1 · <time> EAT", "Syncing" and "Last sync failed".
2. Row actions: Products needs a per-product serial count to pick "Generate serials" (0 serials) or "View serials".
3. Landing after Generate serials: keep `?batch=` selected and poll until GS1 lists the batch (Waiting for GS1 state). Never fall back to the first batch. Both modes land on Batches, no inventory hop.
4. Bulk label print: Print labels for a batch (all, unpacked only, selected), one GS1 DataMatrix label per serial, as one job instead of one click per label.
5. Packing: new route or live_action `/manufacturer/products/:gtin/serials/pack?batch=` (Select serials, Parties, Review). `pack_serials_into_shipper` keeps creating the SSCC, packed_serials and the EPCIS Pack event, but must stop calling `record_dispatch_shipment!`. Packing never creates a shipment.
6. Make to order: also stop auto-creating the PAL pallet, shippers and approved shipment with EPCIS Ship. It should issue serials and shipper SSCCs, then hand off to Build a pallet and Ship this pallet.
7. Serial state filter: View serials needs packed and unpacked from packed_serials, plus search by serial and a shipper filter.
8. Labels: one full-size 100 × 150 mm logistics label (From, To, SSCC as GS1-128, content GTIN, count, batch, expiry, order) for shippers and pallets, with "This shipper / All shippers in batch" and copies. Replaces Print SSCC labels and Case label.
9. Pallets: real GS1 pallet SSCC (not a local PAL- code), an EPCIS aggregation event linking the shipper SSCCs, and a pallet label.
10. Scan-validate endpoint for Build a pallet: returns ready, duplicate (already on this pallet), on shipment (with order), empty shipper (no packed serials) and different destination.
11. One shipment model: merge manufacturer_shipments and distributor_shipments, or read both, so /manufacturer/shipments shows web and mobile shipments in one list with a Packed by field (channel and user). Add a pallet → shipment link. Mobile-packed shipments should not need the web packing step.
12. Shipment lifecycle: Draft → Ready to dispatch → Dispatched → Received. Dispatch records EPCIS Ship. Decide where today's Approve side effects (issue SSCCs, billing charge, EPCIS approval) move to; with SSCCs issued at pack time, Approve should not issue them again.
13. return_to on every manufacturer detail page (product, batch, view serials, shipper, pallet, shipment), with the defaults listed per frame above. 5 detail pages have no back link today.
14. Hover peeks: a `td_peek` function component plus a JS hook (300ms open, 150ms close, focus opens, Esc closes, Enter opens the record) and a small peek endpoint per kind (GTIN, batch, SSCC, order) returning up to 5 rows.
15. Copy fix in code: the SSCC empty state should say "Shipper SSCCs are created when you pack serials into a shipper."


## Polish pass (23 Nov 2026)

Done on the Flagship · Manufacturer page, the two canon manufacturer frames, and the Organization and platform flows page. Every frame was pushed one at a time. No comments were made, no frames were deleted, and nothing was written to a repo. The code was read at `6c38d46`.

### 1. Presend and Kargul checklist fixes (all 58 earlier flagship frames re-pushed)
- Removed the blur-in animation and the hover gradient from the shared HEAD. Screens now fade in on opacity only, and hover is a flat `--color-td-hover` fill.
- Type: removed the 10px and 11px sizes (label sheet keys, slab captions and inline GLN text are now 12px). Bold text is capped at weight 500. The pallet spec title went from 24px/500 to 16px/600.
- Accent is used only on primary, focus, selected and active. The "next step" tile and the progress bars no longer use the accent (they use the control fill and `--color-td-chart`), and the timeline dots use ink-3.
- Pallet spec (`lUbiG4NO-X`) is now 1440x1004, so the frame ends where its content ends.
- No em dashes. Times are in EAT. Orbs are used for every person. GS1 codes are mono and everything else is Inter.

### 2. TD DatePicker single-date mode
- `TD DatePicker` (`chdlkoodd2`) gained a `mode` prop: `range` (the default) or `single`. The 11 range uses are unchanged; for example, `4C-4iO5AGv` still renders its range.
- Expiry date (https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) uses `mode="single"` on November 2028 with 22 Nov selected. The same picker is used on the dark and Amoxicillin copies (https://doop.design/c/LQFIZlhE35?frame=L-Fk8ZKPVO, https://doop.design/c/LQFIZlhE35?frame=ciDd5NCC4u, https://doop.design/c/LQFIZlhE35?frame=o2UVJ_yoY1).

### 3. Dark peeks and dark modals, wired dark to dark
New dark frames (row at y 9900):
- Product detail · dark: https://doop.design/c/LQFIZlhE35?frame=-ybXtapG4g
- Products · GTIN peek · dark: https://doop.design/c/LQFIZlhE35?frame=xwALh_njBk
- Product detail · Batch peek · dark: https://doop.design/c/LQFIZlhE35?frame=pO63sh4icJ
- Pallet SSCC · SSCC peek · dark: https://doop.design/c/LQFIZlhE35?frame=A8IVUhBhYe
- Shipments · Order peek · dark: https://doop.design/c/LQFIZlhE35?frame=czHAVIEm4E
- Generate serials · Mode · dark: https://doop.design/c/LQFIZlhE35?frame=z7nIksc2AY
- Generate serials · Expiry date picker · dark: https://doop.design/c/LQFIZlhE35?frame=L-Fk8ZKPVO
- Generate serials · Batch (order) · dark: https://doop.design/c/LQFIZlhE35?frame=MJClXUZIR7
- Generate serials · From and To · dark: https://doop.design/c/LQFIZlhE35?frame=tdOija7TZR
- Generate serials · Generating · dark: https://doop.design/c/LQFIZlhE35?frame=mihhSmuvyw
- Generate serials · GS1 unavailable · dark: https://doop.design/c/LQFIZlhE35?frame=j97R8GACYt
- Print labels · dark: https://doop.design/c/LQFIZlhE35?frame=UTcGwar31W
- Build a pallet · Create pallet SSCC · dark: https://doop.design/c/LQFIZlhE35?frame=kUB_dU3G2U
- Pallet label · dark: https://doop.design/c/LQFIZlhE35?frame=m3loGYfH_N
- Shipment · Dispatch confirm · dark: https://doop.design/c/LQFIZlhE35?frame=c1MSinFoet

Every dark frame links to the dark version of its target wherever one exists. These targets have no dark version yet, so their links still open light frames:
- Product sync (`p_sync`), from Products dark and the GTIN peek dark.
- Batch selected (`b_sel`), from Product detail dark, Products dark, the GTIN peek dark, the batch peek dark, and Amoxicillin new batch dark.
- Packed serials (`v_packed`), from All serials dark.
- Aggregation scan and parties (`a_scan`, `a_parties`), from Aggregation selected dark.
- Build a pallet scan, step 0 and step 1 (`l_scan0`, `l_scan1`), and Serials done (`v_done`), from Aggregation done dark and Pallet scan step 2 dark.
- New shipment and Shipment done (`s_new`, `s_done`), from the pallet and shipment dark frames and peeks.
- Shared chrome (search, command menu, notifications, the account menu, and org sidebar pages other than Dashboard, Team and API keys).

### 4. Batch selected (Amoxicillin) "Generate serials"
- On Batch selected (https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT), "Generate serials" now opens the Amoxicillin wizard. Product detail's primary button and the batch peek also go there.
- New Amoxicillin chain, light: [Amoxicillin · Generate serials · Mode](https://doop.design/c/LQFIZlhE35?frame=QQY6hz9PIA), [Amoxicillin · Generate serials · Batch (stock)](https://doop.design/c/LQFIZlhE35?frame=ylLmXTPQ4v), [Amoxicillin · Generate serials · Expiry date picker](https://doop.design/c/LQFIZlhE35?frame=ciDd5NCC4u), [Amoxicillin · Generate serials · Batch (order)](https://doop.design/c/LQFIZlhE35?frame=cgRj15Wm7y), [Amoxicillin · Generate serials · From and To](https://doop.design/c/LQFIZlhE35?frame=SDhpsVlCCr), [Amoxicillin · Generate serials · Generating](https://doop.design/c/LQFIZlhE35?frame=CNMDksCdCQ), [Amoxicillin · Print labels](https://doop.design/c/LQFIZlhE35?frame=25-pkCuMIC), [Amoxicillin · Batches · New batch selected](https://doop.design/c/LQFIZlhE35?frame=6TJ0eQ-dyu), [Amoxicillin · View serials · All unpacked](https://doop.design/c/LQFIZlhE35?frame=cRLvBQo596).
- New Amoxicillin chain, dark: [Amoxicillin · Generate serials · Mode · dark](https://doop.design/c/LQFIZlhE35?frame=TRRYz9R2f9), [Amoxicillin · Generate serials · Batch (stock) · dark](https://doop.design/c/LQFIZlhE35?frame=D7gBPUlxEd), [Amoxicillin · Generate serials · Expiry date picker · dark](https://doop.design/c/LQFIZlhE35?frame=o2UVJ_yoY1), [Amoxicillin · Generate serials · Batch (order) · dark](https://doop.design/c/LQFIZlhE35?frame=CNKb_0F67w), [Amoxicillin · Generate serials · From and To · dark](https://doop.design/c/LQFIZlhE35?frame=yDkbun3bI-), [Amoxicillin · Generate serials · Generating · dark](https://doop.design/c/LQFIZlhE35?frame=6nKgHHWY81), [Amoxicillin · Print labels · dark](https://doop.design/c/LQFIZlhE35?frame=06HUeP8Y4B), [Amoxicillin · Batches · New batch selected · dark](https://doop.design/c/LQFIZlhE35?frame=BcK7rSvsGo), [Amoxicillin · View serials · All unpacked · dark](https://doop.design/c/LQFIZlhE35?frame=B7Ovz8_aID).
- In this chain, the copy reads Amoxicillin 500mg capsules, GTIN 06289001001234, batch AMX-2411-04. The batch rail shows the new batch above the 5 AMX batches ("6 batches").
- The packing frames reached after the chain (Aggregation selected onward) are still the Ceftriaxone frames. There is no Amoxicillin packing set yet.

### 5. Canon Product SSCCs and SSCC serials in the flagship language
- https://doop.design/c/LQFIZlhE35?frame=C22opce6ED Product SSCCs, `/manufacturer/products/:gtin/sscc?batch=CFX-2411-01`. The flagship shell is used: "Back to batch CFX-2411-01", Export CSV, Batch and Pallet chips, 10 shippers (6 on pallet 361640010000000405, 4 packed). Each row has a single "Print label" button that opens the shipper label (`NlxXvWnCVy`). "Print SSCC labels" and "Case label" are removed. The primary "Build a pallet" opens the pallet scan (`InMakqK959`).
- https://doop.design/c/LQFIZlhE35?frame=TcfVwKaNOZ SSCC serials, `/manufacturer/sscc/:id/serials`. It has "Back to shipper SSCCs", the On pallet badge, the key values, 8 of 50 serials with a pager, a mini label card, and an On pallet card with "Open pallet". The primary is "Print label".

### 6. Aggregation "Build a pallet" entry
- https://doop.design/c/LQFIZlhE35?frame=nooman_e0w (and its sibling https://doop.design/c/LQFIZlhE35?frame=9eVZhuE_oo) has a secondary "Build a pallet" button (stack icon) before "Add SSCC". It goes to https://doop.design/c/LQFIZlhE35?frame=InMakqK959. The sibling's button also goes to the light pallet scan.

### 7. Org mobile users and the EPCIS submission mode (Organization and platform flows page)
The copy matches `OrgMobileUserLive.Index` and the EPCIS section of `organization_settings_live.ex` at `6c38d46`.
- The sidebar gains "Mobile users" (device-mobile icon) after Team, matching `org_management_groups`.
- The list has these columns: Name with @username, Email, Role (info badge: Distribution or Manufacturing), Access (Full app or Aggregation only), Status, and row actions (Edit, Resend PIN, Deactivate; inactive rows show Activate).
- The flashes and confirm copy are the strings from the code.
- EPCIS: the "EPCIS event reporting" card uses the TD Segment pair Automatic / Manual approval. The subtitle changes with the mode, and switching to manual shows the flash "EPCIS events will now wait as pending until you approve and send them."

#### Org · Mobile users
- Frame: https://doop.design/c/LQFIZlhE35?frame=MYznkJ8Htz
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive](https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · added
- Frame: https://doop.design/c/LQFIZlhE35?frame=S2XB20qIZb
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Daniel Kariuki" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Daniel Kariuki" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive](https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · PIN resent
- Frame: https://doop.design/c/LQFIZlhE35?frame=R1RVbSb0JY
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive](https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · deactivated
- Frame: https://doop.design/c/LQFIZlhE35?frame=55aq0S_F28
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · inactive](https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive](https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · reactivated
- Frame: https://doop.design/c/LQFIZlhE35?frame=N6OYcokOeq
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions](https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · none yet
- Frame: https://doop.design/c/LQFIZlhE35?frame=gVFe2vRX1l
- Route: `/org/mobile-users`
- Buttons and links:
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Mobile users · Connect GS1 first
- Frame: https://doop.design/c/LQFIZlhE35?frame=4ULYRjmjfl
- Route: `/org/mobile-users`
- Buttons and links:
  - "Org settings" → [Org · Organization settings · EPCIS automatic](https://doop.design/c/LQFIZlhE35?frame=GjhsDici0w)

#### Org · Mobile users · GS1 unavailable
- Frame: https://doop.design/c/LQFIZlhE35?frame=x4U31ivg9V
- Route: `/org/mobile-users`
- Buttons and links:
  - "Add mobile user" → [Org · Add a mobile user](https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO) (opens as overlay)

#### Org · Add a mobile user
- Frame: https://doop.design/c/LQFIZlhE35?frame=QYpw0yuTrO
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Save and email PIN" → [Org · Mobile users · added](https://doop.design/c/LQFIZlhE35?frame=S2XB20qIZb)
  - "Close (x)" → closes the modal

#### Org · Edit mobile user
- Frame: https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Save" → [Org · Mobile users](https://doop.design/c/LQFIZlhE35?frame=MYznkJ8Htz)
  - "Close (x)" → closes the modal

#### Org · Resend PIN
- Frame: https://doop.design/c/LQFIZlhE35?frame=wpIwW0Fk5g
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Resend PIN" → [Org · Mobile users · PIN resent](https://doop.design/c/LQFIZlhE35?frame=R1RVbSb0JY)
  - "Close (x)" → closes the modal

#### Org · Deactivate mobile user
- Frame: https://doop.design/c/LQFIZlhE35?frame=d04lKBEC4g
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Deactivate" → [Org · Mobile users · deactivated](https://doop.design/c/LQFIZlhE35?frame=55aq0S_F28)
  - "Close (x)" → closes the modal

#### Org · Mobile user row actions
- Frame: https://doop.design/c/LQFIZlhE35?frame=O57YjmT7r9
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Menu: Edit" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Menu: Resend PIN" → [Org · Resend PIN](https://doop.design/c/LQFIZlhE35?frame=wpIwW0Fk5g) (opens as overlay)
  - "Menu: Deactivate" → [Org · Deactivate mobile user](https://doop.design/c/LQFIZlhE35?frame=d04lKBEC4g) (opens as overlay)

#### Org · Mobile user row actions · inactive
- Frame: https://doop.design/c/LQFIZlhE35?frame=Y54CDe0MG-
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Menu: Edit" → [Org · Edit mobile user](https://doop.design/c/LQFIZlhE35?frame=Qe-s68LnKS) (opens as overlay)
  - "Menu: Resend PIN" → [Org · Resend PIN](https://doop.design/c/LQFIZlhE35?frame=wpIwW0Fk5g) (opens as overlay)
  - "Menu: Activate" → [Org · Mobile users · reactivated](https://doop.design/c/LQFIZlhE35?frame=N6OYcokOeq)

#### Org · Mobile users · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=U2u5djuS4_
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive · dark](https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9) (opens as overlay)

#### Org · Mobile users · added · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=mw5JcgGHGo
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Daniel Kariuki" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Daniel Kariuki" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive · dark](https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9) (opens as overlay)

#### Org · Mobile users · PIN resent · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=tdXyAJ2qHi
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive · dark](https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9) (opens as overlay)

#### Org · Mobile users · deactivated · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=7akMMj2Qfp
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · inactive · dark](https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · inactive · dark](https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9) (opens as overlay)

#### Org · Mobile users · reactivated · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=QoKJIngixY
- Route: `/org/mobile-users`
- Buttons and links:
  - "Row actions: Peter Mwangi" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Peter Mwangi" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Grace Achieng" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Grace Achieng" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Brian Kiprono" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Brian Kiprono" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Row actions: Mercy Wanjiku" → [Org · Mobile user row actions · dark](https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV) (opens as overlay)
  - "Row: Mercy Wanjiku" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Add mobile user" → [Org · Add a mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9) (opens as overlay)

#### Org · Add a mobile user · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=akyIVieeL9
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Save and email PIN" → [Org · Mobile users · added · dark](https://doop.design/c/LQFIZlhE35?frame=mw5JcgGHGo)
  - "Close (x)" → closes the modal

#### Org · Edit mobile user · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Save" → [Org · Mobile users · dark](https://doop.design/c/LQFIZlhE35?frame=U2u5djuS4_)
  - "Close (x)" → closes the modal

#### Org · Resend PIN · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=UZ20wvqLSp
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Resend PIN" → [Org · Mobile users · PIN resent · dark](https://doop.design/c/LQFIZlhE35?frame=tdXyAJ2qHi)
  - "Close (x)" → closes the modal

#### Org · Deactivate mobile user · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=g2ljDnPaT0
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Cancel" → closes the modal
  - "Deactivate" → [Org · Mobile users · deactivated · dark](https://doop.design/c/LQFIZlhE35?frame=7akMMj2Qfp)
  - "Close (x)" → closes the modal

#### Org · Mobile user row actions · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=iVquKjl7NV
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Menu: Edit" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Menu: Resend PIN" → [Org · Resend PIN · dark](https://doop.design/c/LQFIZlhE35?frame=UZ20wvqLSp) (opens as overlay)
  - "Menu: Deactivate" → [Org · Deactivate mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=g2ljDnPaT0) (opens as overlay)

#### Org · Mobile user row actions · inactive · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=36SGZqZ54u
- Opens over `/org/mobile-users`
- Buttons and links:
  - "Menu: Edit" → [Org · Edit mobile user · dark](https://doop.design/c/LQFIZlhE35?frame=xfWF6AGMHM) (opens as overlay)
  - "Menu: Resend PIN" → [Org · Resend PIN · dark](https://doop.design/c/LQFIZlhE35?frame=UZ20wvqLSp) (opens as overlay)
  - "Menu: Activate" → [Org · Mobile users · reactivated · dark](https://doop.design/c/LQFIZlhE35?frame=QoKJIngixY)

#### Org · Organization settings · EPCIS automatic
- Frame: https://doop.design/c/LQFIZlhE35?frame=GjhsDici0w
- Route: `/org/settings`
- Buttons and links:
  - "Segment: Manual approval" → [Org · Organization settings · EPCIS manual](https://doop.design/c/LQFIZlhE35?frame=3XFJf9bEa3)

#### Org · Organization settings · EPCIS manual
- Frame: https://doop.design/c/LQFIZlhE35?frame=3XFJf9bEa3
- Route: `/org/settings`
- Buttons and links:
  - "Segment: Automatic" → [Org · Organization settings · EPCIS automatic](https://doop.design/c/LQFIZlhE35?frame=GjhsDici0w)

#### Org · Organization settings · EPCIS automatic · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=zm5b6_BWvJ
- Route: `/org/settings`
- Buttons and links:
  - "Segment: Manual approval" → [Org · Organization settings · EPCIS manual · dark](https://doop.design/c/LQFIZlhE35?frame=BvB-Jru3Gp)

#### Org · Organization settings · EPCIS manual · dark
- Frame: https://doop.design/c/LQFIZlhE35?frame=BvB-Jru3Gp
- Route: `/org/settings`
- Buttons and links:
  - "Segment: Automatic" → [Org · Organization settings · EPCIS automatic · dark](https://doop.design/c/LQFIZlhE35?frame=zm5b6_BWvJ)

### Code gaps and notes (for Krak)
- The GS1 load error in code is a plain note, so the "GS1 unavailable" frame shows a danger banner with the code string.
- The resend PIN confirm in code is a browser `data-confirm`. Here it is drawn as a TD Modal with the same strings.
- The canon org sidebar frames (Dashboard, Team, Settings and the rest) lack "Mobile users" and "API keys". Code has both. Only the new frames add Mobile users.
- The org settings frames do not include the "GS1 company prefixes" card that exists in code. The canon settings frame never had it, so the EPCIS card sits under GS1 identifiers.
- In the dark settings frames, "Save changes" still goes to the light saved state (`wvo1WwnBJ0`).
- The TD Segmented wrapper did not render a second inline segment, so the EPCIS control wraps two TD Segment instances in a plain group with the Segmented styling, the same approach the TNT reporting frames use.

## Gap pass (23 Nov 2026)

Counts: 63 new frames (49 flagship manufacturer, 5 dark menus, 9 org settings), 112 rebuilt (93 flagship manufacturer, 6 org settings, 13 org mobile users), 129 older frames swept (52 org, 74 distributor, 3 manufacturer canon dark). Nothing deleted, no comments touched, no repo writes.

### 1. Dark versions of light targets
Every dark frame now links dark to dark through one light-to-dark map (`dmap.json`, 156 pairs). A local scan of all 98 dark frame sources finds no link to a light frame that has a dark twin.

- Products · Syncing from GS1 · dark: https://doop.design/c/LQFIZlhE35?frame=AcnUvsvlYe
- Batches · Batch with shippers · dark: https://doop.design/c/LQFIZlhE35?frame=qDtE84pCCX
- View serials · Packed filter · dark: https://doop.design/c/LQFIZlhE35?frame=SyHRLE9vlO
- Pack shipper · 1 Scan error · dark: https://doop.design/c/LQFIZlhE35?frame=7zYNjgg7x0
- Pack shipper · 2 Parties · dark: https://doop.design/c/LQFIZlhE35?frame=RNPXVn4lUd
- Pack shipper · 3 Review · dark: https://doop.design/c/LQFIZlhE35?frame=oRUJdplb39
- Build a pallet · Scan shippers · dark: https://doop.design/c/LQFIZlhE35?frame=mLe3MjEAT_
- Build a pallet · Scanned · dark: https://doop.design/c/LQFIZlhE35?frame=mv2v-CZCTy
- View serials · All serials packed · dark: https://doop.design/c/LQFIZlhE35?frame=kE9f7lzyd-
- New shipment · From pallet · dark: https://doop.design/c/LQFIZlhE35?frame=vnjBmXOjLq
- Shipment · Dispatched · dark: https://doop.design/c/LQFIZlhE35?frame=x8VM_uV8gS
- Org · Organization settings · saved · dark: https://doop.design/c/LQFIZlhE35?frame=Y_ZitHpcRo
- Manufacturer search menu · dark: https://doop.design/c/LQFIZlhE35?frame=f_A2vj2j0_
- Notifications · dark: https://doop.design/c/LQFIZlhE35?frame=i2gfuShtGn
- Org search · dark: https://doop.design/c/LQFIZlhE35?frame=y-M0zHx8tR
- Org search results · dark: https://doop.design/c/LQFIZlhE35?frame=gEGQmERpi6
- Org command menu · dark: https://doop.design/c/LQFIZlhE35?frame=O2AxLakyH_
- Manufacturer canon dark frames rewired to the dark menus: https://doop.design/c/LQFIZlhE35?frame=xhJU95ZpT2, https://doop.design/c/LQFIZlhE35?frame=ccaGTlWZk8, https://doop.design/c/LQFIZlhE35?frame=fbkMkuqkko

### 2. Amoxicillin packing path
From aggregation onward the Amoxicillin path stays Amoxicillin (product, GTIN, batch, serials and SSCCs), light and dark. 19 light and 19 dark frames:

- Pack shipper · 1 Select serials: light https://doop.design/c/LQFIZlhE35?frame=WmpefTeZOx · dark https://doop.design/c/LQFIZlhE35?frame=TDF0X-LVx_
- Pack shipper · 1 Scan error: light https://doop.design/c/LQFIZlhE35?frame=Imfisfaqi9 · dark https://doop.design/c/LQFIZlhE35?frame=6bhMyoP5WD
- Pack shipper · 2 Parties: light https://doop.design/c/LQFIZlhE35?frame=nphjpB1jS6 · dark https://doop.design/c/LQFIZlhE35?frame=ujatezf_1z
- Pack shipper · 3 Review: light https://doop.design/c/LQFIZlhE35?frame=1oBSeqdUMI · dark https://doop.design/c/LQFIZlhE35?frame=LawVZ9xBFn
- Pack shipper · 3 GS1 error: light https://doop.design/c/LQFIZlhE35?frame=ESAYmcDFbE · dark https://doop.design/c/LQFIZlhE35?frame=SPZ8XKbn73
- Shipper SSCC · Created: light https://doop.design/c/LQFIZlhE35?frame=9dUwgBIPzs · dark https://doop.design/c/LQFIZlhE35?frame=dKBNtDuI8f
- Shipper label: light https://doop.design/c/LQFIZlhE35?frame=utKPSAq1Gb · dark https://doop.design/c/LQFIZlhE35?frame=f1u1wRFshh
- View serials · All serials packed: light https://doop.design/c/LQFIZlhE35?frame=2NkReTbOyJ · dark https://doop.design/c/LQFIZlhE35?frame=swiQsrpY-Y
- Build a pallet · Scan shippers: light https://doop.design/c/LQFIZlhE35?frame=uVCVi4Wr9r · dark https://doop.design/c/LQFIZlhE35?frame=T9MhDHT0my
- Build a pallet · Scanned: light https://doop.design/c/LQFIZlhE35?frame=6KdHYRK91c · dark https://doop.design/c/LQFIZlhE35?frame=uz2DI1M0TE
- Build a pallet · Scan errors: light https://doop.design/c/LQFIZlhE35?frame=hIJ_LafWr4 · dark https://doop.design/c/LQFIZlhE35?frame=TPxUqmcsVO
- Build a pallet · Create pallet SSCC: light https://doop.design/c/LQFIZlhE35?frame=9UwDUzPleY · dark https://doop.design/c/LQFIZlhE35?frame=bg3FREsIij
- Pallet SSCC · Created: light https://doop.design/c/LQFIZlhE35?frame=TIr4dpXpUn · dark https://doop.design/c/LQFIZlhE35?frame=wF6cN4b-5x
- Pallet label: light https://doop.design/c/LQFIZlhE35?frame=0GD_xPMcwO · dark https://doop.design/c/LQFIZlhE35?frame=4hBcUpZ--1
- Pallet SSCC · SSCC peek: light https://doop.design/c/LQFIZlhE35?frame=0dRHmYrYgl · dark https://doop.design/c/LQFIZlhE35?frame=YRu1GeQD8m
- New shipment · From pallet: light https://doop.design/c/LQFIZlhE35?frame=j4BEV12ALl · dark https://doop.design/c/LQFIZlhE35?frame=e6ZnInu1aJ
- Shipment · Ready to dispatch: light https://doop.design/c/LQFIZlhE35?frame=2sDnNMebH0 · dark https://doop.design/c/LQFIZlhE35?frame=eyAFo5O05t
- Shipment · Dispatch confirm: light https://doop.design/c/LQFIZlhE35?frame=7YyR6XpKkd · dark https://doop.design/c/LQFIZlhE35?frame=n2C_DmJZEt
- Shipment · Dispatched: light https://doop.design/c/LQFIZlhE35?frame=vrbe8IdrpG · dark https://doop.design/c/LQFIZlhE35?frame=uiLimca3Nm

### 3. GS1 company prefixes card (org settings)
Matches the code at 6c38d46: the GS1 identifiers card keeps only "Organization GLN (optional)" and its verification line; a new "GS1 company prefixes" card sits above EPCIS. Each row shows the prefix in mono, a "Primary" badge on the primary row, and a GS1 status badge ("Verified with GS1" or "Pending verification"). Rows that are not primary get "Make primary" and "Remove". The add form is "Add a GS1 company prefix" with placeholder "e.g. 0614141" and an "Add prefix" button. Empty state copy: "No GS1 company prefixes yet." Remove asks first in a modal: "Remove this GS1 company prefix?"

- Settings (base): light https://doop.design/c/LQFIZlhE35?frame=su8eaSdNu- · dark https://doop.design/c/LQFIZlhE35?frame=zm5b6_BWvJ
- Saved: light https://doop.design/c/LQFIZlhE35?frame=wvo1WwnBJ0 · dark https://doop.design/c/LQFIZlhE35?frame=Y_ZitHpcRo
- Prefix added: light https://doop.design/c/LQFIZlhE35?frame=9fI4t13SRL · dark https://doop.design/c/LQFIZlhE35?frame=rTCn7cbO8q
- Primary changed: light https://doop.design/c/LQFIZlhE35?frame=LGcovUcRzb · dark https://doop.design/c/LQFIZlhE35?frame=RK1wtrNJGs
- Remove confirm: light https://doop.design/c/LQFIZlhE35?frame=NhRv63pG63 · dark https://doop.design/c/LQFIZlhE35?frame=Wd6VM3Fshs
- Prefix removed: light https://doop.design/c/LQFIZlhE35?frame=dDCHvlu34X · dark https://doop.design/c/LQFIZlhE35?frame=RVDN8K91XB

### 4. Sidebar sweep
Org frames now list "Mobile users" (after Team) and "API keys" (before TNT reporting). Distributor frames now use the flagship nav: Dashboard, Orders, Shipments, Receiving, Supplier returns, Customer returns, Stock, Products, Customers; Reference data: Mobile users, Sites; Account: Billing, API keys, TNT reporting, Org settings. The old single "Returns" item becomes Supplier or Customer returns, whichever the frame shows. Dark frames in the sweep were also rewired to dark targets.

- Org: 52 frames swept. Examples: [Org · Admin dashboard](https://doop.design/c/LQFIZlhE35?frame=voIG90Ocbf), [Org · Sites](https://doop.design/c/LQFIZlhE35?frame=_YkjLU_zT_), [Org · Sites · created](https://doop.design/c/LQFIZlhE35?frame=sAWzRq9qay), [Org · Site dashboard](https://doop.design/c/LQFIZlhE35?frame=wMZFC8udDO)
- Distributor: 74 frames swept. Examples: [Distributor · Dashboard](https://doop.design/c/LQFIZlhE35?frame=8OjVBGuJw2), [Distributor · Choose a serialisation plan](https://doop.design/c/LQFIZlhE35?frame=Eu3T4LB1bO), [Distributor · Shipments](https://doop.design/c/LQFIZlhE35?frame=XJBYJekyQ3), [Distributor · Shipments · nothing matches](https://doop.design/c/LQFIZlhE35?frame=4WJVAyBAlz)

### Remaining gaps
- The four "Sidebar collapsed" light frames (org and distributor) show icon-only rails and were left unchanged. Their dark twins only had links rewired.
- Product tour and Site switcher overlays have no dark versions, so they open light from dark frames.
- Canon targets with no dark version still open light from dark frames: Manufacturer Inventory, Mobile users (manufacturer and distributor `uNq45yZlSw`), Org settings, manufacturer API keys (`dNqZMZIzMf`), Packing list, Add product.
- The flagship distributor page (`_mFdqiaAeu`) was not swept, by design; its frames still lack API keys.
- The batch selected frame shows batch `AMX-2409-11`, while the packing path uses `AMX-2411-04`.
- Notifications copy still mentions a pharmacy in one item.
- Prefix verification status is shown as badges. Code shows it as coloured text.

