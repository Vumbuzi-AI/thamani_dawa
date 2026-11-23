# Thamani Dawa · Doop inventory (phase 1 of the Notion doc)

Canvas **LQFIZlhE35** (Sean's canon). Built 23 Nov 2026, 17:30 EAT, by Bau. Read-only: nothing on Doop, the repo or any comment was changed.

## 0. Sources and how to read this

- Doop: `get_canvas` and `get_prototype` read at 17:07 EAT (1,199 frames on the canvas, 12,584 prototype interactions). Web scope below: 691 frames on the six Web pages, Flagship · Manufacturer, Explore · Web auth and Old · Archive. Mobile, DS, landing and icon pages are listed by count only.
- Button labels come from frame HTML where I had it (298 of 691 frames, read from earlier `get_frame` results; 61 of those are byte-fresh against today's `updatedAt`, the rest may lag a recent copy edit). Otherwise the label is the element text from the prototype, or the CSS selector in [brackets]. Sidebar nav and shell overlays (search, ⌘K, notifications, account menu, site switcher, dashboards) are left out of each row.
- Code: arch was offline (all arch machines disconnected), so routes and LiveViews come from the box clone of `origin/sean/td-web-design-system` at **6c38d46** (Krak's merge of master, 17:11 EAT), read with `git show`/`git archive` only. Its `router.ex` is byte-identical to `origin/master`. Krak's `/workspace/thamani/notion-doc/krak-code-map.md` is the source of truth for logic; this file cross-checks it.
- Route and LiveView per frame are mapped from the frame name (same rules as `frame-ledger.md`, extended for AGG-1, APIKEYS-1 and the flagship). "Built" is Krak's ledger status (`ledger/status.json`).
- Status: **canon** (current design), **draft** (flagship, paused 17:05 by Sean), **superseded**, **archived**, **exploration**.

## 1. Counts

- Web frames inventoried: **691** (canon: 559, archived: 75, exploration: 28, draft (flagship, paused 17:05): 25, superseded: 2, superseded (dead UI per Krak §1.4): 2)
- Light / dark among canon: 510 / 49
- Journeys: 9; flows (screen groups): **313**
- LiveView routes in code: 169. Mapped to at least one frame: 155. **Routes with no frame: 14** (plus 5 master features with no frame, §5.2).
- **Frames with no route (design ahead of code): 10**
- **Broken or undefined backs: 14 routes in code** (no back, `history.back()`, or no close target) plus Krak's list (§5.3); 0 web Doop frames use history back (all 656 are on mobile pages).
- Error, empty and failure states among canon frames: 18

## 2. Pages and prototype start frames

| Page | Frames | Prototype start |
|---|---|---|
| Web · Shared | 109 | [`oYsDYjktDQ`](https://doop.design/c/LQFIZlhE35?frame=oYsDYjktDQ) Auth · Log in |
| Web · Pharmacy flows | 72 | [`q2Wvk4Umn8`](https://doop.design/c/LQFIZlhE35?frame=q2Wvk4Umn8) Pharmacy · Dashboard |
| Web · Lab flows | 90 | [`lDrhCsUsP3`](https://doop.design/c/LQFIZlhE35?frame=lDrhCsUsP3) Lab · Dashboard |
| Web · Distributor flows | 101 | [`8OjVBGuJw2`](https://doop.design/c/LQFIZlhE35?frame=8OjVBGuJw2) Distributor · Dashboard |
| Web · Manufacturer flows | 70 | [`ssU7S65tZF`](https://doop.design/c/LQFIZlhE35?frame=ssU7S65tZF) Manufacturer · Dashboard |
| Web · Organization and platform flows | 121 | [`voIG90Ocbf`](https://doop.design/c/LQFIZlhE35?frame=voIG90Ocbf) Org · Admin dashboard |
| DS · Foundations | 0 | — |
| DS · Components | 37 | — |
| DS · Shell and page nav | 7 | — |
| Mobile · Foundations and components | 2 | [`_mpP2LcSqS`](https://doop.design/c/LQFIZlhE35?frame=_mpP2LcSqS) Mobile · Prototype index |
| Mobile · Staff | 160 | [`6UdBXOklhd`](https://doop.design/c/LQFIZlhE35?frame=6UdBXOklhd) Staff · Home · Pharmacist · light |
| Mobile · Admin | 180 | [`KqneyUJxhg`](https://doop.design/c/LQFIZlhE35?frame=KqneyUJxhg) Admin · Pharmacy dashboard · light |
| Mobile · Shared | 56 | [`_F_qmCqOhY`](https://doop.design/c/LQFIZlhE35?frame=_F_qmCqOhY) Shared · Sign in · email |
| Mobile · Approach (draft) | 3 | — |
| Mobile · Sync spec | 8 | [`U6Ud1Ck2j6`](https://doop.design/c/LQFIZlhE35?frame=U6Ud1Ck2j6) Sync spec · Notes |
| Landing (Marketing) | 2 | — |
| Explore · Web auth | 28 | [`AGHtpDz6VS`](https://doop.design/c/LQFIZlhE35?frame=AGHtpDz6VS) A · Forest panel · Log in |
| Explore · Icon alternatives | 27 | — |
| Design Primitives | 4 | [`Q1uvKKBey6`](https://doop.design/c/LQFIZlhE35?frame=Q1uvKKBey6) Mobile · Foundations and components · light |
| Components | 22 | — |
| Old · Archive | 75 | — |
| Flagship · Manufacturer | 25 | — |
| Flagship · Distributor | 0 | — |

Flow starts that matter for the build: Lab stock takes start at `xK6VW836NG`; Auth at `oYsDYjktDQ` (Log in); each portal starts on its dashboard. Flagship · Manufacturer has no start frame set yet (it starts at Products `rOKtmxrk0b`). Flagship · Distributor is an empty page.

## 3. Frames by journey and flow

Columns: frame (link), screen or state, theme, status, route → LiveView, built (Krak), prototype links out (label → target). ★ marks a prototype start frame.

### 3.1 Manufacturer (87 frames, 40 flows)

**Flagship · Batches**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`4KdsxCd1Xj`](https://doop.design/c/LQFIZlhE35?frame=4KdsxCd1Xj) | Flagship · Manufacturer · Batches · New batch selected | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials?batch=` → ManufacturerProductLive.Serials (flagship landing) | — | — |
| [`aDfQMYP8sT`](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT) | Flagship · Manufacturer · Batches · Batch with shippers | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials?batch=` → ManufacturerProductLive.Serials (flagship landing) | — | — |
| [`Zl3Kuvvy9I`](https://doop.design/c/LQFIZlhE35?frame=Zl3Kuvvy9I) | Flagship · Manufacturer · Batches · Loading | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials?batch=` → ManufacturerProductLive.Serials (flagship landing) | — | — |
| [`lbP-59bxKH`](https://doop.design/c/LQFIZlhE35?frame=lbP-59bxKH) | Flagship · Manufacturer · Batches · GS1 error | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials?batch=` → ManufacturerProductLive.Serials (flagship landing) | — | — |
| [`s-Y7-4zrCb`](https://doop.design/c/LQFIZlhE35?frame=s-Y7-4zrCb) | Flagship · Manufacturer · Batches · No serials yet | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials?batch=` → ManufacturerProductLive.Serials (flagship landing) | — | — |

**Flagship · Generate serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`1j4NIqJHuF`](https://doop.design/c/LQFIZlhE35?frame=1j4NIqJHuF) | Flagship · Manufacturer · Generate serials · Mode | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`60lAgEf28c`](https://doop.design/c/LQFIZlhE35?frame=60lAgEf28c) | Flagship · Manufacturer · Generate serials · Batch (stock) | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`JL8VPDk7sr`](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr) | Flagship · Manufacturer · Generate serials · Expiry date picker | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`QTcjh85AAT`](https://doop.design/c/LQFIZlhE35?frame=QTcjh85AAT) | Flagship · Manufacturer · Generate serials · Batch (order) | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`EAR8n3VwU-`](https://doop.design/c/LQFIZlhE35?frame=EAR8n3VwU-) | Flagship · Manufacturer · Generate serials · From and To | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`z4FjhC8wTp`](https://doop.design/c/LQFIZlhE35?frame=z4FjhC8wTp) | Flagship · Manufacturer · Generate serials · Generating | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |
| [`w0jvpBd9vY`](https://doop.design/c/LQFIZlhE35?frame=w0jvpBd9vY) | Flagship · Manufacturer · Generate serials · GS1 unavailable | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive.Index :new_serial + SerialWizard (flagship) | — | — |

**Flagship · Pack shipper**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ijOdE3IvVJ`](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ) | Flagship · Manufacturer · Pack shipper · 1 Batch | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (pack panel) → /manufacturer/sscc/:id/serials` → ManufacturerProductLive.Serials pack_serials_into_shipper (flagship) | — | — |
| [`IQ2oV6Y6Gn`](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn) | Flagship · Manufacturer · Pack shipper · 2 Units | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (pack panel) → /manufacturer/sscc/:id/serials` → ManufacturerProductLive.Serials pack_serials_into_shipper (flagship) | — | — |
| [`fbgqW4GxfP`](https://doop.design/c/LQFIZlhE35?frame=fbgqW4GxfP) | Flagship · Manufacturer · Pack shipper · 2 Units scan error | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (pack panel) → /manufacturer/sscc/:id/serials` → ManufacturerProductLive.Serials pack_serials_into_shipper (flagship) | — | — |

**Flagship · Print labels**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`sPHNupiZjM`](https://doop.design/c/LQFIZlhE35?frame=sPHNupiZjM) | Flagship · Manufacturer · Print labels | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (print)` → ManufacturerProductLive.Serials LabelPrint (flagship, new bulk print) | — | — |

**Flagship · Product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`oR30_7au26`](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26) | Flagship · Manufacturer · Product detail | light | draft (flagship, paused 17:05) | `/manufacturer/products[/:id]` → ManufacturerProductLive.Index / Show (flagship) | — | — |

**Flagship · Products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`rOKtmxrk0b`](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b) | Flagship · Manufacturer · Products | light | draft (flagship, paused 17:05) | `NO ROUTE` → unmapped | — | — |
| [`Dejg7rMSP_`](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_) | Flagship · Manufacturer · Products · Syncing from GS1 | light | draft (flagship, paused 17:05) | `/manufacturer/products[/:id]` → ManufacturerProductLive.Index / Show (flagship) | — | — |
| [`jEHjO102Ab`](https://doop.design/c/LQFIZlhE35?frame=jEHjO102Ab) | Flagship · Manufacturer · Products · Sync failed | light | draft (flagship, paused 17:05) | `/manufacturer/products[/:id]` → ManufacturerProductLive.Index / Show (flagship) | — | — |
| [`AywKWZYjJ5`](https://doop.design/c/LQFIZlhE35?frame=AywKWZYjJ5) | Flagship · Manufacturer · Products · Empty | light | draft (flagship, paused 17:05) | `/manufacturer/products[/:id]` → ManufacturerProductLive.Index / Show (flagship) | — | — |

**Flagship · View serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Dc-F0U2xu2`](https://doop.design/c/LQFIZlhE35?frame=Dc-F0U2xu2) | Flagship · Manufacturer · View serials · All unpacked | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (serials view)` → ManufacturerProductLive.Serials (flagship) | — | — |
| [`S_jxhlbOcE`](https://doop.design/c/LQFIZlhE35?frame=S_jxhlbOcE) | Flagship · Manufacturer · View serials · Packed filter | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (serials view)` → ManufacturerProductLive.Serials (flagship) | — | — |
| [`N47kkIH5F7`](https://doop.design/c/LQFIZlhE35?frame=N47kkIH5F7) | Flagship · Manufacturer · View serials · No matches | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (serials view)` → ManufacturerProductLive.Serials (flagship) | — | — |
| [`RWCTScqFsc`](https://doop.design/c/LQFIZlhE35?frame=RWCTScqFsc) | Flagship · Manufacturer · View serials · GS1 error | light | draft (flagship, paused 17:05) | `/manufacturer/products/:gtin/serials (serials view)` → ManufacturerProductLive.Serials (flagship) | — | — |

**Manufacturer · API keys**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`dNqZMZIzMf`](https://doop.design/c/LQFIZlhE35?frame=dNqZMZIzMf) | Manufacturer · API keys | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | "(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` |

**Manufacturer · Add SSCC**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`lHqj6ZUNd9`](https://doop.design/c/LQFIZlhE35?frame=lHqj6ZUNd9) | Manufacturer · Add SSCC · choose type | light | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard :new (AGG-1) | done | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Add SSCC · pallet `SynBwMYmxH`<br>"(unlabelled)" → Manufacturer · Add SSCC · standalone shipper `dFl7bLVBCX`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` (+1 more) |
| [`SynBwMYmxH`](https://doop.design/c/LQFIZlhE35?frame=SynBwMYmxH) | Manufacturer · Add SSCC · pallet | light | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard :new (AGG-1) | — | Aggregation → Manufacturer · Aggregation `nooman_e0w`<br>Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>[.lk] → Manufacturer · Add SSCC · standalone shipper `dFl7bLVBCX`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>[.lk] → Manufacturer · Products `nOHadNSnnW` (+2 more) |
| [`dFl7bLVBCX`](https://doop.design/c/LQFIZlhE35?frame=dFl7bLVBCX) | Manufacturer · Add SSCC · standalone shipper | light | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard :new (AGG-1) | — | Aggregation → Manufacturer · Aggregation `nooman_e0w`<br>Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>[.lk] → Manufacturer · Add SSCC · pallet `SynBwMYmxH`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW`<br>[.lk] → Manufacturer · Shipments `dD_f7mT7VA` (+2 more) |
| [`c9jkythg4W`](https://doop.design/c/LQFIZlhE35?frame=c9jkythg4W) | Manufacturer · Add SSCC · GS1 key missing | light | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard :new (AGG-1) | done | Aggregation → Manufacturer · Aggregation `nooman_e0w`<br>Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>Open API keys → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>[.lk] → Manufacturer · Add SSCC · pallet `SynBwMYmxH`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW` (+3 more) |
| [`q-15ZUmjys`](https://doop.design/c/LQFIZlhE35?frame=q-15ZUmjys) | Manufacturer · Add SSCC · GS1 key missing · dark | dark | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard :new (AGG-1) | done | Aggregation → Manufacturer · Aggregation · dark `9eVZhuE_oo`<br>Industrial Area Plant → Manufacturer · Dashboard · dark `xhJU95ZpT2`<br>Open API keys → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>[.lk] → Manufacturer · Add SSCC · pallet `SynBwMYmxH`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW` (+3 more) |

**Manufacturer · Add a GTIN**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`lR-QAyMqkU`](https://doop.design/c/LQFIZlhE35?frame=lR-QAyMqkU) | Manufacturer · Add a GTIN | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | "(unlabelled)" opens Manufacturer · Add a GTIN · verified `0Bgaf217sX`<br>"Close" closes overlay |
| [`0Bgaf217sX`](https://doop.design/c/LQFIZlhE35?frame=0Bgaf217sX) | Manufacturer · Add a GTIN · verified | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay |
| [`_z_kvN4J3u`](https://doop.design/c/LQFIZlhE35?frame=_z_kvN4J3u) | Manufacturer · Add a GTIN · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay<br>[.lk] opens Manufacturer · Add a GTIN · verified · dark `0ICDRrcaQm` |
| [`0ICDRrcaQm`](https://doop.design/c/LQFIZlhE35?frame=0ICDRrcaQm) | Manufacturer · Add a GTIN · verified · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay |

**Manufacturer · Add a batch**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`N6mJklIrFy`](https://doop.design/c/LQFIZlhE35?frame=N6mJklIrFy) | Manufacturer · Add a batch | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | "Close" closes overlay |
| [`k7yr3odkh-`](https://doop.design/c/LQFIZlhE35?frame=k7yr3odkh-) | Manufacturer · Add a batch · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay |

**Manufacturer · Add mobile user**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PHuUbfzLYd`](https://doop.design/c/LQFIZlhE35?frame=PHuUbfzLYd) | Manufacturer · Add mobile user | light | canon | `/manufacturer/mobile-users[/new|/:id/edit]` → ManufacturerMobileUserLive.Index | — | [span] closes overlay<br>[span] → Manufacturer · Mobile users `ePbnW2fsM1` |

**Manufacturer · Add product**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`yWiBLt5W4_`](https://doop.design/c/LQFIZlhE35?frame=yWiBLt5W4_) | Manufacturer · Add product | light | canon | `/manufacturer/products[/new]` → ManufacturerProductLive.Index | — | [span] closes overlay<br>[span] → Manufacturer · Products `nOHadNSnnW` |

**Manufacturer · Add serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`CSIvAn03cl`](https://doop.design/c/LQFIZlhE35?frame=CSIvAn03cl) | Manufacturer · Add serials | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay |
| [`z6oVqrpt2g`](https://doop.design/c/LQFIZlhE35?frame=z6oVqrpt2g) | Manufacturer · Add serials · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay |

**Manufacturer · Add shipper SSCC to pallet**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`qGit1zj1rm`](https://doop.design/c/LQFIZlhE35?frame=qGit1zj1rm) | Manufacturer · Add shipper SSCC to pallet | light | canon | `/manufacturer/aggregations/pallets/:pallet_id/ssccs/new` → ManufacturerAggregationLive.Wizard :new_on_pallet (AGG-1) | — | Aggregation → Manufacturer · Aggregation `nooman_e0w`<br>Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>Pallet → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>[.lk] → Manufacturer · Products `nOHadNSnnW`<br>[.lk] → Manufacturer · Shipments `dD_f7mT7VA` (+2 more) |

**Manufacturer · Aggregation**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`nooman_e0w`](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w) | Manufacturer · Aggregation | light | canon | `/manufacturer/aggregations` → ManufacturerAggregationLive.Dashboard (AGG-1, released 23 Nov) | done | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"361640010000000184 Thamani Pharma Limited Kilimo Distributor" → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>"361640010000000191 Thamani Pharma Limited Afya Bora Health L" → Manufacturer · Pallet SSCC `rDvQtkfRwC` (+3 more) |
| [`GcfERrqXwb`](https://doop.design/c/LQFIZlhE35?frame=GcfERrqXwb) | Manufacturer · Aggregation · empty | light | canon | `/manufacturer/aggregations` → ManufacturerAggregationLive.Dashboard (AGG-1, released 23 Nov) | done | Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW`<br>[.lk] → Manufacturer · Shipments `dD_f7mT7VA`<br>[.lk] → Manufacturer · TNT reporting `6h1jP1RQB5` |
| [`9eVZhuE_oo`](https://doop.design/c/LQFIZlhE35?frame=9eVZhuE_oo) | Manufacturer · Aggregation · dark | dark | canon | `/manufacturer/aggregations` → ManufacturerAggregationLive.Dashboard (AGG-1, released 23 Nov) | — | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Add SSCC · choose type `lHqj6ZUNd9`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"361640010000000184 Thamani Pharma Limited Kilimo Distributor" → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>"361640010000000191 Thamani Pharma Limited Afya Bora Health L" → Manufacturer · Pallet SSCC `rDvQtkfRwC` (+3 more) |

**Manufacturer · Aggregation review**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`gqkhVbK6z_`](https://doop.design/c/LQFIZlhE35?frame=gqkhVbK6z_) | Manufacturer · Aggregation review | light | canon | `/manufacturer/aggregations/:id` → ManufacturerAggregationLive.Review (AGG-1, released 23 Nov) | — | "(unlabelled)" opens Manufacturer · Case label `iqCZv_AYnf`<br>"(unlabelled)" opens Manufacturer · Reject aggregation `LjYz-aVJzL`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` (+1 more) |

**Manufacturer · Case label**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`iqCZv_AYnf`](https://doop.design/c/LQFIZlhE35?frame=iqCZv_AYnf) | Manufacturer · Case label | light | canon | `/manufacturer/sscc/:id/label` → ManufacturerSsccLive.Label | — | [span] closes overlay |

**Manufacturer · Dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ssU7S65tZF`](https://doop.design/c/LQFIZlhE35?frame=ssU7S65tZF) ★ | Manufacturer · Dashboard | light | canon | `/manufacturer` → ManufacturerDashboardLive | done | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |
| [`xhJU95ZpT2`](https://doop.design/c/LQFIZlhE35?frame=xhJU95ZpT2) | Manufacturer · Dashboard · dark | dark | canon | `/manufacturer` → ManufacturerDashboardLive | — | [.li] → Manufacturer · Aggregation · dark `9eVZhuE_oo`<br>[.li] → Manufacturer · Shipments `dD_f7mT7VA`<br>[.lk] opens Manufacturer · Add product `yWiBLt5W4_`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Aggregation · dark `9eVZhuE_oo`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW`<br>[.lk] → Manufacturer · Shipments `dD_f7mT7VA` (+3 more) |

**Manufacturer · Deactivate mobile user**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`k4McyoV5Ze`](https://doop.design/c/LQFIZlhE35?frame=k4McyoV5Ze) | Manufacturer · Deactivate mobile user | light | canon | `/manufacturer/mobile-users[/new|/:id/edit]` → ManufacturerMobileUserLive.Index | — | [span] closes overlay<br>[span] → Manufacturer · Mobile users `ePbnW2fsM1` |

**Manufacturer · Generate serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`K4RLF5VaaL`](https://doop.design/c/LQFIZlhE35?frame=K4RLF5VaaL) | Manufacturer · Generate serials · Mode | light | canon | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | "(unlabelled)" opens Manufacturer · Generate serials · Order batch `KmXWmRHQdm`<br>"(unlabelled)" opens Manufacturer · Generate serials · Stock `qFO1qTLxuX`<br>"Close" closes overlay |
| [`qFO1qTLxuX`](https://doop.design/c/LQFIZlhE35?frame=qFO1qTLxuX) | Manufacturer · Generate serials · Stock | light | canon | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | "(unlabelled)" opens Manufacturer · Generate serials · Mode `K4RLF5VaaL`<br>"(unlabelled)" opens Manufacturer · Serials issued · Stock `kyQHKTVNuw`<br>"Close" closes overlay |
| [`KmXWmRHQdm`](https://doop.design/c/LQFIZlhE35?frame=KmXWmRHQdm) | Manufacturer · Generate serials · Order batch | light | canon | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | [span] closes overlay<br>[span] opens Manufacturer · Generate serials · Mode `K4RLF5VaaL`<br>[span] opens Manufacturer · Generate serials · Order parties `9OowcBjmWP` |
| [`9OowcBjmWP`](https://doop.design/c/LQFIZlhE35?frame=9OowcBjmWP) | Manufacturer · Generate serials · Order parties | light | canon | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | [span] closes overlay<br>[span] opens Manufacturer · Generate serials · Order batch `KmXWmRHQdm`<br>[span] opens Manufacturer · Serials issued · Order `pu69ruhFa_` |

**Manufacturer · Inventory**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PSRp5BYBqa`](https://doop.design/c/LQFIZlhE35?frame=PSRp5BYBqa) | Manufacturer · Inventory | light | canon | `/manufacturer/inventory` → ManufacturerInventoryLive | — | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` |

**Manufacturer · Mobile users**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ePbnW2fsM1`](https://doop.design/c/LQFIZlhE35?frame=ePbnW2fsM1) | Manufacturer · Mobile users | light | canon | `/manufacturer/mobile-users[/new|/:id/edit]` → ManufacturerMobileUserLive.Index | — | "(unlabelled)" opens Manufacturer · Add mobile user `PHuUbfzLYd`<br>"(unlabelled)" opens Manufacturer · Deactivate mobile user `k4McyoV5Ze`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` |

**Manufacturer · New aggregation**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`R2MvAEcBgQ`](https://doop.design/c/LQFIZlhE35?frame=R2MvAEcBgQ) | Manufacturer · New aggregation | light | canon | `/manufacturer/aggregations/new` → ManufacturerAggregationLive.Wizard (AGG-1, released 23 Nov) | — | [span] closes overlay<br>[span] → Manufacturer · Aggregation review `gqkhVbK6z_` |

**Manufacturer · New shipment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fR48lnlLFS`](https://doop.design/c/LQFIZlhE35?frame=fR48lnlLFS) | Manufacturer · New shipment | light | canon | `/manufacturer/shipments/new` → ManufacturerShipmentLive.Form | — | [span] closes overlay |

**Manufacturer · Org settings**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`a5BIYP5fvv`](https://doop.design/c/LQFIZlhE35?frame=a5BIYP5fvv) | Manufacturer · Org settings | light | canon | `/manufacturer/settings` → OrganizationSettingsLive | — | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5` |

**Manufacturer · Packing list**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`_5mVCvDB4-`](https://doop.design/c/LQFIZlhE35?frame=_5mVCvDB4-) | Manufacturer · Packing list | light | canon | `/manufacturer/shipments/:id/packing-list` → ManufacturerShipmentLive.Review | — | [span] closes overlay |

**Manufacturer · Pallet SSCC**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`rDvQtkfRwC`](https://doop.design/c/LQFIZlhE35?frame=rDvQtkfRwC) | Manufacturer · Pallet SSCC | light | canon | `/manufacturer/aggregations/pallets/:id` → ManufacturerAggregationLive.PalletShow (AGG-1) | done | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Add shipper SSCC to pallet `qGit1zj1rm`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"361640010000000221 Amoxicillin 500mg capsules GTIN 061640012" → Manufacturer · Shipper SSCC `6s_cVMiQkS`<br>"361640010000000238 Amoxicillin 500mg capsules GTIN 061640012" → Manufacturer · Shipper SSCC `6s_cVMiQkS` (+3 more) |
| [`XEj-QF2bKn`](https://doop.design/c/LQFIZlhE35?frame=XEj-QF2bKn) | Manufacturer · Pallet SSCC · dark | dark | canon | `/manufacturer/aggregations/pallets/:id` → ManufacturerAggregationLive.PalletShow (AGG-1) | — | Aggregation → Manufacturer · Aggregation · dark `9eVZhuE_oo`<br>Industrial Area Plant → Manufacturer · Dashboard · dark `xhJU95ZpT2`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Add shipper SSCC to pallet `qGit1zj1rm`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW`<br>[.lk] → Manufacturer · Shipments `dD_f7mT7VA`<br>[.lk] → Manufacturer · Shipper SSCC · dark `tY878a4EFK` (+1 more) |

**Manufacturer · Product SSCCs**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`C22opce6ED`](https://doop.design/c/LQFIZlhE35?frame=C22opce6ED) | Manufacturer · Product SSCCs | light | canon | `/manufacturer/products/:gtin/ssccs` → ManufacturerProductLive.Ssccs | — | "(unlabelled)" opens Distributor · Print SSCC labels `AG21KELEMP`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA` (+13 more) |

**Manufacturer · Product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`vGTuM5LTeA`](https://doop.design/c/LQFIZlhE35?frame=vGTuM5LTeA) | Manufacturer · Product detail | light | canon | `/manufacturer/products/:id` → ManufacturerProductLive.Show | — | "(unlabelled)" opens Manufacturer · Generate serials · Mode `K4RLF5VaaL`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Product SSCCs `C22opce6ED`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Products" → Manufacturer · Products `nOHadNSnnW` |

**Manufacturer · Products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`nOHadNSnnW`](https://doop.design/c/LQFIZlhE35?frame=nOHadNSnnW) | Manufacturer · Products | light | canon | `/manufacturer/products[/new]` → ManufacturerProductLive.Index | — | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 4 4,800" → Manufacturer · Product detail `vGTuM5LTeA`<br>"Ceftriaxone 1g injection 06289001005678 1 400" → Manufacturer · Product detail `vGTuM5LTeA` (+3 more) |

**Manufacturer · Reject aggregation**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`LjYz-aVJzL`](https://doop.design/c/LQFIZlhE35?frame=LjYz-aVJzL) | Manufacturer · Reject aggregation | light | canon | `/manufacturer/aggregations/:id` → ManufacturerAggregationLive.Review (AGG-1, released 23 Nov) | — | [span] closes overlay<br>[span] → Manufacturer · Aggregation `nooman_e0w` |

**Manufacturer · SSCC serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`TcfVwKaNOZ`](https://doop.design/c/LQFIZlhE35?frame=TcfVwKaNOZ) | Manufacturer · SSCC serials | light | canon | `/manufacturer/sscc/:id/serials` → ManufacturerSsccLive.Serials | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Back to SSCCs" → Manufacturer · Product SSCCs `C22opce6ED`<br>"Products" → Manufacturer · Products `nOHadNSnnW` (+1 more) |

**Manufacturer · Serials issued**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`kyQHKTVNuw`](https://doop.design/c/LQFIZlhE35?frame=kyQHKTVNuw) | Manufacturer · Serials issued · Stock | light | superseded (dead UI per Krak §1.4) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | [span] closes overlay<br>[span] → Manufacturer · Inventory `PSRp5BYBqa`<br>[span] → Manufacturer · Product detail `vGTuM5LTeA` |
| [`pu69ruhFa_`](https://doop.design/c/LQFIZlhE35?frame=pu69ruhFa_) | Manufacturer · Serials issued · Order | light | superseded (dead UI per Krak §1.4) | `/manufacturer/products/:gtin/serials/new` → ManufacturerProductLive serials wizard | — | [span] closes overlay<br>[span] opens Manufacturer · New shipment `fR48lnlLFS`<br>[span] → Manufacturer · Aggregation `nooman_e0w` |

**Manufacturer · Shipment review**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zlgzwWEFqF`](https://doop.design/c/LQFIZlhE35?frame=zlgzwWEFqF) | Manufacturer · Shipment review | light | canon | `/manufacturer/shipments/:id` → ManufacturerShipmentLive.Review | — | "(unlabelled)" opens Manufacturer · Packing list `_5mVCvDB4-`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Shipments" → Manufacturer · Shipments `dD_f7mT7VA` |

**Manufacturer · Shipments**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`dD_f7mT7VA`](https://doop.design/c/LQFIZlhE35?frame=dD_f7mT7VA) | Manufacturer · Shipments | light | canon | `/manufacturer/shipments` → ManufacturerShipmentLive.List | — | "(unlabelled)" opens Manufacturer · New shipment `fR48lnlLFS`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"MSH-2026-0038 Westlands Diagnostics GLN 0628900000312 3" → Manufacturer · Shipment review `zlgzwWEFqF`<br>"MSH-2026-0039 Nairobi CBD Pharmacy GLN 0628900000221 8" → Manufacturer · Shipment review `zlgzwWEFqF` (+2 more) |

**Manufacturer · Shipper SSCC**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`6s_cVMiQkS`](https://doop.design/c/LQFIZlhE35?frame=6s_cVMiQkS) | Manufacturer · Shipper SSCC | light | canon | `/manufacturer/aggregations/ssccs/:id` → ManufacturerAggregationLive.SsccShow (AGG-1) | done | "(unlabelled)" opens Manufacturer · Add a GTIN `lR-QAyMqkU`<br>"(unlabelled)" opens Manufacturer · Add a batch `N6mJklIrFy`<br>"(unlabelled)" opens Manufacturer · Add serials `CSIvAn03cl`<br>"(unlabelled)" opens Manufacturer · Upload GTINs `fVih9AULeV`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA` (+3 more) |
| [`rYXMrp0LxV`](https://doop.design/c/LQFIZlhE35?frame=rYXMrp0LxV) | Manufacturer · Shipper SSCC · no contents | light | canon | `/manufacturer/aggregations/ssccs/:id` → ManufacturerAggregationLive.SsccShow (AGG-1) | — | Aggregation → Manufacturer · Aggregation `nooman_e0w`<br>Industrial Area Plant → Manufacturer · Dashboard `ssU7S65tZF`<br>Pallet → Manufacturer · Pallet SSCC `rDvQtkfRwC`<br>[.lk] opens Manufacturer · Add a GTIN `lR-QAyMqkU`<br>[.lk] opens Manufacturer · Upload GTINs `fVih9AULeV`<br>[.lk] → Manufacturer · API keys `dNqZMZIzMf`<br>[.lk] → Manufacturer · Inventory `PSRp5BYBqa`<br>[.lk] → Manufacturer · Mobile users `ePbnW2fsM1`<br>[.lk] → Manufacturer · Org settings `a5BIYP5fvv`<br>[.lk] → Manufacturer · Products `nOHadNSnnW` (+2 more) |
| [`tY878a4EFK`](https://doop.design/c/LQFIZlhE35?frame=tY878a4EFK) | Manufacturer · Shipper SSCC · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id` → ManufacturerAggregationLive.SsccShow (AGG-1) | — | "(unlabelled)" opens Manufacturer · Add a GTIN `lR-QAyMqkU`<br>"(unlabelled)" opens Manufacturer · Add a batch `N6mJklIrFy`<br>"(unlabelled)" opens Manufacturer · Add serials `CSIvAn03cl`<br>"(unlabelled)" opens Manufacturer · Upload GTINs `fVih9AULeV`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA` (+3 more) |

**Manufacturer · TNT event details**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`0zmvdMTWIE`](https://doop.design/c/LQFIZlhE35?frame=0zmvdMTWIE) | Manufacturer · TNT event details · Pending | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | [span] closes overlay<br>[span] opens TNT · Send event confirm `m-gTgjUcmi` |
| [`8B4C8tDPqC`](https://doop.design/c/LQFIZlhE35?frame=8B4C8tDPqC) | Manufacturer · TNT event details · Sent | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | [span] closes overlay |
| [`G1_T8lFZ2b`](https://doop.design/c/LQFIZlhE35?frame=G1_T8lFZ2b) | Manufacturer · TNT event details · Dark | dark | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | [span] closes overlay<br>[span] opens TNT · Send event confirm `m-gTgjUcmi` |

**Manufacturer · TNT reporting**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`6h1jP1RQB5`](https://doop.design/c/LQFIZlhE35?frame=6h1jP1RQB5) | Manufacturer · TNT reporting | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | "(unlabelled)" opens Manufacturer · TNT event details · Pending `0zmvdMTWIE`<br>"(unlabelled)" opens TNT · Send event confirm `m-gTgjUcmi`<br>"(unlabelled)" opens TNT · Send pending now confirm `0OTimjfTsi`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA` (+2 more) |
| [`IUuHyR8EK6`](https://doop.design/c/LQFIZlhE35?frame=IUuHyR8EK6) | Manufacturer · TNT reporting · Automatic | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | "(unlabelled)" opens Manufacturer · TNT event details · Sent `8B4C8tDPqC`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting · Automatic `IUuHyR8EK6`<br>"API keys" → Manufacturer · API keys `dNqZMZIzMf` |
| [`Ey__g8H971`](https://doop.design/c/LQFIZlhE35?frame=Ey__g8H971) | Manufacturer · TNT reporting · No events | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | "(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting · No events `Ey__g8H971`<br>"API keys" → Manufacturer · API keys `dNqZMZIzMf` |
| [`ccaGTlWZk8`](https://doop.design/c/LQFIZlhE35?frame=ccaGTlWZk8) | Manufacturer · TNT reporting · Dark | dark | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | "(unlabelled)" opens Manufacturer · TNT event details · Dark `G1_T8lFZ2b`<br>"(unlabelled)" opens TNT · Send event confirm `m-gTgjUcmi`<br>"(unlabelled)" opens TNT · Send pending now confirm `0OTimjfTsi`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA` (+2 more) |

**Manufacturer · Upload GTINs**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fVih9AULeV`](https://doop.design/c/LQFIZlhE35?frame=fVih9AULeV) | Manufacturer · Upload GTINs | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs · verifying `rhHZl42YEh` |
| [`NS4itJFiPZ`](https://doop.design/c/LQFIZlhE35?frame=NS4itJFiPZ) | Manufacturer · Upload GTINs · review | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs `fVih9AULeV` |
| [`rhHZl42YEh`](https://doop.design/c/LQFIZlhE35?frame=rhHZl42YEh) | Manufacturer · Upload GTINs · verifying | light | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | done | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs · review `NS4itJFiPZ` |
| [`YkH8thqsrO`](https://doop.design/c/LQFIZlhE35?frame=YkH8thqsrO) | Manufacturer · Upload GTINs · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs · verifying · dark `Kcw3QZqZg3` |
| [`-lU-wxAX4p`](https://doop.design/c/LQFIZlhE35?frame=-lU-wxAX4p) | Manufacturer · Upload GTINs · review · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | — | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs · dark `YkH8thqsrO` |
| [`Kcw3QZqZg3`](https://doop.design/c/LQFIZlhE35?frame=Kcw3QZqZg3) | Manufacturer · Upload GTINs · verifying · dark | dark | canon | `/manufacturer/aggregations/ssccs/:id (modal)` → ManufacturerAggregationLive.SsccShow modals (AGG-1) | done | [.lk] closes overlay<br>[.lk] opens Manufacturer · Upload GTINs · review · dark `-lU-wxAX4p` |


### 3.2 Distributor (96 frames, 49 flows)

**Distributor · API keys**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`eq1hvM1JAm`](https://doop.design/c/LQFIZlhE35?frame=eq1hvM1JAm) | Distributor · API keys | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Embakasi Warehouse → Distributor · Shipments `XJBYJekyQ3`<br>[.lk] opens Org · Clear API key `9a056M-Yir`<br>[.lk] → Distributor · API keys `eq1hvM1JAm`<br>[.lk] → Distributor · Billing · prepay `nNSes79vHo`<br>[.lk] → Distributor · Customers `tpsqpH3pfq`<br>[.lk] → Distributor · Mobile users `uNq45yZlSw`<br>[.lk] → Distributor · Org settings `6c3WqEKBCP`<br>[.lk] → Distributor · Products `GbcOmL7hjr`<br>[.lk] → Distributor · Receiving `pTKmcZsilq`<br>[.lk] → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+4 more) |
| [`fOIbHB-8_d`](https://doop.design/c/LQFIZlhE35?frame=fOIbHB-8_d) | Distributor · API keys · dark | dark | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Embakasi Warehouse → Distributor · Shipments `XJBYJekyQ3`<br>[.lk] opens Org · Clear API key · dark `2oBHtPAwc_`<br>[.lk] → Distributor · API keys `eq1hvM1JAm`<br>[.lk] → Distributor · Billing · prepay `nNSes79vHo`<br>[.lk] → Distributor · Customers `tpsqpH3pfq`<br>[.lk] → Distributor · Mobile users `uNq45yZlSw`<br>[.lk] → Distributor · Org settings `6c3WqEKBCP`<br>[.lk] → Distributor · Products `GbcOmL7hjr`<br>[.lk] → Distributor · Receiving `pTKmcZsilq`<br>[.lk] → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+4 more) |

**Distributor · Add customer**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`yfImGybMH4`](https://doop.design/c/LQFIZlhE35?frame=yfImGybMH4) | Distributor · Add customer | light | canon | `/distributor/customers[/new|/:id/edit]` → DistributorCustomerLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Customers `tpsqpH3pfq` |

**Distributor · Add item**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ZoTRfv1hsN`](https://doop.design/c/LQFIZlhE35?frame=ZoTRfv1hsN) | Distributor · Add item · product found | light | canon | `/distributor/receiving/new` → DistributorReceivingLive :distributor_new | — | [.lk] closes overlay<br>[.lk] opens Distributor · Add item · new product `cuTiC1b_gF`<br>[.lk] opens Distributor · Add item · new supplier `G02PxKZRth`<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] → Distributor · Receive inventory · items added `NwX0CruZHC` |
| [`cuTiC1b_gF`](https://doop.design/c/LQFIZlhE35?frame=cuTiC1b_gF) | Distributor · Add item · new product | light | canon | `/distributor/receiving/new` → DistributorReceivingLive :distributor_new | — | [.lk] closes overlay<br>[.lk] opens Distributor · Add item · product found `ZoTRfv1hsN` |
| [`G02PxKZRth`](https://doop.design/c/LQFIZlhE35?frame=G02PxKZRth) | Distributor · Add item · new supplier | light | canon | `/distributor/receiving/new` → DistributorReceivingLive :distributor_new | — | [.lk] closes overlay<br>[.lk] opens Distributor · Add item · product found `ZoTRfv1hsN` |

**Distributor · Add mobile user**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`_8R2f0HWVA`](https://doop.design/c/LQFIZlhE35?frame=_8R2f0HWVA) | Distributor · Add mobile user | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Mobile users · added `FUYV1G6_oq` |

**Distributor · Add product**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`qHoPkYGnpt`](https://doop.design/c/LQFIZlhE35?frame=qHoPkYGnpt) | Distributor · Add product | light | canon | `/distributor/products[/new]` → DistributorProductLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Products · added `-h8zVFSeZ0` |

**Distributor · Add site**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zPFVqJpCoT`](https://doop.design/c/LQFIZlhE35?frame=zPFVqJpCoT) | Distributor · Add site | light | canon | `/org/sites[/new]` → SiteLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Sites · created `VtFnWKWwhA` |

**Distributor · Approve shipment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`EA9ystUKuK`](https://doop.design/c/LQFIZlhE35?frame=EA9ystUKuK) | Distributor · Approve shipment | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | [.lk] closes overlay<br>[.lk] → Distributor · Shipment · just approved `lQVs5LkQSv` |

**Distributor · Batch detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Yd-me0Se-p`](https://doop.design/c/LQFIZlhE35?frame=Yd-me0Se-p) | Distributor · Batch detail | light | canon | `/distributor/batches/:id` → DistributorBatchLive | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Goods receipt `v-q64497Ft`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+3 more) |

**Distributor · Billing**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`nNSes79vHo`](https://doop.design/c/LQFIZlhE35?frame=nNSes79vHo) | Distributor · Billing · prepay | light | canon | `/distributor/billing` → DistributorBillingLive.Index | — | "(unlabelled)" → Distributor · Buy serials `5dblYmDL3P`<br>"(unlabelled)" → Distributor · Choose a serialisation plan `Eu3T4LB1bO`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+7 more) |
| [`onc1mah2wo`](https://doop.design/c/LQFIZlhE35?frame=onc1mah2wo) | Distributor · Billing · flex | light | canon | `/distributor/billing` → DistributorBillingLive.Index | — | "(unlabelled)" → Distributor · Choose a serialisation plan `Eu3T4LB1bO`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Settle usage `jFNgzgD5q1`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+7 more) |
| [`vi5a6Pe3nV`](https://doop.design/c/LQFIZlhE35?frame=vi5a6Pe3nV) | Distributor · Billing · payment received | light | canon | `/distributor/billing` → DistributorBillingLive.Index | — | "(unlabelled)" → Distributor · Buy serials `5dblYmDL3P`<br>"(unlabelled)" → Distributor · Choose a serialisation plan `Eu3T4LB1bO`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+7 more) |

**Distributor · Break case**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`9mhLuDdvyF`](https://doop.design/c/LQFIZlhE35?frame=9mhLuDdvyF) | Distributor · Break case | light | canon | `/distributor/cases/:id` → DistributorCaseLive | — | "(unlabelled)" opens Distributor · Break case confirm `jDbPbmLbzu`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+4 more) |

**Distributor · Break case confirm**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`jDbPbmLbzu`](https://doop.design/c/LQFIZlhE35?frame=jDbPbmLbzu) | Distributor · Break case confirm | light | canon | `/distributor/cases/:id` → DistributorCaseLive | — | [.lk] closes overlay<br>[.lk] → Distributor · Stock · storage zone `j2u8BBnf6m` |

**Distributor · Buy serials**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5dblYmDL3P`](https://doop.design/c/LQFIZlhE35?frame=5dblYmDL3P) | Distributor · Buy serials | light | canon | `/distributor/billing/payment | /postpay-payment` → DistributorBillingLive.Payment | — | "(unlabelled)" → Distributor · Buy serials `5dblYmDL3P`<br>"(unlabelled)" → Distributor · Buy serials · check your phone `yqxtyU599f`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |
| [`yqxtyU599f`](https://doop.design/c/LQFIZlhE35?frame=yqxtyU599f) | Distributor · Buy serials · check your phone | light | canon | `/distributor/billing/payment | /postpay-payment` → DistributorBillingLive.Payment | — | "(unlabelled)" → Distributor · Billing · payment received `vi5a6Pe3nV`<br>"(unlabelled)" → Distributor · Buy serials `5dblYmDL3P`<br>"(unlabelled)" → Distributor · Buy serials · check your phone `yqxtyU599f`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+5 more) |

**Distributor · Change status**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hRt_Ys_3Bg`](https://doop.design/c/LQFIZlhE35?frame=hRt_Ys_3Bg) | Distributor · Change status | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Stock · status updated `swbFp29AJY` |

**Distributor · Choose a serialisation plan**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Eu3T4LB1bO`](https://doop.design/c/LQFIZlhE35?frame=Eu3T4LB1bO) | Distributor · Choose a serialisation plan | light | canon | `/distributor/billing/options` → DistributorBillingLive.Options | — | "(unlabelled)" → Distributor · Billing · flex `onc1mah2wo`<br>"(unlabelled)" → Distributor · Buy serials `5dblYmDL3P`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+2 more) |

**Distributor · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`FUN-ITw_Qj`](https://doop.design/c/LQFIZlhE35?frame=FUN-ITw_Qj) | Distributor · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | Esc closes overlay<br>[.pr] opens Distributor · Add mobile user `_8R2f0HWVA`<br>[.pr] → Distributor · Buy serials `5dblYmDL3P`<br>[.pr] → Distributor · Mobile users `uNq45yZlSw`<br>[.pr] → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>[.pr] → Distributor · Products `GbcOmL7hjr`<br>[.pr] → Distributor · Receive inventory · items added `NwX0CruZHC`<br>[.pr] → Distributor · Receiving `pTKmcZsilq`<br>[.pr] → Distributor · Shipments `XJBYJekyQ3`<br>[.pr] → Distributor · Stock · storage zone `j2u8BBnf6m` |

**Distributor · Customer return detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2poLrBv3Wq`](https://doop.design/c/LQFIZlhE35?frame=2poLrBv3Wq) | Distributor · Customer return detail | light | canon | `/distributor/customer-returns[/new|/:id]` → DistributorCustomerReturnLive.Index | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m`<br>"(unlabelled)" → Distributor · TNT reporting `brAo4lH0vA` (+2 more) |

**Distributor · Customers**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tpsqpH3pfq`](https://doop.design/c/LQFIZlhE35?frame=tpsqpH3pfq) | Distributor · Customers | light | canon | `/distributor/customers[/new|/:id/edit]` → DistributorCustomerLive.Index | — | "(unlabelled)" opens Distributor · Add customer `yfImGybMH4`<br>"(unlabelled)" opens Distributor · Edit customer `WvABh70bsk`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+3 more) |
| [`eLeVZImSse`](https://doop.design/c/LQFIZlhE35?frame=eLeVZImSse) | Distributor · Customers · none yet | light | canon | `/distributor/customers[/new|/:id/edit]` → DistributorCustomerLive.Index | — | "(unlabelled)" opens Distributor · Add customer `yfImGybMH4`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+1 more) |

**Distributor · Dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8OjVBGuJw2`](https://doop.design/c/LQFIZlhE35?frame=8OjVBGuJw2) ★ | Distributor · Dashboard | light | canon | `/distributor` → DistributorDashboardLive | done | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+12 more) |
| [`bmmS6NYoqO`](https://doop.design/c/LQFIZlhE35?frame=bmmS6NYoqO) | Distributor · Dashboard · dark | dark | canon | `/distributor` → DistributorDashboardLive | — | [.lk] → Distributor · Billing · prepay `nNSes79vHo`<br>[.lk] → Distributor · Customers `tpsqpH3pfq`<br>[.lk] → Distributor · Mobile users `uNq45yZlSw`<br>[.lk] → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>[.lk] → Distributor · Org settings `6c3WqEKBCP`<br>[.lk] → Distributor · Products `GbcOmL7hjr`<br>[.lk] → Distributor · Products · all batches `4JRxjqsjai`<br>[.lk] → Distributor · Receive inventory · items added `NwX0CruZHC`<br>[.lk] → Distributor · Receiving `pTKmcZsilq`<br>[.lk] → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+9 more) |

**Distributor · Deactivate mobile user**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`z9vglBIUjs`](https://doop.design/c/LQFIZlhE35?frame=z9vglBIUjs) | Distributor · Deactivate mobile user | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Mobile users · deactivated `SgbVcf0GcK` |

**Distributor · Delivery note**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`UiVBLpI9Cx`](https://doop.design/c/LQFIZlhE35?frame=UiVBLpI9Cx) | Distributor · Delivery note | light | canon | `/distributor/shipments/:id/delivery-note` → DistributorShipmentLive delivery note | — | — |

**Distributor · Edit customer**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`WvABh70bsk`](https://doop.design/c/LQFIZlhE35?frame=WvABh70bsk) | Distributor · Edit customer | light | canon | `/distributor/customers[/new|/:id/edit]` → DistributorCustomerLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Customers `tpsqpH3pfq` |

**Distributor · Edit mobile user**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`h5-N5tqIvS`](https://doop.design/c/LQFIZlhE35?frame=h5-N5tqIvS) | Distributor · Edit mobile user | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | [.lk] closes overlay<br>[.lk] opens Distributor · Deactivate mobile user `z9vglBIUjs`<br>[.lk] → Distributor · Mobile users `uNq45yZlSw`<br>[.lk] → Distributor · Mobile users · PIN resent `eZdGCDlHbo` |

**Distributor · Goods receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`v-q64497Ft`](https://doop.design/c/LQFIZlhE35?frame=v-q64497Ft) | Distributor · Goods receipt | light | canon | `/distributor/receiving/:id` → DistributorGoodsReceiptLive | — | "(unlabelled)" opens Download ready `zkycQlzsjO`<br>"(unlabelled)" opens Print `d687xWcrBC`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |

**Distributor · Invoice**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tmGVB7EA_h`](https://doop.design/c/LQFIZlhE35?frame=tmGVB7EA_h) | Distributor · Invoice | light | canon | `/distributor/billing/invoices/:id` → DistributorBillingLive.Invoice | — | "(unlabelled)" opens Print `d687xWcrBC`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+3 more) |

**Distributor · Mobile user row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2m66wHWWE7`](https://doop.design/c/LQFIZlhE35?frame=2m66wHWWE7) | Distributor · Mobile user row actions | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | [.lk] opens Distributor · Deactivate mobile user `z9vglBIUjs`<br>[.lk] opens Distributor · Edit mobile user `h5-N5tqIvS`<br>[.lk] → Distributor · Mobile users · PIN resent `eZdGCDlHbo` |

**Distributor · Mobile users**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`uNq45yZlSw`](https://doop.design/c/LQFIZlhE35?frame=uNq45yZlSw) | Distributor · Mobile users | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | "(unlabelled)" opens Distributor · Add mobile user `_8R2f0HWVA`<br>"(unlabelled)" opens Distributor · Mobile user row actions `2m66wHWWE7`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Get the mobile app `_AkYsfMrBW`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+10 more) |
| [`FUYV1G6_oq`](https://doop.design/c/LQFIZlhE35?frame=FUYV1G6_oq) | Distributor · Mobile users · added | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | "(unlabelled)" opens Distributor · Add mobile user `_8R2f0HWVA`<br>"(unlabelled)" opens Distributor · Mobile user row actions `2m66wHWWE7`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Get the mobile app `_AkYsfMrBW`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users · added `FUYV1G6_oq`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+9 more) |
| [`eZdGCDlHbo`](https://doop.design/c/LQFIZlhE35?frame=eZdGCDlHbo) | Distributor · Mobile users · PIN resent | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | "(unlabelled)" opens Distributor · Add mobile user `_8R2f0HWVA`<br>"(unlabelled)" opens Distributor · Mobile user row actions `2m66wHWWE7`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Get the mobile app `_AkYsfMrBW`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users · PIN resent `eZdGCDlHbo`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+9 more) |
| [`SgbVcf0GcK`](https://doop.design/c/LQFIZlhE35?frame=SgbVcf0GcK) | Distributor · Mobile users · deactivated | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | "(unlabelled)" opens Distributor · Add mobile user `_8R2f0HWVA`<br>"(unlabelled)" opens Distributor · Mobile user row actions `2m66wHWWE7`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Get the mobile app `_AkYsfMrBW`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users · deactivated `SgbVcf0GcK`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+9 more) |
| [`FBYkmZgLdp`](https://doop.design/c/LQFIZlhE35?frame=FBYkmZgLdp) | Distributor · Mobile users · none yet | light | canon | `/distributor/mobile-users[/new|/:id/edit]` → DistributorMobileUserLive.Index | — | "(unlabelled)" opens Distributor · Add mobile user `_8R2f0HWVA`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Get the mobile app `_AkYsfMrBW`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+3 more) |

**Distributor · Move stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`9JOOh3G1S8`](https://doop.design/c/LQFIZlhE35?frame=9JOOh3G1S8) | Distributor · Move stock | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | [.lk] closes overlay<br>[.lk] → Distributor · Stock · moved `c7Hoa67z3h` |

**Distributor · New customer return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`gag0zJMVuV`](https://doop.design/c/LQFIZlhE35?frame=gag0zJMVuV) | Distributor · New customer return | light | canon | `/distributor/customer-returns[/new|/:id]` → DistributorCustomerReturnLive.Index | — | "(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customer return detail `2poLrBv3Wq`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |

**Distributor · New shipment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`z6VSLXmqsn`](https://doop.design/c/LQFIZlhE35?frame=z6VSLXmqsn) | Distributor · New shipment · GLN verified | light | canon | `/distributor/shipments/new` → DistributorShipmentLive.Form | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipment · draft saved `n3E_4eHtB7`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+5 more) |
| [`8WcwnQK6TA`](https://doop.design/c/LQFIZlhE35?frame=8WcwnQK6TA) | Distributor · New shipment · GLN not verified | light | canon | `/distributor/shipments/new` → DistributorShipmentLive.Form | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN not verified `8WcwnQK6TA`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |

**Distributor · Org settings**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`6c3WqEKBCP`](https://doop.design/c/LQFIZlhE35?frame=6c3WqEKBCP) | Distributor · Org settings | light | canon | `/distributor/settings` → OrganizationSettingsLive | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings · saved `X1yBg1glDy`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+1 more) |
| [`X1yBg1glDy`](https://doop.design/c/LQFIZlhE35?frame=X1yBg1glDy) | Distributor · Org settings · saved | light | canon | `/distributor/settings` → OrganizationSettingsLive | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings · saved `X1yBg1glDy`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+1 more) |

**Distributor · Print SSCC labels**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`AG21KELEMP`](https://doop.design/c/LQFIZlhE35?frame=AG21KELEMP) | Distributor · Print SSCC labels | light | canon | `/distributor/shipments/:id (labels)` → DistributorShipmentLive.Show | — | [.lk] closes overlay |

**Distributor · Product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`lqrh3ko8nX`](https://doop.design/c/LQFIZlhE35?frame=lqrh3ko8nX) | Distributor · Product detail | light | canon | `/distributor/products/:id` → DistributorProductLive.Show | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m` (+6 more) |

**Distributor · Products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`GbcOmL7hjr`](https://doop.design/c/LQFIZlhE35?frame=GbcOmL7hjr) | Distributor · Products | light | canon | `/distributor/products[/new]` → DistributorProductLive.Index | — | "(unlabelled)" opens Distributor · Add product `qHoPkYGnpt`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+15 more) |
| [`4JRxjqsjai`](https://doop.design/c/LQFIZlhE35?frame=4JRxjqsjai) | Distributor · Products · all batches | light | canon | `/distributor/products[/new]` → DistributorProductLive.Index | — | "(unlabelled)" opens Distributor · Add product `qHoPkYGnpt`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+11 more) |
| [`-h8zVFSeZ0`](https://doop.design/c/LQFIZlhE35?frame=-h8zVFSeZ0) | Distributor · Products · added | light | canon | `/distributor/products[/new]` → DistributorProductLive.Index | — | "(unlabelled)" opens Distributor · Add product `qHoPkYGnpt`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products · added `-h8zVFSeZ0`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+15 more) |

**Distributor · Receive inventory**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`R3EZTr4ePq`](https://doop.design/c/LQFIZlhE35?frame=R3EZTr4ePq) | Distributor · Receive inventory · start | light | canon | `/distributor/receiving/new` → DistributorReceivingLive :distributor_new | — | "(unlabelled)" opens Distributor · Add item · product found `ZoTRfv1hsN`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+5 more) |
| [`NwX0CruZHC`](https://doop.design/c/LQFIZlhE35?frame=NwX0CruZHC) | Distributor · Receive inventory · items added | light | canon | `/distributor/receiving/new` → DistributorReceivingLive :distributor_new | — | "(unlabelled)" opens Distributor · Add item · product found `ZoTRfv1hsN`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Receiving · delivery received `JoswSNZBZB`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+6 more) |

**Distributor · Receiving**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`pTKmcZsilq`](https://doop.design/c/LQFIZlhE35?frame=pTKmcZsilq) | Distributor · Receiving | light | canon | `/distributor/receiving` → DistributorReceivingLive | — | "(unlabelled)" opens Filter menu · Received `X42vxHfarW`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+11 more) |
| [`L7MPRjX9Qe`](https://doop.design/c/LQFIZlhE35?frame=L7MPRjX9Qe) | Distributor · Receiving · no receipts | light | canon | `/distributor/receiving` → DistributorReceivingLive | — | "(unlabelled)" opens Filter menu · Received `X42vxHfarW`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3` (+3 more) |
| [`JoswSNZBZB`](https://doop.design/c/LQFIZlhE35?frame=JoswSNZBZB) | Distributor · Receiving · delivery received | light | canon | `/distributor/receiving` → DistributorReceivingLive | — | "(unlabelled)" opens Filter menu · Received `X42vxHfarW`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving · delivery received `JoswSNZBZB`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+9 more) |

**Distributor · Reject shipment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`rQCrmvANKH`](https://doop.design/c/LQFIZlhE35?frame=rQCrmvANKH) | Distributor · Reject shipment | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | [.lk] closes overlay<br>[.lk] → Distributor · Shipments · rejected `kzJGEKhPLK` |

**Distributor · Returns**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`SLxbPI5Z4A`](https://doop.design/c/LQFIZlhE35?frame=SLxbPI5Z4A) | Distributor · Returns · supplier returns | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | "(unlabelled)" opens Distributor · Start supplier return `Nv4Cfb715M`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · customer returns `oxNAXRBPCz` (+6 more) |
| [`05gOuYcviW`](https://doop.design/c/LQFIZlhE35?frame=05gOuYcviW) | Distributor · Returns · no supplier returns | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | "(unlabelled)" opens Distributor · Start supplier return `Nv4Cfb715M`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · customer returns `oxNAXRBPCz`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+2 more) |
| [`oxNAXRBPCz`](https://doop.design/c/LQFIZlhE35?frame=oxNAXRBPCz) | Distributor · Returns · customer returns | light | canon | `/distributor/customer-returns[/new|/:id]` → DistributorCustomerReturnLive.Index | — | "#37 Mombasa Wholesale Chemists Embakasi Warehouse Other 1 it" → Distributor · Customer return detail `2poLrBv3Wq`<br>"#38 Eldoret Mission Hospital Embakasi Warehouse Damaged 3 it" → Distributor · Customer return detail `2poLrBv3Wq`<br>"#39 Nairobi CBD Pharmacy Embakasi Warehouse Wrong item 1 ite" → Distributor · Customer return detail `2poLrBv3Wq`<br>"#40 Kisumu Medical Centre Embakasi Warehouse Overstock 1 ite" → Distributor · Customer return detail `2poLrBv3Wq`<br>"#41 MedPoint Pharmacy Embakasi Warehouse Damaged 2 items 22 " → Distributor · Customer return detail `2poLrBv3Wq`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw` (+9 more) |

**Distributor · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`a_9Z4X_p7f`](https://doop.design/c/LQFIZlhE35?frame=a_9Z4X_p7f) | Distributor · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] opens Distributor · Add mobile user `_8R2f0HWVA`<br>[.pr] → Distributor · Batch detail `Yd-me0Se-p`<br>[.pr] → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>[.pr] → Distributor · Product detail `lqrh3ko8nX`<br>[.pr] → Distributor · Receive inventory · items added `NwX0CruZHC`<br>[.pr] → Distributor · Shipment · submitted `IiThKMTc0e` |
| [`OzaMqDsP6e`](https://doop.design/c/LQFIZlhE35?frame=OzaMqDsP6e) | Distributor · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Distributor · Batch detail `Yd-me0Se-p`<br>[.pr] → Distributor · Product detail `lqrh3ko8nX`<br>[.pr] → Distributor · Shipment · submitted `IiThKMTc0e` |

**Distributor · Settle usage**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`jFNgzgD5q1`](https://doop.design/c/LQFIZlhE35?frame=jFNgzgD5q1) | Distributor · Settle usage | light | canon | `/distributor/billing/postpay-payment` → DistributorBillingLive.Payment :postpay | — | "(unlabelled)" → Distributor · Buy serials · check your phone `yqxtyU599f`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Settle usage `jFNgzgD5q1`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |

**Distributor · Shipment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ynvC_CLltK`](https://doop.design/c/LQFIZlhE35?frame=ynvC_CLltK) | Distributor · Shipment · draft | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Item details `gCMI-5oDzE`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+6 more) |
| [`n3E_4eHtB7`](https://doop.design/c/LQFIZlhE35?frame=n3E_4eHtB7) | Distributor · Shipment · draft saved | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Item details `gCMI-5oDzE`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+6 more) |
| [`EU_pnVe8Bz`](https://doop.design/c/LQFIZlhE35?frame=EU_pnVe8Bz) | Distributor · Shipment · pick list generated | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Item details `gCMI-5oDzE`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+6 more) |
| [`wWgSbjzUSa`](https://doop.design/c/LQFIZlhE35?frame=wWgSbjzUSa) | Distributor · Shipment · pick confirmed | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Item details `gCMI-5oDzE`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+6 more) |
| [`IiThKMTc0e`](https://doop.design/c/LQFIZlhE35?frame=IiThKMTc0e) | Distributor · Shipment · submitted | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Distributor · Approve shipment `EA9ystUKuK`<br>"(unlabelled)" opens Distributor · Reject shipment `rQCrmvANKH`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+8 more) |
| [`KfQfsgpVkN`](https://doop.design/c/LQFIZlhE35?frame=KfQfsgpVkN) | Distributor · Shipment · can't approve yet | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Distributor · Reject shipment `rQCrmvANKH`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+7 more) |
| [`8SCAEjcIlW`](https://doop.design/c/LQFIZlhE35?frame=8SCAEjcIlW) | Distributor · Shipment · approved | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Distributor · Print SSCC labels `AG21KELEMP`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Delivery note `UiVBLpI9Cx`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+5 more) |
| [`lQVs5LkQSv`](https://doop.design/c/LQFIZlhE35?frame=lQVs5LkQSv) | Distributor · Shipment · just approved | light | canon | `/distributor/shipments/:id[/edit]` → DistributorShipmentLive.Show/Form | — | "(unlabelled)" opens Distributor · Print SSCC labels `AG21KELEMP`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |

**Distributor · Shipments**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`XJBYJekyQ3`](https://doop.design/c/LQFIZlhE35?frame=XJBYJekyQ3) | Distributor · Shipments | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+16 more) |
| [`4WJVAyBAlz`](https://doop.design/c/LQFIZlhE35?frame=4WJVAyBAlz) | Distributor · Shipments · nothing matches | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+7 more) |
| [`kzJGEKhPLK`](https://doop.design/c/LQFIZlhE35?frame=kzJGEKhPLK) | Distributor · Shipments · rejected | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+15 more) |
| [`4C-4iO5AGv`](https://doop.design/c/LQFIZlhE35?frame=4C-4iO5AGv) | Distributor · Shipments · created between | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | [.lk] closes overlay |
| [`b-sThvfHQD`](https://doop.design/c/LQFIZlhE35?frame=b-sThvfHQD) | Distributor · Shipments · Draft | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+9 more) |
| [`_L9q82a0i8`](https://doop.design/c/LQFIZlhE35?frame=_L9q82a0i8) | Distributor · Shipments · Submitted | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+11 more) |
| [`Lb1ooUthfE`](https://doop.design/c/LQFIZlhE35?frame=Lb1ooUthfE) | Distributor · Shipments · Approved | light | canon | `/distributor/shipments` → DistributorShipmentLive.Index | — | "(unlabelled)" opens Distributor · Shipments · created between `4C-4iO5AGv`<br>"(unlabelled)" opens Filter menu · Mobile user `xse0VhnCxA`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+10 more) |

**Distributor · Site row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hcfdn9XxbD`](https://doop.design/c/LQFIZlhE35?frame=hcfdn9XxbD) | Distributor · Site row actions | light | canon | `/org/sites[/new]` → SiteLive.Index | — | [.lk] closes overlay<br>[.lk] opens Distributor · Add site `zPFVqJpCoT` |

**Distributor · Sites**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`iwqRqWwzqP`](https://doop.design/c/LQFIZlhE35?frame=iwqRqWwzqP) | Distributor · Sites | light | canon | `/org/sites[/new]` → SiteLive.Index | — | "(unlabelled)" opens Distributor · Add site `zPFVqJpCoT`<br>"(unlabelled)" opens Distributor · Site row actions `hcfdn9XxbD`<br>"(unlabelled)" opens Filter menu · Activity `GNR8ZG0WQa`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+5 more) |
| [`VtFnWKWwhA`](https://doop.design/c/LQFIZlhE35?frame=VtFnWKWwhA) | Distributor · Sites · created | light | canon | `/org/sites[/new]` → SiteLive.Index | — | "(unlabelled)" opens Distributor · Add site `zPFVqJpCoT`<br>"(unlabelled)" opens Distributor · Site row actions `hcfdn9XxbD`<br>"(unlabelled)" opens Filter menu · Activity `GNR8ZG0WQa`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+5 more) |

**Distributor · Start supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Nv4Cfb715M`](https://doop.design/c/LQFIZlhE35?frame=Nv4Cfb715M) | Distributor · Start supplier return | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | [.lk] closes overlay<br>[.lk] → Distributor · Supplier return · draft `zo7Me6_9Ya` |

**Distributor · Stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`j2u8BBnf6m`](https://doop.design/c/LQFIZlhE35?frame=j2u8BBnf6m) | Distributor · Stock · storage zone | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Break case `9mhLuDdvyF`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP` (+21 more) |
| [`3fqhLARkKR`](https://doop.design/c/LQFIZlhE35?frame=3fqhLARkKR) | Distributor · Stock · empty zone | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+9 more) |
| [`S0calaqsas`](https://doop.design/c/LQFIZlhE35?frame=S0calaqsas) | Distributor · Stock · pick a warehouse | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq` (+10 more) |
| [`c7Hoa67z3h`](https://doop.design/c/LQFIZlhE35?frame=c7Hoa67z3h) | Distributor · Stock · moved | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+19 more) |
| [`swbFp29AJY`](https://doop.design/c/LQFIZlhE35?frame=swbFp29AJY) | Distributor · Stock · status updated | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+19 more) |
| [`UKUgQMR4Jy`](https://doop.design/c/LQFIZlhE35?frame=UKUgQMR4Jy) | Distributor · Stock · Receiving | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+15 more) |
| [`sVU0g3wEAw`](https://doop.design/c/LQFIZlhE35?frame=sVU0g3wEAw) | Distributor · Stock · Picking | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+19 more) |
| [`7zytGb6V4h`](https://doop.design/c/LQFIZlhE35?frame=7zytGb6V4h) | Distributor · Stock · Staging | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+16 more) |
| [`FvnY7JCNQz`](https://doop.design/c/LQFIZlhE35?frame=FvnY7JCNQz) | Distributor · Stock · Dispatch | light | canon | `/distributor/stock` → DistributorStockLive.Index | — | "(unlabelled)" opens Distributor · Change status `hRt_Ys_3Bg`<br>"(unlabelled)" opens Distributor · Move stock `9JOOh3G1S8`<br>"(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr` (+14 more) |

**Distributor · Submit supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Atyo7QvDVx`](https://doop.design/c/LQFIZlhE35?frame=Atyo7QvDVx) | Distributor · Submit supplier return | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | [.lk] closes overlay<br>[.lk] → Distributor · Supplier return · submitted `DE6Mpnt79E` |

**Distributor · Supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zo7Me6_9Ya`](https://doop.design/c/LQFIZlhE35?frame=zo7Me6_9Ya) | Distributor · Supplier return · draft | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | "(unlabelled)" opens Distributor · Submit supplier return `Atyo7QvDVx`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+4 more) |
| [`DE6Mpnt79E`](https://doop.design/c/LQFIZlhE35?frame=DE6Mpnt79E) | Distributor · Supplier return · submitted | light | canon | `/distributor/returns[/new|/:id]` → DistributorSupplierReturnLive / DistributorDisposalLive.Show | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP`<br>"(unlabelled)" → Distributor · Stock · storage zone `j2u8BBnf6m`<br>"(unlabelled)" → Distributor · Supplier return · draft `zo7Me6_9Ya` (+3 more) |

**Distributor · TNT event details**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`14m9-tXF_w`](https://doop.design/c/LQFIZlhE35?frame=14m9-tXF_w) | Distributor · TNT event details · Pending | light | canon | `/distributor/epcis` → DistributorEpcisLive | — | "Close" closes overlay |
| [`xbhMUOwlrl`](https://doop.design/c/LQFIZlhE35?frame=xbhMUOwlrl) | Distributor · TNT event details · Sent | light | canon | `/distributor/epcis` → DistributorEpcisLive | — | [span] closes overlay |

**Distributor · TNT reporting**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`brAo4lH0vA`](https://doop.design/c/LQFIZlhE35?frame=brAo4lH0vA) | Distributor · TNT reporting | light | canon | `/distributor/epcis` → DistributorEpcisLive | — | "(unlabelled)" opens Distributor · TNT event details · Pending `14m9-tXF_w`<br>"(unlabelled)" opens TNT · Send event confirm `m-gTgjUcmi`<br>"(unlabelled)" opens TNT · Send pending now confirm `0OTimjfTsi`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+4 more) |
| [`wKLi2KlP3Q`](https://doop.design/c/LQFIZlhE35?frame=wKLi2KlP3Q) | Distributor · TNT reporting · Automatic | light | canon | `/distributor/epcis` → DistributorEpcisLive | — | "(unlabelled)" opens Distributor · TNT event details · Sent `xbhMUOwlrl`<br>"(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+2 more) |


### 3.3 Pharmacy (99 frames, 62 flows)

**Pharma-lab · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`pBbtVnD7n2`](https://doop.design/c/LQFIZlhE35?frame=pBbtVnD7n2) | Pharma-lab · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | Esc closes overlay<br>[.pr] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.pr] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.pr] → Lab · Lab orders `3GldJbxDi_`<br>[.pr] → Lab · Test catalog `30D8lWH2dY`<br>[.pr] → Pharma-lab · Patients `bqOkfOEJid`<br>[.pr] → Pharma-lab · Receive stock `8iVW7r9PTq`<br>[.pr] → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>[.pr] → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>[.pr] → Pharmacy · Prescriptions `mGgl_Tv3Ej` (+1 more) |

**Pharma-lab · New requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`m0G-EwG5xI`](https://doop.design/c/LQFIZlhE35?frame=m0G-EwG5xI) | Pharma-lab · New requisition | light | canon | `/pharmacy/requisitions/new` → RequisitionLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] opens Remove item `5mZQ-49VPF`<br>[.lk] → Pharma-lab · Requisitions · sent `XzIaUb-TRg` |

**Pharma-lab · Patient detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`HKuQgCEMDo`](https://doop.design/c/LQFIZlhE35?frame=HKuQgCEMDo) | Pharma-lab · Patient detail | light | canon | `/pharmacy/patients/:id` → PatientLive.Show | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+7 more) |

**Pharma-lab · Patients**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`bqOkfOEJid`](https://doop.design/c/LQFIZlhE35?frame=bqOkfOEJid) | Pharma-lab · Patients | light | canon | `/pharmacy/patients` → PatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Patients · visits `ZHDa9azVGo`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7` (+13 more) |
| [`ZHDa9azVGo`](https://doop.design/c/LQFIZlhE35?frame=ZHDa9azVGo) | Pharma-lab · Patients · visits | light | canon | `/pharmacy/patients` → PatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Patients · visits `ZHDa9azVGo`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7` (+13 more) |

**Pharma-lab · Payment receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`XhrkUGbBw-`](https://doop.design/c/LQFIZlhE35?frame=XhrkUGbBw-) | Pharma-lab · Payment receipt | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Print `d687xWcrBC` |

**Pharma-lab · Print Data Matrix**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`NoAAUBFYIM`](https://doop.design/c/LQFIZlhE35?frame=NoAAUBFYIM) | Pharma-lab · Print Data Matrix | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | [.lk] closes overlay |

**Pharma-lab · Receive batch**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2i2uC75baP`](https://doop.design/c/LQFIZlhE35?frame=2i2uC75baP) | Pharma-lab · Receive batch | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | [.lk] closes overlay<br>[.lk] → Pharma-lab · Receive stock · received `zbldFTPOl8` |

**Pharma-lab · Receive stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8iVW7r9PTq`](https://doop.design/c/LQFIZlhE35?frame=8iVW7r9PTq) | Pharma-lab · Receive stock | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | "(unlabelled)" opens Pharma-lab · Receive batch `2i2uC75baP`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej` (+2 more) |
| [`zbldFTPOl8`](https://doop.design/c/LQFIZlhE35?frame=zbldFTPOl8) | Pharma-lab · Receive stock · received | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | "(unlabelled)" opens Pharma-lab · Receive batch `2i2uC75baP`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej` (+2 more) |

**Pharma-lab · Refund payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`g0AWNx5smP`](https://doop.design/c/LQFIZlhE35?frame=g0AWNx5smP) | Pharma-lab · Refund payment | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] → Pharma-lab · Transactions · refunded `wyJQ6GLU2P` |

**Pharma-lab · Requested between**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`N-VnSYQtSj`](https://doop.design/c/LQFIZlhE35?frame=N-VnSYQtSj) | Pharma-lab · Requested between | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | [.lk] closes overlay |

**Pharma-lab · Requisition detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tHrj71_Sgx`](https://doop.design/c/LQFIZlhE35?frame=tHrj71_Sgx) | Pharma-lab · Requisition detail | light | canon | `/pharmacy/requisitions/:id` → RequisitionLive.Show | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+8 more) |

**Pharma-lab · Requisitions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`D4seM_mRUZ`](https://doop.design/c/LQFIZlhE35?frame=D4seM_mRUZ) | Pharma-lab · Requisitions | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharma-lab · New requisition `m0G-EwG5xI`<br>"(unlabelled)" opens Pharma-lab · Requested between `N-VnSYQtSj`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7` (+11 more) |
| [`XzIaUb-TRg`](https://doop.design/c/LQFIZlhE35?frame=XzIaUb-TRg) | Pharma-lab · Requisitions · sent | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharma-lab · New requisition `m0G-EwG5xI`<br>"(unlabelled)" opens Pharma-lab · Requested between `N-VnSYQtSj`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions · sent `XzIaUb-TRg`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7` (+11 more) |

**Pharma-lab · Scan lookup**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`AtpiHFUFn_`](https://doop.design/c/LQFIZlhE35?frame=AtpiHFUFn_) | Pharma-lab · Scan lookup · ready | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · found `nUtvlhnxmd`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej` (+5 more) |
| [`nUtvlhnxmd`](https://doop.design/c/LQFIZlhE35?frame=nUtvlhnxmd) | Pharma-lab · Scan lookup · found | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock product detail `MS7rEsXApn`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW` (+7 more) |
| [`8Dk9fCPTKi`](https://doop.design/c/LQFIZlhE35?frame=8Dk9fCPTKi) | Pharma-lab · Scan lookup · not found | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" opens Pharma-lab · New requisition `m0G-EwG5xI`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW` (+6 more) |

**Pharma-lab · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`LDU1m5zU_D`](https://doop.design/c/LQFIZlhE35?frame=LDU1m5zU_D) | Pharma-lab · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.pr] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.pr] → Lab · Order detail · samples `LYzxIpGTSt`<br>[.pr] → Pharma-lab · Patient detail `HKuQgCEMDo`<br>[.pr] → Pharmacy · Prescription detail `oBlQhsWTT7`<br>[.pr] → Pharmacy · Quick sale · empty `nIkqRsQnw0` |
| [`DaHpKXC8VZ`](https://doop.design/c/LQFIZlhE35?frame=DaHpKXC8VZ) | Pharma-lab · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Lab · Order detail · samples `LYzxIpGTSt`<br>[.pr] → Pharma-lab · Patient detail `HKuQgCEMDo`<br>[.pr] → Pharma-lab · Scan lookup · found `nUtvlhnxmd`<br>[.pr] → Pharma-lab · Stock product detail `MS7rEsXApn`<br>[.pr] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharma-lab · Site dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`0xQtYRdBP7`](https://doop.design/c/LQFIZlhE35?frame=0xQtYRdBP7) | Pharma-lab · Site dashboard | light | canon | `/pharmacy (combined site)` → PharmacyDashboardLive | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0` (+9 more) |
| [`WhDXvN7qc-`](https://doop.design/c/LQFIZlhE35?frame=WhDXvN7qc-) | Pharma-lab · Site dashboard · dark | dark | canon | `/pharmacy (combined site)` → PharmacyDashboardLive | — | [.lk] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.lk] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.lk] → Lab · Lab orders `3GldJbxDi_`<br>[.lk] → Lab · Test catalog `30D8lWH2dY`<br>[.lk] → Pharma-lab · Patients `bqOkfOEJid`<br>[.lk] → Pharma-lab · Receive stock `8iVW7r9PTq`<br>[.lk] → Pharma-lab · Requisitions `D4seM_mRUZ`<br>[.lk] → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>[.lk] → Pharma-lab · Stock · all batches `fiY29WINlP`<br>[.lk] → Pharma-lab · Stock · products `c3EiqRelu0` (+6 more) |

**Pharma-lab · Stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`c3EiqRelu0`](https://doop.design/c/LQFIZlhE35?frame=c3EiqRelu0) | Pharma-lab · Stock · products | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharma-lab · Stock row actions `KNGUgpK574`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ` (+16 more) |
| [`fiY29WINlP`](https://doop.design/c/LQFIZlhE35?frame=fiY29WINlP) | Pharma-lab · Stock · all batches | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_` (+15 more) |

**Pharma-lab · Stock batch detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hXPInx920g`](https://doop.design/c/LQFIZlhE35?frame=hXPInx920g) | Pharma-lab · Stock batch detail | light | canon | `/pharmacy/stock/batches/:id` → PharmacyStockBatchLive | done | "(unlabelled)" opens Pharma-lab · Print Data Matrix `NoAAUBFYIM`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej` (+9 more) |

**Pharma-lab · Stock product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`MS7rEsXApn`](https://doop.design/c/LQFIZlhE35?frame=MS7rEsXApn) | Pharma-lab · Stock product detail | light | canon | `/pharmacy/stock/products/:id` → PharmacyStockProductLive | done | "(unlabelled)" opens Pharma-lab · New requisition `m0G-EwG5xI`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · found `nUtvlhnxmd`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Transactions `7wrWcmujxW` (+8 more) |

**Pharma-lab · Stock row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`KNGUgpK574`](https://doop.design/c/LQFIZlhE35?frame=KNGUgpK574) | Pharma-lab · Stock row actions | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | [.lk] closes overlay<br>[.lk] opens Pharma-lab · New requisition `m0G-EwG5xI`<br>[.lk] → Pharma-lab · Scan lookup · found `nUtvlhnxmd`<br>[.lk] → Pharma-lab · Stock product detail `MS7rEsXApn` |

**Pharma-lab · Transaction actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5_jH3LQdKe`](https://doop.design/c/LQFIZlhE35?frame=5_jH3LQdKe) | Pharma-lab · Transaction actions | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Pharma-lab · Payment receipt `XhrkUGbBw-`<br>[.lk] opens Pharma-lab · Refund payment `g0AWNx5smP`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharma-lab · Transaction detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`O6qBL6WmLK`](https://doop.design/c/LQFIZlhE35?frame=O6qBL6WmLK) | Pharma-lab · Transaction detail | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Pharma-lab · Payment receipt `XhrkUGbBw-`<br>[.lk] opens Pharma-lab · Transaction actions `5_jH3LQdKe`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharma-lab · Transactions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`7wrWcmujxW`](https://doop.design/c/LQFIZlhE35?frame=7wrWcmujxW) | Pharma-lab · Transactions | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharma-lab · Transactions · date range `UGem41P4cJ`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_` (+14 more) |
| [`UGem41P4cJ`](https://doop.design/c/LQFIZlhE35?frame=UGem41P4cJ) | Pharma-lab · Transactions · date range | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay |
| [`wyJQ6GLU2P`](https://doop.design/c/LQFIZlhE35?frame=wyJQ6GLU2P) | Pharma-lab · Transactions · refunded | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharma-lab · Transactions · date range `UGem41P4cJ`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_` (+14 more) |

**Pharmacy · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`oEEi6oe1SM`](https://doop.design/c/LQFIZlhE35?frame=oEEi6oe1SM) | Pharmacy · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | Esc closes overlay<br>[.pr] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.pr] opens Pharmacy · New requisition `8jIK-HzR1_`<br>[.pr] → Pharmacy · Patients `fysrRIVfjl`<br>[.pr] → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>[.pr] → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>[.pr] → Pharmacy · Receive stock `VpVCkmNrin`<br>[.pr] → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>[.pr] → Pharmacy · Stock · products `puMtQXqNOq` |

**Pharmacy · Dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`q2Wvk4Umn8`](https://doop.design/c/LQFIZlhE35?frame=q2Wvk4Umn8) ★ | Pharmacy · Dashboard | light | canon | `/pharmacy` → PharmacyDashboardLive | — | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+8 more) |
| [`wUsA9ZdXrU`](https://doop.design/c/LQFIZlhE35?frame=wUsA9ZdXrU) | Pharmacy · Dashboard · dark | dark | canon | `/pharmacy` → PharmacyDashboardLive | — | [.lk] opens Calendar view menu `UwAiusb5oG`<br>[.lk] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.lk] → Pharmacy · Patients `fysrRIVfjl`<br>[.lk] → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>[.lk] → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>[.lk] → Pharmacy · Receive stock `VpVCkmNrin`<br>[.lk] → Pharmacy · Requisition detail `qAAuZfHK88`<br>[.lk] → Pharmacy · Requisitions `R0-3QT_OPy`<br>[.lk] → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>[.lk] → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+5 more) |

**Pharmacy · Dispense item**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`D-QWKUeNkj`](https://doop.design/c/LQFIZlhE35?frame=D-QWKUeNkj) | Pharmacy · Dispense item | light | canon | `/pharmacy/prescriptions/:id` → PrescriptionLive.Show | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |
| [`EnmtwPsOaU`](https://doop.design/c/LQFIZlhE35?frame=EnmtwPsOaU) | Pharmacy · Dispense item · role blocked | light | canon | `/pharmacy/prescriptions/:id` → PrescriptionLive.Show | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharmacy · Disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`GUbfteruTM`](https://doop.design/c/LQFIZlhE35?frame=GUbfteruTM) | Pharmacy · Disposal · draft | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Pharmacy · Submit disposal `jsbe4tiSoH`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Disposals" → Pharmacy · Disposals `tYEXxq_6Bv` (+2 more) |
| [`rfdJAC7blZ`](https://doop.design/c/LQFIZlhE35?frame=rfdJAC7blZ) | Pharmacy · Disposal · submitted | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" → Pharmacy · Disposal · draft `GUbfteruTM`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Disposals" → Pharmacy · Disposals `tYEXxq_6Bv`<br>"Disposals" → Pharmacy · Disposals `tYEXxq_6Bv` (+1 more) |

**Pharmacy · Disposals**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tYEXxq_6Bv`](https://doop.design/c/LQFIZlhE35?frame=tYEXxq_6Bv) | Pharmacy · Disposals | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Start disposal `tULjmgrTnG`<br>"(unlabelled)" → Pharmacy · Disposals · supplier returns `Oxk8_GkQ7m`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI` (+6 more) |
| [`99LzqIZcf_`](https://doop.design/c/LQFIZlhE35?frame=99LzqIZcf_) | Pharmacy · Disposals · no expiry write-offs | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Pharmacy · Start disposal `tULjmgrTnG`<br>"(unlabelled)" → Pharmacy · Disposals · no supplier returns `rsjJ9t28Zj`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Stock" → Pharmacy · Stock · products `puMtQXqNOq` (+1 more) |
| [`Oxk8_GkQ7m`](https://doop.design/c/LQFIZlhE35?frame=Oxk8_GkQ7m) | Pharmacy · Disposals · supplier returns | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Start supplier return `hHPVIKVxvx`<br>"(unlabelled)" → Pharmacy · Disposals `tYEXxq_6Bv`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI` (+5 more) |
| [`rsjJ9t28Zj`](https://doop.design/c/LQFIZlhE35?frame=rsjJ9t28Zj) | Pharmacy · Disposals · no supplier returns | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Pharmacy · Start supplier return `hHPVIKVxvx`<br>"(unlabelled)" → Pharmacy · Disposals · no expiry write-offs `99LzqIZcf_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Stock" → Pharmacy · Stock · products `puMtQXqNOq` (+1 more) |

**Pharmacy · New prescription**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`V57ys398o_`](https://doop.design/c/LQFIZlhE35?frame=V57ys398o_) | Pharmacy · New prescription · existing patient | light | canon | `/pharmacy/prescriptions/new` → PrescriptionLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] opens Remove item `5mZQ-49VPF`<br>[.lk] → Pharmacy · New prescription · new patient `50yafn4tfg`<br>[.lk] → Pharmacy · Prescription detail · just created `kk8xYfpH6O` |
| [`50yafn4tfg`](https://doop.design/c/LQFIZlhE35?frame=50yafn4tfg) | Pharmacy · New prescription · new patient | light | canon | `/pharmacy/prescriptions/new` → PrescriptionLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.lk] → Pharmacy · New prescription · existing patient `V57ys398o_` |

**Pharmacy · New requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8jIK-HzR1_`](https://doop.design/c/LQFIZlhE35?frame=8jIK-HzR1_) | Pharmacy · New requisition | light | canon | `/pharmacy/requisitions/new` → RequisitionLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] opens Remove item `5mZQ-49VPF`<br>[.lk] → Pharmacy · Requisitions · sent `dVFTApB_-o` |

**Pharmacy · Patient detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Vc5-hRnH8E`](https://doop.design/c/LQFIZlhE35?frame=Vc5-hRnH8E) | Pharmacy · Patient detail | light | canon | `/pharmacy/patients/:id` → PatientLive.Show | — | "(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Patients" → Pharmacy · Patients `fysrRIVfjl`<br>"Kisumu Medical Centre Wanjiru Mwangi Prescription 19 Sep 202" → Pharmacy · Prescription detail `oBlQhsWTT7`<br>"Nairobi CBD Pharmacy Amina Otieno Prescription 18 Nov 2026" → Pharmacy · Prescription detail `oBlQhsWTT7` (+3 more) |

**Pharmacy · Patients**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fysrRIVfjl`](https://doop.design/c/LQFIZlhE35?frame=fysrRIVfjl) | Pharmacy · Patients | light | canon | `/pharmacy/patients` → PatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Patients · visits `PzFZTh8Hqw`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq` (+9 more) |
| [`PzFZTh8Hqw`](https://doop.design/c/LQFIZlhE35?frame=PzFZTh8Hqw) | Pharmacy · Patients · visits | light | canon | `/pharmacy/patients` → PatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Patients · visits `PzFZTh8Hqw`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq` (+9 more) |

**Pharmacy · Payment receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`McK_NH1FTW`](https://doop.design/c/LQFIZlhE35?frame=McK_NH1FTW) | Pharmacy · Payment receipt | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Print `d687xWcrBC` |

**Pharmacy · Prescription detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`oBlQhsWTT7`](https://doop.design/c/LQFIZlhE35?frame=oBlQhsWTT7) | Pharmacy · Prescription detail | light | canon | `/pharmacy/prescriptions/:id` → PrescriptionLive.Show | — | "(unlabelled)" opens Pharmacy · Dispense item `D-QWKUeNkj`<br>"(unlabelled)" opens Pharmacy · Prescription receipt `2GZ7SeAWi0`<br>"(unlabelled)" opens Pharmacy · Record payment `I3I6tP8uFj`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` (+3 more) |
| [`kk8xYfpH6O`](https://doop.design/c/LQFIZlhE35?frame=kk8xYfpH6O) | Pharmacy · Prescription detail · just created | light | canon | `/pharmacy/prescriptions/:id` → PrescriptionLive.Show | — | "(unlabelled)" opens Pharmacy · Dispense item `D-QWKUeNkj`<br>"(unlabelled)" opens Pharmacy · Prescription receipt `2GZ7SeAWi0`<br>"(unlabelled)" opens Pharmacy · Record payment `I3I6tP8uFj`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` (+2 more) |

**Pharmacy · Prescription receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2GZ7SeAWi0`](https://doop.design/c/LQFIZlhE35?frame=2GZ7SeAWi0) | Pharmacy · Prescription receipt | light | canon | `/pharmacy/prescriptions/:id/receipt` → PrescriptionLive.Show :receipt | — | [.lk] closes overlay |

**Pharmacy · Prescriptions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`mGgl_Tv3Ej`](https://doop.design/c/LQFIZlhE35?frame=mGgl_Tv3Ej) | Pharmacy · Prescriptions | light | canon | `/pharmacy/prescriptions` → PrescriptionLive.Index | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Payment `U6QCMLJ8LN`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Prescriptions · Completed `PP6AFx7PEM`<br>"(unlabelled)" → Pharmacy · Prescriptions · Partially dispensed `fR7za4TcRy`<br>"(unlabelled)" → Pharmacy · Prescriptions · Pending `h1ctG5HEZ0`<br>"(unlabelled)" → Pharmacy · Prescriptions · no results `Mpn9ChDfzN`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+14 more) |
| [`Mpn9ChDfzN`](https://doop.design/c/LQFIZlhE35?frame=Mpn9ChDfzN) | Pharmacy · Prescriptions · no results | light | canon | `/pharmacy/prescriptions` → PrescriptionLive.Index | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Payment `U6QCMLJ8LN`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Prescriptions · Completed `PP6AFx7PEM`<br>"(unlabelled)" → Pharmacy · Prescriptions · Partially dispensed `fR7za4TcRy`<br>"(unlabelled)" → Pharmacy · Prescriptions · Pending `h1ctG5HEZ0`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin` (+4 more) |
| [`h1ctG5HEZ0`](https://doop.design/c/LQFIZlhE35?frame=h1ctG5HEZ0) | Pharmacy · Prescriptions · Pending | light | canon | `/pharmacy/prescriptions` → PrescriptionLive.Index | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Payment `U6QCMLJ8LN`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Prescriptions · Completed `PP6AFx7PEM`<br>"(unlabelled)" → Pharmacy · Prescriptions · Partially dispensed `fR7za4TcRy`<br>"(unlabelled)" → Pharmacy · Prescriptions · Pending `h1ctG5HEZ0`<br>"(unlabelled)" → Pharmacy · Prescriptions · no results `Mpn9ChDfzN`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+7 more) |
| [`fR7za4TcRy`](https://doop.design/c/LQFIZlhE35?frame=fR7za4TcRy) | Pharmacy · Prescriptions · Partially dispensed | light | canon | `/pharmacy/prescriptions` → PrescriptionLive.Index | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Payment `U6QCMLJ8LN`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Prescriptions · Completed `PP6AFx7PEM`<br>"(unlabelled)" → Pharmacy · Prescriptions · Partially dispensed `fR7za4TcRy`<br>"(unlabelled)" → Pharmacy · Prescriptions · Pending `h1ctG5HEZ0`<br>"(unlabelled)" → Pharmacy · Prescriptions · no results `Mpn9ChDfzN`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+6 more) |
| [`PP6AFx7PEM`](https://doop.design/c/LQFIZlhE35?frame=PP6AFx7PEM) | Pharmacy · Prescriptions · Completed | light | canon | `/pharmacy/prescriptions` → PrescriptionLive.Index | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Payment `U6QCMLJ8LN`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Prescriptions · Completed `PP6AFx7PEM`<br>"(unlabelled)" → Pharmacy · Prescriptions · Partially dispensed `fR7za4TcRy`<br>"(unlabelled)" → Pharmacy · Prescriptions · Pending `h1ctG5HEZ0`<br>"(unlabelled)" → Pharmacy · Prescriptions · no results `Mpn9ChDfzN`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+9 more) |

**Pharmacy · Print Data Matrix**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`87EK_g6B4h`](https://doop.design/c/LQFIZlhE35?frame=87EK_g6B4h) | Pharmacy · Print Data Matrix | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | [.lk] closes overlay |

**Pharmacy · Quick sale**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`nIkqRsQnw0`](https://doop.design/c/LQFIZlhE35?frame=nIkqRsQnw0) | Pharmacy · Quick sale · empty | light | canon | `/pharmacy/quick-sale` → QuickSaleLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Quick sale · items in sale `WjL-tNN_VO`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Amlodipine 5mg tablets 06160012340062 320 left KSh 10" → Pharmacy · Quick sale · items in sale `WjL-tNN_VO` (+7 more) |
| [`WjL-tNN_VO`](https://doop.design/c/LQFIZlhE35?frame=WjL-tNN_VO) | Pharmacy · Quick sale · items in sale | light | canon | `/pharmacy/quick-sale` → QuickSaleLive | — | "(unlabelled)" opens Pharmacy · Quick sale · confirm payment `N461d8znxS`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Quick sale · items in sale `WjL-tNN_VO`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq` (+9 more) |
| [`N461d8znxS`](https://doop.design/c/LQFIZlhE35?frame=N461d8znxS) | Pharmacy · Quick sale · confirm payment | light | canon | `/pharmacy/quick-sale` → QuickSaleLive | — | [.lk] closes overlay<br>[.lk] opens Pharmacy · Quick sale · sale complete receipt `pZUoyG0NbM` |
| [`pZUoyG0NbM`](https://doop.design/c/LQFIZlhE35?frame=pZUoyG0NbM) | Pharmacy · Quick sale · sale complete receipt | light | canon | `/pharmacy/quick-sale` → QuickSaleLive | — | [.lk] closes overlay<br>[.lk] opens Print `d687xWcrBC`<br>[.lk] → Pharmacy · Quick sale · empty `nIkqRsQnw0` |

**Pharmacy · Receive batch**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`W4rtCphTmP`](https://doop.design/c/LQFIZlhE35?frame=W4rtCphTmP) | Pharmacy · Receive batch | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Receive stock · received `kuH9a_Hlb4` |

**Pharmacy · Receive stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`VpVCkmNrin`](https://doop.design/c/LQFIZlhE35?frame=VpVCkmNrin) | Pharmacy · Receive stock | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | "(unlabelled)" opens Pharmacy · Receive batch `W4rtCphTmP`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"No deliveries" → Pharmacy · Receive stock · nothing pending `cdW-D3F-WD` |
| [`kuH9a_Hlb4`](https://doop.design/c/LQFIZlhE35?frame=kuH9a_Hlb4) | Pharmacy · Receive stock · received | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | "(unlabelled)" opens Pharmacy · Receive batch `W4rtCphTmP`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` |
| [`cdW-D3F-WD`](https://doop.design/c/LQFIZlhE35?frame=cdW-D3F-WD) | Pharmacy · Receive stock · nothing pending | light | canon | `/pharmacy/receive-stock[/:id/receive]` → ReceiveStockLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` |

**Pharmacy · Record payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`I3I6tP8uFj`](https://doop.design/c/LQFIZlhE35?frame=I3I6tP8uFj) | Pharmacy · Record payment | light | canon | `/pharmacy/prescriptions/:id/payments/new` → PrescriptionLive.Show :new_payment | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharmacy · Refund payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`AVv0nB0ws7`](https://doop.design/c/LQFIZlhE35?frame=AVv0nB0ws7) | Pharmacy · Refund payment | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Transactions · refunded `lQNYAcVoz_` |

**Pharmacy · Requested between**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`YK8WeJ4D9U`](https://doop.design/c/LQFIZlhE35?frame=YK8WeJ4D9U) | Pharmacy · Requested between · date range | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | [.lk] closes overlay |

**Pharmacy · Requisition detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`qAAuZfHK88`](https://doop.design/c/LQFIZlhE35?frame=qAAuZfHK88) | Pharmacy · Requisition detail | light | canon | `/pharmacy/requisitions/:id` → RequisitionLive.Show | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Amoxicillin 500mg capsules 200 14 Nov 2026 200" → Pharmacy · Stock product detail `k6in9fJ2Ub`<br>"Artemether/Lumefantrine 20/120 30 14 Nov 2026 30" → Pharmacy · Stock product detail `k6in9fJ2Ub`<br>"Back to Requisitions" → Pharmacy · Requisitions `R0-3QT_OPy` (+4 more) |

**Pharmacy · Requisitions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`R0-3QT_OPy`](https://doop.design/c/LQFIZlhE35?frame=R0-3QT_OPy) | Pharmacy · Requisitions | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · New requisition `8jIK-HzR1_`<br>"(unlabelled)" opens Pharmacy · Requested between · date range `YK8WeJ4D9U`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq` (+7 more) |
| [`dVFTApB_-o`](https://doop.design/c/LQFIZlhE35?frame=dVFTApB_-o) | Pharmacy · Requisitions · sent | light | canon | `/pharmacy/requisitions` → RequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · New requisition `8jIK-HzR1_`<br>"(unlabelled)" opens Pharmacy · Requested between · date range `YK8WeJ4D9U`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions · sent `dVFTApB_-o`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq` (+7 more) |

**Pharmacy · Scan lookup**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`WDnObl1yFI`](https://doop.design/c/LQFIZlhE35?frame=WDnObl1yFI) | Pharmacy · Scan lookup · ready | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Match" → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>"No match" → Pharmacy · Scan lookup · not at your site `oEYztKz59R` (+1 more) |
| [`t2AQmt0try`](https://doop.design/c/LQFIZlhE35?frame=t2AQmt0try) | Pharmacy · Scan lookup · approved stock found | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Quick sale · items in sale `WjL-tNN_VO`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock product detail `k6in9fJ2Ub`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` (+3 more) |
| [`oEYztKz59R`](https://doop.design/c/LQFIZlhE35?frame=oEYztKz59R) | Pharmacy · Scan lookup · not at your site | light | canon | `/pharmacy/scan` → PharmacyScanLive | — | "(unlabelled)" opens Pharmacy · New requisition `8jIK-HzR1_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · products `puMtQXqNOq`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Match" → Pharmacy · Scan lookup · approved stock found `t2AQmt0try` (+2 more) |

**Pharmacy · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hfzoIrlQm2`](https://doop.design/c/LQFIZlhE35?frame=hfzoIrlQm2) | Pharmacy · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>[.pr] → Pharmacy · Patient detail `Vc5-hRnH8E`<br>[.pr] → Pharmacy · Prescription detail `oBlQhsWTT7`<br>[.pr] → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>[.pr] → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>[.pr] → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>[.pr] → Pharmacy · Stock product detail `k6in9fJ2Ub` |
| [`xmBPwSy8U7`](https://doop.design/c/LQFIZlhE35?frame=xmBPwSy8U7) | Pharmacy · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Pharmacy · Patient detail `Vc5-hRnH8E`<br>[.pr] → Pharmacy · Prescription detail `oBlQhsWTT7`<br>[.pr] → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>[.pr] → Pharmacy · Stock product detail `k6in9fJ2Ub`<br>[.pr] → Pharmacy · Stock · products `puMtQXqNOq` |

**Pharmacy · Start disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tULjmgrTnG`](https://doop.design/c/LQFIZlhE35?frame=tULjmgrTnG) | Pharmacy · Start disposal | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Disposal · draft `GUbfteruTM` |

**Pharmacy · Start stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`eTe6yFWa7P`](https://doop.design/c/LQFIZlhE35?frame=eTe6yFWa7P) | Pharmacy · Start stock take | light | canon | `/pharmacy/stock-takes[/new|/:id]` → StockTakeLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Stock take · counting `FxJu0mMXnB` |

**Pharmacy · Start supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hHPVIKVxvx`](https://doop.design/c/LQFIZlhE35?frame=hHPVIKVxvx) | Pharmacy · Start supplier return | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Supplier return · draft `PWA0gFjF5G` |

**Pharmacy · Stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`puMtQXqNOq`](https://doop.design/c/LQFIZlhE35?frame=puMtQXqNOq) | Pharmacy · Stock · products | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Stock row actions `YIT-Xr3ym_`<br>"(unlabelled)" → Pharmacy · Disposals `tYEXxq_6Bv`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin` (+15 more) |
| [`fO2XgZ8Xir`](https://doop.design/c/LQFIZlhE35?frame=fO2XgZ8Xir) | Pharmacy · Stock · all batches | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Pharmacy · Disposals `tYEXxq_6Bv`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy` (+13 more) |

**Pharmacy · Stock batch detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`UlUYBX60A_`](https://doop.design/c/LQFIZlhE35?frame=UlUYBX60A_) | Pharmacy · Stock batch detail | light | canon | `/pharmacy/stock/batches/:id` → PharmacyStockBatchLive | done | "(unlabelled)" opens Pharmacy · Print Data Matrix `87EK_g6B4h`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"02 Oct 2026, 08:20 Amina Otieno Received 200 from Kilele Pha" → Pharmacy · Receive stock `VpVCkmNrin`<br>"10 Nov 2026, 11:30 Amina Otieno Quick sale of 55 · TD-QS-004" → Pharmacy · Transactions `8SwyrgWmlD` (+5 more) |

**Pharmacy · Stock product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`k6in9fJ2Ub`](https://doop.design/c/LQFIZlhE35?frame=k6in9fJ2Ub) | Pharmacy · Stock product detail | light | canon | `/pharmacy/stock/products/:id` → PharmacyStockProductLive | done | "(unlabelled)" opens Pharmacy · New requisition `8jIK-HzR1_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Stock" → Pharmacy · Stock · products `puMtQXqNOq` (+4 more) |

**Pharmacy · Stock row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`YIT-Xr3ym_`](https://doop.design/c/LQFIZlhE35?frame=YIT-Xr3ym_) | Pharmacy · Stock row actions | light | canon | `/pharmacy/stock` → PharmacyStockLive | done | [.lk] closes overlay<br>[.lk] opens Pharmacy · New requisition `8jIK-HzR1_`<br>[.lk] → Pharmacy · Scan lookup · approved stock found `t2AQmt0try`<br>[.lk] → Pharmacy · Stock product detail `k6in9fJ2Ub` |

**Pharmacy · Stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`FxJu0mMXnB`](https://doop.design/c/LQFIZlhE35?frame=FxJu0mMXnB) | Pharmacy · Stock take · counting | light | canon | `/pharmacy/stock-takes[/new|/:id]` → StockTakeLive | — | "(unlabelled)" opens Pharmacy · Submit stock take `KYYC_z9FD_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Stock takes" → Pharmacy · Stock takes `fO4InWJM_1`<br>"Stock takes" → Pharmacy · Stock takes `fO4InWJM_1` (+1 more) |
| [`jA5FCpOM3b`](https://doop.design/c/LQFIZlhE35?frame=jA5FCpOM3b) | Pharmacy · Stock take · submitted | light | canon | `/pharmacy/stock-takes[/new|/:id]` → StockTakeLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock take · counting `FxJu0mMXnB`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Stock takes" → Pharmacy · Stock takes `fO4InWJM_1`<br>"Stock takes" → Pharmacy · Stock takes `fO4InWJM_1` (+1 more) |

**Pharmacy · Stock takes**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fO4InWJM_1`](https://doop.design/c/LQFIZlhE35?frame=fO4InWJM_1) | Pharmacy · Stock takes | light | canon | `/pharmacy/stock-takes[/new|/:id]` → StockTakeLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Start stock take `eTe6yFWa7P`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD` (+6 more) |

**Pharmacy · Submit disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`jsbe4tiSoH`](https://doop.design/c/LQFIZlhE35?frame=jsbe4tiSoH) | Pharmacy · Submit disposal | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Disposal · submitted `rfdJAC7blZ` |

**Pharmacy · Submit stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`KYYC_z9FD_`](https://doop.design/c/LQFIZlhE35?frame=KYYC_z9FD_) | Pharmacy · Submit stock take | light | canon | `/pharmacy/stock-takes[/new|/:id]` → StockTakeLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Stock take · submitted `jA5FCpOM3b` |

**Pharmacy · Submit supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`-Y9ypf1BqR`](https://doop.design/c/LQFIZlhE35?frame=-Y9ypf1BqR) | Pharmacy · Submit supplier return | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | [.lk] closes overlay<br>[.lk] → Pharmacy · Supplier return · submitted `gwRHfpWdbQ` |

**Pharmacy · Supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PWA0gFjF5G`](https://doop.design/c/LQFIZlhE35?frame=PWA0gFjF5G) | Pharmacy · Supplier return · draft | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" opens Pharmacy · Submit supplier return `-Y9ypf1BqR`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Disposals" → Pharmacy · Disposals · supplier returns `Oxk8_GkQ7m` (+2 more) |
| [`gwRHfpWdbQ`](https://doop.design/c/LQFIZlhE35?frame=gwRHfpWdbQ) | Pharmacy · Supplier return · submitted | light | canon | `/pharmacy/disposals[/new|/:id]` → DisposalLive | — | "(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Supplier return · draft `PWA0gFjF5G`<br>"(unlabelled)" → Pharmacy · Transactions `8SwyrgWmlD`<br>"Back to Disposals" → Pharmacy · Disposals · supplier returns `Oxk8_GkQ7m`<br>"Disposals" → Pharmacy · Disposals · supplier returns `Oxk8_GkQ7m` (+1 more) |

**Pharmacy · Transaction actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`4EBIQw1oOJ`](https://doop.design/c/LQFIZlhE35?frame=4EBIQw1oOJ) | Pharmacy · Transaction actions | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Pharmacy · Payment receipt `McK_NH1FTW`<br>[.lk] opens Pharmacy · Refund payment `AVv0nB0ws7`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharmacy · Transaction detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`m_jp8035Ug`](https://doop.design/c/LQFIZlhE35?frame=m_jp8035Ug) | Pharmacy · Transaction detail | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay<br>[.lk] opens Pharmacy · Payment receipt `McK_NH1FTW`<br>[.lk] opens Pharmacy · Transaction actions `4EBIQw1oOJ`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Pharmacy · Transactions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8SwyrgWmlD`](https://doop.design/c/LQFIZlhE35?frame=8SwyrgWmlD) | Pharmacy · Transactions | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Transactions · date range `iXgHWN9Wlx`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI` (+10 more) |
| [`iXgHWN9Wlx`](https://doop.design/c/LQFIZlhE35?frame=iXgHWN9Wlx) | Pharmacy · Transactions · date range | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | [.lk] closes overlay |
| [`lQNYAcVoz_`](https://doop.design/c/LQFIZlhE35?frame=lQNYAcVoz_) | Pharmacy · Transactions · refunded | light | canon | `/pharmacy/transactions` → EarningsLive :pharmacy | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Pharmacy · Transactions · date range `iXgHWN9Wlx`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI` (+10 more) |


### 3.4 Lab (85 frames, 52 flows)

**Lab · Add test**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`kHgteJkTep`](https://doop.design/c/LQFIZlhE35?frame=kHgteJkTep) | Lab · Add test | light | canon | `/lab/orders/:id/tests/new` → LabOrderLive.Show :add_test | done | [.lk] closes overlay<br>[.lk] → Lab · Order detail · results `8fsD6dEWtV` |

**Lab · Amend result**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`WEiVx73bYh`](https://doop.design/c/LQFIZlhE35?frame=WEiVx73bYh) | Lab · Amend result | light | canon | `/lab/orders/:id/results/:rid/edit` → LabOrderLive.Show :edit_result | done | [.lk] closes overlay<br>[.lk] → Lab · Order detail · results recorded `gDvL3sltff` |

**Lab · Collect specimen**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`63lZ570X4e`](https://doop.design/c/LQFIZlhE35?frame=63lZ570X4e) | Lab · Collect specimen | light | canon | `/lab/orders/:id/collect` → LabOrderLive.Show :collect_specimen | done | [.lk] closes overlay<br>[.lk] → Lab · Order detail · specimen collected `s_nAxnvYOE` |

**Lab · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`SObwoLbfus`](https://doop.design/c/LQFIZlhE35?frame=SObwoLbfus) | Lab · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | Esc closes overlay<br>[.pr] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.pr] opens Lab · New requisition `d6TPatVK5h`<br>[.pr] opens Lab · New test `YI4SPze5du`<br>[.pr] → Lab · Lab orders `3GldJbxDi_`<br>[.pr] → Lab · Lab stock · products `_VFeE7v1Z3`<br>[.pr] → Lab · Patients `UvrfVC7Fqk`<br>[.pr] → Lab · Receive stock `4zyleLd04x`<br>[.pr] → Lab · Scan consumable · ready `TAzvg2vh9s`<br>[.pr] → Lab · Test catalog `30D8lWH2dY` |

**Lab · Dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`lDrhCsUsP3`](https://doop.design/c/LQFIZlhE35?frame=lDrhCsUsP3) ★ | Lab · Dashboard | light | canon | `/lab` → LabDashboardLive | done | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+8 more) |
| [`DK81R55zDL`](https://doop.design/c/LQFIZlhE35?frame=DK81R55zDL) | Lab · Dashboard · dark | dark | canon | `/lab` → LabDashboardLive | — | [.lk] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.lk] opens Period menu `5I9pJoGa6G`<br>[.lk] → Lab · Lab orders `3GldJbxDi_`<br>[.lk] → Lab · Lab stock · products `_VFeE7v1Z3`<br>[.lk] → Lab · Order detail · results `8fsD6dEWtV`<br>[.lk] → Lab · Patients `UvrfVC7Fqk`<br>[.lk] → Lab · Receive stock `4zyleLd04x`<br>[.lk] → Lab · Requisitions `W3kDRxq2N5`<br>[.lk] → Lab · Scan consumable · ready `TAzvg2vh9s`<br>[.lk] → Lab · Test catalog `30D8lWH2dY` (+4 more) |

**Lab · Disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Dj1Fl499QM`](https://doop.design/c/LQFIZlhE35?frame=Dj1Fl499QM) | Lab · Disposal · draft | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Lab · Submit disposal `2Cd-gN77X0`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Disposals" → Lab · Disposals `OsoDOCNQ8G` (+2 more) |
| [`Qautl3niIH`](https://doop.design/c/LQFIZlhE35?frame=Qautl3niIH) | Lab · Disposal · submitted | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" → Lab · Disposal · draft `Dj1Fl499QM`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Disposals" → Lab · Disposals `OsoDOCNQ8G`<br>"Disposals" → Lab · Disposals `OsoDOCNQ8G` (+1 more) |

**Lab · Disposals**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`OsoDOCNQ8G`](https://doop.design/c/LQFIZlhE35?frame=OsoDOCNQ8G) | Lab · Disposals | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Start disposal `KWvYEUyMFd`<br>"(unlabelled)" → Lab · Disposals · supplier returns `y0FY06NVXy`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+6 more) |
| [`SRcJwOLocx`](https://doop.design/c/LQFIZlhE35?frame=SRcJwOLocx) | Lab · Disposals · no expiry write-offs | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Lab · Start disposal `KWvYEUyMFd`<br>"(unlabelled)" → Lab · Disposals · no supplier returns `Gk7InyRKVS`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Stock" → Lab · Lab stock · products `_VFeE7v1Z3` (+1 more) |
| [`y0FY06NVXy`](https://doop.design/c/LQFIZlhE35?frame=y0FY06NVXy) | Lab · Disposals · supplier returns | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Start supplier return `M_aJhSQSjt`<br>"(unlabelled)" → Lab · Disposals `OsoDOCNQ8G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+5 more) |
| [`Gk7InyRKVS`](https://doop.design/c/LQFIZlhE35?frame=Gk7InyRKVS) | Lab · Disposals · no supplier returns | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Lab · Start supplier return `M_aJhSQSjt`<br>"(unlabelled)" → Lab · Disposals · no expiry write-offs `SRcJwOLocx`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Stock" → Lab · Lab stock · products `_VFeE7v1Z3` (+1 more) |

**Lab · Edit test**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`xOFNLJ6gpC`](https://doop.design/c/LQFIZlhE35?frame=xOFNLJ6gpC) | Lab · Edit test | light | canon | `/lab/tests/new | /lab/tests/:id/edit` → LabTestLive.Index | — | [.lk] closes overlay<br>[.lk] opens Add a result field `PUBr8g1meJ`<br>[.lk] opens Remove item `5mZQ-49VPF`<br>[.lk] → Lab · Test catalog · saved `7RjaqhNF4N` |

**Lab · Enter test results**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zJW8IHMTZV`](https://doop.design/c/LQFIZlhE35?frame=zJW8IHMTZV) | Lab · Enter test results | light | canon | `/lab/orders/:id/results/:rid/edit` → LabOrderLive.Show :edit_result | done | [.lk] closes overlay<br>[.lk] → Lab · Order detail · results recorded `gDvL3sltff` |

**Lab · Lab orders**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`3GldJbxDi_`](https://doop.design/c/LQFIZlhE35?frame=3GldJbxDi_) | Lab · Lab orders | light | canon | `/lab/orders` → LabOrderLive.Index | — | "(unlabelled)" opens Filter menu · Paid `lC7VMdCEri`<br>"(unlabelled)" opens Filter menu · Urgency `feg9yL0s8X`<br>"(unlabelled)" opens Lab · Lab orders · created date range `y11_7Bfo8B`<br>"(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab orders · no results `7ibhYgNGj7`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Orders · Completed `riyYzJBrXt`<br>"(unlabelled)" → Lab · Orders · In progress `uxHhaGcWYf`<br>"(unlabelled)" → Lab · Orders · Pending `xI4O9rP0gg` (+14 more) |
| [`7ibhYgNGj7`](https://doop.design/c/LQFIZlhE35?frame=7ibhYgNGj7) | Lab · Lab orders · no results | light | canon | `/lab/orders` → LabOrderLive.Index | — | "(unlabelled)" opens Filter menu · Paid `lC7VMdCEri`<br>"(unlabelled)" opens Filter menu · Urgency `feg9yL0s8X`<br>"(unlabelled)" opens Lab · Lab orders · created date range `y11_7Bfo8B`<br>"(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Orders · Completed `riyYzJBrXt`<br>"(unlabelled)" → Lab · Orders · In progress `uxHhaGcWYf`<br>"(unlabelled)" → Lab · Orders · Pending `xI4O9rP0gg`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk` (+5 more) |
| [`y11_7Bfo8B`](https://doop.design/c/LQFIZlhE35?frame=y11_7Bfo8B) | Lab · Lab orders · created date range | light | canon | `/lab/orders` → LabOrderLive.Index | done | [.lk] closes overlay |

**Lab · Lab stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`_VFeE7v1Z3`](https://doop.design/c/LQFIZlhE35?frame=_VFeE7v1Z3) | Lab · Lab stock · products | light | canon | `/lab/stock` → LabStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Stock row actions `scWNUBy5nv`<br>"(unlabelled)" → Lab · Disposals `OsoDOCNQ8G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · all batches `QxyvdDb1ea`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk` (+14 more) |
| [`QxyvdDb1ea`](https://doop.design/c/LQFIZlhE35?frame=QxyvdDb1ea) | Lab · Lab stock · all batches | light | canon | `/lab/stock` → LabStockLive | done | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Expiry `v0UH0bx6L9`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Lab · Disposals `OsoDOCNQ8G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · all batches `QxyvdDb1ea`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x` (+13 more) |

**Lab · New lab order**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`IGb-vyGRK9`](https://doop.design/c/LQFIZlhE35?frame=IGb-vyGRK9) | Lab · New lab order · existing patient | light | canon | `/lab/orders/new` → LabOrderLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Lab · New lab order · tests `gBcldzvNa3`<br>[.lk] → Lab · New lab order · new patient `AZQrJLFBy5` |
| [`AZQrJLFBy5`](https://doop.design/c/LQFIZlhE35?frame=AZQrJLFBy5) | Lab · New lab order · new patient | light | canon | `/lab/orders/new` → LabOrderLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Lab · New lab order · tests `gBcldzvNa3`<br>[.lk] → Lab · New lab order · existing patient `IGb-vyGRK9` |
| [`gBcldzvNa3`](https://doop.design/c/LQFIZlhE35?frame=gBcldzvNa3) | Lab · New lab order · tests | light | canon | `/lab/orders/new` → LabOrderLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Add a test `p_Ib5oNNEe`<br>[.lk] opens Lab · New lab order · details and payment `ORIy7H5PbC`<br>[.lk] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.lk] opens Remove item `5mZQ-49VPF` |
| [`ORIy7H5PbC`](https://doop.design/c/LQFIZlhE35?frame=ORIy7H5PbC) | Lab · New lab order · details and payment | light | canon | `/lab/orders/new` → LabOrderLive.Index :new | — | [.lk] closes overlay<br>[.lk] opens Lab · New lab order · tests `gBcldzvNa3`<br>[.lk] → Lab · Order detail · just created `BkDfHtaY4M` |

**Lab · New requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`d6TPatVK5h`](https://doop.design/c/LQFIZlhE35?frame=d6TPatVK5h) | Lab · New requisition | light | canon | `/lab/requisitions/new` → LabRequisitionLive.Index :new | — | "(unlabelled)" opens Item details `gCMI-5oDzE`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Lab · Requisitions · sent `-6iUpBxdKZ`<br>"Close" closes overlay |

**Lab · New test**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`YI4SPze5du`](https://doop.design/c/LQFIZlhE35?frame=YI4SPze5du) | Lab · New test | light | canon | `/lab/tests/new | /lab/tests/:id/edit` → LabTestLive.Index | — | [.lk] closes overlay<br>[.lk] opens Add a result field `PUBr8g1meJ`<br>[.lk] opens Remove item `5mZQ-49VPF`<br>[.lk] → Lab · Test catalog · saved `7RjaqhNF4N` |

**Lab · Order detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`BkDfHtaY4M`](https://doop.design/c/LQFIZlhE35?frame=BkDfHtaY4M) | Lab · Order detail · just created | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Collect specimen `63lZ570X4e`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+4 more) |
| [`LYzxIpGTSt`](https://doop.design/c/LQFIZlhE35?frame=LYzxIpGTSt) | Lab · Order detail · samples | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Collect specimen `63lZ570X4e`<br>"(unlabelled)" opens Lab · Print specimen label `5O8udg27kd`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5` (+5 more) |
| [`8fsD6dEWtV`](https://doop.design/c/LQFIZlhE35?frame=8fsD6dEWtV) | Lab · Order detail · results | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Amend result `WEiVx73bYh`<br>"(unlabelled)" opens Lab · Enter test results `zJW8IHMTZV`<br>"(unlabelled)" opens Lab · Print results `WAOief8IVU`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · samples `LYzxIpGTSt`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x` (+6 more) |
| [`r1L-tWO8eU`](https://doop.design/c/LQFIZlhE35?frame=r1L-tWO8eU) | Lab · Order detail · consumables | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Record consumable `ry2wSAtctR`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Order detail · samples `LYzxIpGTSt`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+4 more) |
| [`s_nAxnvYOE`](https://doop.design/c/LQFIZlhE35?frame=s_nAxnvYOE) | Lab · Order detail · specimen collected | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Collect specimen `63lZ570X4e`<br>"(unlabelled)" opens Lab · Print specimen label `5O8udg27kd`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5` (+5 more) |
| [`gDvL3sltff`](https://doop.design/c/LQFIZlhE35?frame=gDvL3sltff) | Lab · Order detail · results recorded | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Amend result `WEiVx73bYh`<br>"(unlabelled)" opens Lab · Enter test results `zJW8IHMTZV`<br>"(unlabelled)" opens Lab · Print results `WAOief8IVU`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · samples `LYzxIpGTSt`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x` (+6 more) |
| [`CgyYJqj1cF`](https://doop.design/c/LQFIZlhE35?frame=CgyYJqj1cF) | Lab · Order detail · consumable recorded | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Record consumable `ry2wSAtctR`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Order detail · samples `LYzxIpGTSt`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+4 more) |
| [`1jvAaFyqCV`](https://doop.design/c/LQFIZlhE35?frame=1jvAaFyqCV) | Lab · Order detail · payment recorded | light | canon | `/lab/orders/:id` → LabOrderLive.Show | — | "(unlabelled)" opens Lab · Add test `kHgteJkTep`<br>"(unlabelled)" opens Lab · Collect specimen `63lZ570X4e`<br>"(unlabelled)" opens Lab · Print specimen label `5O8udg27kd`<br>"(unlabelled)" opens Lab · Record payment `15D90zhEQF`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · consumables `r1L-tWO8eU`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5` (+5 more) |

**Lab · Orders**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`xI4O9rP0gg`](https://doop.design/c/LQFIZlhE35?frame=xI4O9rP0gg) | Lab · Orders · Pending | light | canon | `/lab/orders` → LabOrderLive.Index | — | "(unlabelled)" opens Filter menu · Paid `lC7VMdCEri`<br>"(unlabelled)" opens Filter menu · Urgency `feg9yL0s8X`<br>"(unlabelled)" opens Lab · Lab orders · created date range `y11_7Bfo8B`<br>"(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab orders · no results `7ibhYgNGj7`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Orders · Completed `riyYzJBrXt`<br>"(unlabelled)" → Lab · Orders · In progress `uxHhaGcWYf`<br>"(unlabelled)" → Lab · Orders · Pending `xI4O9rP0gg` (+8 more) |
| [`uxHhaGcWYf`](https://doop.design/c/LQFIZlhE35?frame=uxHhaGcWYf) | Lab · Orders · In progress | light | canon | `/lab/orders` → LabOrderLive.Index | — | "(unlabelled)" opens Filter menu · Paid `lC7VMdCEri`<br>"(unlabelled)" opens Filter menu · Urgency `feg9yL0s8X`<br>"(unlabelled)" opens Lab · Lab orders · created date range `y11_7Bfo8B`<br>"(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab orders · no results `7ibhYgNGj7`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Orders · Completed `riyYzJBrXt`<br>"(unlabelled)" → Lab · Orders · In progress `uxHhaGcWYf`<br>"(unlabelled)" → Lab · Orders · Pending `xI4O9rP0gg` (+8 more) |
| [`riyYzJBrXt`](https://doop.design/c/LQFIZlhE35?frame=riyYzJBrXt) | Lab · Orders · Completed | light | canon | `/lab/orders` → LabOrderLive.Index | — | "(unlabelled)" opens Filter menu · Paid `lC7VMdCEri`<br>"(unlabelled)" opens Filter menu · Urgency `feg9yL0s8X`<br>"(unlabelled)" opens Lab · Lab orders · created date range `y11_7Bfo8B`<br>"(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab orders · no results `7ibhYgNGj7`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Orders · Completed `riyYzJBrXt`<br>"(unlabelled)" → Lab · Orders · In progress `uxHhaGcWYf`<br>"(unlabelled)" → Lab · Orders · Pending `xI4O9rP0gg` (+9 more) |

**Lab · Patient detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`SaY_PCI1oD`](https://doop.design/c/LQFIZlhE35?frame=SaY_PCI1oD) | Lab · Patient detail | light | canon | `/lab/patients/:id` → LabPatientLive.Show | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Patients" → Lab · Patients `UvrfVC7Fqk`<br>"Kisumu Medical Centre Wanjiru Mwangi Prescription 19 Sep 202" → Pharmacy · Prescription detail `oBlQhsWTT7`<br>"Patients" → Lab · Patients `UvrfVC7Fqk` (+3 more) |

**Lab · Patients**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`UvrfVC7Fqk`](https://doop.design/c/LQFIZlhE35?frame=UvrfVC7Fqk) | Lab · Patients | light | canon | `/lab/patients` → LabPatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Patients · visits `Gk9dR356pj`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+9 more) |
| [`Gk9dR356pj`](https://doop.design/c/LQFIZlhE35?frame=Gk9dR356pj) | Lab · Patients · visits | light | canon | `/lab/patients` → LabPatientLive.Index | — | "(unlabelled)" opens Filter menu · Gender `flG9lx1Pxp`<br>"(unlabelled)" opens Filter menu · Visited `HZvoVe9Hug`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Patients · visits `Gk9dR356pj`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+9 more) |

**Lab · Payment receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`VRY0p3ZE2z`](https://doop.design/c/LQFIZlhE35?frame=VRY0p3ZE2z) | Lab · Payment receipt | light | canon | `/lab/transactions/:id/receipt` → EarningsLive :lab_receipt | done | "(unlabelled)" opens Print `d687xWcrBC`<br>"Close" closes overlay |

**Lab · Print Data Matrix**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`6gWHYiELXI`](https://doop.design/c/LQFIZlhE35?frame=6gWHYiELXI) | Lab · Print Data Matrix | light | canon | `/lab/stock` → LabStockLive | done | "Close" closes overlay |

**Lab · Print results**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`WAOief8IVU`](https://doop.design/c/LQFIZlhE35?frame=WAOief8IVU) | Lab · Print results | light | canon | `/lab/orders/:id/report` → LabOrderLive.Show · LabReportComponent | done | "Close" closes overlay |

**Lab · Print specimen label**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5O8udg27kd`](https://doop.design/c/LQFIZlhE35?frame=5O8udg27kd) | Lab · Print specimen label | light | canon | `/lab/orders/:id/specimens/:sid/label` → LabOrderLive.Show · SpecimenLabelComponent | done | "Close" closes overlay |

**Lab · Printed lab report**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`-0cH-9CyjR`](https://doop.design/c/LQFIZlhE35?frame=-0cH-9CyjR) | Lab · Printed lab report | light | canon | `/lab/orders/:id/report` → LabOrderLive.Show · LabReportComponent | — | — |

**Lab · Printed specimen label**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`N-RxCNzKsm`](https://doop.design/c/LQFIZlhE35?frame=N-RxCNzKsm) | Lab · Printed specimen label | light | canon | `/lab/orders/:id/specimens/:sid/label` → LabOrderLive.Show · SpecimenLabelComponent | — | — |

**Lab · Receive batch**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`smasDT3VJx`](https://doop.design/c/LQFIZlhE35?frame=smasDT3VJx) | Lab · Receive batch | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | [.lk] closes overlay<br>[.lk] → Lab · Receive stock · received `jeML6KCYpu` |

**Lab · Receive stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`4zyleLd04x`](https://doop.design/c/LQFIZlhE35?frame=4zyleLd04x) | Lab · Receive stock | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | "(unlabelled)" opens Lab · Receive batch `smasDT3VJx`<br>"(unlabelled)" opens Lab · Receive stock directly `UAtyAbR4zW`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"No deliveries" → Lab · Receive stock · nothing pending `yEEv1GtG-f` |
| [`jeML6KCYpu`](https://doop.design/c/LQFIZlhE35?frame=jeML6KCYpu) | Lab · Receive stock · received | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | "(unlabelled)" opens Lab · Receive batch `smasDT3VJx`<br>"(unlabelled)" opens Lab · Receive stock directly `UAtyAbR4zW`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4` |
| [`SGSvCmQYUS`](https://doop.design/c/LQFIZlhE35?frame=SGSvCmQYUS) | Lab · Receive stock · received directly | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | "(unlabelled)" opens Lab · Receive batch `smasDT3VJx`<br>"(unlabelled)" opens Lab · Receive stock directly `UAtyAbR4zW`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4` |
| [`yEEv1GtG-f`](https://doop.design/c/LQFIZlhE35?frame=yEEv1GtG-f) | Lab · Receive stock · nothing pending | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | "(unlabelled)" opens Lab · Receive stock directly `UAtyAbR4zW`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4` |

**Lab · Receive stock directly**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`UAtyAbR4zW`](https://doop.design/c/LQFIZlhE35?frame=UAtyAbR4zW) | Lab · Receive stock directly | light | canon | `/lab/receive-stock[/:id/receive]` → LabReceiveStockLive | — | [.lk] closes overlay<br>[.lk] → Lab · Receive stock · received directly `SGSvCmQYUS` |

**Lab · Record consumable**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ry2wSAtctR`](https://doop.design/c/LQFIZlhE35?frame=ry2wSAtctR) | Lab · Record consumable | light | canon | `/lab/orders/:id/consumables/new` → LabOrderLive.Show :record_consumable | done | [.lk] closes overlay<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] → Lab · Order detail · consumable recorded `CgyYJqj1cF` |

**Lab · Record payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`15D90zhEQF`](https://doop.design/c/LQFIZlhE35?frame=15D90zhEQF) | Lab · Record payment | light | canon | `/lab/orders/:id/payments/new` → LabOrderLive.Show :new_payment | — | "(unlabelled)" → Lab · Order detail · payment recorded `1jvAaFyqCV`<br>"Close" closes overlay |

**Lab · Refund payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5kI8h3aBwo`](https://doop.design/c/LQFIZlhE35?frame=5kI8h3aBwo) | Lab · Refund payment | light | canon | `/lab/transactions` → EarningsLive :lab | — | [.lk] closes overlay<br>[.lk] → Lab · Transactions · refunded `DnuQVVOIuE` |

**Lab · Requested between**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`7ikGY9Ebrz`](https://doop.design/c/LQFIZlhE35?frame=7ikGY9Ebrz) | Lab · Requested between · date range | light | canon | `/lab/requisitions` → LabRequisitionLive.Index | done | [.lk] closes overlay |

**Lab · Requisition detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`9FqxTu2HSn`](https://doop.design/c/LQFIZlhE35?frame=9FqxTu2HSn) | Lab · Requisition detail | light | canon | `/lab/requisitions/:id` → LabRequisitionLive.Show | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Requisitions" → Lab · Requisitions `W3kDRxq2N5`<br>"EDTA tubes 4ml 50 14 Nov 2026 0" → Lab · Stock product detail `eKD_3r3UqQ`<br>"Glucose test strips 100 14 Nov 2026 60" → Lab · Stock product detail `eKD_3r3UqQ` (+4 more) |

**Lab · Requisitions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`W3kDRxq2N5`](https://doop.design/c/LQFIZlhE35?frame=W3kDRxq2N5) | Lab · Requisitions | light | canon | `/lab/requisitions` → LabRequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · New requisition `d6TPatVK5h`<br>"(unlabelled)" opens Lab · Requested between · date range `7ikGY9Ebrz`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+7 more) |
| [`-6iUpBxdKZ`](https://doop.design/c/LQFIZlhE35?frame=-6iUpBxdKZ) | Lab · Requisitions · sent | light | canon | `/lab/requisitions` → LabRequisitionLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · New requisition `d6TPatVK5h`<br>"(unlabelled)" opens Lab · Requested between · date range `7ikGY9Ebrz`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions · sent `-6iUpBxdKZ`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+7 more) |

**Lab · Scan consumable**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`TAzvg2vh9s`](https://doop.design/c/LQFIZlhE35?frame=TAzvg2vh9s) | Lab · Scan consumable · ready | light | canon | `/lab/scan` → LabScanLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · match `W_3ImmTRlp`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Match" → Lab · Scan consumable · match `W_3ImmTRlp`<br>"No match" → Lab · Scan consumable · no match `XJfIJtIz4i` (+1 more) |
| [`W_3ImmTRlp`](https://doop.design/c/LQFIZlhE35?frame=W_3ImmTRlp) | Lab · Scan consumable · match | light | canon | `/lab/scan` → LabScanLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Stock batch detail `5MdRlvaDiH`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Match" → Lab · Scan consumable · match `W_3ImmTRlp` (+2 more) |
| [`XJfIJtIz4i`](https://doop.design/c/LQFIZlhE35?frame=XJfIJtIz4i) | Lab · Scan consumable · no match | light | canon | `/lab/scan` → LabScanLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Match" → Lab · Scan consumable · match `W_3ImmTRlp`<br>"No match" → Lab · Scan consumable · no match `XJfIJtIz4i`<br>"Ready" → Lab · Scan consumable · ready `TAzvg2vh9s` |

**Lab · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`A-NSb15zZW`](https://doop.design/c/LQFIZlhE35?frame=A-NSb15zZW) | Lab · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.pr] → Lab · Order detail · samples `LYzxIpGTSt`<br>[.pr] → Lab · Patient detail `SaY_PCI1oD`<br>[.pr] → Lab · Receive stock `4zyleLd04x`<br>[.pr] → Lab · Scan consumable · ready `TAzvg2vh9s`<br>[.pr] → Lab · Stock product detail `eKD_3r3UqQ`<br>[.pr] → Lab · Test catalog `30D8lWH2dY` |
| [`NEa-OK75GL`](https://doop.design/c/LQFIZlhE35?frame=NEa-OK75GL) | Lab · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Lab · Order detail · results `8fsD6dEWtV`<br>[.pr] → Lab · Order detail · samples `LYzxIpGTSt`<br>[.pr] → Lab · Patient detail `SaY_PCI1oD`<br>[.pr] → Lab · Scan consumable · match `W_3ImmTRlp`<br>[.pr] → Lab · Stock product detail `eKD_3r3UqQ` |

**Lab · Start disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`KWvYEUyMFd`](https://doop.design/c/LQFIZlhE35?frame=KWvYEUyMFd) | Lab · Start disposal | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | [.lk] closes overlay<br>[.lk] → Lab · Disposal · draft `Dj1Fl499QM` |

**Lab · Start stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`j1xqm59fX7`](https://doop.design/c/LQFIZlhE35?frame=j1xqm59fX7) | Lab · Start stock take | light | canon | `/lab/stock-takes[/new|/:id]` → LabStockTakeLive | — | [.lk] closes overlay<br>[.lk] → Lab · Stock take · counting `xWBHSEfCXQ` |

**Lab · Start supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`M_aJhSQSjt`](https://doop.design/c/LQFIZlhE35?frame=M_aJhSQSjt) | Lab · Start supplier return | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | [.lk] closes overlay<br>[.lk] → Lab · Supplier return · draft `Wx7_TyNlII` |

**Lab · Stock batch detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5MdRlvaDiH`](https://doop.design/c/LQFIZlhE35?frame=5MdRlvaDiH) | Lab · Stock batch detail | light | canon | `/lab/stock/batches/:id` → LabStockBatchLive | done | "(unlabelled)" opens Lab · Print Data Matrix `6gWHYiELXI`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"02 Oct 2026, 08:20 Amina Otieno Received 200 from Kilele Pha" → Lab · Receive stock `4zyleLd04x`<br>"10 Nov 2026, 11:30 Amina Otieno Quick sale of 55 · TD-QS-004" → Lab · Transactions `Pef-1fqHs4` (+5 more) |

**Lab · Stock product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`eKD_3r3UqQ`](https://doop.design/c/LQFIZlhE35?frame=eKD_3r3UqQ) | Lab · Stock product detail | light | canon | `/lab/stock/products/:id` → LabStockProductLive | done | "(unlabelled)" opens Lab · New requisition `d6TPatVK5h`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · match `W_3ImmTRlp`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Stock" → Lab · Lab stock · products `_VFeE7v1Z3` (+4 more) |

**Lab · Stock row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`scWNUBy5nv`](https://doop.design/c/LQFIZlhE35?frame=scWNUBy5nv) | Lab · Stock row actions | light | canon | `/lab/stock` → LabStockLive | done | [.lk] closes overlay<br>[.lk] opens Lab · New requisition `d6TPatVK5h`<br>[.lk] → Lab · Scan consumable · match `W_3ImmTRlp`<br>[.lk] → Lab · Stock product detail `eKD_3r3UqQ` |

**Lab · Stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`xWBHSEfCXQ`](https://doop.design/c/LQFIZlhE35?frame=xWBHSEfCXQ) | Lab · Stock take · counting | light | canon | `/lab/stock-takes[/new|/:id]` → LabStockTakeLive | — | "(unlabelled)" opens Lab · Submit stock take `NmxaX7eNHW`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Stock takes" → Lab · Stock takes `xK6VW836NG`<br>"Stock takes" → Lab · Stock takes `xK6VW836NG` (+1 more) |
| [`CQLYEPcaOX`](https://doop.design/c/LQFIZlhE35?frame=CQLYEPcaOX) | Lab · Stock take · submitted | light | canon | `/lab/stock-takes[/new|/:id]` → LabStockTakeLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Stock take · counting `xWBHSEfCXQ`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Stock takes" → Lab · Stock takes `xK6VW836NG`<br>"Stock takes" → Lab · Stock takes `xK6VW836NG` (+1 more) |

**Lab · Stock takes**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`xK6VW836NG`](https://doop.design/c/LQFIZlhE35?frame=xK6VW836NG) | Lab · Stock takes | light | canon | `/lab/stock-takes[/new|/:id]` → LabStockTakeLive | — | "(unlabelled)" opens Filter menu · Created `Q6s3o1UKRS`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Start stock take `j1xqm59fX7`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4` (+6 more) |

**Lab · Submit disposal**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2Cd-gN77X0`](https://doop.design/c/LQFIZlhE35?frame=2Cd-gN77X0) | Lab · Submit disposal | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | [.lk] closes overlay<br>[.lk] → Lab · Disposal · submitted `Qautl3niIH` |

**Lab · Submit stock take**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`NmxaX7eNHW`](https://doop.design/c/LQFIZlhE35?frame=NmxaX7eNHW) | Lab · Submit stock take | light | canon | `/lab/stock-takes[/new|/:id]` → LabStockTakeLive | — | [.lk] closes overlay<br>[.lk] → Lab · Stock take · submitted `CQLYEPcaOX` |

**Lab · Submit supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8pBS5RcfYF`](https://doop.design/c/LQFIZlhE35?frame=8pBS5RcfYF) | Lab · Submit supplier return | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | [.lk] closes overlay<br>[.lk] → Lab · Supplier return · submitted `BNVMha_eAs` |

**Lab · Supplier return**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Wx7_TyNlII`](https://doop.design/c/LQFIZlhE35?frame=Wx7_TyNlII) | Lab · Supplier return · draft | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" opens Lab · Submit supplier return `8pBS5RcfYF`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Disposals" → Lab · Disposals · supplier returns `y0FY06NVXy` (+2 more) |
| [`BNVMha_eAs`](https://doop.design/c/LQFIZlhE35?frame=BNVMha_eAs) | Lab · Supplier return · submitted | light | canon | `/lab/disposals[/new|/:id]` → LabDisposalLive | — | "(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Supplier return · draft `Wx7_TyNlII`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Lab · Transactions `Pef-1fqHs4`<br>"Back to Disposals" → Lab · Disposals · supplier returns `y0FY06NVXy`<br>"Disposals" → Lab · Disposals · supplier returns `y0FY06NVXy` (+1 more) |

**Lab · Test catalog**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`30D8lWH2dY`](https://doop.design/c/LQFIZlhE35?frame=30D8lWH2dY) | Lab · Test catalog | light | canon | `/lab/tests` → LabTestLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · New test `YI4SPze5du`<br>"(unlabelled)" opens Lab · Test row actions `bpzbAF-loY`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+10 more) |
| [`7RjaqhNF4N`](https://doop.design/c/LQFIZlhE35?frame=7RjaqhNF4N) | Lab · Test catalog · saved | light | canon | `/lab/tests` → LabTestLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · New test `YI4SPze5du`<br>"(unlabelled)" opens Lab · Test row actions `bpzbAF-loY`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+10 more) |

**Lab · Test row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`bpzbAF-loY`](https://doop.design/c/LQFIZlhE35?frame=bpzbAF-loY) | Lab · Test row actions | light | canon | `/lab/tests` → LabTestLive.Index | — | [.lk] closes overlay<br>[.lk] opens Lab · Edit test `xOFNLJ6gpC` |

**Lab · Transaction actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`00v8gxaGGq`](https://doop.design/c/LQFIZlhE35?frame=00v8gxaGGq) | Lab · Transaction actions | light | canon | `/lab/transactions` → EarningsLive :lab | — | [.lk] closes overlay<br>[.lk] opens Lab · Payment receipt `VRY0p3ZE2z`<br>[.lk] opens Lab · Refund payment `5kI8h3aBwo`<br>[.lk] → Lab · Order detail · samples `LYzxIpGTSt` |

**Lab · Transaction detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`45FlJvpVyi`](https://doop.design/c/LQFIZlhE35?frame=45FlJvpVyi) | Lab · Transaction detail | light | canon | `/lab/transactions/:id` → EarningsLive :lab_show | done | "(unlabelled)" opens Lab · Payment receipt `VRY0p3ZE2z`<br>"(unlabelled)" opens Lab · Transaction actions `00v8gxaGGq`<br>"Close" closes overlay<br>"LO-2026-0317" → Lab · Order detail · samples `LYzxIpGTSt` |

**Lab · Transactions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Pef-1fqHs4`](https://doop.design/c/LQFIZlhE35?frame=Pef-1fqHs4) | Lab · Transactions | light | canon | `/lab/transactions` → EarningsLive :lab | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Transactions · date range `MC_1GL3a94`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+10 more) |
| [`MC_1GL3a94`](https://doop.design/c/LQFIZlhE35?frame=MC_1GL3a94) | Lab · Transactions · date range | light | canon | `/lab/transactions` → EarningsLive :lab | done | [.lk] closes overlay |
| [`DnuQVVOIuE`](https://doop.design/c/LQFIZlhE35?frame=DnuQVVOIuE) | Lab · Transactions · refunded | light | canon | `/lab/transactions` → EarningsLive :lab | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Lab · Transactions · date range `MC_1GL3a94`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s` (+10 more) |


### 3.5 Org, admin, team, API keys, TNT (113 frames, 59 flows)

**Org · API keys**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Wymc1OcGAx`](https://doop.design/c/LQFIZlhE35?frame=Wymc1OcGAx) | Org · API keys | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] opens Org · Clear API key `9a056M-Yir`<br>[.lk] → Org · API keys · adding TNT key `Kt5nPKwiu2`<br>[.lk] → Org · API keys · replacing GS1 key `naaWbccXBO`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_` (+4 more) |
| [`ZkVNOumC9w`](https://doop.design/c/LQFIZlhE35?frame=ZkVNOumC9w) | Org · API keys · no keys yet | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · API keys · adding TNT key `Kt5nPKwiu2`<br>[.lk] → Org · API keys · replacing GS1 key `naaWbccXBO`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_`<br>[.lk] → Org · Suppliers `OzelvYK3yA` (+3 more) |
| [`Kt5nPKwiu2`](https://doop.design/c/LQFIZlhE35?frame=Kt5nPKwiu2) | Org · API keys · adding TNT key | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · API keys · key saved `28Gy0LUyw-`<br>[.lk] → Org · API keys · no keys yet `ZkVNOumC9w`<br>[.lk] → Org · API keys · replacing GS1 key `naaWbccXBO`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_` (+4 more) |
| [`naaWbccXBO`](https://doop.design/c/LQFIZlhE35?frame=naaWbccXBO) | Org · API keys · replacing GS1 key | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] opens Org · Clear API key `9a056M-Yir`<br>[.lk] → Org · API keys `Wymc1OcGAx`<br>[.lk] → Org · API keys · adding TNT key `Kt5nPKwiu2`<br>[.lk] → Org · API keys · key saved `28Gy0LUyw-`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx` (+5 more) |
| [`ldt0X9c853`](https://doop.design/c/LQFIZlhE35?frame=ldt0X9c853) | Org · API keys · dark | dark | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] opens Org · Clear API key · dark `2oBHtPAwc_`<br>[.lk] → Org · API keys · adding TNT key `Kt5nPKwiu2`<br>[.lk] → Org · API keys · replacing GS1 key `naaWbccXBO`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_` (+4 more) |
| [`28Gy0LUyw-`](https://doop.design/c/LQFIZlhE35?frame=28Gy0LUyw-) | Org · API keys · key saved | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] opens Org · Clear API key `9a056M-Yir`<br>[.lk] → Org · API keys · adding TNT key `Kt5nPKwiu2`<br>[.lk] → Org · API keys · replacing GS1 key `naaWbccXBO`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_` (+4 more) |

**Org · Add item**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zlnJOqaCJ2`](https://doop.design/c/LQFIZlhE35?frame=zlnJOqaCJ2) | Org · Add item | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | [.lk] closes overlay<br>[.lk] opens Item details `gCMI-5oDzE`<br>[.lk] opens Org · Add item · new product `5mYf4LJWPD`<br>[.lk] opens Org · Add item · new supplier `-ihp-A1mBi`<br>[.lk] → Org · Receive inventory `C2qqpiyP9-` |
| [`5mYf4LJWPD`](https://doop.design/c/LQFIZlhE35?frame=5mYf4LJWPD) | Org · Add item · new product | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | [.lk] closes overlay<br>[.lk] opens Org · Add item `zlnJOqaCJ2` |
| [`-ihp-A1mBi`](https://doop.design/c/LQFIZlhE35?frame=-ihp-A1mBi) | Org · Add item · new supplier | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | [.lk] closes overlay<br>[.lk] opens Org · Add item `zlnJOqaCJ2` |

**Org · Add product**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ebFMw2ujwl`](https://doop.design/c/LQFIZlhE35?frame=ebFMw2ujwl) | Org · Add product · GTIN lookup | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Add product · details `P1YyR3c2zD` |
| [`P1YyR3c2zD`](https://doop.design/c/LQFIZlhE35?frame=P1YyR3c2zD) | Org · Add product · details | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Products · created `7T5Ej-s71E` |

**Org · Add site**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`3Sc9KGsLbu`](https://doop.design/c/LQFIZlhE35?frame=3Sc9KGsLbu) | Org · Add site · GLN verified | light | canon | `/org/sites[/new|/:id/edit]` → SiteLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Sites · created `sAWzRq9qay` |
| [`VNh-f2-P62`](https://doop.design/c/LQFIZlhE35?frame=VNh-f2-P62) | Org · Add site · GLN not found | light | canon | `/org/sites[/new|/:id/edit]` → SiteLive.Index | — | [.lk] closes overlay |

**Org · Add supplier**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`GExUc2gMoK`](https://doop.design/c/LQFIZlhE35?frame=GExUc2gMoK) | Org · Add supplier | light | canon | `/org/suppliers[/new|/:id/edit]` → SupplierLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Suppliers · created `1Q0pdnYpNX` |

**Org · Add to stock**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PlITdIuONs`](https://doop.design/c/LQFIZlhE35?frame=PlITdIuONs) | Org · Add to stock | light | canon | `/org/products/:id[/batches/new|/dispatch]` → ProductLive.Show | — | [.lk] closes overlay<br>[.lk] → Org · Product detail · stock added `G_OlReyO_J` |

**Org · Admin dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`voIG90Ocbf`](https://doop.design/c/LQFIZlhE35?frame=voIG90Ocbf) ★ | Org · Admin dashboard | light | canon | `/org/dashboard` → OrgDashboardLive | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_` (+6 more) |
| [`2t7LNnigQz`](https://doop.design/c/LQFIZlhE35?frame=2t7LNnigQz) | Org · Admin dashboard · dark | dark | canon | `/org/dashboard` → OrgDashboardLive | — | [.lk] opens Filter menu · Site `M733hm_3tb`<br>[.lk] opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>[.lk] opens Org · Filters and date range `ZZmLwye-Ku`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx`<br>[.lk] → Org · Sites `_YkjLU_zT_`<br>[.lk] → Org · Suppliers `OzelvYK3yA`<br>[.lk] → Org · TNT reporting `ZdiOKCCEg_` (+4 more) |

**Org · Batch detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8Q1WL7sVvp`](https://doop.design/c/LQFIZlhE35?frame=8Q1WL7sVvp) | Org · Batch detail | light | canon | `/org/batches/:id` → BatchLive.Show | — | "(unlabelled)" opens Org · Dispatch batch to site `G2_gAudVRD`<br>"(unlabelled)" opens Org · Print Data Matrix `kHfilJh18d`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+4 more) |

**Org · Clear API key**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`9a056M-Yir`](https://doop.design/c/LQFIZlhE35?frame=9a056M-Yir) | Org · Clear API key | light | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | [.lk] closes overlay<br>[.lk] → Org · API keys · no keys yet `ZkVNOumC9w` |
| [`2oBHtPAwc_`](https://doop.design/c/LQFIZlhE35?frame=2oBHtPAwc_) | Org · Clear API key · dark | dark | canon | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` → ApiKeysLive (APIKEYS-1) | done | [.lk] closes overlay<br>[.lk] → Org · API keys · dark `ldt0X9c853` |

**Org · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`07-8zNav0v`](https://doop.design/c/LQFIZlhE35?frame=07-8zNav0v) | Org · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | "Add product" opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>"Add site N" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"Dashboard" → Org · Admin dashboard `voIG90Ocbf`<br>"Esc" closes overlay<br>"Invite a teammate" opens Org · Invite staff `DQNLz1gSP4`<br>"Products" → Org · Products `U90FoygrHh`<br>"Receive stock R" → Org · Receive inventory `C2qqpiyP9-`<br>"Receiving" → Org · Receiving `2CQZtx0m1X`<br>"Requisitions" → Org · Requisition queue `9M_rqF3EVx`<br>"Sites" → Org · Sites `_YkjLU_zT_` (+1 more) |

**Org · Deactivate confirm**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2SgnW5Uol9`](https://doop.design/c/LQFIZlhE35?frame=2SgnW5Uol9) | Org · Deactivate confirm | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" → Org · Team · deactivated `F1AjINQBbP`<br>"Close" closes overlay |
| [`M0u047G0_t`](https://doop.design/c/LQFIZlhE35?frame=M0u047G0_t) | Org · Deactivate confirm · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · deactivated · dark `h1QyV_djKg` |

**Org · Dispatch batch to site**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`G2_gAudVRD`](https://doop.design/c/LQFIZlhE35?frame=G2_gAudVRD) | Org · Dispatch batch to site | light | canon | `/org/products/:id[/batches/new|/dispatch]` → ProductLive.Show | — | [.lk] closes overlay<br>[.lk] → Org · Product detail · dispatched `a4VMCbMZQJ` |

**Org · Disposals**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`O2D6yB49p7`](https://doop.design/c/LQFIZlhE35?frame=O2D6yB49p7) | Org · Disposals | light | canon | `/org/disposals` → InventoryDisposalQueueLive.Index | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Stock takes `Fe0oA1BIfd` |

**Org · Edit team member**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`yPDN9VJLDO`](https://doop.design/c/LQFIZlhE35?frame=yPDN9VJLDO) | Org · Edit team member | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Org · Deactivate confirm `2SgnW5Uol9`<br>"(unlabelled)" → Org · Team · updated `Z3khDQ-YI3`<br>"Close" closes overlay |
| [`NedbrC0gje`](https://doop.design/c/LQFIZlhE35?frame=NedbrC0gje) | Org · Edit team member · invited | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Deactivate confirm `2SgnW5Uol9`<br>[.lk] → Org · Team · updated `Z3khDQ-YI3` |
| [`WKjqxreB-S`](https://doop.design/c/LQFIZlhE35?frame=WKjqxreB-S) | Org · Edit team member · admin (you) | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · updated `Z3khDQ-YI3` |
| [`BoCBydTazK`](https://doop.design/c/LQFIZlhE35?frame=BoCBydTazK) | Org · Edit team member · inactive | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · updated `Z3khDQ-YI3` |
| [`wuYjejg5y0`](https://doop.design/c/LQFIZlhE35?frame=wuYjejg5y0) | Org · Edit team member · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Deactivate confirm · dark `M0u047G0_t`<br>[.lk] → Org · Team · dark `hJ1Mh7LATb` |
| [`atutxIdxzw`](https://doop.design/c/LQFIZlhE35?frame=atutxIdxzw) | Org · Edit team member · invited · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Deactivate confirm · dark `M0u047G0_t`<br>[.lk] → Org · Team · dark `hJ1Mh7LATb` |
| [`waSN0oUASt`](https://doop.design/c/LQFIZlhE35?frame=waSN0oUASt) | Org · Edit team member · admin (you) · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · dark `hJ1Mh7LATb` |
| [`P6mOUHvaAl`](https://doop.design/c/LQFIZlhE35?frame=P6mOUHvaAl) | Org · Edit team member · inactive · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · dark `hJ1Mh7LATb` |

**Org · Filters and date range**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ZZmLwye-Ku`](https://doop.design/c/LQFIZlhE35?frame=ZZmLwye-Ku) | Org · Filters and date range | light | canon | `/org/dashboard` → OrgDashboardLive | — | [.lk] closes overlay |

**Org · Fulfill requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`muEbyHxoXB`](https://doop.design/c/LQFIZlhE35?frame=muEbyHxoXB) | Org · Fulfill requisition | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Requisitions · dispatched `hLNbpWQx_q` |

**Org · Goods receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`aTuOrvCy4u`](https://doop.design/c/LQFIZlhE35?frame=aTuOrvCy4u) | Org · Goods receipt | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | "(unlabelled)" opens Download ready `zkycQlzsjO`<br>"(unlabelled)" opens Print `d687xWcrBC`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+4 more) |

**Org · Import products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8Y5PKREa6b`](https://doop.design/c/LQFIZlhE35?frame=8Y5PKREa6b) | Org · Import products · upload | light | canon | `/org/products/import` → ProductLive.Import | — | "(unlabelled)" opens Download ready `zkycQlzsjO`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · map columns `y0ei0hPW3l`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+6 more) |
| [`y0ei0hPW3l`](https://doop.design/c/LQFIZlhE35?frame=y0ei0hPW3l) | Org · Import products · map columns | light | canon | `/org/products/import` → ProductLive.Import | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · review `YjpcXimA0V`<br>"(unlabelled)" → Org · Import products · upload `8Y5PKREa6b`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+4 more) |
| [`YjpcXimA0V`](https://doop.design/c/LQFIZlhE35?frame=YjpcXimA0V) | Org · Import products · review | light | canon | `/org/products/import` → ProductLive.Import | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · map columns `y0ei0hPW3l`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products · imported `PFWPVocsJO`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+4 more) |

**Org · Invite staff**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`DQNLz1gSP4`](https://doop.design/c/LQFIZlhE35?frame=DQNLz1gSP4) | Org · Invite staff | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" → Org · Team · invite sent `oxV_PIz1td`<br>"Close" closes overlay |
| [`bCEk08BuY1`](https://doop.design/c/LQFIZlhE35?frame=bCEk08BuY1) | Org · Invite staff · no role yet | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · invite sent `oxV_PIz1td` |
| [`P_17R-JE3z`](https://doop.design/c/LQFIZlhE35?frame=P_17R-JE3z) | Org · Invite staff · admin | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · invite sent `oxV_PIz1td` |
| [`pjA5e3tWBR`](https://doop.design/c/LQFIZlhE35?frame=pjA5e3tWBR) | Org · Invite staff · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Team · dark `hJ1Mh7LATb` |

**Org · Organization settings**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`su8eaSdNu-`](https://doop.design/c/LQFIZlhE35?frame=su8eaSdNu-) | Org · Organization settings | light | canon | `/org/settings` → OrganizationSettingsLive | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings · saved `wvo1WwnBJ0`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9`<br>"(unlabelled)" → Org · Transactions `DSjQ_Epu5w` (+1 more) |
| [`wvo1WwnBJ0`](https://doop.design/c/LQFIZlhE35?frame=wvo1WwnBJ0) | Org · Organization settings · saved | light | canon | `/org/settings` → OrganizationSettingsLive | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings · saved `wvo1WwnBJ0`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9`<br>"(unlabelled)" → Org · Transactions `DSjQ_Epu5w` (+1 more) |

**Org · Payment receipt**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Oh4IwFJvUg`](https://doop.design/c/LQFIZlhE35?frame=Oh4IwFJvUg) | Org · Payment receipt | light | canon | `/org/earnings` → EarningsLive :index | — | [.lk] closes overlay<br>[.lk] opens Print `d687xWcrBC` |

**Org · Print Data Matrix**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`kHfilJh18d`](https://doop.design/c/LQFIZlhE35?frame=kHfilJh18d) | Org · Print Data Matrix | light | canon | `/org/batches/:id (print)` → BatchLive.Show | — | [.lk] closes overlay |

**Org · Product detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`a8lUVVHA5V`](https://doop.design/c/LQFIZlhE35?frame=a8lUVVHA5V) | Org · Product detail | light | canon | `/org/products/:id[/batches/new|/dispatch]` → ProductLive.Show | — | "(unlabelled)" opens Org · Add product · details `P1YyR3c2zD`<br>"(unlabelled)" opens Org · Add to stock `PlITdIuONs`<br>"(unlabelled)" opens Org · Dispatch batch to site `G2_gAudVRD`<br>"(unlabelled)" opens Org · Print Data Matrix `kHfilJh18d`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+11 more) |
| [`G_OlReyO_J`](https://doop.design/c/LQFIZlhE35?frame=G_OlReyO_J) | Org · Product detail · stock added | light | canon | `/org/products/:id[/batches/new|/dispatch]` → ProductLive.Show | — | "(unlabelled)" opens Org · Add product · details `P1YyR3c2zD`<br>"(unlabelled)" opens Org · Add to stock `PlITdIuONs`<br>"(unlabelled)" opens Org · Dispatch batch to site `G2_gAudVRD`<br>"(unlabelled)" opens Org · Print Data Matrix `kHfilJh18d`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+11 more) |
| [`a4VMCbMZQJ`](https://doop.design/c/LQFIZlhE35?frame=a4VMCbMZQJ) | Org · Product detail · dispatched | light | canon | `/org/products/:id[/batches/new|/dispatch]` → ProductLive.Show | — | "(unlabelled)" opens Org · Add product · details `P1YyR3c2zD`<br>"(unlabelled)" opens Org · Add to stock `PlITdIuONs`<br>"(unlabelled)" opens Org · Dispatch batch to site `G2_gAudVRD`<br>"(unlabelled)" opens Org · Print Data Matrix `kHfilJh18d`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+11 more) |

**Org · Product row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tuBuNxEu2S`](https://doop.design/c/LQFIZlhE35?frame=tuBuNxEu2S) | Org · Product row actions | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Add product · details `P1YyR3c2zD`<br>[.lk] opens Org · Add to stock `PlITdIuONs` |

**Org · Products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`U90FoygrHh`](https://doop.design/c/LQFIZlhE35?frame=U90FoygrHh) | Org · Products | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Flags `hsTdh4fT_Z`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>"(unlabelled)" opens Org · Product row actions `tuBuNxEu2S`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · upload `8Y5PKREa6b`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X` (+18 more) |
| [`1bDRkfghe0`](https://doop.design/c/LQFIZlhE35?frame=1bDRkfghe0) | Org · Products · first product | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Flags `hsTdh4fT_Z`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · upload `8Y5PKREa6b`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_` (+5 more) |
| [`7T5Ej-s71E`](https://doop.design/c/LQFIZlhE35?frame=7T5Ej-s71E) | Org · Products · created | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Flags `hsTdh4fT_Z`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>"(unlabelled)" opens Org · Product row actions `tuBuNxEu2S`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · upload `8Y5PKREa6b`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products · created `7T5Ej-s71E`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X` (+17 more) |
| [`PFWPVocsJO`](https://doop.design/c/LQFIZlhE35?frame=PFWPVocsJO) | Org · Products · imported | light | canon | `/org/products[/new|/:id/edit]` → ProductLive.Index | — | "(unlabelled)" opens Filter menu · Category `RBA4UYrkXr`<br>"(unlabelled)" opens Filter menu · Flags `hsTdh4fT_Z`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>"(unlabelled)" opens Org · Product row actions `tuBuNxEu2S`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Import products · upload `8Y5PKREa6b`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products · imported `PFWPVocsJO`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X` (+17 more) |

**Org · Receive inventory**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`C2qqpiyP9-`](https://doop.design/c/LQFIZlhE35?frame=C2qqpiyP9-) | Org · Receive inventory | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | "(unlabelled)" opens Org · Add item `zlnJOqaCJ2`<br>"(unlabelled)" opens Remove item `5mZQ-49VPF`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Receiving · received `pCRl3tBxpV`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+6 more) |

**Org · Receiving**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2CQZtx0m1X`](https://doop.design/c/LQFIZlhE35?frame=2CQZtx0m1X) | Org · Receiving | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | "(unlabelled)" opens Filter menu · Received `X42vxHfarW`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receive inventory `C2qqpiyP9-`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+9 more) |
| [`pCRl3tBxpV`](https://doop.design/c/LQFIZlhE35?frame=pCRl3tBxpV) | Org · Receiving · received | light | canon | `MISSING (/org/receiving)` → MISSING — no org receiving route | — | "(unlabelled)" opens Filter menu · Received `X42vxHfarW`<br>"(unlabelled)" opens Filter menu · Warehouse `qtRoKxMMu1`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receive inventory `C2qqpiyP9-`<br>"(unlabelled)" → Org · Receiving · received `pCRl3tBxpV`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+9 more) |

**Org · Refund payment**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fi0pTx-1f7`](https://doop.design/c/LQFIZlhE35?frame=fi0pTx-1f7) | Org · Refund payment | light | canon | `/org/earnings` → EarningsLive :index | — | [.lk] closes overlay<br>[.lk] → Org · Transactions · refunded `gTIcNKn1Ie` |

**Org · Reject requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`WIRHaj6N90`](https://doop.design/c/LQFIZlhE35?frame=WIRHaj6N90) | Org · Reject requisition | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | [.lk] closes overlay<br>[.lk] → Org · Requisitions · rejected `Z2-QOnLxHN` |

**Org · Requested between**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`dIPT7cCITO`](https://doop.design/c/LQFIZlhE35?frame=dIPT7cCITO) | Org · Requested between | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | [.lk] closes overlay |

**Org · Requisition detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`nzi5p4-AI5`](https://doop.design/c/LQFIZlhE35?frame=nzi5p4-AI5) | Org · Requisition detail | light | canon | `/org/requisitions/:id` → RequisitionQueueLive.Show | — | "(unlabelled)" opens Org · Fulfill requisition `muEbyHxoXB`<br>"(unlabelled)" opens Org · Review requisition `vMFVABkZbL`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+9 more) |

**Org · Requisition queue**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`9M_rqF3EVx`](https://doop.design/c/LQFIZlhE35?frame=9M_rqF3EVx) | Org · Requisition queue | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_` (+15 more) |

**Org · Requisition row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Sjnr9gxKcg`](https://doop.design/c/LQFIZlhE35?frame=Sjnr9gxKcg) | Org · Requisition row actions | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | [.lk] opens Org · Fulfill requisition `muEbyHxoXB`<br>[.lk] opens Org · Reject requisition `WIRHaj6N90`<br>[.lk] opens Org · Review requisition `vMFVABkZbL` |

**Org · Requisitions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`igIKdkIMxW`](https://doop.design/c/LQFIZlhE35?frame=igIKdkIMxW) | Org · Requisitions · reviewed | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_`<br>"(unlabelled)" → Org · Requisitions · Pending `zBzFGblRnK` (+15 more) |
| [`Z2-QOnLxHN`](https://doop.design/c/LQFIZlhE35?frame=Z2-QOnLxHN) | Org · Requisitions · rejected | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_`<br>"(unlabelled)" → Org · Requisitions · Pending `zBzFGblRnK` (+15 more) |
| [`hLNbpWQx_q`](https://doop.design/c/LQFIZlhE35?frame=hLNbpWQx_q) | Org · Requisitions · dispatched | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_`<br>"(unlabelled)" → Org · Requisitions · Pending `zBzFGblRnK` (+15 more) |
| [`zBzFGblRnK`](https://doop.design/c/LQFIZlhE35?frame=zBzFGblRnK) | Org · Requisitions · Pending | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_` (+10 more) |
| [`0TOJ-OerfR`](https://doop.design/c/LQFIZlhE35?frame=0TOJ-OerfR) | Org · Requisitions · Approved | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_` (+9 more) |
| [`LHl7qlHyR_`](https://doop.design/c/LQFIZlhE35?frame=LHl7qlHyR_) | Org · Requisitions · Fulfilled | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_` (+9 more) |
| [`xYILh6bLB1`](https://doop.design/c/LQFIZlhE35?frame=xYILh6bLB1) | Org · Requisitions · Rejected | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Requested between `dIPT7cCITO`<br>"(unlabelled)" opens Org · Requisition row actions `Sjnr9gxKcg`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Requisitions · Approved `0TOJ-OerfR`<br>"(unlabelled)" → Org · Requisitions · Fulfilled `LHl7qlHyR_` (+9 more) |

**Org · Review requisition**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`vMFVABkZbL`](https://doop.design/c/LQFIZlhE35?frame=vMFVABkZbL) | Org · Review requisition | light | canon | `/org/requisitions | /org/requisitions/:id/review | /org/requisitions/:id/reject | /org/requisitions/:id/fulfill` → RequisitionQueueLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Reject requisition `WIRHaj6N90`<br>[.lk] → Org · Requisitions · reviewed `igIKdkIMxW` |

**Org · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`p_lyQcEmhk`](https://doop.design/c/LQFIZlhE35?frame=p_lyQcEmhk) | Org · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>[.pr] opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>[.pr] opens Org · Invite staff `DQNLz1gSP4`<br>[.pr] → Org · Product detail `a8lUVVHA5V`<br>[.pr] → Org · Requisition detail `nzi5p4-AI5`<br>[.pr] → Org · Site dashboard `wMZFC8udDO` |
| [`RhKDiFO6f_`](https://doop.design/c/LQFIZlhE35?frame=RhKDiFO6f_) | Org · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Org · Product detail `a8lUVVHA5V`<br>[.pr] → Org · Requisition detail `nzi5p4-AI5`<br>[.pr] → Org · Site dashboard `wMZFC8udDO` |

**Org · Site dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`wMZFC8udDO`](https://doop.design/c/LQFIZlhE35?frame=wMZFC8udDO) | Org · Site dashboard | light | canon | `/org/sites/:id` → SiteLive.Show | — | "(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+10 more) |

**Org · Site row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2eBvlpe3ly`](https://doop.design/c/LQFIZlhE35?frame=2eBvlpe3ly) | Org · Site row actions | light | canon | `/org/sites[/new|/:id/edit]` → SiteLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Add site · GLN verified `3Sc9KGsLbu` |

**Org · Sites**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`_YkjLU_zT_`](https://doop.design/c/LQFIZlhE35?frame=_YkjLU_zT_) | Org · Sites | light | canon | `/org/sites[/new|/:id/edit]` → SiteLive.Index | — | "(unlabelled)" opens Filter menu · Activity `GNR8ZG0WQa`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Site row actions `2eBvlpe3ly`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_` (+12 more) |
| [`sAWzRq9qay`](https://doop.design/c/LQFIZlhE35?frame=sAWzRq9qay) | Org · Sites · created | light | canon | `/org/sites[/new|/:id/edit]` → SiteLive.Index | — | "(unlabelled)" opens Filter menu · Activity `GNR8ZG0WQa`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Site row actions `2eBvlpe3ly`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites · created `sAWzRq9qay` (+11 more) |

**Org · Stock takes**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`Fe0oA1BIfd`](https://doop.design/c/LQFIZlhE35?frame=Fe0oA1BIfd) | Org · Stock takes | light | canon | `/org/stock-takes` → StockTakeQueueLive.Index | — | "(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Disposals `O2D6yB49p7`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` |

**Org · Supplier row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`YE-Ck_dDLy`](https://doop.design/c/LQFIZlhE35?frame=YE-Ck_dDLy) | Org · Supplier row actions | light | canon | `/org/suppliers[/new|/:id/edit]` → SupplierLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Add supplier `GExUc2gMoK` |

**Org · Suppliers**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`OzelvYK3yA`](https://doop.design/c/LQFIZlhE35?frame=OzelvYK3yA) | Org · Suppliers | light | canon | `/org/suppliers[/new|/:id/edit]` → SupplierLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add supplier `GExUc2gMoK`<br>"(unlabelled)" opens Org · Supplier row actions `YE-Ck_dDLy`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+4 more) |
| [`1Q0pdnYpNX`](https://doop.design/c/LQFIZlhE35?frame=1Q0pdnYpNX) | Org · Suppliers · created | light | canon | `/org/suppliers[/new|/:id/edit]` → SupplierLive.Index | — | "(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Add supplier `GExUc2gMoK`<br>"(unlabelled)" opens Org · Supplier row actions `YE-Ck_dDLy`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers · created `1Q0pdnYpNX` (+4 more) |

**Org · TNT event details**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`duj3-u6uPd`](https://doop.design/c/LQFIZlhE35?frame=duj3-u6uPd) | Org · TNT event details · Pending | light | canon | `/org/epcis` → DistributorEpcisLive (org portal) | — | "Close" closes overlay |
| [`34PdLETg5c`](https://doop.design/c/LQFIZlhE35?frame=34PdLETg5c) | Org · TNT event details · Sent | light | canon | `/org/epcis` → DistributorEpcisLive (org portal) | — | [span] closes overlay |

**Org · TNT reporting**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`ZdiOKCCEg_`](https://doop.design/c/LQFIZlhE35?frame=ZdiOKCCEg_) | Org · TNT reporting | light | canon | `/org/epcis` → DistributorEpcisLive (org portal) | — | "(unlabelled)" opens Org · TNT event details · Pending `duj3-u6uPd`<br>"(unlabelled)" opens TNT · Send event confirm `m-gTgjUcmi`<br>"(unlabelled)" opens TNT · Send pending now confirm `0OTimjfTsi`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+4 more) |
| [`IXtDUwcf_S`](https://doop.design/c/LQFIZlhE35?frame=IXtDUwcf_S) | Org · TNT reporting · Automatic | light | canon | `/org/epcis` → DistributorEpcisLive (org portal) | — | "(unlabelled)" opens Org · TNT event details · Sent `34PdLETg5c`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting · Automatic `IXtDUwcf_S`<br>"(unlabelled)" → Org · Team `lrsiMDnvg9` (+2 more) |

**Org · Team**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`lrsiMDnvg9`](https://doop.design/c/LQFIZlhE35?frame=lrsiMDnvg9) | Org · Team | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Filter menu · Role `5uprTqJznQ`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Invite staff `DQNLz1gSP4`<br>"(unlabelled)" opens Org · Team row actions `iZtnCpcAK5`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+12 more) |
| [`oxV_PIz1td`](https://doop.design/c/LQFIZlhE35?frame=oxV_PIz1td) | Org · Team · invite sent | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Filter menu · Role `5uprTqJznQ`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Invite staff `DQNLz1gSP4`<br>"(unlabelled)" opens Org · Team row actions `iZtnCpcAK5`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+12 more) |
| [`Z3khDQ-YI3`](https://doop.design/c/LQFIZlhE35?frame=Z3khDQ-YI3) | Org · Team · updated | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Filter menu · Role `5uprTqJznQ`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Invite staff `DQNLz1gSP4`<br>"(unlabelled)" opens Org · Team row actions `iZtnCpcAK5`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+12 more) |
| [`F1AjINQBbP`](https://doop.design/c/LQFIZlhE35?frame=F1AjINQBbP) | Org · Team · deactivated | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Filter menu · Role `5uprTqJznQ`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Invite staff `DQNLz1gSP4`<br>"(unlabelled)" opens Org · Team row actions `iZtnCpcAK5`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+12 more) |
| [`hJ1Mh7LATb`](https://doop.design/c/LQFIZlhE35?frame=hJ1Mh7LATb) | Org · Team · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Filter menu · Role `5uprTqJznQ`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Invite staff `DQNLz1gSP4`<br>"(unlabelled)" opens Org · Team row actions `iZtnCpcAK5`<br>"(unlabelled)" opens Org · Team row actions · inactive `_WNIkxsMWh`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X` (+13 more) |
| [`rt7EciPgt1`](https://doop.design/c/LQFIZlhE35?frame=rt7EciPgt1) | Org · Team · no matches | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | Afya Bora Health → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] opens Filter menu · Role `5uprTqJznQ`<br>[.lk] opens Filter menu · Site `M733hm_3tb`<br>[.lk] opens Filter menu · Status `TTXzDZPEWP`<br>[.lk] opens Org · Invite staff `DQNLz1gSP4`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh`<br>[.lk] → Org · Receiving `2CQZtx0m1X`<br>[.lk] → Org · Requisition queue `9M_rqF3EVx` (+5 more) |
| [`h1QyV_djKg`](https://doop.design/c/LQFIZlhE35?frame=h1QyV_djKg) | Org · Team · deactivated · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | Afya Bora Health → Org · Admin dashboard · dark `2t7LNnigQz`<br>[.lk] opens Filter menu · Role `5uprTqJznQ`<br>[.lk] opens Filter menu · Site `M733hm_3tb`<br>[.lk] opens Filter menu · Status `TTXzDZPEWP`<br>[.lk] opens Org · Invite staff · dark `pjA5e3tWBR`<br>[.lk] opens Org · Team row actions · dark `usg46YuulW`<br>[.lk] opens Org · Team row actions · inactive · dark `9QS4GQVnnG`<br>[.lk] → Org · Admin dashboard · dark `2t7LNnigQz`<br>[.lk] → Org · Organization settings `su8eaSdNu-`<br>[.lk] → Org · Products `U90FoygrHh` (+11 more) |

**Org · Team row actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`iZtnCpcAK5`](https://doop.design/c/LQFIZlhE35?frame=iZtnCpcAK5) | Org · Team row actions | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | "(unlabelled)" opens Org · Deactivate confirm `2SgnW5Uol9`<br>"(unlabelled)" opens Org · Edit team member `yPDN9VJLDO` |
| [`_WNIkxsMWh`](https://doop.design/c/LQFIZlhE35?frame=_WNIkxsMWh) | Org · Team row actions · inactive | light | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Edit team member · inactive `BoCBydTazK` |
| [`usg46YuulW`](https://doop.design/c/LQFIZlhE35?frame=usg46YuulW) | Org · Team row actions · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] opens Org · Deactivate confirm · dark `M0u047G0_t`<br>[.lk] opens Org · Edit team member · dark `wuYjejg5y0` |
| [`9QS4GQVnnG`](https://doop.design/c/LQFIZlhE35?frame=9QS4GQVnnG) | Org · Team row actions · inactive · dark | dark | canon | `/org/team[/new|/:id/edit]` → TeamLive.Index | — | [.lk] closes overlay<br>[.lk] opens Org · Edit team member · inactive · dark `P6mOUHvaAl` |

**Org · Transaction actions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`3DKqAH3VB8`](https://doop.design/c/LQFIZlhE35?frame=3DKqAH3VB8) | Org · Transaction actions | light | canon | `/org/earnings` → EarningsLive :index | — | [.lk] closes overlay<br>[.lk] opens Org · Payment receipt `Oh4IwFJvUg`<br>[.lk] opens Org · Refund payment `fi0pTx-1f7`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Org · Transaction detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tvMYqHud3S`](https://doop.design/c/LQFIZlhE35?frame=tvMYqHud3S) | Org · Transaction detail | light | canon | `/org/earnings` → EarningsLive :index | — | [.lk] closes overlay<br>[.lk] opens Org · Payment receipt `Oh4IwFJvUg`<br>[.lk] opens Org · Transaction actions `3DKqAH3VB8`<br>[.lk] → Pharmacy · Prescription detail `oBlQhsWTT7` |

**Org · Transactions**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`DSjQ_Epu5w`](https://doop.design/c/LQFIZlhE35?frame=DSjQ_Epu5w) | Org · Transactions | light | canon | `/org/earnings` → EarningsLive :index | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Transactions date range `53BedS4v4m`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+14 more) |
| [`gTIcNKn1Ie`](https://doop.design/c/LQFIZlhE35?frame=gTIcNKn1Ie) | Org · Transactions · refunded | light | canon | `/org/earnings` → EarningsLive :index | — | "(unlabelled)" opens Export CSV `2E9yucAGjQ`<br>"(unlabelled)" opens Filter menu · Method `gYpvtPDu1v`<br>"(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" opens Org · Transactions date range `53BedS4v4m`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx` (+14 more) |

**Org · Transactions date range**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`53BedS4v4m`](https://doop.design/c/LQFIZlhE35?frame=53BedS4v4m) | Org · Transactions date range | light | canon | `/org/earnings` → EarningsLive :index | — | [.lk] closes overlay |

**Platform · Audit activity**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2MEScH0sKV`](https://doop.design/c/LQFIZlhE35?frame=2MEScH0sKV) | Platform · Audit activity | light | canon | `/platform/audit` → PlatformAuditLive | — | "(unlabelled)" opens Filter menu · Date `2trt8GDgl8`<br>"(unlabelled)" opens Filter menu · Organization `ntkXbBL-C6`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl` |

**Platform · Command menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`6kqmSrYrj0`](https://doop.design/c/LQFIZlhE35?frame=6kqmSrYrj0) | Platform · Command menu | light | canon | `(shell) ⌘K command menu` → MISSING (verify global search hook) | — | Esc closes overlay<br>[.pr] → Platform · Audit activity `2MEScH0sKV`<br>[.pr] → Platform · Organizations `OPeL_8IxLl` |

**Platform · Dashboard**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`1SYxbLx8Fm`](https://doop.design/c/LQFIZlhE35?frame=1SYxbLx8Fm) | Platform · Dashboard | light | canon | `/platform` → PlatformDashboardLive | — | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"18 Nov, 09:58 Wanjiru Mwangi Afya Bora Health Invited brian@" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:12 Joseph Kamau Afya Bora Health Recorded results" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:31 Brian Mutua Kilimo Distributors Approved SH-20" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:42 Amina Otieno Afya Bora Health Dispensed RX-104" → Platform · Audit activity `2MEScH0sKV`<br>"Coast Diagnostics No audited activity in 12 days" → Platform · Organizations `OPeL_8IxLl`<br>"Mlimani Chemists No audited activity in 9 days" → Platform · Organizations `OPeL_8IxLl` |
| [`Rar-eyv7TH`](https://doop.design/c/LQFIZlhE35?frame=Rar-eyv7TH) | Platform · Dashboard · dark | dark | canon | `/platform` → PlatformDashboardLive | — | [.lk] → Platform · Audit activity `2MEScH0sKV`<br>[.lk] → Platform · Organizations `OPeL_8IxLl`<br>[.tg] → Platform · Sidebar collapsed · Dark `xQ8gu75RDf`<br>[tr] → Platform · Audit activity `2MEScH0sKV`<br>[tr] → Platform · Organizations `OPeL_8IxLl` |

**Platform · Organization detail**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5o7nNuRzYl`](https://doop.design/c/LQFIZlhE35?frame=5o7nNuRzYl) | Platform · Organization detail | light | canon | `MISSING (/platform/organizations[/:id])` → MISSING — no route | — | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"Back to Organizations" → Platform · Organizations `OPeL_8IxLl`<br>"Kisumu Medical Centre Pharmacy · Lab 6160012300039 18 Nov 20" → Platform · Audit activity `2MEScH0sKV`<br>"Nairobi CBD Pharmacy Pharmacy 6160012300015 18 Nov 2026" → Platform · Audit activity `2MEScH0sKV`<br>"Nakuru Town Pharmacy Pharmacy 6160012300046 18 Nov 2026" → Platform · Audit activity `2MEScH0sKV`<br>"Organizations" → Platform · Organizations `OPeL_8IxLl`<br>"Westlands Diagnostics Lab 6160012300022 18 Nov 2026" → Platform · Audit activity `2MEScH0sKV` |

**Platform · Organizations**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`OPeL_8IxLl`](https://doop.design/c/LQFIZlhE35?frame=OPeL_8IxLl) | Platform · Organizations | light | canon | `MISSING (/platform/organizations[/:id])` → MISSING — no route | — | "(unlabelled)" opens Filter menu · Activity `GNR8ZG0WQa`<br>"(unlabelled)" opens Filter menu · Status `TTXzDZPEWP`<br>"(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"Afya Bora Health Pharmacy · Lab 6 38 18 Nov 2026" → Platform · Organization detail `5o7nNuRzYl`<br>"Coast Diagnostics Lab 2 6 06 Nov 2026" → Platform · Organization detail `5o7nNuRzYl`<br>"Kilimo Distributors Ltd Distribution 2 14 18 Nov 2026" → Platform · Organization detail `5o7nNuRzYl`<br>"Lancet Diagnostics Lab 4 22 18 Nov 2026" → Platform · Organization detail `5o7nNuRzYl`<br>"MedPoint Pharmacy Pharmacy 3 11 17 Nov 2026" → Platform · Organization detail `5o7nNuRzYl`<br>"Mlimani Chemists Pharmacy 1 3 09 Nov 2026" → Platform · Organization detail `5o7nNuRzYl` (+1 more) |

**Platform · Recalls**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`FSi8DNwuSY`](https://doop.design/c/LQFIZlhE35?frame=FSi8DNwuSY) | Platform · Recalls | light | canon | `/platform/recalls` → PlatformRecallLive | — | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl` |

**Platform · Search**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5RcyWy41dg`](https://doop.design/c/LQFIZlhE35?frame=5RcyWy41dg) | Platform · Search | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Platform · Audit activity `2MEScH0sKV`<br>[.pr] → Platform · Organization detail `5o7nNuRzYl`<br>[.pr] → Platform · Organizations `OPeL_8IxLl` |
| [`H2ErF6VkIY`](https://doop.design/c/LQFIZlhE35?frame=H2ErF6VkIY) | Platform · Search · results | light | canon | `(shell) global search` → Layouts · td-global-search | — | Esc closes overlay<br>[.pr] → Platform · Audit activity `2MEScH0sKV`<br>[.pr] → Platform · Organization detail `5o7nNuRzYl` |

**TNT · Send event confirm**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`m-gTgjUcmi`](https://doop.design/c/LQFIZlhE35?frame=m-gTgjUcmi) | TNT · Send event confirm | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | [span] closes overlay |

**TNT · Send pending now confirm**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`0OTimjfTsi`](https://doop.design/c/LQFIZlhE35?frame=0OTimjfTsi) | TNT · Send pending now confirm | light | canon | `/manufacturer/epcis (+ /org/epcis, /distributor/epcis)` → ManufacturerEpcisLive / DistributorEpcisLive | — | [span] closes overlay |


### 3.6 Auth and signup (29 frames, 19 flows)

**Auth · Accept invite**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fbPy5QWJp3`](https://doop.design/c/LQFIZlhE35?frame=fbPy5QWJp3) | Auth · Accept invite | light | canon | `/invites/:token` → AcceptInviteLive | — | Expired link → Auth · Invalid invite `fVLfnbTWpZ`<br>[.lk] → Auth · Log in `oYsDYjktDQ` |

**Auth · Choose a new password**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`SmQvGu5eAA`](https://doop.design/c/LQFIZlhE35?frame=SmQvGu5eAA) | Auth · Choose a new password | light | canon | `/reset-password[/:token]` → PasswordResetController | — | Back to log in → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Log in `oYsDYjktDQ` |

**Auth · Choose a site**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`pG6LqCfcwP`](https://doop.design/c/LQFIZlhE35?frame=pG6LqCfcwP) | Auth · Choose a site | light | canon | `/login → site picker` → SessionController (verify) | — | Log in with another account → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.srow] → Org · Admin dashboard `voIG90Ocbf`<br>[.srow] → Pharma-lab · Site dashboard `0xQtYRdBP7` |

**Auth · Confirm your email**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`HILJpytHOT`](https://doop.design/c/LQFIZlhE35?frame=HILJpytHOT) | Auth · Confirm your email | light | canon | `/confirm-email` → ConfirmEmailLive | — | Log out → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Confirmation resent `2_xpgW-wlF`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Onboarding · Workspace ready `v1kqSDbicp` |

**Auth · Confirmation resent**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2_xpgW-wlF`](https://doop.design/c/LQFIZlhE35?frame=2_xpgW-wlF) | Auth · Confirmation resent | light | canon | `/confirm-email` → ConfirmEmailLive | — | Log out → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Confirmation resent `2_xpgW-wlF`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Onboarding · Workspace ready `v1kqSDbicp` |

**Auth · Invalid invite**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`fVLfnbTWpZ`](https://doop.design/c/LQFIZlhE35?frame=fVLfnbTWpZ) | Auth · Invalid invite | light | canon | `/invites/:token` → AcceptInviteLive | — | [.lk] → Auth · Log in `oYsDYjktDQ` |

**Auth · Log in**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`oYsDYjktDQ`](https://doop.design/c/LQFIZlhE35?frame=oYsDYjktDQ) ★ | Auth · Log in | light | canon | `/login` → SessionController :new | — | "(unlabelled)" → Auth · Choose a site `pG6LqCfcwP`<br>"(unlabelled)" → Sign up · Organization `CLsksg2sae`<br>"Create an account" → Sign up · Organization `CLsksg2sae`<br>"Forgot password?" → Auth · Reset password `GvVnAtQkik`<br>"Invite link" → Auth · Accept invite `fbPy5QWJp3`<br>"Org admin" → Org · Admin dashboard `voIG90Ocbf`<br>"Pharma-lab" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"Wrong password" → Auth · Log in error `zq-cSnBhZm` |

**Auth · Log in error**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zq-cSnBhZm`](https://doop.design/c/LQFIZlhE35?frame=zq-cSnBhZm) | Auth · Log in error | light | canon | `/login` → SessionController :new | — | Create an account → Sign up · Organization `CLsksg2sae`<br>Distributor → Distributor · Dashboard `8OjVBGuJw2`<br>Forgot password? → Auth · Reset password `GvVnAtQkik`<br>Lab technician → Lab · Dashboard `lDrhCsUsP3`<br>Org admin → Org · Admin dashboard `voIG90Ocbf`<br>Pharma-lab → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>Pharmacist → Pharmacy · Dashboard `q2Wvk4Umn8`<br>Platform → Platform · Dashboard `1SYxbLx8Fm`<br>[.lk] → Auth · Choose a site `pG6LqCfcwP`<br>[.lk] → Sign up · Organization `CLsksg2sae` |

**Auth · Reset link sent**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`tRNixmPXUk`](https://doop.design/c/LQFIZlhE35?frame=tRNixmPXUk) | Auth · Reset link sent | light | canon | `/reset-password[/:token]` → PasswordResetController | — | Back to log in → Auth · Log in `oYsDYjktDQ`<br>Open the reset link → Auth · Choose a new password `SmQvGu5eAA`<br>Use a different email → Auth · Reset password `GvVnAtQkik`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Reset link sent `tRNixmPXUk` |

**Auth · Reset password**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`GvVnAtQkik`](https://doop.design/c/LQFIZlhE35?frame=GvVnAtQkik) | Auth · Reset password | light | canon | `/reset-password[/:token]` → PasswordResetController | — | Back to log in → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Reset link sent `tRNixmPXUk` |

**Onboarding · Primary site**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`uVN_MBMLkT`](https://doop.design/c/LQFIZlhE35?frame=uVN_MBMLkT) | Onboarding · Primary site | light | canon | `/onboarding` → OnboardingLive | — | [.it] → Onboarding · Primary site `uVN_MBMLkT`<br>[.it] → Onboarding · Products `DgQOClHH9A`<br>[.it] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.it] → Onboarding · Team `PCwYGGREAA`<br>[.lk] opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>[.lk] → Onboarding · Products `DgQOClHH9A`<br>[.lk] → Onboarding · Workspace ready `v1kqSDbicp`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf` |

**Onboarding · Products**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`DgQOClHH9A`](https://doop.design/c/LQFIZlhE35?frame=DgQOClHH9A) | Onboarding · Products | light | canon | `/onboarding` → OnboardingLive | — | [.it] → Onboarding · Primary site `uVN_MBMLkT`<br>[.it] → Onboarding · Products `DgQOClHH9A`<br>[.it] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.it] → Onboarding · Team `PCwYGGREAA`<br>[.lk] opens Org · Add product · GTIN lookup `ebFMw2ujwl`<br>[.lk] → Onboarding · Primary site `uVN_MBMLkT`<br>[.lk] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf` |

**Onboarding · Suppliers**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`BiJ52LwtJR`](https://doop.design/c/LQFIZlhE35?frame=BiJ52LwtJR) | Onboarding · Suppliers | light | canon | `/onboarding` → OnboardingLive | — | [.it] → Onboarding · Primary site `uVN_MBMLkT`<br>[.it] → Onboarding · Products `DgQOClHH9A`<br>[.it] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.it] → Onboarding · Team `PCwYGGREAA`<br>[.lk] opens Org · Add supplier `GExUc2gMoK`<br>[.lk] → Onboarding · Products `DgQOClHH9A`<br>[.lk] → Onboarding · Team `PCwYGGREAA`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf` |

**Onboarding · Team**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PCwYGGREAA`](https://doop.design/c/LQFIZlhE35?frame=PCwYGGREAA) | Onboarding · Team | light | canon | `/onboarding` → OnboardingLive | — | [.it] → Onboarding · Primary site `uVN_MBMLkT`<br>[.it] → Onboarding · Products `DgQOClHH9A`<br>[.it] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.it] → Onboarding · Team `PCwYGGREAA`<br>[.lk] opens Org · Invite staff `DQNLz1gSP4`<br>[.lk] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf` |

**Onboarding · Workspace ready**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`v1kqSDbicp`](https://doop.design/c/LQFIZlhE35?frame=v1kqSDbicp) | Onboarding · Workspace ready | light | canon | `/onboarding` → OnboardingLive | — | [.it] → Onboarding · Primary site `uVN_MBMLkT`<br>[.it] → Onboarding · Products `DgQOClHH9A`<br>[.it] → Onboarding · Suppliers `BiJ52LwtJR`<br>[.it] → Onboarding · Team `PCwYGGREAA`<br>[.lk] → Onboarding · Primary site `uVN_MBMLkT`<br>[.lk] → Org · Admin dashboard `voIG90Ocbf` |

**Sign up · Administrator**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`1P50qYkBt1`](https://doop.design/c/LQFIZlhE35?frame=1P50qYkBt1) | Sign up · Administrator | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | "(unlabelled)" → Auth · Confirm your email `HILJpytHOT`<br>"(unlabelled)" → Auth · Log in `oYsDYjktDQ`<br>"(unlabelled)" → Sign up · Main location `_DHaSIu5T5` |

**Sign up · GS1 account**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`VwxTOORndK`](https://doop.design/c/LQFIZlhE35?frame=VwxTOORndK) | Sign up · GS1 account | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | Key not accepted → Sign up · GS1 account · key not accepted `4F6aZWhPLl`<br>No company name → Sign up · GS1 account · no company name `HSXX62zpxA`<br>Registry unavailable → Sign up · GS1 account · registry unavailable `G_PnFvidFs`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · checking `OV5Tdr9ydZ`<br>[.lk] → Sign up · Organization `CLsksg2sae` |
| [`OV5Tdr9ydZ`](https://doop.design/c/LQFIZlhE35?frame=OV5Tdr9ydZ) | Sign up · GS1 account · checking | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · Organization `CLsksg2sae`<br>[div] → Sign up · GS1 account · verified `2XUobNcrNt` |
| [`2XUobNcrNt`](https://doop.design/c/LQFIZlhE35?frame=2XUobNcrNt) | Sign up · GS1 account · verified | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · Main location · choose GLN `2N_Kzpr0VC`<br>[.lk] → Sign up · Organization `CLsksg2sae` |
| [`4F6aZWhPLl`](https://doop.design/c/LQFIZlhE35?frame=4F6aZWhPLl) | Sign up · GS1 account · key not accepted | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · checking `OV5Tdr9ydZ`<br>[.lk] → Sign up · Organization `CLsksg2sae` |
| [`G_PnFvidFs`](https://doop.design/c/LQFIZlhE35?frame=G_PnFvidFs) | Sign up · GS1 account · registry unavailable | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · checking `OV5Tdr9ydZ`<br>[.lk] → Sign up · Organization `CLsksg2sae` |
| [`HSXX62zpxA`](https://doop.design/c/LQFIZlhE35?frame=HSXX62zpxA) | Sign up · GS1 account · no company name | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · checking `OV5Tdr9ydZ`<br>[.lk] → Sign up · Organization `CLsksg2sae` |
| [`O8kLNYf3Fk`](https://doop.design/c/LQFIZlhE35?frame=O8kLNYf3Fk) | Sign up · GS1 account · verified · dark | dark | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · Main location · choose GLN `2N_Kzpr0VC`<br>[.lk] → Sign up · Organization · dark `4Z4YHM7Y_Y` |

**Sign up · Main location**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2N_Kzpr0VC`](https://doop.design/c/LQFIZlhE35?frame=2N_Kzpr0VC) | Sign up · Main location · choose GLN | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · verified `2XUobNcrNt`<br>[.mi] → Sign up · Main location `_DHaSIu5T5` |
| [`_DHaSIu5T5`](https://doop.design/c/LQFIZlhE35?frame=_DHaSIu5T5) | Sign up · Main location | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | "(unlabelled)" → Auth · Log in `oYsDYjktDQ`<br>"(unlabelled)" → Sign up · Administrator `1P50qYkBt1`<br>"(unlabelled)" → Sign up · Organization `CLsksg2sae`<br>"Multiple PPB matches" → ARCHIVED 23 Nov · Sign up · multiple PPB matches `NKlXWNuz3M` |
| [`niHaE_gCEX`](https://doop.design/c/LQFIZlhE35?frame=niHaE_gCEX) | Sign up · Main location · GLN already registered | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | Choose another GLN → Sign up · Main location · choose GLN `2N_Kzpr0VC`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · verified `2XUobNcrNt` |
| [`2VMo4rHr0a`](https://doop.design/c/LQFIZlhE35?frame=2VMo4rHr0a) | Sign up · Main location · registry unavailable | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | [.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · verified `2XUobNcrNt`<br>[.lk] → Sign up · Main location `_DHaSIu5T5` |

**Sign up · Organization**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`CLsksg2sae`](https://doop.design/c/LQFIZlhE35?frame=CLsksg2sae) | Sign up · Organization | light | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | "(unlabelled)" → Auth · Log in `oYsDYjktDQ`<br>"(unlabelled)" → Sign up · Main location `_DHaSIu5T5`<br>"Log in" → Auth · Log in `oYsDYjktDQ` |
| [`4Z4YHM7Y_Y`](https://doop.design/c/LQFIZlhE35?frame=4Z4YHM7Y_Y) | Sign up · Organization · dark | dark | canon | `/signup` → SignupLive (SIGNUP-1, GS1 key only) | in progress | Log in → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Sign up · GS1 account · verified · dark `O8kLNYf3Fk` |


### 3.7 Shell (shared overlays) (38 frames, 14 flows)

**Add a result field**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`PUBr8g1meJ`](https://doop.design/c/LQFIZlhE35?frame=PUBr8g1meJ) | Add a result field | light | canon | `/lab/tests/new (result fields)` → LabTestLive.Index | — | [.pr] closes overlay |

**Add a test**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`p_Ib5oNNEe`](https://doop.design/c/LQFIZlhE35?frame=p_Ib5oNNEe) | Add a test | light | canon | `/lab/orders/:id/tests/new` → LabOrderLive.Show :add_test | — | [.pr] closes overlay |

**Calendar view menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`UwAiusb5oG`](https://doop.design/c/LQFIZlhE35?frame=UwAiusb5oG) | Calendar view menu | light | canon | `(component) date range picker` → td date_range_picker (DATE-1) | — | [.pr] closes overlay |

**Download ready**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`zkycQlzsjO`](https://doop.design/c/LQFIZlhE35?frame=zkycQlzsjO) | Download ready | light | canon | `(component) export CSV` → per list page export (verify) | — | [.lk] closes overlay |

**Export CSV**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`2E9yucAGjQ`](https://doop.design/c/LQFIZlhE35?frame=2E9yucAGjQ) | Export CSV | light | canon | `(component) export CSV` → per list page export (verify) | in progress | [.lk] closes overlay<br>[.lk] opens Download ready `zkycQlzsjO` |

**Filter menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`GNR8ZG0WQa`](https://doop.design/c/LQFIZlhE35?frame=GNR8ZG0WQa) | Filter menu · Activity | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`RBA4UYrkXr`](https://doop.design/c/LQFIZlhE35?frame=RBA4UYrkXr) | Filter menu · Category | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | in progress | [.pr] closes overlay |
| [`Q6s3o1UKRS`](https://doop.design/c/LQFIZlhE35?frame=Q6s3o1UKRS) | Filter menu · Created | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`2trt8GDgl8`](https://doop.design/c/LQFIZlhE35?frame=2trt8GDgl8) | Filter menu · Date | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`v0UH0bx6L9`](https://doop.design/c/LQFIZlhE35?frame=v0UH0bx6L9) | Filter menu · Expiry | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | in progress | [.pr] closes overlay |
| [`hsTdh4fT_Z`](https://doop.design/c/LQFIZlhE35?frame=hsTdh4fT_Z) | Filter menu · Flags | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`flG9lx1Pxp`](https://doop.design/c/LQFIZlhE35?frame=flG9lx1Pxp) | Filter menu · Gender | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`gYpvtPDu1v`](https://doop.design/c/LQFIZlhE35?frame=gYpvtPDu1v) | Filter menu · Method | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`xse0VhnCxA`](https://doop.design/c/LQFIZlhE35?frame=xse0VhnCxA) | Filter menu · Mobile user | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`ntkXbBL-C6`](https://doop.design/c/LQFIZlhE35?frame=ntkXbBL-C6) | Filter menu · Organization | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`lC7VMdCEri`](https://doop.design/c/LQFIZlhE35?frame=lC7VMdCEri) | Filter menu · Paid | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`U6QCMLJ8LN`](https://doop.design/c/LQFIZlhE35?frame=U6QCMLJ8LN) | Filter menu · Payment | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`X42vxHfarW`](https://doop.design/c/LQFIZlhE35?frame=X42vxHfarW) | Filter menu · Received | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`5uprTqJznQ`](https://doop.design/c/LQFIZlhE35?frame=5uprTqJznQ) | Filter menu · Role | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`M733hm_3tb`](https://doop.design/c/LQFIZlhE35?frame=M733hm_3tb) | Filter menu · Site | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`TTXzDZPEWP`](https://doop.design/c/LQFIZlhE35?frame=TTXzDZPEWP) | Filter menu · Status | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | in progress | [.pr] closes overlay |
| [`feg9yL0s8X`](https://doop.design/c/LQFIZlhE35?frame=feg9yL0s8X) | Filter menu · Urgency | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`HZvoVe9Hug`](https://doop.design/c/LQFIZlhE35?frame=HZvoVe9Hug) | Filter menu · Visited | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |
| [`qtRoKxMMu1`](https://doop.design/c/LQFIZlhE35?frame=qtRoKxMMu1) | Filter menu · Warehouse | light | canon | `(component) filter menu` → td_components filter chip popover (per list page) | — | [.pr] closes overlay |

**Get the mobile app**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`_AkYsfMrBW`](https://doop.design/c/LQFIZlhE35?frame=_AkYsfMrBW) | Get the mobile app | light | canon | `(component) shared dialog` → — | — | [.lk] closes overlay |

**Item details**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`gCMI-5oDzE`](https://doop.design/c/LQFIZlhE35?frame=gCMI-5oDzE) | Item details | light | canon | `(component) shared dialog` → — | — | [.lk] closes overlay |

**Notifications**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`TzQlEuhO6H`](https://doop.design/c/LQFIZlhE35?frame=TzQlEuhO6H) | Notifications | light | canon | `(shell) notifications` → MISSING (no notifications surface) | — | [.li] → Pharmacy · Receive stock `VpVCkmNrin`<br>[.li] → Pharmacy · Requisition detail `qAAuZfHK88`<br>[.li] → Pharmacy · Stock · all batches `fO2XgZ8Xir`<br>[.li] → Pharmacy · Stock · products `puMtQXqNOq`<br>[.lk] closes overlay |

**Period menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5I9pJoGa6G`](https://doop.design/c/LQFIZlhE35?frame=5I9pJoGa6G) | Period menu | light | canon | `(component) date range picker` → td date_range_picker (DATE-1) | — | [.pr] closes overlay |

**Print**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`d687xWcrBC`](https://doop.design/c/LQFIZlhE35?frame=d687xWcrBC) | Print | light | canon | `(component) print dialog` → — | — | [.lk] closes overlay |

**Product tour**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`pRWh641rg7`](https://doop.design/c/LQFIZlhE35?frame=pRWh641rg7) | Product tour · step 1 | light | canon | `(shell) product tour` → Layouts · tour hook | — | [.lk] closes overlay |
| [`sHEmCo_9oR`](https://doop.design/c/LQFIZlhE35?frame=sHEmCo_9oR) | Product tour · step 2 | light | canon | `(shell) product tour` → Layouts · tour hook | — | [.lk] closes overlay |
| [`F-mzfB-j8y`](https://doop.design/c/LQFIZlhE35?frame=F-mzfB-j8y) | Product tour · step 3 | light | canon | `(shell) product tour` → Layouts · tour hook | — | [.lk] closes overlay |

**Remove item**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`5mZQ-49VPF`](https://doop.design/c/LQFIZlhE35?frame=5mZQ-49VPF) | Remove item | light | canon | `(component) shared dialog` → — | — | [.lk] closes overlay |

**Site switcher open**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`l3PRkMH9kA`](https://doop.design/c/LQFIZlhE35?frame=l3PRkMH9kA) | Site switcher open · pharmacy | light | canon | `(shell) site switcher` → Layouts · site switcher | — | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+10 more) |
| [`IJAc4XSYTP`](https://doop.design/c/LQFIZlhE35?frame=IJAc4XSYTP) | Site switcher open · lab | light | canon | `(shell) site switcher` → Layouts · site switcher | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+10 more) |
| [`QwOww6J_-C`](https://doop.design/c/LQFIZlhE35?frame=QwOww6J_-C) | Site switcher open · combined | light | canon | `(shell) site switcher` → Layouts · site switcher | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP` (+12 more) |
| [`CUy1Ue75h-`](https://doop.design/c/LQFIZlhE35?frame=CUy1Ue75h-) | Site switcher open · dist | light | canon | `(shell) site switcher` → Layouts · site switcher | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Shipments `XJBYJekyQ3`<br>"(unlabelled)" → Distributor · Sites `iwqRqWwzqP` (+12 more) |
| [`xKjyrzVPWd`](https://doop.design/c/LQFIZlhE35?frame=xKjyrzVPWd) | Site switcher open · org | light | canon | `(shell) site switcher` → Layouts · site switcher | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+9 more) |


### 3.8 Account menu and collapsed shell (36 frames, 15 flows)

**Distributor · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`jHrWur7OeT`](https://doop.design/c/LQFIZlhE35?frame=jHrWur7OeT) | Distributor · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+12 more) |
| [`5tAJJwmXEA`](https://doop.design/c/LQFIZlhE35?frame=5tAJJwmXEA) | Distributor · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+12 more) |

**Distributor · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`l-R4s4jvz6`](https://doop.design/c/LQFIZlhE35?frame=l-R4s4jvz6) | Distributor · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Distributor · Billing · prepay `nNSes79vHo`<br>[.ci] → Distributor · Customers `tpsqpH3pfq`<br>[.ci] → Distributor · Mobile users `uNq45yZlSw`<br>[.ci] → Distributor · Org settings `6c3WqEKBCP`<br>[.ci] → Distributor · Products `GbcOmL7hjr`<br>[.ci] → Distributor · Receiving `pTKmcZsilq`<br>[.ci] → Distributor · Returns · supplier returns `SLxbPI5Z4A`<br>[.ci] → Distributor · Shipments `XJBYJekyQ3`<br>[.ci] → Distributor · Sites `iwqRqWwzqP`<br>[.ci] → Distributor · Stock · storage zone `j2u8BBnf6m` (+11 more) |
| [`4ei1VPTckH`](https://doop.design/c/LQFIZlhE35?frame=4ei1VPTckH) | Distributor · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+12 more) |
| [`sDY1vtG1_v`](https://doop.design/c/LQFIZlhE35?frame=sDY1vtG1_v) | Distributor · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" → Distributor · Billing · prepay `nNSes79vHo`<br>"(unlabelled)" → Distributor · Customers `tpsqpH3pfq`<br>"(unlabelled)" → Distributor · Mobile users `uNq45yZlSw`<br>"(unlabelled)" → Distributor · New shipment · GLN verified `z6VSLXmqsn`<br>"(unlabelled)" → Distributor · Org settings `6c3WqEKBCP`<br>"(unlabelled)" → Distributor · Products `GbcOmL7hjr`<br>"(unlabelled)" → Distributor · Products · all batches `4JRxjqsjai`<br>"(unlabelled)" → Distributor · Receive inventory · items added `NwX0CruZHC`<br>"(unlabelled)" → Distributor · Receiving `pTKmcZsilq`<br>"(unlabelled)" → Distributor · Returns · supplier returns `SLxbPI5Z4A` (+12 more) |

**Lab · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`hWFPMYtHfw`](https://doop.design/c/LQFIZlhE35?frame=hWFPMYtHfw) | Lab · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+8 more) |
| [`dmDflEXJzh`](https://doop.design/c/LQFIZlhE35?frame=dmDflEXJzh) | Lab · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+8 more) |

**Lab · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`wDPDmgntHD`](https://doop.design/c/LQFIZlhE35?frame=wDPDmgntHD) | Lab · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Lab · Lab orders `3GldJbxDi_`<br>[.ci] → Lab · Lab stock · products `_VFeE7v1Z3`<br>[.ci] → Lab · Patients `UvrfVC7Fqk`<br>[.ci] → Lab · Receive stock `4zyleLd04x`<br>[.ci] → Lab · Requisitions `W3kDRxq2N5`<br>[.ci] → Lab · Scan consumable · ready `TAzvg2vh9s`<br>[.ci] → Lab · Test catalog `30D8lWH2dY`<br>[.ci] → Lab · Transactions `Pef-1fqHs4`<br>[.lk] opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>[.lk] opens Period menu `5I9pJoGa6G` (+6 more) |
| [`vHqhV0Iw7I`](https://doop.design/c/LQFIZlhE35?frame=vHqhV0Iw7I) | Lab · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+8 more) |
| [`QN8jY331nC`](https://doop.design/c/LQFIZlhE35?frame=QN8jY331nC) | Lab · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Period menu `5I9pJoGa6G`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Lab stock · products `_VFeE7v1Z3`<br>"(unlabelled)" → Lab · Order detail · results `8fsD6dEWtV`<br>"(unlabelled)" → Lab · Patients `UvrfVC7Fqk`<br>"(unlabelled)" → Lab · Receive stock `4zyleLd04x`<br>"(unlabelled)" → Lab · Requisitions `W3kDRxq2N5`<br>"(unlabelled)" → Lab · Scan consumable · ready `TAzvg2vh9s`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY` (+8 more) |

**Log out confirm**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`cwUKNlhijG`](https://doop.design/c/LQFIZlhE35?frame=cwUKNlhijG) | Log out confirm | light | canon | `(shell) log out` → Layouts · account menu | — | "(unlabelled)" → Auth · Log in `oYsDYjktDQ`<br>"Close" closes overlay |

**Manufacturer · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`xn2gfMFpoN`](https://doop.design/c/LQFIZlhE35?frame=xn2gfMFpoN) | Manufacturer · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |
| [`fbkMkuqkko`](https://doop.design/c/LQFIZlhE35?frame=fbkMkuqkko) | Manufacturer · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |

**Manufacturer · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`LToUOeDNer`](https://doop.design/c/LQFIZlhE35?frame=LToUOeDNer) | Manufacturer · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | done | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |
| [`a5DbXnpQwK`](https://doop.design/c/LQFIZlhE35?frame=a5DbXnpQwK) | Manufacturer · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |
| [`40_pwuNQzC`](https://doop.design/c/LQFIZlhE35?frame=40_pwuNQzC) | Manufacturer · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" opens Manufacturer · Add product `yWiBLt5W4_`<br>"(unlabelled)" → Manufacturer · API keys `dNqZMZIzMf`<br>"(unlabelled)" → Manufacturer · Aggregation `nooman_e0w`<br>"(unlabelled)" → Manufacturer · Inventory `PSRp5BYBqa`<br>"(unlabelled)" → Manufacturer · Mobile users `ePbnW2fsM1`<br>"(unlabelled)" → Manufacturer · Org settings `a5BIYP5fvv`<br>"(unlabelled)" → Manufacturer · Products `nOHadNSnnW`<br>"(unlabelled)" → Manufacturer · Shipments `dD_f7mT7VA`<br>"(unlabelled)" → Manufacturer · TNT reporting `6h1jP1RQB5`<br>"Amoxicillin 500mg capsules 06289001001234 LOT-AX-2408 2,400" → Manufacturer · Product detail `vGTuM5LTeA` (+6 more) |

**Org · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`mCPsIZVgxf`](https://doop.design/c/LQFIZlhE35?frame=mCPsIZVgxf) | Org · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+7 more) |
| [`9WU5fkjygR`](https://doop.design/c/LQFIZlhE35?frame=9WU5fkjygR) | Org · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Admin dashboard `voIG90Ocbf`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA` (+7 more) |

**Org · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`scM_EYqIrM`](https://doop.design/c/LQFIZlhE35?frame=scM_EYqIrM) | Org · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Org · Organization settings `su8eaSdNu-`<br>[.ci] → Org · Products `U90FoygrHh`<br>[.ci] → Org · Receiving `2CQZtx0m1X`<br>[.ci] → Org · Requisition queue `9M_rqF3EVx`<br>[.ci] → Org · Sites `_YkjLU_zT_`<br>[.ci] → Org · Suppliers `OzelvYK3yA`<br>[.ci] → Org · TNT reporting `ZdiOKCCEg_`<br>[.ci] → Org · Team `lrsiMDnvg9`<br>[.ci] → Org · Transactions `DSjQ_Epu5w`<br>[.lk] opens Filter menu · Site `M733hm_3tb` (+6 more) |
| [`yr3ahvmXCi`](https://doop.design/c/LQFIZlhE35?frame=yr3ahvmXCi) | Org · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_` (+6 more) |
| [`gWKEKhjgay`](https://doop.design/c/LQFIZlhE35?frame=gWKEKhjgay) | Org · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" opens Filter menu · Site `M733hm_3tb`<br>"(unlabelled)" opens Org · Add site · GLN verified `3Sc9KGsLbu`<br>"(unlabelled)" opens Org · Filters and date range `ZZmLwye-Ku`<br>"(unlabelled)" → Org · Organization settings `su8eaSdNu-`<br>"(unlabelled)" → Org · Products `U90FoygrHh`<br>"(unlabelled)" → Org · Receiving `2CQZtx0m1X`<br>"(unlabelled)" → Org · Requisition queue `9M_rqF3EVx`<br>"(unlabelled)" → Org · Sites `_YkjLU_zT_`<br>"(unlabelled)" → Org · Suppliers `OzelvYK3yA`<br>"(unlabelled)" → Org · TNT reporting `ZdiOKCCEg_` (+6 more) |

**Pharma-lab · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`bXky4oNIZD`](https://doop.design/c/LQFIZlhE35?frame=bXky4oNIZD) | Pharma-lab · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP` (+10 more) |
| [`pTsV2tO6pN`](https://doop.design/c/LQFIZlhE35?frame=pTsV2tO6pN) | Pharma-lab · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Site dashboard `0xQtYRdBP7`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP` (+10 more) |

**Pharma-lab · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`uph54TOXbd`](https://doop.design/c/LQFIZlhE35?frame=uph54TOXbd) | Pharma-lab · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Lab · Lab orders `3GldJbxDi_`<br>[.ci] → Lab · Test catalog `30D8lWH2dY`<br>[.ci] → Pharma-lab · Patients `bqOkfOEJid`<br>[.ci] → Pharma-lab · Receive stock `8iVW7r9PTq`<br>[.ci] → Pharma-lab · Requisitions `D4seM_mRUZ`<br>[.ci] → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>[.ci] → Pharma-lab · Stock · products `c3EiqRelu0`<br>[.ci] → Pharma-lab · Transactions `7wrWcmujxW`<br>[.ci] → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>[.ci] → Pharmacy · Quick sale · empty `nIkqRsQnw0` (+12 more) |
| [`w8LaQy0Qdg`](https://doop.design/c/LQFIZlhE35?frame=w8LaQy0Qdg) | Pharma-lab · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0` (+9 more) |
| [`Y9Oy43oHk9`](https://doop.design/c/LQFIZlhE35?frame=Y9Oy43oHk9) | Pharma-lab · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" opens Lab · New lab order · existing patient `IGb-vyGRK9`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Lab · Lab orders `3GldJbxDi_`<br>"(unlabelled)" → Lab · Test catalog `30D8lWH2dY`<br>"(unlabelled)" → Pharma-lab · Patients `bqOkfOEJid`<br>"(unlabelled)" → Pharma-lab · Receive stock `8iVW7r9PTq`<br>"(unlabelled)" → Pharma-lab · Requisitions `D4seM_mRUZ`<br>"(unlabelled)" → Pharma-lab · Scan lookup · ready `AtpiHFUFn_`<br>"(unlabelled)" → Pharma-lab · Stock · all batches `fiY29WINlP`<br>"(unlabelled)" → Pharma-lab · Stock · products `c3EiqRelu0` (+9 more) |

**Pharmacy · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`y4OlKMJCvP`](https://doop.design/c/LQFIZlhE35?frame=y4OlKMJCvP) | Pharmacy · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+8 more) |
| [`jYraWHiZ8A`](https://doop.design/c/LQFIZlhE35?frame=jYraWHiZ8A) | Pharmacy · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+8 more) |

**Pharmacy · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`z-_Z3Rv4qH`](https://doop.design/c/LQFIZlhE35?frame=z-_Z3Rv4qH) | Pharmacy · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Pharmacy · Patients `fysrRIVfjl`<br>[.ci] → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>[.ci] → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>[.ci] → Pharmacy · Receive stock `VpVCkmNrin`<br>[.ci] → Pharmacy · Requisitions `R0-3QT_OPy`<br>[.ci] → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>[.ci] → Pharmacy · Stock · products `puMtQXqNOq`<br>[.ci] → Pharmacy · Transactions `8SwyrgWmlD`<br>[.lk] opens Calendar view menu `UwAiusb5oG`<br>[.lk] opens Pharmacy · New prescription · existing patient `V57ys398o_` (+10 more) |
| [`yVco6_I9AL`](https://doop.design/c/LQFIZlhE35?frame=yVco6_I9AL) | Pharmacy · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+8 more) |
| [`-lOBfXJD2F`](https://doop.design/c/LQFIZlhE35?frame=-lOBfXJD2F) | Pharmacy · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" opens Calendar view menu `UwAiusb5oG`<br>"(unlabelled)" opens Pharmacy · New prescription · existing patient `V57ys398o_`<br>"(unlabelled)" → Pharmacy · Patients `fysrRIVfjl`<br>"(unlabelled)" → Pharmacy · Prescriptions `mGgl_Tv3Ej`<br>"(unlabelled)" → Pharmacy · Quick sale · empty `nIkqRsQnw0`<br>"(unlabelled)" → Pharmacy · Receive stock `VpVCkmNrin`<br>"(unlabelled)" → Pharmacy · Requisition detail `qAAuZfHK88`<br>"(unlabelled)" → Pharmacy · Requisitions `R0-3QT_OPy`<br>"(unlabelled)" → Pharmacy · Scan lookup · ready `WDnObl1yFI`<br>"(unlabelled)" → Pharmacy · Stock · all batches `fO2XgZ8Xir` (+8 more) |

**Platform · Account menu**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`8Aov3K8OB_`](https://doop.design/c/LQFIZlhE35?frame=8Aov3K8OB_) | Platform · Account menu open · Light | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"18 Nov, 09:58 Wanjiru Mwangi Afya Bora Health Invited brian@" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:12 Joseph Kamau Afya Bora Health Recorded results" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:31 Brian Mutua Kilimo Distributors Approved SH-20" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:42 Amina Otieno Afya Bora Health Dispensed RX-104" → Platform · Audit activity `2MEScH0sKV`<br>"Coast Diagnostics No audited activity in 12 days" → Platform · Organizations `OPeL_8IxLl`<br>"Mlimani Chemists No audited activity in 9 days" → Platform · Organizations `OPeL_8IxLl` |
| [`m3L9wqE8ed`](https://doop.design/c/LQFIZlhE35?frame=m3L9wqE8ed) | Platform · Account menu open · Dark | dark | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | done | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"18 Nov, 09:58 Wanjiru Mwangi Afya Bora Health Invited brian@" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:12 Joseph Kamau Afya Bora Health Recorded results" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:31 Brian Mutua Kilimo Distributors Approved SH-20" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:42 Amina Otieno Afya Bora Health Dispensed RX-104" → Platform · Audit activity `2MEScH0sKV`<br>"Coast Diagnostics No audited activity in 12 days" → Platform · Organizations `OPeL_8IxLl`<br>"Mlimani Chemists No audited activity in 9 days" → Platform · Organizations `OPeL_8IxLl` |

**Platform · Sidebar collapsed**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`CUuSnDv903`](https://doop.design/c/LQFIZlhE35?frame=CUuSnDv903) | Platform · Sidebar collapsed · Light | light | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | [.ci] → Platform · Audit activity `2MEScH0sKV`<br>[.ci] → Platform · Organizations `OPeL_8IxLl`<br>[.cs] → Platform · Organizations `OPeL_8IxLl`<br>[.lk] → Platform · Audit activity `2MEScH0sKV`<br>[.lk] → Platform · Organizations `OPeL_8IxLl`<br>[tr] → Platform · Audit activity `2MEScH0sKV`<br>[tr] → Platform · Organizations `OPeL_8IxLl` |
| [`xQ8gu75RDf`](https://doop.design/c/LQFIZlhE35?frame=xQ8gu75RDf) | Platform · Sidebar collapsed · Dark | dark | canon | `(shell) collapsed sidebar` → Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED) | — | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"18 Nov, 09:58 Wanjiru Mwangi Afya Bora Health Invited brian@" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:12 Joseph Kamau Afya Bora Health Recorded results" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:31 Brian Mutua Kilimo Distributors Approved SH-20" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:42 Amina Otieno Afya Bora Health Dispensed RX-104" → Platform · Audit activity `2MEScH0sKV`<br>"Coast Diagnostics No audited activity in 12 days" → Platform · Organizations `OPeL_8IxLl`<br>"Mlimani Chemists No audited activity in 9 days" → Platform · Organizations `OPeL_8IxLl` |
| [`x6rOztF1f8`](https://doop.design/c/LQFIZlhE35?frame=x6rOztF1f8) | Platform · Sidebar collapsed · Account menu open | light | canon | `(shell) account menu` → Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov) | — | "(unlabelled)" → Platform · Audit activity `2MEScH0sKV`<br>"(unlabelled)" → Platform · Organizations `OPeL_8IxLl`<br>"18 Nov, 09:58 Wanjiru Mwangi Afya Bora Health Invited brian@" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:12 Joseph Kamau Afya Bora Health Recorded results" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:31 Brian Mutua Kilimo Distributors Approved SH-20" → Platform · Audit activity `2MEScH0sKV`<br>"18 Nov, 10:42 Amina Otieno Afya Bora Health Dispensed RX-104" → Platform · Audit activity `2MEScH0sKV`<br>"Coast Diagnostics No audited activity in 12 days" → Platform · Organizations `OPeL_8IxLl`<br>"Mlimani Chemists No audited activity in 9 days" → Platform · Organizations `OPeL_8IxLl` |


### 3.9 Error and empty states (3 frames, 3 flows)

**Error · 403**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`OQFyEOkUDz`](https://doop.design/c/LQFIZlhE35?frame=OQFyEOkUDz) | Error · 403 | light | canon | `403` → ErrorHTML | — | Log in as someone else → Auth · Log in `oYsDYjktDQ`<br>[.lk] → Landing — Home `nh9lfzCWtR` |

**Error · 404**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`S17bRTza4-`](https://doop.design/c/LQFIZlhE35?frame=S17bRTza4-) | Error · 404 | light | canon | `404` → ErrorHTML | — | [.lk] → Landing — Home `nh9lfzCWtR` |

**Error · 500**

| Frame | Screen / state | Theme | Status | Route → LiveView | Built | Links out |
|---|---|---|---|---|---|---|
| [`BPT3jcEdcm`](https://doop.design/c/LQFIZlhE35?frame=BPT3jcEdcm) | Error · 500 | light | canon | `500` → ErrorHTML | — | [.lk] → Landing — Home `nh9lfzCWtR` |

### 3.11 Superseded, archived and exploration frames

| Frame | Name | Status |
|---|---|---|
| [`hB-Q2itaVG`](https://doop.design/c/LQFIZlhE35?frame=hB-Q2itaVG) | Account menu · old, replaced by TD AccountMenu | superseded |
| [`5afS8LiRoa`](https://doop.design/c/LQFIZlhE35?frame=5afS8LiRoa) | SUPERSEDED · Generate serials (single form) | superseded |
| [`kyQHKTVNuw`](https://doop.design/c/LQFIZlhE35?frame=kyQHKTVNuw) | Manufacturer · Serials issued · Stock | superseded (dead UI per Krak §1.4) |
| [`pu69ruhFa_`](https://doop.design/c/LQFIZlhE35?frame=pu69ruhFa_) | Manufacturer · Serials issued · Order | superseded (dead UI per Krak §1.4) |
| [`FhhVQry3xx`](https://doop.design/c/LQFIZlhE35?frame=FhhVQry3xx) | A · Note | exploration |
| [`AGHtpDz6VS`](https://doop.design/c/LQFIZlhE35?frame=AGHtpDz6VS) | A · Forest panel · Log in | exploration |
| [`tLzvpnR27e`](https://doop.design/c/LQFIZlhE35?frame=tLzvpnR27e) | A · Forest panel · Log in · wrong password | exploration |
| [`X36fy7QzbF`](https://doop.design/c/LQFIZlhE35?frame=X36fy7QzbF) | A · Forest panel · Forgot password | exploration |
| [`-ZwOF6O0No`](https://doop.design/c/LQFIZlhE35?frame=-ZwOF6O0No) | A · Forest panel · Check your email | exploration |
| [`Hn7mL0jOgn`](https://doop.design/c/LQFIZlhE35?frame=Hn7mL0jOgn) | A · Forest panel · Choose a new password | exploration |
| [`hbdpECUtcX`](https://doop.design/c/LQFIZlhE35?frame=hbdpECUtcX) | A · Forest panel · Choose a site | exploration |
| [`kvE4oT9WO5`](https://doop.design/c/LQFIZlhE35?frame=kvE4oT9WO5) | B · Canon · Note | exploration |
| [`Z4xtsYFfPZ`](https://doop.design/c/LQFIZlhE35?frame=Z4xtsYFfPZ) | B · Centred (Canon) · Log in | exploration |
| [`OkNUknYNnY`](https://doop.design/c/LQFIZlhE35?frame=OkNUknYNnY) | B · Centred (Canon) · Log in · wrong password | exploration |
| [`6-2V6SHKrS`](https://doop.design/c/LQFIZlhE35?frame=6-2V6SHKrS) | B · Centred (Canon) · Forgot password | exploration |
| [`LsnQ3HRcff`](https://doop.design/c/LQFIZlhE35?frame=LsnQ3HRcff) | B · Centred (Canon) · Check your email | exploration |
| [`6L4KZZQSoI`](https://doop.design/c/LQFIZlhE35?frame=6L4KZZQSoI) | B · Centred (Canon) · Choose a new password | exploration |
| [`IH-V1-1KtT`](https://doop.design/c/LQFIZlhE35?frame=IH-V1-1KtT) | B · Centred (Canon) · Choose a site | exploration |
| [`W3msIwPCG7`](https://doop.design/c/LQFIZlhE35?frame=W3msIwPCG7) | C · Note | exploration |
| [`HaW1EZ0obc`](https://doop.design/c/LQFIZlhE35?frame=HaW1EZ0obc) | C · Wordmark panel · Log in | exploration |
| [`Nz0psla_yi`](https://doop.design/c/LQFIZlhE35?frame=Nz0psla_yi) | C · Wordmark panel · Log in · wrong password | exploration |
| [`GtT63-0_xd`](https://doop.design/c/LQFIZlhE35?frame=GtT63-0_xd) | C · Wordmark panel · Forgot password | exploration |
| [`AJHc7hrj2i`](https://doop.design/c/LQFIZlhE35?frame=AJHc7hrj2i) | C · Wordmark panel · Check your email | exploration |
| [`G89K1Yuat3`](https://doop.design/c/LQFIZlhE35?frame=G89K1Yuat3) | C · Wordmark panel · Choose a new password | exploration |
| [`b1uQ6zSfOh`](https://doop.design/c/LQFIZlhE35?frame=b1uQ6zSfOh) | C · Wordmark panel · Choose a site | exploration |
| [`kkpjavlH2r`](https://doop.design/c/LQFIZlhE35?frame=kkpjavlH2r) | D · Note | exploration |
| [`bVPthpyLCE`](https://doop.design/c/LQFIZlhE35?frame=bVPthpyLCE) | D · GS1 code panel · Log in | exploration |
| [`2I-axUHzIr`](https://doop.design/c/LQFIZlhE35?frame=2I-axUHzIr) | D · GS1 code panel · Log in · wrong password | exploration |
| [`8SkZ_G5_Vx`](https://doop.design/c/LQFIZlhE35?frame=8SkZ_G5_Vx) | D · GS1 code panel · Forgot password | exploration |
| [`S0x-oq--Lu`](https://doop.design/c/LQFIZlhE35?frame=S0x-oq--Lu) | D · GS1 code panel · Check your email | exploration |
| [`wg5o1QPJvN`](https://doop.design/c/LQFIZlhE35?frame=wg5o1QPJvN) | D · GS1 code panel · Choose a new password | exploration |
| [`0leyRyJ56_`](https://doop.design/c/LQFIZlhE35?frame=0leyRyJ56_) | D · GS1 code panel · Choose a site | exploration |
| [`HnOEZEEEZc`](https://doop.design/c/LQFIZlhE35?frame=HnOEZEEEZc) | Pharmacy — Dashboard | archived |
| [`E5BnYTjrKo`](https://doop.design/c/LQFIZlhE35?frame=E5BnYTjrKo) | Pharmacy — Stock | archived |
| [`maprWv74cq`](https://doop.design/c/LQFIZlhE35?frame=maprWv74cq) | Pharmacy — Stock product detail | archived |
| [`ljSJfgIst2`](https://doop.design/c/LQFIZlhE35?frame=ljSJfgIst2) | Pharmacy — Stock batch detail | archived |
| [`0PKYNepqmK`](https://doop.design/c/LQFIZlhE35?frame=0PKYNepqmK) | Pharmacy — Scan | archived |
| [`6CKSDJok5c`](https://doop.design/c/LQFIZlhE35?frame=6CKSDJok5c) | Pharmacy — Receive stock | archived |
| [`91TxCL1j2c`](https://doop.design/c/LQFIZlhE35?frame=91TxCL1j2c) | Pharmacy — Transactions / Earnings | archived |
| [`DoGMzaNGi_`](https://doop.design/c/LQFIZlhE35?frame=DoGMzaNGi_) | Admin · Receive inventory | archived |
| [`KC48hUTfHU`](https://doop.design/c/LQFIZlhE35?frame=KC48hUTfHU) | Admin · Add item sheet | archived |
| [`jHgAnLA6ar`](https://doop.design/c/LQFIZlhE35?frame=jHgAnLA6ar) | Admin · Add item · product picker | archived |
| [`zq8niAMcwF`](https://doop.design/c/LQFIZlhE35?frame=zq8niAMcwF) | Admin · Supplier picker | archived |
| [`ZRDPFLsLkV`](https://doop.design/c/LQFIZlhE35?frame=ZRDPFLsLkV) | Admin · TNT reporting | archived |
| [`zU8iKxMFzF`](https://doop.design/c/LQFIZlhE35?frame=zU8iKxMFzF) | Admin · TNT event payload | archived |
| [`i7J7xlKr4H`](https://doop.design/c/LQFIZlhE35?frame=i7J7xlKr4H) | Admin · Close organization dialog | archived |
| [`e8vft9UlXc`](https://doop.design/c/LQFIZlhE35?frame=e8vft9UlXc) | Platform · Dashboard | archived |
| [`ClHqqCjpQd`](https://doop.design/c/LQFIZlhE35?frame=ClHqqCjpQd) | Platform · Organizations | archived |
| [`PUzfT4U02h`](https://doop.design/c/LQFIZlhE35?frame=PUzfT4U02h) | Platform · Filter sheet | archived |
| [`CYex1oMoQk`](https://doop.design/c/LQFIZlhE35?frame=CYex1oMoQk) | Distributor · Home | archived |
| [`2bswAHwEi1`](https://doop.design/c/LQFIZlhE35?frame=2bswAHwEi1) | Distributor · Warehouse switcher sheet | archived |
| [`mRgEFoqHwx`](https://doop.design/c/LQFIZlhE35?frame=mRgEFoqHwx) | Distributor · Camera · warehouse | archived |
| [`xsO_eA2EwJ`](https://doop.design/c/LQFIZlhE35?frame=xsO_eA2EwJ) | Distributor · Shipments · approved | archived |
| [`5e3gAg8M_r`](https://doop.design/c/LQFIZlhE35?frame=5e3gAg8M_r) | Lab — Dashboard | archived |
| [`f-7t2NeMSO`](https://doop.design/c/LQFIZlhE35?frame=f-7t2NeMSO) | Lab — Stock | archived |
| [`0P9AXf7Rze`](https://doop.design/c/LQFIZlhE35?frame=0P9AXf7Rze) | Lab — Stock product detail | archived |
| [`ZGCzjAxrVR`](https://doop.design/c/LQFIZlhE35?frame=ZGCzjAxrVR) | Lab — Stock batch detail | archived |
| [`-j54H3sihm`](https://doop.design/c/LQFIZlhE35?frame=-j54H3sihm) | Lab — Scan | archived |
| [`F9TMb-YfHn`](https://doop.design/c/LQFIZlhE35?frame=F9TMb-YfHn) | Lab — Receive stock | archived |
| [`Cu4P7Lpc59`](https://doop.design/c/LQFIZlhE35?frame=Cu4P7Lpc59) | Admin · Receiving | archived |
| [`iJ9n8olBMp`](https://doop.design/c/LQFIZlhE35?frame=iJ9n8olBMp) | Admin · Receiving · received | archived |
| [`pLXmq-fDu-`](https://doop.design/c/LQFIZlhE35?frame=pLXmq-fDu-) | Admin · Goods receipt | archived |
| [`ZeFjKdmNk2`](https://doop.design/c/LQFIZlhE35?frame=ZeFjKdmNk2) | Admin · Organization settings | archived |
| [`3_Urw--tA1`](https://doop.design/c/LQFIZlhE35?frame=3_Urw--tA1) | Admin · Organization settings · saved | archived |
| [`hTMC0iTw46`](https://doop.design/c/LQFIZlhE35?frame=hTMC0iTw46) | Admin · M-Pesa till sheet | archived |
| [`3xW0md-DK5`](https://doop.design/c/LQFIZlhE35?frame=3xW0md-DK5) | Platform · Organization detail | archived |
| [`vFp3dMMda5`](https://doop.design/c/LQFIZlhE35?frame=vFp3dMMda5) | Platform · Organization actions sheet | archived |
| [`5ew6nNnEou`](https://doop.design/c/LQFIZlhE35?frame=5ew6nNnEou) | Platform · Suspend dialog | archived |
| [`63KwHAagqg`](https://doop.design/c/LQFIZlhE35?frame=63KwHAagqg) | Platform · Audit activity | archived |
| [`y5A51w8aVL`](https://doop.design/c/LQFIZlhE35?frame=y5A51w8aVL) | Platform · Activity detail | archived |
| [`pvsu3FkF1p`](https://doop.design/c/LQFIZlhE35?frame=pvsu3FkF1p) | Distributor · Choose a serialisation plan | archived |
| [`RU2wU-ygJA`](https://doop.design/c/LQFIZlhE35?frame=RU2wU-ygJA) | Distributor · Shipments · draft | archived |
| [`QfzSUq4Q04`](https://doop.design/c/LQFIZlhE35?frame=QfzSUq4Q04) | Distributor · Shipments · submitted | archived |
| [`sXmXfv8gRy`](https://doop.design/c/LQFIZlhE35?frame=sXmXfv8gRy) | Distributor — Dashboard | archived |
| [`qO-k3a33qg`](https://doop.design/c/LQFIZlhE35?frame=qO-k3a33qg) | Distributor — Batch detail | archived |
| [`5Aq2WLekuH`](https://doop.design/c/LQFIZlhE35?frame=5Aq2WLekuH) | Distributor — PPB reporting (EPCIS) | archived |
| [`byrMLi0W97`](https://doop.design/c/LQFIZlhE35?frame=byrMLi0W97) | Distributor — Receiving | archived |
| [`LYTLBykGqW`](https://doop.design/c/LQFIZlhE35?frame=LYTLBykGqW) | Distributor — Goods receipt detail | archived |
| [`KRYLXVoqqD`](https://doop.design/c/LQFIZlhE35?frame=KRYLXVoqqD) | Org — Admin Dashboard | archived |
| [`eE7-hld966`](https://doop.design/c/LQFIZlhE35?frame=eE7-hld966) | Org — Organization settings | archived |
| [`idq44sydrA`](https://doop.design/c/LQFIZlhE35?frame=idq44sydrA) | Platform — Dashboard | archived |
| [`0au93Lx1SB`](https://doop.design/c/LQFIZlhE35?frame=0au93Lx1SB) | Platform — Audit activity | archived |
| [`m13ujSw1qj`](https://doop.design/c/LQFIZlhE35?frame=m13ujSw1qj) | Platform — Organizations | archived |
| [`UOJMWy1ngD`](https://doop.design/c/LQFIZlhE35?frame=UOJMWy1ngD) | Auth — Accept invite | archived |
| [`0P0BP4yJuD`](https://doop.design/c/LQFIZlhE35?frame=0P0BP4yJuD) | Auth — Signup (step 1 of 3) | archived |
| [`3i5pngvPaf`](https://doop.design/c/LQFIZlhE35?frame=3i5pngvPaf) | Auth — Login | archived |
| [`PMqsCiLv9B`](https://doop.design/c/LQFIZlhE35?frame=PMqsCiLv9B) | Auth — Confirm email | archived |
| [`ugVBPgP6kt`](https://doop.design/c/LQFIZlhE35?frame=ugVBPgP6kt) | Pharmacy · Dashboard · light | archived |
| [`0LF2cMP31i`](https://doop.design/c/LQFIZlhE35?frame=0LF2cMP31i) | Pharmacy · Dashboard · dark | archived |
| [`quNb8z0cPx`](https://doop.design/c/LQFIZlhE35?frame=quNb8z0cPx) | Lab · Dashboard · light | archived |
| [`SNSyLsUNYg`](https://doop.design/c/LQFIZlhE35?frame=SNSyLsUNYg) | Lab · Dashboard · dark | archived |
| [`mTvrHMplwt`](https://doop.design/c/LQFIZlhE35?frame=mTvrHMplwt) | Pharmacy · Lab · Site dashboard · light | archived |
| [`sW5Yew2jgh`](https://doop.design/c/LQFIZlhE35?frame=sW5Yew2jgh) | Pharmacy · Lab · Site dashboard · dark | archived |
| [`lCvvGPaRVW`](https://doop.design/c/LQFIZlhE35?frame=lCvvGPaRVW) | Pharmacy · Stock list · light | archived |
| [`5alp9L68Ry`](https://doop.design/c/LQFIZlhE35?frame=5alp9L68Ry) | Pharmacy · Stock list · dark | archived |
| [`wPNNAPbtbQ`](https://doop.design/c/LQFIZlhE35?frame=wPNNAPbtbQ) | Pharmacy · Receive stock (scan) · light | archived |
| [`I6V_oAJVPA`](https://doop.design/c/LQFIZlhE35?frame=I6V_oAJVPA) | Pharmacy · Receive stock (scan) · dark | archived |
| [`DTvi4B5QP8`](https://doop.design/c/LQFIZlhE35?frame=DTvi4B5QP8) | ARCHIVED 23 Nov · Sign up · Organization (with PPB era copy) | archived |
| [`r_mJHlKTRh`](https://doop.design/c/LQFIZlhE35?frame=r_mJHlKTRh) | ARCHIVED 23 Nov · Sign up · Main location (PPB + KMLTTB) | archived |
| [`o8Ghn-FKi-`](https://doop.design/c/LQFIZlhE35?frame=o8Ghn-FKi-) | ARCHIVED 23 Nov · Sign up · Administrator (3 step) | archived |
| [`pcEk276aX8`](https://doop.design/c/LQFIZlhE35?frame=pcEk276aX8) | ARCHIVED 23 Nov · SUPERSEDED · Sign up · GS1 prefix verified | archived |
| [`UQkSsnRqBF`](https://doop.design/c/LQFIZlhE35?frame=UQkSsnRqBF) | ARCHIVED 23 Nov · SUPERSEDED · Sign up · prefix already registered | archived |
| [`NKlXWNuz3M`](https://doop.design/c/LQFIZlhE35?frame=NKlXWNuz3M) | ARCHIVED 23 Nov · Sign up · multiple PPB matches | archived |
| [`_1h-hwz542`](https://doop.design/c/LQFIZlhE35?frame=_1h-hwz542) | ARCHIVED 23 Nov · Manufacturer · Aggregation (review-queue era) | archived |
| [`kS9WXG6QX_`](https://doop.design/c/LQFIZlhE35?frame=kS9WXG6QX_) | ARCHIVED 23 Nov · Org · Edit team member (home site era) | archived |
| [`gitgTFvqqH`](https://doop.design/c/LQFIZlhE35?frame=gitgTFvqqH) | ARCHIVED 23 Nov · Org · Invite staff (single role) | archived |
| [`vwnD8zZGTK`](https://doop.design/c/LQFIZlhE35?frame=vwnD8zZGTK) | ARCHIVED 23 Nov · Manufacturer · API keys (issued keys era) | archived |

## 4. Error and empty states (cross-index)

| Frame | Name | Route |
|---|---|---|
| [`zq-cSnBhZm`](https://doop.design/c/LQFIZlhE35?frame=zq-cSnBhZm) | Auth · Log in error | `/login` |
| [`G_PnFvidFs`](https://doop.design/c/LQFIZlhE35?frame=G_PnFvidFs) | Sign up · GS1 account · registry unavailable | `/signup` |
| [`2VMo4rHr0a`](https://doop.design/c/LQFIZlhE35?frame=2VMo4rHr0a) | Sign up · Main location · registry unavailable | `/signup` |
| [`8Dk9fCPTKi`](https://doop.design/c/LQFIZlhE35?frame=8Dk9fCPTKi) | Pharma-lab · Scan lookup · not found | `/pharmacy/scan` |
| [`OQFyEOkUDz`](https://doop.design/c/LQFIZlhE35?frame=OQFyEOkUDz) | Error · 403 | `403` |
| [`S17bRTza4-`](https://doop.design/c/LQFIZlhE35?frame=S17bRTza4-) | Error · 404 | `404` |
| [`BPT3jcEdcm`](https://doop.design/c/LQFIZlhE35?frame=BPT3jcEdcm) | Error · 500 | `500` |
| [`nIkqRsQnw0`](https://doop.design/c/LQFIZlhE35?frame=nIkqRsQnw0) | Pharmacy · Quick sale · empty | `/pharmacy/quick-sale` |
| [`Mpn9ChDfzN`](https://doop.design/c/LQFIZlhE35?frame=Mpn9ChDfzN) | Pharmacy · Prescriptions · no results | `/pharmacy/prescriptions` |
| [`7ibhYgNGj7`](https://doop.design/c/LQFIZlhE35?frame=7ibhYgNGj7) | Lab · Lab orders · no results | `/lab/orders` |
| [`4WJVAyBAlz`](https://doop.design/c/LQFIZlhE35?frame=4WJVAyBAlz) | Distributor · Shipments · nothing matches | `/distributor/shipments` |
| [`3fqhLARkKR`](https://doop.design/c/LQFIZlhE35?frame=3fqhLARkKR) | Distributor · Stock · empty zone | `/distributor/stock` |
| [`FBYkmZgLdp`](https://doop.design/c/LQFIZlhE35?frame=FBYkmZgLdp) | Distributor · Mobile users · none yet | `/distributor/mobile-users[/new|/:id/edit]` |
| [`eLeVZImSse`](https://doop.design/c/LQFIZlhE35?frame=eLeVZImSse) | Distributor · Customers · none yet | `/distributor/customers[/new|/:id/edit]` |
| [`GcfERrqXwb`](https://doop.design/c/LQFIZlhE35?frame=GcfERrqXwb) | Manufacturer · Aggregation · empty | `/manufacturer/aggregations` |
| [`VNh-f2-P62`](https://doop.design/c/LQFIZlhE35?frame=VNh-f2-P62) | Org · Add site · GLN not found | `/org/sites[/new|/:id/edit]` |
| [`bCEk08BuY1`](https://doop.design/c/LQFIZlhE35?frame=bCEk08BuY1) | Org · Invite staff · no role yet | `/org/team[/new|/:id/edit]` |
| [`ZkVNOumC9w`](https://doop.design/c/LQFIZlhE35?frame=ZkVNOumC9w) | Org · API keys · no keys yet | `/org/api-keys | /distributor/api-keys | /manufacturer/api-keys` |

## 5. Gaps

### 5.1 Routes with no frame

| Route | LiveView :action | Note |
|---|---|---|
| `/org/mobile-users` | OrgMobileUserLive.Index :index | Added by master. No Doop frame (distributor and manufacturer mobile users frames exist and can be cloned). |
| `/org/mobile-users/new` | OrgMobileUserLive.Index :new | Added by master. No Doop frame (distributor and manufacturer mobile users frames exist and can be cloned). |
| `/org/mobile-users/:id/edit` | OrgMobileUserLive.Index :edit | Added by master. No Doop frame (distributor and manufacturer mobile users frames exist and can be cloned). |
| `/org/products/:id/batches/:batch_id/dispatch` | ProductLive.Show :dispatch_batch | Modal or detail without its own frame |
| `/org/stock-takes/:id/approve` | StockTakeQueueLive.Index :approve | Modal or detail without its own frame |
| `/org/stock-takes/:id/reject` | StockTakeQueueLive.Index :reject | Modal or detail without its own frame |
| `/org/stock-takes/:id` | StockTakeQueueLive.Show :show | Modal or detail without its own frame |
| `/org/disposals/:id/approve` | InventoryDisposalQueueLive.Index :approve | Modal or detail without its own frame |
| `/org/disposals/:id/reject` | InventoryDisposalQueueLive.Index :reject | Modal or detail without its own frame |
| `/org/disposals/:id` | InventoryDisposalQueueLive.Show :show | Modal or detail without its own frame |
| `/distributor/shipments/:id/packing-list` | DistributorShipmentLive.Document :packing_list | Distributor packing list print doc. Only the delivery note is drawn. |
| `/distributor/expiring` | DistributorStockLive.Index :expiry | Redirect stub to products?view=batches&expiry=near. Keep, no frame needed. |
| `/manufacturer/products/:id/sscc` | ManufacturerProductLive.Show :create_sscc | Create SSCC from product detail. No frame. |
| `/manufacturer/aggregations/pallets/new` | ManufacturerAggregationLive.PalletNew :new | Added by master. Flagship "Build a pallet · Scan shippers" is planned but not drawn yet. |

### 5.2 Master features with no frame (from Krak, 17:13)

- `/org/mobile-users` (OrgMobileUserLive): list, new, edit.
- Org settings: the EPCIS submission mode picker (Automatic or Manual approval).
- Manufacturer Product SSCCs: select unpacked serials and pack them into a new shipper SSCC.
- The full-size shipper label modal. It matches neither "Print SSCC labels" nor "Case label".
- Product serials states "Create shipper SSCC" and "All serials packed".

Also: master's spacing pass (56px rows) was dropped because Doop is canon. SIGNUP-1 logic is in code (afa472e "GS1 API key and GLN are the only signup requirements"); the screens still need restyling to `CLsksg2sae`.

### 5.3 Frames with no route (design ahead of code)

| Frame | Name | Mapped to |
|---|---|---|
| [`2CQZtx0m1X`](https://doop.design/c/LQFIZlhE35?frame=2CQZtx0m1X) | Org · Receiving | MISSING (/org/receiving) |
| [`pCRl3tBxpV`](https://doop.design/c/LQFIZlhE35?frame=pCRl3tBxpV) | Org · Receiving · received | MISSING (/org/receiving) |
| [`C2qqpiyP9-`](https://doop.design/c/LQFIZlhE35?frame=C2qqpiyP9-) | Org · Receive inventory | MISSING (/org/receiving) |
| [`aTuOrvCy4u`](https://doop.design/c/LQFIZlhE35?frame=aTuOrvCy4u) | Org · Goods receipt | MISSING (/org/receiving) |
| [`zlnJOqaCJ2`](https://doop.design/c/LQFIZlhE35?frame=zlnJOqaCJ2) | Org · Add item | MISSING (/org/receiving) |
| [`5mYf4LJWPD`](https://doop.design/c/LQFIZlhE35?frame=5mYf4LJWPD) | Org · Add item · new product | MISSING (/org/receiving) |
| [`-ihp-A1mBi`](https://doop.design/c/LQFIZlhE35?frame=-ihp-A1mBi) | Org · Add item · new supplier | MISSING (/org/receiving) |
| [`OPeL_8IxLl`](https://doop.design/c/LQFIZlhE35?frame=OPeL_8IxLl) | Platform · Organizations | MISSING (/platform/organizations[/:id]) |
| [`5o7nNuRzYl`](https://doop.design/c/LQFIZlhE35?frame=5o7nNuRzYl) | Platform · Organization detail | MISSING (/platform/organizations[/:id]) |
| [`rOKtmxrk0b`](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b) | Flagship · Manufacturer · Products | NO ROUTE |

Also design ahead of code without a missing route: Notifications `TzQlEuhO6H`, ⌘K and search results, Transaction detail and refund on pharmacy and org, Account settings modal (14 frames), Distributor Stock page with zones and Move stock, Distributor pick list states (`EU_pnVe8Bz`, `wWgSbjzUSa`), Log out confirm `cwUKNlhijG`.

### 5.4 Broken or undefined back targets

**In code** (static scan of 6c38d46, matches Krak §2.3):

| Route | LiveView | Finding |
|---|---|---|
| `/invites/:token` | AcceptInviteLive :edit | modal, no close target found |
| `/org/products/import` | ProductLive.Import :new | modal, no close target found |
| `/org/batches/:id` | BatchLive.Show :show | MISSING: no back or parent link |
| `/pharmacy/stock-takes/:id` | StockTakeLive.Show :show | MISSING: no back or parent link |
| `/pharmacy/disposals/:id` | DisposalLive.Show :show | MISSING: no back or parent link |
| `/pharmacy/prescriptions/:id` | PrescriptionLive.Show :show | MISSING: no back or parent link |
| `/lab/stock-takes/:id` | LabStockTakeLive.Show :show | MISSING: no back or parent link |
| `/lab/disposals/:id` | LabDisposalLive.Show :show | MISSING: no back or parent link |
| `/distributor/batches/:id` | DistributorBatchLive :show | MISSING: no back or parent link |
| `/distributor/cases/:id` | DistributorCaseLive :show | BROKEN: history.back() (no defined target) |
| `/distributor/returns/:id` | DistributorDisposalLive.Show :show | MISSING: no back or parent link |
| `/manufacturer/shipments/new` | ManufacturerShipmentLive.Form :new | modal, no close target found |
| `/manufacturer/sscc/:id/serials` | ManufacturerSsccLive.Serials :show | MISSING: no back or parent link |
| `/manufacturer/sscc/:id/label` | ManufacturerSsccLive.Label :show | MISSING: no back or parent link |

Krak adds `/manufacturer/products/:id`, `/manufacturer/shipments/:id`, `/manufacturer/aggregations/:id` and `/lab/transactions/:id` (+ receipt). Fix pattern for all: a `return_to` param, falling back to the parent list.

**In Doop**: no web frame uses the prototype `back` action (history back). All 656 history-back interactions on the canvas are on Mobile pages. Every web detail frame I checked has an explicit back or breadcrumb target (for example Shipper SSCC `6s_cVMiQkS`: "Aggregation" → `nooman_e0w`, "Pallet" → `rDvQtkfRwC`). The one Doop problem: frames reached from several places draw a single fixed crumb, so the code needs `return_to` to honour where the user came from. Flagship frames still need their back targets written down per button (Krak asked for from/to on every button).

## 6. Everything Sean has asked for

| Ask | Detail |
|---|---|
| Flagship manufacturer flow (16:57 via Krak) | Products synced from GS1 with clear row actions "Generate serials" and "View serials" (today "Serial" and two "View"); after the wizard, land on Batches with the new batch selected, a serial preview and Print right there (code already lands on /manufacturer/products/:gtin/serials?batch=, but the page is legacy and has no batch print); a clear View serials page with a working back link; aggregate serials into shipper SSCCs; scan shipper SSCCs into a pallet SSCC; ship. Master logic is canon, only UI is replaced. Every button and back gets a defined from/to. |
| Distributor flows | Clean order views; receiving; shipments draft and dispatch; returns (supplier and customer); customers. Same flagship style, no bouncing between pages (e.g. after receiving, stay on the receipt). |
| Interface map (17:05) | A Notion doc with all frames and flows, how they map to LiveViews, each user journey and its logic, and the plan to implement all of the above. |
| Scale and flow (17:12) | The design system must scale with engineering features and the product must flow. Hover to peek rich tooltips for every entity ID (§7). |
| Uniform language | Every route matches its Doop frame: padding, borders, radii, controls, popovers inside modals. Doop is canon; "full compliance, nothing on Doop misses in Phoenix". Desktop only, fixed layout. |
| No native date pickers (DATE-1) | TD DatePicker `chdlkoodd2` everywhere; remove `datetime-local` from allowed input types and the dead `input[type=date]` CSS. |
| Times in EAT | Every time shows in Africa/Nairobi as "18 Nov 2026, 10:44". Krak found 53 lib files still calling `Calendar.strftime` directly. |
| Dark mode | Every screen in light and dark from TD tokens (`td-tokens.css`, `[data-theme="dark"]`); dark frames exist for dashboards, TNT, AGG-1, TEAM-1, API keys, account menus. Remaining dark gaps on a few modals. |
| Briefs already issued | brief.md §1-§9 (lab), brief-areas.md §0 cross-cutting (search and ⌘K, transaction detail and refund UI, notifications, Export CSV, filter menus), areas 1-7 (110 items), §9 OLD-1 to OLD-11, §10 NAV-1, NAV-2, EMPTY-1, §11 DATE-1 and TNT-1, §12 SHELL-ACCOUNT, §13 SIGNUP-1, §14 SHELL-COLLAPSED, §15 AGG-1, §16 TEAM-1, §17 APIKEYS-1 ("i need this on brand"), §18 gaps closed. |
| Standing rules | Never delete an old flow before it is on Doop. Phosphor icons, Inter, mono only for real codes, orb avatars, no ghost secondary buttons, no shadows or blur, whites #F9F9FA / #EFEFF0 / #FFFFFF. |

## 7. Hover to peek (rich tooltips)

**Existing components.** Doop: no tooltip, popover or hover-card component among the 57 components (closest: TD MenuItem popovers, TD KeyValue rows, TD Badge, TD Orb). Code: no tooltip or popover function in `core_components.ex` or `td_components.ex`; only `data-tooltip` on collapsed sidebar nav items (`layouts.ex` ~L517, rendered by `#sidebar-floating-tooltip` in app.css) and the `.td-popover` menu class (app.css ~L2824) used by filter and row menus. A peek therefore needs one new TD component (Doop) and one new function plus hook (code).

| Entity | Code source | Peek fields (from the schema) | Canon frames showing it | Routes showing it |
|---|---|---|---|---|
| Lab order (LO-YYYY-NNNN) | lab_orders | Reference (LabOrders.reference/1, derived from id), patient (via patient_visit), status, urgency, tests count (lab_order_results), total_amount, has_paid / payment_type, prescriber_name, referral (is_referral, referring_facility), ordered_by, inserted_at (EAT) | 37: [`dmDflEXJzh`](https://doop.design/c/LQFIZlhE35?frame=dmDflEXJzh), [`hWFPMYtHfw`](https://doop.design/c/LQFIZlhE35?frame=hWFPMYtHfw), [`lDrhCsUsP3`](https://doop.design/c/LQFIZlhE35?frame=lDrhCsUsP3), [`3GldJbxDi_`](https://doop.design/c/LQFIZlhE35?frame=3GldJbxDi_), [`y11_7Bfo8B`](https://doop.design/c/LQFIZlhE35?frame=y11_7Bfo8B), [`7ibhYgNGj7`](https://doop.design/c/LQFIZlhE35?frame=7ibhYgNGj7), [`CgyYJqj1cF`](https://doop.design/c/LQFIZlhE35?frame=CgyYJqj1cF), [`r1L-tWO8eU`](https://doop.design/c/LQFIZlhE35?frame=r1L-tWO8eU), [`BkDfHtaY4M`](https://doop.design/c/LQFIZlhE35?frame=BkDfHtaY4M), [`1jvAaFyqCV`](https://doop.design/c/LQFIZlhE35?frame=1jvAaFyqCV), [`8fsD6dEWtV`](https://doop.design/c/LQFIZlhE35?frame=8fsD6dEWtV), [`gDvL3sltff`](https://doop.design/c/LQFIZlhE35?frame=gDvL3sltff), [`LYzxIpGTSt`](https://doop.design/c/LQFIZlhE35?frame=LYzxIpGTSt), [`s_nAxnvYOE`](https://doop.design/c/LQFIZlhE35?frame=s_nAxnvYOE) (+23) | 15: `/lab/orders`, `/lab/orders/:id`, `/lab/orders/:id/collect`, `/lab/orders/:id/consumables/new`, `/lab/orders/:id/payments/new`, `/lab/orders/:id/report`, `/lab/orders/:id/results/:result_id/edit`, `/lab/orders/:id/specimens/:specimen_id/label`, `/lab/orders/:id/tests/new`, `/lab/orders/new`, `/lab/transactions`, `/lab/transactions/:id` (+3) |
| Prescription (RX-) | prescriptions | Patient name and phone, items_count, status, total_amount, has_paid / payment_type, is_external and source_facility, created by, inserted_at | 23: [`5MdRlvaDiH`](https://doop.design/c/LQFIZlhE35?frame=5MdRlvaDiH), [`DSjQ_Epu5w`](https://doop.design/c/LQFIZlhE35?frame=DSjQ_Epu5w), [`gTIcNKn1Ie`](https://doop.design/c/LQFIZlhE35?frame=gTIcNKn1Ie), [`hXPInx920g`](https://doop.design/c/LQFIZlhE35?frame=hXPInx920g), [`7wrWcmujxW`](https://doop.design/c/LQFIZlhE35?frame=7wrWcmujxW), [`wyJQ6GLU2P`](https://doop.design/c/LQFIZlhE35?frame=wyJQ6GLU2P), [`oBlQhsWTT7`](https://doop.design/c/LQFIZlhE35?frame=oBlQhsWTT7), [`kk8xYfpH6O`](https://doop.design/c/LQFIZlhE35?frame=kk8xYfpH6O), [`2GZ7SeAWi0`](https://doop.design/c/LQFIZlhE35?frame=2GZ7SeAWi0), [`mGgl_Tv3Ej`](https://doop.design/c/LQFIZlhE35?frame=mGgl_Tv3Ej), [`PP6AFx7PEM`](https://doop.design/c/LQFIZlhE35?frame=PP6AFx7PEM), [`fR7za4TcRy`](https://doop.design/c/LQFIZlhE35?frame=fR7za4TcRy), [`h1ctG5HEZ0`](https://doop.design/c/LQFIZlhE35?frame=h1ctG5HEZ0), [`Mpn9ChDfzN`](https://doop.design/c/LQFIZlhE35?frame=Mpn9ChDfzN) (+9) | 8: `/org/batches/:id`, `/org/sites/:id`, `/pharmacy`, `/pharmacy/prescriptions`, `/pharmacy/prescriptions/:id`, `/pharmacy/prescriptions/:id/payments/new`, `/pharmacy/prescriptions/:id/receipt`, `/pharmacy/prescriptions/new` |
| Transaction / payment (order ID on transactions) | payments (+ sales, prescriptions, lab_orders) | Order type and its reference (prescription, lab order or sale), amount, payment_type, provider_reference (M-Pesa code, mono), status, failure_reason, paid_at (EAT), site | 29: [`VRY0p3ZE2z`](https://doop.design/c/LQFIZlhE35?frame=VRY0p3ZE2z), [`5kI8h3aBwo`](https://doop.design/c/LQFIZlhE35?frame=5kI8h3aBwo), [`00v8gxaGGq`](https://doop.design/c/LQFIZlhE35?frame=00v8gxaGGq), [`45FlJvpVyi`](https://doop.design/c/LQFIZlhE35?frame=45FlJvpVyi), [`Pef-1fqHs4`](https://doop.design/c/LQFIZlhE35?frame=Pef-1fqHs4), [`MC_1GL3a94`](https://doop.design/c/LQFIZlhE35?frame=MC_1GL3a94), [`DnuQVVOIuE`](https://doop.design/c/LQFIZlhE35?frame=DnuQVVOIuE), [`07-8zNav0v`](https://doop.design/c/LQFIZlhE35?frame=07-8zNav0v), [`Oh4IwFJvUg`](https://doop.design/c/LQFIZlhE35?frame=Oh4IwFJvUg), [`fi0pTx-1f7`](https://doop.design/c/LQFIZlhE35?frame=fi0pTx-1f7), [`3DKqAH3VB8`](https://doop.design/c/LQFIZlhE35?frame=3DKqAH3VB8), [`tvMYqHud3S`](https://doop.design/c/LQFIZlhE35?frame=tvMYqHud3S), [`DSjQ_Epu5w`](https://doop.design/c/LQFIZlhE35?frame=DSjQ_Epu5w), [`53BedS4v4m`](https://doop.design/c/LQFIZlhE35?frame=53BedS4v4m) (+15) | 22: `/distributor/billing/invoices/:id`, `/lab/orders`, `/lab/orders/:id`, `/lab/orders/:id/collect`, `/lab/orders/:id/consumables/new`, `/lab/orders/:id/payments/new`, `/lab/orders/:id/report`, `/lab/orders/:id/results/:result_id/edit`, `/lab/orders/:id/specimens/:specimen_id/label`, `/lab/orders/:id/tests/new`, `/lab/orders/new`, `/lab/transactions` (+10) |
| Batch / lot | batches (site stock) and manufacturer_batches | Site stock: batch_no (mono), product, GTIN, expiry_date, remaining_quantity / quantity, status, zone and bin, supplier, received_at, goods receipt number, SSCC if received in a case. Manufacturer: batch_no, product, production_date, expiry_date, serial count, shippers count | 76: [`Yd-me0Se-p`](https://doop.design/c/LQFIZlhE35?frame=Yd-me0Se-p), [`9mhLuDdvyF`](https://doop.design/c/LQFIZlhE35?frame=9mhLuDdvyF), [`2poLrBv3Wq`](https://doop.design/c/LQFIZlhE35?frame=2poLrBv3Wq), [`v-q64497Ft`](https://doop.design/c/LQFIZlhE35?frame=v-q64497Ft), [`gag0zJMVuV`](https://doop.design/c/LQFIZlhE35?frame=gag0zJMVuV), [`lqrh3ko8nX`](https://doop.design/c/LQFIZlhE35?frame=lqrh3ko8nX), [`4JRxjqsjai`](https://doop.design/c/LQFIZlhE35?frame=4JRxjqsjai), [`NwX0CruZHC`](https://doop.design/c/LQFIZlhE35?frame=NwX0CruZHC), [`wWgSbjzUSa`](https://doop.design/c/LQFIZlhE35?frame=wWgSbjzUSa), [`EU_pnVe8Bz`](https://doop.design/c/LQFIZlhE35?frame=EU_pnVe8Bz), [`FvnY7JCNQz`](https://doop.design/c/LQFIZlhE35?frame=FvnY7JCNQz), [`sVU0g3wEAw`](https://doop.design/c/LQFIZlhE35?frame=sVU0g3wEAw), [`UKUgQMR4Jy`](https://doop.design/c/LQFIZlhE35?frame=UKUgQMR4Jy), [`7zytGb6V4h`](https://doop.design/c/LQFIZlhE35?frame=7zytGb6V4h) (+62) | 68: `/distributor/batches/:id`, `/distributor/cases/:id`, `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/products`, `/distributor/products/:id`, `/distributor/products/new`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/distributor/returns/:id` (+56) |
| SSCC (shipper) | manufacturer_shipper_ssccs, distributor_shippers, logistic_units | Code (mono), GTIN and batch, production and expiry dates, count_of_trade_items or unit_count, packed count (packed_serials), from and to party (company and GLN), order_number, pallet code, shipment status. Distributor: sequence, product_name, sscc_assigned_at. Logistic unit: kind, status, parent | 53: [`5tAJJwmXEA`](https://doop.design/c/LQFIZlhE35?frame=5tAJJwmXEA), [`jHrWur7OeT`](https://doop.design/c/LQFIZlhE35?frame=jHrWur7OeT), [`9mhLuDdvyF`](https://doop.design/c/LQFIZlhE35?frame=9mhLuDdvyF), [`8OjVBGuJw2`](https://doop.design/c/LQFIZlhE35?frame=8OjVBGuJw2), [`tmGVB7EA_h`](https://doop.design/c/LQFIZlhE35?frame=tmGVB7EA_h), [`AG21KELEMP`](https://doop.design/c/LQFIZlhE35?frame=AG21KELEMP), [`8SCAEjcIlW`](https://doop.design/c/LQFIZlhE35?frame=8SCAEjcIlW), [`lQVs5LkQSv`](https://doop.design/c/LQFIZlhE35?frame=lQVs5LkQSv), [`sDY1vtG1_v`](https://doop.design/c/LQFIZlhE35?frame=sDY1vtG1_v), [`4ei1VPTckH`](https://doop.design/c/LQFIZlhE35?frame=4ei1VPTckH), [`aDfQMYP8sT`](https://doop.design/c/LQFIZlhE35?frame=aDfQMYP8sT), [`ijOdE3IvVJ`](https://doop.design/c/LQFIZlhE35?frame=ijOdE3IvVJ), [`IQ2oV6Y6Gn`](https://doop.design/c/LQFIZlhE35?frame=IQ2oV6Y6Gn), [`fbgqW4GxfP`](https://doop.design/c/LQFIZlhE35?frame=fbgqW4GxfP) (+39) | 23: `/distributor/batches/:id`, `/distributor/cases/:id`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/distributor/shipments/:id`, `/distributor/shipments/:id/delivery-note`, `/distributor/shipments/:id/packing-list`, `/manufacturer/aggregations`, `/manufacturer/aggregations/:id`, `/manufacturer/aggregations/new`, `/manufacturer/aggregations/pallets/:id` (+11) |
| Pallet (PAL- / pallet SSCC) | manufacturer_pallets (+ logistic_units kind pallet) | Code (today PAL-, not GS1), shippers count, from and to (company, GLN, address), created at. Total units derived from shipper counts | 9: [`SynBwMYmxH`](https://doop.design/c/LQFIZlhE35?frame=SynBwMYmxH), [`qGit1zj1rm`](https://doop.design/c/LQFIZlhE35?frame=qGit1zj1rm), [`nooman_e0w`](https://doop.design/c/LQFIZlhE35?frame=nooman_e0w), [`9eVZhuE_oo`](https://doop.design/c/LQFIZlhE35?frame=9eVZhuE_oo), [`rDvQtkfRwC`](https://doop.design/c/LQFIZlhE35?frame=rDvQtkfRwC), [`XEj-QF2bKn`](https://doop.design/c/LQFIZlhE35?frame=XEj-QF2bKn), [`C22opce6ED`](https://doop.design/c/LQFIZlhE35?frame=C22opce6ED), [`6s_cVMiQkS`](https://doop.design/c/LQFIZlhE35?frame=6s_cVMiQkS), [`tY878a4EFK`](https://doop.design/c/LQFIZlhE35?frame=tY878a4EFK) | 8: `/manufacturer/aggregations`, `/manufacturer/aggregations/new`, `/manufacturer/aggregations/pallets/:id`, `/manufacturer/aggregations/pallets/:pallet_id/ssccs/new`, `/manufacturer/aggregations/pallets/new`, `/manufacturer/products/:gtin/ssccs`, `/manufacturer/products/:id`, `/manufacturer/products/:id/sscc` |
| SGTIN / serial | manufacturer_serials (GS1 is the remote source) | Serial (mono), GTIN and product, batch_no and expiry, packed into which shipper SSCC (or unpacked), created at. Status beyond packed is not stored locally | 52: [`onc1mah2wo`](https://doop.design/c/LQFIZlhE35?frame=onc1mah2wo), [`vi5a6Pe3nV`](https://doop.design/c/LQFIZlhE35?frame=vi5a6Pe3nV), [`nNSes79vHo`](https://doop.design/c/LQFIZlhE35?frame=nNSes79vHo), [`5dblYmDL3P`](https://doop.design/c/LQFIZlhE35?frame=5dblYmDL3P), [`yqxtyU599f`](https://doop.design/c/LQFIZlhE35?frame=yqxtyU599f), [`Eu3T4LB1bO`](https://doop.design/c/LQFIZlhE35?frame=Eu3T4LB1bO), [`tmGVB7EA_h`](https://doop.design/c/LQFIZlhE35?frame=tmGVB7EA_h), [`jFNgzgD5q1`](https://doop.design/c/LQFIZlhE35?frame=jFNgzgD5q1), [`s-Y7-4zrCb`](https://doop.design/c/LQFIZlhE35?frame=s-Y7-4zrCb), [`QTcjh85AAT`](https://doop.design/c/LQFIZlhE35?frame=QTcjh85AAT), [`60lAgEf28c`](https://doop.design/c/LQFIZlhE35?frame=60lAgEf28c), [`JL8VPDk7sr`](https://doop.design/c/LQFIZlhE35?frame=JL8VPDk7sr), [`EAR8n3VwU-`](https://doop.design/c/LQFIZlhE35?frame=EAR8n3VwU-), [`w0jvpBd9vY`](https://doop.design/c/LQFIZlhE35?frame=w0jvpBd9vY) (+38) | 23: `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/distributor/shipments/:id`, `/distributor/shipments/:id/delivery-note`, `/distributor/shipments/:id/packing-list`, `/lab/receive-stock`, `/lab/receive-stock/:id/receive`, `/lab/scan` (+11) |
| GTIN / product | manufacturer_products, products | Manufacturer: name, GTIN (mono), brand_owner, licence_type, status, batches and serial counts. Site catalogue: brand and generic name, strength, uom and pack, category, is_otc / dangerous drug, price, reorder level, stock on hand | 90: [`Yd-me0Se-p`](https://doop.design/c/LQFIZlhE35?frame=Yd-me0Se-p), [`lqrh3ko8nX`](https://doop.design/c/LQFIZlhE35?frame=lqrh3ko8nX), [`GbcOmL7hjr`](https://doop.design/c/LQFIZlhE35?frame=GbcOmL7hjr), [`-h8zVFSeZ0`](https://doop.design/c/LQFIZlhE35?frame=-h8zVFSeZ0), [`4JRxjqsjai`](https://doop.design/c/LQFIZlhE35?frame=4JRxjqsjai), [`zo7Me6_9Ya`](https://doop.design/c/LQFIZlhE35?frame=zo7Me6_9Ya), [`DE6Mpnt79E`](https://doop.design/c/LQFIZlhE35?frame=DE6Mpnt79E), [`oR30_7au26`](https://doop.design/c/LQFIZlhE35?frame=oR30_7au26), [`rOKtmxrk0b`](https://doop.design/c/LQFIZlhE35?frame=rOKtmxrk0b), [`AywKWZYjJ5`](https://doop.design/c/LQFIZlhE35?frame=AywKWZYjJ5), [`jEHjO102Ab`](https://doop.design/c/LQFIZlhE35?frame=jEHjO102Ab), [`Dejg7rMSP_`](https://doop.design/c/LQFIZlhE35?frame=Dejg7rMSP_), [`Dj1Fl499QM`](https://doop.design/c/LQFIZlhE35?frame=Dj1Fl499QM), [`Qautl3niIH`](https://doop.design/c/LQFIZlhE35?frame=Qautl3niIH) (+76) | 58: `/distributor/batches/:id`, `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/products`, `/distributor/products/:id`, `/distributor/products/new`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/distributor/returns/:id`, `/distributor/shipments/:id` (+46) |
| GLN / location (site, supplier) | sites, suppliers, customers (gln) | Site: name, GLN (mono), address, activities, gln_verified_at, PPB licence number, status and valid till. Supplier: name, GLN, contact, phone, location, verified. GS1 directory lookups for outside parties: company and address | 45: [`pG6LqCfcwP`](https://doop.design/c/LQFIZlhE35?frame=pG6LqCfcwP), [`zPFVqJpCoT`](https://doop.design/c/LQFIZlhE35?frame=zPFVqJpCoT), [`tpsqpH3pfq`](https://doop.design/c/LQFIZlhE35?frame=tpsqpH3pfq), [`eLeVZImSse`](https://doop.design/c/LQFIZlhE35?frame=eLeVZImSse), [`8WcwnQK6TA`](https://doop.design/c/LQFIZlhE35?frame=8WcwnQK6TA), [`z6VSLXmqsn`](https://doop.design/c/LQFIZlhE35?frame=z6VSLXmqsn), [`hcfdn9XxbD`](https://doop.design/c/LQFIZlhE35?frame=hcfdn9XxbD), [`iwqRqWwzqP`](https://doop.design/c/LQFIZlhE35?frame=iwqRqWwzqP), [`VtFnWKWwhA`](https://doop.design/c/LQFIZlhE35?frame=VtFnWKWwhA), [`zo7Me6_9Ya`](https://doop.design/c/LQFIZlhE35?frame=zo7Me6_9Ya), [`DE6Mpnt79E`](https://doop.design/c/LQFIZlhE35?frame=DE6Mpnt79E), [`M733hm_3tb`](https://doop.design/c/LQFIZlhE35?frame=M733hm_3tb), [`HZvoVe9Hug`](https://doop.design/c/LQFIZlhE35?frame=HZvoVe9Hug), [`Wx7_TyNlII`](https://doop.design/c/LQFIZlhE35?frame=Wx7_TyNlII) (+31) | 40: `/distributor/batches/:id`, `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/customers`, `/distributor/customers/:id/edit`, `/distributor/customers/new`, `/distributor/epcis`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/distributor/settings` (+28) |
| Customer | customers | Name, GLN, customer_type, address, contact name, email and phone; recent shipments to this GLN (query) | 4: [`2poLrBv3Wq`](https://doop.design/c/LQFIZlhE35?frame=2poLrBv3Wq), [`tpsqpH3pfq`](https://doop.design/c/LQFIZlhE35?frame=tpsqpH3pfq), [`eLeVZImSse`](https://doop.design/c/LQFIZlhE35?frame=eLeVZImSse), [`oxNAXRBPCz`](https://doop.design/c/LQFIZlhE35?frame=oxNAXRBPCz) | 7: `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/customers`, `/distributor/customers/:id/edit`, `/distributor/customers/new`, `/distributor/shipments/:id` |
| Shipment (SH-/MSH- reference, order number) | distributor_shipments (manufacturer_shipments for auto shipments) | Reference, order_number, status, origin and destination (company, GLN), shippers count, assigned mobile user, submitted / approved / rejected at and by, rejection_reason, is_return | 33: [`5tAJJwmXEA`](https://doop.design/c/LQFIZlhE35?frame=5tAJJwmXEA), [`jHrWur7OeT`](https://doop.design/c/LQFIZlhE35?frame=jHrWur7OeT), [`Yd-me0Se-p`](https://doop.design/c/LQFIZlhE35?frame=Yd-me0Se-p), [`8OjVBGuJw2`](https://doop.design/c/LQFIZlhE35?frame=8OjVBGuJw2), [`UiVBLpI9Cx`](https://doop.design/c/LQFIZlhE35?frame=UiVBLpI9Cx), [`gag0zJMVuV`](https://doop.design/c/LQFIZlhE35?frame=gag0zJMVuV), [`8SCAEjcIlW`](https://doop.design/c/LQFIZlhE35?frame=8SCAEjcIlW), [`KfQfsgpVkN`](https://doop.design/c/LQFIZlhE35?frame=KfQfsgpVkN), [`ynvC_CLltK`](https://doop.design/c/LQFIZlhE35?frame=ynvC_CLltK), [`n3E_4eHtB7`](https://doop.design/c/LQFIZlhE35?frame=n3E_4eHtB7), [`lQVs5LkQSv`](https://doop.design/c/LQFIZlhE35?frame=lQVs5LkQSv), [`wWgSbjzUSa`](https://doop.design/c/LQFIZlhE35?frame=wWgSbjzUSa), [`EU_pnVe8Bz`](https://doop.design/c/LQFIZlhE35?frame=EU_pnVe8Bz), [`IiThKMTc0e`](https://doop.design/c/LQFIZlhE35?frame=IiThKMTc0e) (+19) | 34: `/distributor`, `/distributor/customer-returns`, `/distributor/customer-returns/:id`, `/distributor/customer-returns/new`, `/distributor/shipments`, `/distributor/shipments/:id`, `/distributor/shipments/:id/delivery-note`, `/distributor/shipments/:id/edit`, `/distributor/shipments/:id/packing-list`, `/distributor/shipments/new`, `/lab/orders`, `/lab/orders/:id` (+22) |
| Goods receipt (GR-) | goods_receipts | Number, origin company and GLN, received_at, received_by, items count, discrepancies count, is_return | 26: [`v-q64497Ft`](https://doop.design/c/LQFIZlhE35?frame=v-q64497Ft), [`NwX0CruZHC`](https://doop.design/c/LQFIZlhE35?frame=NwX0CruZHC), [`R3EZTr4ePq`](https://doop.design/c/LQFIZlhE35?frame=R3EZTr4ePq), [`pTKmcZsilq`](https://doop.design/c/LQFIZlhE35?frame=pTKmcZsilq), [`JoswSNZBZB`](https://doop.design/c/LQFIZlhE35?frame=JoswSNZBZB), [`L7MPRjX9Qe`](https://doop.design/c/LQFIZlhE35?frame=L7MPRjX9Qe), [`UKUgQMR4Jy`](https://doop.design/c/LQFIZlhE35?frame=UKUgQMR4Jy), [`X42vxHfarW`](https://doop.design/c/LQFIZlhE35?frame=X42vxHfarW), [`smasDT3VJx`](https://doop.design/c/LQFIZlhE35?frame=smasDT3VJx), [`4zyleLd04x`](https://doop.design/c/LQFIZlhE35?frame=4zyleLd04x), [`UAtyAbR4zW`](https://doop.design/c/LQFIZlhE35?frame=UAtyAbR4zW), [`yEEv1GtG-f`](https://doop.design/c/LQFIZlhE35?frame=yEEv1GtG-f), [`jeML6KCYpu`](https://doop.design/c/LQFIZlhE35?frame=jeML6KCYpu), [`SGSvCmQYUS`](https://doop.design/c/LQFIZlhE35?frame=SGSvCmQYUS) (+12) | 5: `/distributor/batches/:id`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/platform/recalls` |
| Requisition (REQ-) | requisitions | Number, site, product and quantity (or lines), status, requested_by, reviewed_by and reviewed_at, rejection_reason, needs_reorder | 19: [`9FqxTu2HSn`](https://doop.design/c/LQFIZlhE35?frame=9FqxTu2HSn), [`W3kDRxq2N5`](https://doop.design/c/LQFIZlhE35?frame=W3kDRxq2N5), [`-6iUpBxdKZ`](https://doop.design/c/LQFIZlhE35?frame=-6iUpBxdKZ), [`nzi5p4-AI5`](https://doop.design/c/LQFIZlhE35?frame=nzi5p4-AI5), [`9M_rqF3EVx`](https://doop.design/c/LQFIZlhE35?frame=9M_rqF3EVx), [`Sjnr9gxKcg`](https://doop.design/c/LQFIZlhE35?frame=Sjnr9gxKcg), [`0TOJ-OerfR`](https://doop.design/c/LQFIZlhE35?frame=0TOJ-OerfR), [`LHl7qlHyR_`](https://doop.design/c/LQFIZlhE35?frame=LHl7qlHyR_), [`zBzFGblRnK`](https://doop.design/c/LQFIZlhE35?frame=zBzFGblRnK), [`xYILh6bLB1`](https://doop.design/c/LQFIZlhE35?frame=xYILh6bLB1), [`hLNbpWQx_q`](https://doop.design/c/LQFIZlhE35?frame=hLNbpWQx_q), [`Z2-QOnLxHN`](https://doop.design/c/LQFIZlhE35?frame=Z2-QOnLxHN), [`igIKdkIMxW`](https://doop.design/c/LQFIZlhE35?frame=igIKdkIMxW), [`tHrj71_Sgx`](https://doop.design/c/LQFIZlhE35?frame=tHrj71_Sgx) (+5) | 15: `/distributor/batches/:id`, `/distributor/receiving`, `/distributor/receiving/:id`, `/distributor/receiving/new`, `/lab/requisitions`, `/lab/requisitions/:id`, `/lab/requisitions/new`, `/org/requisitions`, `/org/requisitions/:id`, `/org/requisitions/:id/fulfill`, `/org/requisitions/:id/reject`, `/org/requisitions/:id/review` (+3) |
| Patient | patients | Full name, gender, date of birth (age), phone, national ID, GSRN, last visit | 37: [`dmDflEXJzh`](https://doop.design/c/LQFIZlhE35?frame=dmDflEXJzh), [`hWFPMYtHfw`](https://doop.design/c/LQFIZlhE35?frame=hWFPMYtHfw), [`lDrhCsUsP3`](https://doop.design/c/LQFIZlhE35?frame=lDrhCsUsP3), [`3GldJbxDi_`](https://doop.design/c/LQFIZlhE35?frame=3GldJbxDi_), [`riyYzJBrXt`](https://doop.design/c/LQFIZlhE35?frame=riyYzJBrXt), [`uxHhaGcWYf`](https://doop.design/c/LQFIZlhE35?frame=uxHhaGcWYf), [`xI4O9rP0gg`](https://doop.design/c/LQFIZlhE35?frame=xI4O9rP0gg), [`SaY_PCI1oD`](https://doop.design/c/LQFIZlhE35?frame=SaY_PCI1oD), [`UvrfVC7Fqk`](https://doop.design/c/LQFIZlhE35?frame=UvrfVC7Fqk), [`Gk9dR356pj`](https://doop.design/c/LQFIZlhE35?frame=Gk9dR356pj), [`VRY0p3ZE2z`](https://doop.design/c/LQFIZlhE35?frame=VRY0p3ZE2z), [`QN8jY331nC`](https://doop.design/c/LQFIZlhE35?frame=QN8jY331nC), [`vHqhV0Iw7I`](https://doop.design/c/LQFIZlhE35?frame=vHqhV0Iw7I), [`45FlJvpVyi`](https://doop.design/c/LQFIZlhE35?frame=45FlJvpVyi) (+23) | 28: `/lab`, `/lab/orders`, `/lab/orders/:id`, `/lab/orders/:id/collect`, `/lab/orders/:id/consumables/new`, `/lab/orders/:id/payments/new`, `/lab/orders/:id/report`, `/lab/orders/:id/results/:result_id/edit`, `/lab/orders/:id/specimens/:specimen_id/label`, `/lab/orders/:id/tests/new`, `/lab/orders/new`, `/lab/patients` (+16) |

Frame and route lists are a text scan (ID patterns and labels in frame HTML and names; field names in LiveView templates), so they are broad. Peek rules: open on hover after a short delay and on keyboard focus, show 4 to 6 key-value rows plus one "Open" link to the entity's own page (with `return_to`), codes in mono, times in EAT, no shadow (1px border on the raised surface), works in light and dark, never inside another peek.