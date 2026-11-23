# Thamani Dawa API v1

Requests for the mobile JSON API under `/api/v1`. Open this folder in Bruno
and pick the `local` environment.

1. Set `email`, and `password` as a secret, then run **Sessions / Login**. It
   saves `access_token`.
2. For the packing app, set `mobile_username` and `pin`, then run
   **Sessions / Mobile login**. It saves `mobile_access_token`.
3. Set the ids (`product_id`, `site_id`, `stock_take_id`, ...) to rows in
   your local database.

Writes signed in as staff send a fresh `Idempotency-Key`. See
`docs/API.md` for the rules behind each endpoint.
