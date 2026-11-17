# Known security risks — signup / onboarding

Identified while building the 4-step signup wizard (GS1 + PPB regulatory
verification). Both are open; neither is blocked on the other.

## 1. Organization impersonation at signup

**Where:** `lib/thamani_dawa_web/live/signup_live.ex`, the `:regulatory_details`
step (`ThamaniDawa.Grp.verify_prefix/1`, `ThamaniDawa.Ppb.verify_license/3`).

**Risk:** The regulatory-details step proves that an organization *exists* in
GS1's and PPB's public registries — it does not prove that the person signing
up is actually authorized to represent that organization. A GS1 company
prefix and a PPB license number are both things a competitor, a former
employee, or anyone who has seen a pharmacy's paperwork could plausibly
obtain, since PPB's facilities register is public by design.

As it stands, anyone who knows those two numbers for an existing licensed
organization (e.g. "MedPoint Pharmacy") can complete signup, pass
verification, and start operating in Thamani Dawa *as* that organization. No
proof-of-ownership challenge (confirmation email to a registered contact,
phone verification, manual review, etc.) exists anywhere in the flow.

**Mitigation options (not yet decided/implemented):**
- Require the admin's email domain to match a domain already associated with
  the GS1/PPB registration, where available.
- Flag newly self-signed-up organizations for manual review before they can
  transact, rather than granting full access immediately on signup.
- Send the post-signup confirmation link (see Part D of the onboarding plan)
  to an address independently sourced from the registry record, not just the
  address the signer typed in — this doesn't fully close the gap by itself,
  but narrows it since the signer must additionally control that inbox.

## 2. No rate limiting on registry lookups during signup

**Where:** `lib/thamani_dawa_web/live/signup_live.ex`'s `check_gs1_prefix/2`
and `check_gln/2` (via `ThamaniDawa.Grp`), and the equivalent PPB lookup (via
`ThamaniDawa.Ppb`) — all reachable from the unauthenticated `/signup` page.

**Risk:** These lookups are debounced client-side (`phx-debounce="blur"`)
but have no server-side rate limit per IP/session. An attacker could script
the signup form to batch-query either registry through our server:

- Using Thamani Dawa as a free scraping proxy for GS1/PPB data (company
  prefixes → names/addresses; facility names → license status).
- Risk of our server's IP getting rate-limited or blocked by GS1
  Kenya/PPB for abusive traffic patterns that aren't actually ours.
- Resource exhaustion on our own `Req`-based lookup workers
  (`start_async(:gs1_prefix_lookup, ...)` / `start_async(:gln_lookup, ...)`)
  if hit at volume.

**Mitigation options (not yet decided/implemented):**
- Per-IP rate limit on `/signup`'s lookup-triggering events (e.g. via
  `Hammer` or a Plug-level limiter in front of the LiveView socket).
- CAPTCHA or similar friction before the first registry lookup in a session.
- Cache recent lookup results briefly server-side to absorb repeated queries
  for the same prefix/GLN/license number within a short window.

## 3. External API integrations need a full best-practices survey

**Where:** every outbound HTTP client — `ThamaniDawa.Grp` (GS1 GRP),
`ThamaniDawa.Ppb` (PPB registry), `ThamaniDawa.Daraja` (M-Pesa), `ThamaniDawa.GtinLookup`/`VerifyGtin`,
and the planned KMLTTB (lab registry) client.

**Risk:** each client was built somewhat independently, with inconsistent
timeout/retry policies and no shared story for rate limiting (ours or
theirs), caching of repeat lookups, circuit-breaking during an outage, or a
consistent error taxonomy. Item 2 above (no rate limiting on signup's
registry lookups) is one symptom of this broader gap, not the whole of it.

**Not yet done:** a proper survey of all external integrations against a
standard checklist — auth/credential handling, our-side rate limiting,
documented limits on their side, timeout + retry/backoff policy, outage/
circuit-breaking behavior, caching, error taxonomy, and logging/
observability — to be written up and prioritized later, not assumed fine
by default.

## 4. PPB/KMLTTB facility name isn't cross-checked against the GS1-resolved org name

**Where:** `lib/thamani_dawa_web/live/signup_live.ex`'s `check_ppb/2` and
`check_kmlttb/2` — `ppb_facility_name`/`kmlttb_facility_name` are prefilled
from the GS1-resolved organization name (`maybe_autofill_ppb_facility_name/1`,
`maybe_autofill_kmlttb_facility_name/1`) but left freely editable, and nothing
re-validates the two against each other afterward.

**Risk:** the GS1 company prefix step can resolve one organization's
registered name (e.g. "GS1 Kenya GLN Registry" in one observed case), while
the PPB/KMLTTB facility-name field is then changed to something entirely
different (e.g. "Pharmaplus") and still verifies successfully — because PPB
and KMLTTB verification only checks that *that* typed name+license pair
exists in *their* registry, independent of whatever the GS1 step resolved.
There's currently no step that confirms the same real-world organization is
behind all three identifiers (GS1 prefix, PPB license, KMLTTB license).

**Not yet fixed (flagged only):** some fuzzy-match or explicit confirmation
step tying the GS1-resolved name to the PPB/KMLTTB-resolved facility name
(e.g. a warning when they diverge significantly, or requiring explicit
confirmation of the mismatch) would close this, but needs product input on
how strict that check should be — trading names legitimately differ from
legal names, so an exact-match requirement would likely produce false
positives.
