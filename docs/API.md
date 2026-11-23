# Mobile JSON API (`/api/v1`)

The mobile apps call `/api/v1`. Controllers live in
`lib/thamani_dawa_web/controllers/api/v1/` and call the same contexts as the
web portals, so the business rules stay in one place. Requests for every
endpoint below are in `docs/bruno/api-v1`.

## Conventions

- Success: `{"data": ...}`, plus `"meta"` on lists
  (`page`, `per_page`, `total`, `total_pages`; `?page=` and `?per_page=`,
  100 at most).
- Errors: `{"error": {"code", "message", "fields"?}}`. Apps branch on
  `code`; `fields` holds changeset errors on a 422 `validation_failed`.
- Staff writes need an `Idempotency-Key` header. A retry with the same key
  replays the first answer instead of doing the work twice.
- Ids in bodies can be numbers or numeric strings.

## Signing in

- Staff (every portal except packing): `POST /login` with email and
  password, `POST /token/refresh`, `POST /logout`, `GET /me`. `/me` lists
  the portals the user can open; the rules match `ThamaniDawaWeb.Portals`.
- Distributor packers: `POST /distributor/mobile/login` with `username` and
  `pin`, then `token/refresh`, `logout` and `me` under the same prefix.
  These are `Distributor.MobileUser` accounts with their own tokens
  (`Distributor.MobileAuth`: one-hour access, 30-day refresh). A staff
  token is refused on mobile routes, and a mobile token on staff routes.
  Wrong PINs lock the account (423) and repeated attempts are rate limited
  (429).

## Catalog and warehouse stock

- `GET /products/:id` includes `undispatched` (warehouse batches not yet
  sent to a site) and `pending_receipt` (dispatched batches the site has
  not confirmed).
- Products expose `strength`, `pack_uom`, `units_per_pack`,
  `net_content_quantity` and `net_content_uom`. Batches expose `status`,
  `serials`, `sscc`, `logistic_unit_id`, `zone` and `bin`.
- `POST /products/:id/batches`:
  - with `site_id`: received straight at that site, auto-approved, and the
    EPCIS facility receipt fires;
  - no `site_id`, single-site organization: received at its only site;
  - no `site_id`, multi-site organization: received into warehouse stock,
    as on the web.
  - A `site_id` that is not a number is 422 `invalid_site_id`; another
    organization's site is 404.
- `POST /batches/:id/dispatch` with `site_id` and `quantity` moves
  warehouse stock to a site. A batch already at a site is 422
  `already_dispatched`.

## Usable stock

Pharmacy and lab stock lists leave out batches that are disaggregated,
returned or expired (expiry on or before today), matching the web.

## Stock takes and disposals

Site staff work at their current site under `/pharmacy/...` (medicine) or
`/lab/...` (lab consumables):

- Stock takes: `stock-takes`, `stock-takes/:id/items` (add a batch),
  `PUT stock-takes/:id/items/:item_id` (`counted_quantity`), `submit`,
  `reopen`.
- Disposals: `kind` is `expiry` (write-off) or `returned` (supplier
  return). Add batches with a `quantity`, then `submit` or `reopen`.

Only admins approve, under `/org/stock-takes` and `/org/disposals`
(`approve`, and `reject` with `rejection_reason`). Approving a disposal
re-checks stock; if it moved since submission the answer is 409
`stock_changed`.

## Recalls

Admins list recalls that touch their stock with `GET /org/recalls`
(`?status=open|closed` filters by the recall's status) and acknowledge one with
`POST /org/recalls/holders/:id/acknowledge`.

## Distributor staff

Under `/distributor`, for distributor staff and admins in an organization on
the distributor model. Staff stationed at a warehouse only see that
warehouse's receipts, discrepancies and returns.

- `GET receipts`, `GET receipts/:id`: goods receipts with their batches and
  discrepancies.
- `GET discrepancies` (open only), `POST discrepancies/:id/resolve` with
  `status` `found`, `lost` or `stolen`. Lost and stolen need
  `resolution_reference` and fire the EPCIS event.
- `GET`/`POST customers`, `PATCH customers/:id`.
- Customer returns: `POST customer-returns` (`customer_id`, `reason`,
  `notes`, `document_reference`; `site_id` only for staff with no station),
  `POST :id/items`, `DELETE :id/items/:item_id`, `POST :id/receive`,
  `PUT :id/items/:item_id` with `condition` (`sellable`, `damaged`,
  `quarantine`), `POST :id/inspect`, `POST :id/complete`. Completing puts
  each item away as a new batch and fires the EPCIS receiving event.

Receiving a delivery (`GoodsReceipts.receive_delivery`) is web only for
now; see the open questions in the pull request.

## Distributor packing (mobile users)

Under `/distributor/mobile`, with a mobile token:

- `GET shipments` (claimed or submitted by me), `GET shipments/search?order_number=`
  (drafts I can claim), `GET shipments/:id`.
- `POST shipments/:id/select` claims a draft, `release` lets it go.
- `POST shipments/:id/shippers`, `PATCH`/`DELETE shippers/:shipper_id`.
- `POST shippers/:shipper_id/items` with `raw_data_matrix` scans a pack.
  `DELETE items/:item_id` removes it; `PATCH items/:item_id` with
  `shipper_id` moves it.
- `POST shipments/:id/submit`, `POST shipments/:id/reopen`.

Writes answer with the whole shipment so the app redraws once. Mobile routes
don't take an `Idempotency-Key` yet, because the replay store is keyed to
staff users.

## Manufacturer

Under `/manufacturer`, for manufacturer staff and admins in a manufacturer
organization (the same check as the web portal). Only `GET gs1-prefixes` is
admin only. API keys, settings and EPCIS resends stay on the web.

- `GET dashboard`: counts, and aggregations awaiting review.
- Products: `GET`/`POST products`, `GET products/:id`,
  `GET products/gtin/:gtin`. The licence key is never returned.
- `GET products/:id/batches`, `GET products/:id/batches/:batch_id/serials`
  (paginated, with each serial's GS1 text) and `.../serials/export`.
- `POST products/:id/serials` is the + Serial wizard. `mode` is `stock`
  (`batch_no`, `production_date`, `expiry_date`, `primary_quantity`, at
  most 100) or `order` (also `shipper_quantity` and `to_gln`; From defaults
  to the current site). Serials are minted at the user's current site, which
  needs a GLN (422 `site_gln_required`). The validation rules are
  `Manufacturing.SerialGeneration`, shared with the web wizard; errors come
  back as 422 `validation_failed` with `fields`. A GS1 outage is 502
  `gs1_unavailable`.
- SSCCs: `GET products/:id/ssccs` (with serial counts), `GET ssccs/:id`,
  `GET ssccs/:id/serials`, `GET ssccs/:id/label` (the label's data),
  `GET ssccs/:id/export`.
- Exports return one object per row, keyed by the CSV's column names;
  `?format=csv` downloads the web's CSV.
- `GET inventory`: batches grouped by product.
- Aggregations: `GET aggregations` (`status`, `search`),
  `GET aggregations/ssccs` (SSCCs that can be packed),
  `POST aggregations/classify` (`sscc_id`, `serial`; read only),
  `POST aggregations` (`sscc_id`, and optionally `serials` to create it
  already submitted), `GET aggregations/:id`, `POST :id/items` (`serial`,
  drafts only), `POST :id/submit`, `POST :id/approve`, `POST :id/reject`
  (`reason`). Approving can return 422 `over_capacity` or `invalid_serials`;
  a step in the wrong state is 409 `invalid_state`.
- Shipments: `GET shipments` (`status`, `search`, `date_from`, `date_to`),
  `POST shipments` (`order_number`, `destination_gln`; `origin_gln`
  defaults to the current site), `GET shipments/:id`,
  `POST shipments/:id/approve`. These are the same manufacturer-tier
  shipments as the web: packers fill and submit them, staff approve.
  Approving an approved shipment returns it unchanged.
- EPCIS (read only): `GET epcis/status` (counts per status, whether the
  queue is halted, submission mode), `GET epcis/events` (newest 200,
  `status` and `search`), `GET epcis/events/:id` with the payload.
- `GET gs1-prefixes`: the organization's GS1 company prefixes.
