# TODO

## Product backlog

- Customer quotations as printable/emailable documents: a formal price quote the distributor can
  hand or send (print, email, text) to a customer before they commit — no stock reservation, no
  conversion into an order. A prior attempt (`Quotations`/`DistributorQuotationLive`) built this as
  a DB-backed record with a "convert to sales order" step and was removed because (a) it had no
  actual document generation — nothing to print/email/send, so it was a dead end as a quoting tool,
  and (b) the conversion target (`SalesOrders`) was removed too (see below). Re-scope to just the
  document: customer + line items + price, rendered as something shareable, with no stock or order
  logic attached.
- Customer payment/invoicing: currently a distributor and customer settle outside the system
  entirely (no invoice, no payment status tracked anywhere). Deferred deliberately for MVP — adding
  a manually-ticked "paid" field with nothing downstream reading it would just be stale bookkeeping
  nobody trusts. Revisit once there's an actual accounting/invoicing need; if/when a sales-order-like
  concept returns, payment status belongs on that commercial record, not on `Shipment` (which has no
  `customer_id`/price — its destination is just a GLN, not necessarily a paying customer).
- A prior `SalesOrders`/`DistributorSalesOrderLive` feature (customer + price + FEFO stock
  allocation, `draft -> confirmed -> fulfilled/cancelled`) was removed. It decremented
  `batch.remaining_quantity` directly on confirmation, as a second, uncoordinated stock-reservation
  mechanism alongside `Distributor.Shipment`'s serial reservation on submit (finalized on
  `approve_shipment/3`, which depletes scanned units' batches) — the two could draw from the
  same batch with neither aware of the other. Its `:fulfilled` status was also never wired to
  anything; nothing ever created or linked a `Shipment` from a confirmed order, so it was a dead
  end in practice. If a customer-order concept is rebuilt, it should delegate actual stock
  movement to `Shipment` approval rather than decrementing batches itself.
- Gate the requisition queue (`Requisitions`, `RequisitionQueueLive`) behind `Sites.multi_site?/1`.
  Single-site orgs currently have to create a requisition, wait for org approval, then dispatch
  stock to the one site they already own — no stock actually moves, so the whole
  approve→dispatch→receive cycle is pure overhead. Stock received by a single-site org should
  land directly on that site.
- Add a `BatchEvent` audit log (mirroring `Distributor.ShipmentEvent`) so the Batch Show page can
  display an "Activity"/journey timeline like the Shipment Show page already has (e.g. "Received
  from X", "Entered quarantine", "Released from quarantine", "EPCIS event sent/accepted"), instead
  of only showing the batch's current status/zone. Needs: a `batch_events` table (event, details,
  actor, timestamp), inserts at every `receive_changeset`/`status_changeset`/`location_changeset`
  transition in `lib/thamani_dawa/batches.ex`, and rendering on the batch show LiveView. Existing
  `Epcis.OutboxEvent` rows (`source_type: "batch"`) already give EPCIS submission history for free
  and should be merged into the same timeline rather than duplicated.
- Breaking bulk for receiving/storage needs real design work before building: a fixed
  per-`Product` conversion ratio (`units_per_pack`/a hypothetical `units_per_case`) is the wrong
  model, because box/carton size varies by delivery, not by product — the same product can arrive
  in differently-sized cartons across shipments. The real shape (per internal chat) is: receiving
  happens under a shipper SSCC, and "breaking bulk for storage" means splitting that received SSCC
  into several new child SSCCs for storage/shipping, where the user specifies arbitrary item counts
  per group at split time (not a fixed per-product ratio) — e.g. "this pallet had 3 shippers of 20
  boxes each." Those mini-SSCCs should then be shippable either as a whole (reusing their own SSCC
  outbound, which `Distributor.issue_ssccs!/1` doesn't support today — it always mints a fresh SSCC
  per shipper) or broken again recursively into smaller mini-SSCCs. Needs: an SSCC-level batch-split
  context function (mirroring `Batches.dispatch_to_site/3`'s lock-parent/debit/create-child shape,
  but same site, minting a new SSCC per group via `GS1.Sscc.allocate/2`), EPCIS Pack/Unpack
  aggregation events for the split (requires first recording an aggregation at receipt time, which
  doesn't exist today — `record_goods_receipt/1` only emits a class-level `ObjectEvent`, no
  parent/child linkage), and a `Shipper`→source-batch link so packing can reuse an existing SSCC
  instead of always minting one.
- Add the ability to add (not remove) operating models from the org settings screen
  (`organization_settings_live.ex`). Backend already supports it — `Organization.changeset/2`
  casts/validates `:operating_models` and `update_organization_settings/2` already routes
  through it — the settings LiveView just renders `operating_models_label/1` as a read-only
  string (no form control). Add a multi-select wired to the existing "save" event; keep it
  additive only. Activities/operating_models must never be removable once set — once a site has
  done lab work (tests, patients, results tied to it), the lab operating model stays even if the
  org stops staffing lab work, because historical records are tied to it.

Thamani Dawa is better at symbol generation, but its implementation is not a perfect drop-in:

- Its invalid-GTIN fallback pads the original string instead of refusing generation.
- It places AI 10 before dates, which is valid but unnecessarily requires a separator.
- Its raw decoder accepts empty variable fields and duplicate AIs.
- Its raw decoder does not validate the GTIN check digit.
- Parentheses within batch or serial values require proper encoder escaping.


GS1's own rule settles which is right. Per the GS1 General Specifications, the governing rule has two parts:
1. A variable-length AI's data field must be terminated by FNC1/GS (ASCII 29) unless it's the last element string in the symbol — the terminator is only skippable at the very end.
2. On ordering: "predefined [fixed] length element strings should be followed by non-predefined [variable] length element strings" (GS1 Application Identifiers guide (https://plainbarcode.com/guides/gs1-application-identifiers-guide/); corroborated in multiple GS1 technical references found via search, and consistent with barcodefaq.com's AIM/GS1 FNC1 explainer (https://www.barcodefaq.com/2d/qr-code/aim-gs1-fnc1/)).

That second point is exactly the design decision in question, and it's not a stylistic preference — it's a direct robustness consequence of rule 1. Group all the fixed-length AIs first, and the only place in the whole symbol that ever depends on the separator surviving is the single boundary where the first variable field begins. Every fixed field before that point is immune to separator loss, because its boundary is positional, not separator-defined.

thamani_dawa's order violates that convention, and it's not just a style nit — it actively creates the exact failure mode you're fighting. By putting 10 (variable) immediately before 11/17 (fixed), it forces every label that has a batch number to rely on a surviving separator just to read the dates at all. If that separator is lost in transit, the batch value swallows into what should be the date bytes — you get garbage like letters inside a 6-digit date field instead of a clean parse failure. That's a worse failure shape than medic's: in medic's order, the dates always parse correctly regardless of separator survival; the fragile boundary is isolated to batch↔serial, which is the minimum unavoidable risk given both are free text.