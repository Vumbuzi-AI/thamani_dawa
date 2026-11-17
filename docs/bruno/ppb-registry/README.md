# PPB Registry Bruno collection

Open this directory as a collection in Bruno:

```text
docs/bruno/ppb-registry
```

The collection contains three requests:

1. A retail facility search using `Curewave Pharmacy`.
2. A wholesale distributor search using `Abacus Pharma`.
3. A KMLTTB lab facility search using `Cerba Lancet` — a different board and
   host (`kmlttb.org`) from the first two, since PPB doesn't license
   diagnostic labs at all; that's KMLTTB's remit.

For the two PPB requests, change only `search[value]`. Keep the DataTables
parameters in place because the PPB endpoint returns an empty result when the
column metadata is omitted. Use `ftype: retail` for pharmacies and
`ftype: wholesale` for distributors. The endpoint returns JSON but
incorrectly labels it as `text/html`.

For the KMLTTB request, change only `search` — it's a plain query param, not
DataTables-style, and the response is a real HTML table fragment, not JSON.
Unlike PPB's masked license numbers, KMLTTB's per-facility detail page
(`view_record.php?id=<id>`, linked from each search result row) shows the
full, unmasked Licence No.

If Bruno reports a certificate error, disable SSL certificate verification for
this collection while the PPB host's certificate is invalid.
