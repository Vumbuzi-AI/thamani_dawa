# Thamani Dawa web: design-system handoff (23 Nov 2026, 21:50 EAT)

Branch `sean/td-web-design-system`. Everything below is pushed. Nothing is left only on Krak's box.

## Ground rules
- The source of truth for UI is Doop canvas `LQFIZlhE35` (https://doop.design/c/LQFIZlhE35). Master's flow **logic** (routes, steps, data, behaviour) is canon. Master's markup and design are not: Doop and the TD design system are.
- Product leads engineering. Bau designs in Doop, then engineering builds frame by frame. Each spec gives the route, the `return_to` back target and every button's destination.
- Components: the `td_*` components in `lib/thamani_dawa_web/components/td_components.ex` (`td_dashboard`, `td_peek`, `GlnField`, `td_filter_menu`, the date picker and modals). Tokens are in `assets/css/td-tokens.css`. The dark map is `dmap.json` (156 light-to-dark pairs).
- Design rules: Phosphor icons. Seeded gradient orbs, never letter avatars. No native date inputs. EAT times like "18 Nov 2026, 10:44". Clean whites, no illustrations. Desktop only. Font weights at most 500, no 10 or 11px text. Fade with no blur, flat hover fills.
- Git rules: commit as Sean (agent19music <seanmotanya@gmail.com>) with no AI attribution. Never force-push. Never push to master unless Sean asks. Never run remote D1 or Sean's dev DB migrations.
- Before calling a screen done, check its empty, no-data and new-account states, and make sure every back button works.

## Test baseline
These 6 tests also fail on master:
- admin setup end-to-end
- SiteLive "verifying the GLN"
- requisition fulfill
- distributor draft shipment (the old `/distributor/shipments/new` form, no longer linked)
- manufacturer shipment create
- inventory disposals `approve_disposal`

These are known flakes that pass on retry: SiteLive GLN picker, ManufacturerProductLive "label resolves From/To", signup and pallet hierarchy. Run `mix test`, then `mix test --failed`.

## Files in this folder
| File | What it is |
|---|---|
| `distributor-handoff.md` | Bau's distributor flagship spec (68 frames, page "Flagship · Distributor", prototype from `BtVvvYcI0u`) |
| `manufacturer-handoff.md` | Bau's manufacturer flagship spec (58 frames, page `GCvBvFLYxw`, prototype from `rOKtmxrk0b`), including the **Polish pass** and **Gap pass** sections at the end, which supersede "Code gaps and notes" |
| `dmap.json` | The light-to-dark colour map for dark mode |
| `frame-ledger.md` | Per-frame status for all 482 web frames. Section 12 covers the distributor flagship |
| `ledger/` | `status.json` (done ids), `web_frames.tsv`, `flows.json`, `build_ledger.py`. Don't rerun `build_ledger.py` blindly: it drops hand-added notes 10 and 11 and doesn't know the flagship pages |
| `brief-areas.md` | Bau's area specs, §1 to §18 |
| `krak-code-map.md` | A map of how routes and flows work in code today, and their known logic problems |
| `doop-inventory.md` | Bau's inventory of the Doop frames |

## Where things stand

### 1. General restyle (ledger)
- 147 of 482 web frames are done. 333 are todo, split like this:
  - 15 are held for Bau's gap frames (now unheld; see below).
  - 96 belong to the flagship flows.
  - 222 are eligible: shared 70, org and platform 61, pharmacy 50, lab 41.
- Latest restyle commit is `f353f45`. It covers the org products list, pharmacy prescriptions, goods-receipt print and download, CSV export, filter menus, the org receive wizard, the org admin and site dashboards, TNT reporting, signup, the pharmacy dashboard, lab §5 and §6, NAV-1 and NAV-2, EMPTY-1, notifications and the manufacturer command menu.
- Next areas, largest first: shared (auth, onboarding, site switcher, product tour, error pages), org and platform (sites, add/import product steps, suppliers, requisition queue, settings), then pharmacy (quick sale, dispense, payment, patients, stock takes) and lab.

### 2. Distributor flagship (`7988b64`..`15d1376`)
- About 39 of the 68 frames are done, and the partials were mostly closed in `942c852` and `53ceb17`. What's built:
  - Orders: tabs for draft, submitted and rejected; the New order modal with the shared GlnField; detail; approve, reject and edit details; approving with too few serials shows an error.
  - Shipments: open on Ready (approved), with peeks.
  - Receiving: filters, an inline scanner with an expected-vs-received table, the accept-delivery confirm, the receipt, and resolve discrepancy with an outcome.
  - Returns: supplier and customer lists, detail pages and modals.
  - Customers: a list with stats, a side panel (`?customer=ID`) and the GLN peek.
  - The peeks sheet and the didn't-load states.
  - Nav: Orders, Supplier returns, Customer returns, API keys. The dashboard button now says "New order".
- Migration `20261123180000` adds `outcome` and `resolution_note` to receiving discrepancies. It ran only on Krak's box test DB.
- Not done:
  - A visual dark-mode check (the new CSS uses tokens; check it against `dmap.json`).
  - Loading skeletons (the lists render on the server).
  - Anything on HOLD.

### 3. Manufacturer flagship (`366d805`, `8672ffa`, `e76d638`)
- Done:
  - Step 1, Products: Generate serials and View serials, the GTIN peek, a serials filter, plus sync error and empty states.
  - Step 2, Batches: the selected batch summary, a serial preview, a label preview and bulk Print labels.
  - Step 3, View serials: the list, plus the shipper SSCC serials page with a `return_to` back link and Print label.
- Still to check: that generating serials lands on Batches with `?batch` selected (spec frame `4KdsxCd1Xj`), and which routes were used for the serials/pack live_action and `/manufacturer/sscc/:id/serials`. Read `router.ex`, then confirm them to Bau.
- Next, in this order:
  1. Step 4, Pack into shipper: `ijOdE3IvVJ` to `Og6REur2VF` to `97tWE2wGEU`, with one shipper label modal `NlxXvWnCVy`. Product SSCCs `C22opce6ED` gets a per-row Print label and Build a pallet. `TcfVwKaNOZ` becomes the shipper detail.
  2. Step 5, pallet scan: `InMakqK959` (errors `Vwv8gSu322`) to `Df97I34rKN` to pallet detail `kJVstU1vN8`. The AGG lists `nooman_e0w` and `9eVZhuE_oo` get Build a pallet.
  3. Step 6, Ship this pallet: `NSxDs_eqdr`, then the single shipments list `RRJbfBqPlL`.
  4. A single-date mode on the TD DatePicker (`chdlkoodd2`, example `JL8VPDk7sr`).
  5. Dark mode for every target, from `dmap.json`.
- HOLD: Add product.

### 4. Bau's former gap frames (now designed, not built)
- Org mobile users `/org/mobile-users`:
  - List `MYznkJ8Htz` (dark `U2u5djuS4_`).
  - Add and edit `QYpw0yuTrO` and `Qe-s68LnKS`.
  - Resend PIN and deactivate confirms `wpIwW0Fk5g` and `d04lKBEC4g`, as TD modals.
  - The sidebar item goes after Team.
- Org settings EPCIS mode (Automatic or Manual approval): `GjhsDici0w` and `3XFJf9bEa3` (dark `zm5b6_BWvJ` and `BvB-Jru3Gp`).
- GS1 company prefixes card in org settings: base `su8eaSdNu-`, remove confirm `NhRv63pG63`. The identifiers card keeps only the org GLN.
- Org sidebar: add API keys before TNT reporting.
- Still held: the dark card border token.

## Decisions Sean or Lucy need to make
1. **GS1 down:** should saved customers still go through when GS1 is down? Sean said to keep master's rule for now and is checking with Lucy.
2. **Automatic shipments:** should packing still create a shipment automatically?
3. **Pallet codes:** switch pallets from local `PAL-` codes to GS1 SSCCs?
4. **Shipments model:** merge the two shipment tables into one, and decide on EPCIS aggregation events.
5. **Pallets and shipped shippers:** pallets currently miss shippers that are already on a shipment.
6. **Reopen as draft:** it's mobile-only today. Should web have it?
7. **Approving with short serials:** master warns but still allows it.
8. **GS1 verification record:** the "Verified / Not in GS1" badge and the peek's "verified on" row need a stored record, which master doesn't keep.
9. **New order from a customer's panel:** pre-filling the customer needs a GS1 check first.
10. **Customer return on receiving:** the "is a customer return" switch is org-only.
11. **Refunds:** payments have no refunded status, so the refund UI is disabled.
12. **Near expiry:** the pharmacy window is 30 days (master); the frame says 90.
13. **Distributor HOLDs:**
    - adding items to an order on the web
    - a dispatched state
    - stock and pick list
    - where supplier return approval lives
    - orders for a GLN that isn't in GS1
    - what completing a customer return does to stock
    - the packing list copy

## Links
- Notion: [Thamani Dawa · Interface map](https://app.notion.com/p/421c34053a1f81429505e68c1b91557a)
- Doop canvas: https://doop.design/c/LQFIZlhE35
