# Authentication And Authorization

Authentication is implemented in `ThamaniDawaWeb.SessionController` and `ThamaniDawaWeb.UserAuth`.

## User Model

`ThamaniDawa.Accounts.User` stores:

- `organization_id`: required tenant boundary.
- `site_id`: optional default/assigned site.
- `invited_by_id`: optional inviter.
- `name`, `email`, `hashed_password`.
- `hashed_pin`: optional 4-digit secondary-auth PIN hash.
- `role`: `:admin`, `:pharmacist`, or `:lab_technician`.
- `is_active`.

Passwords and PINs are hashed with Bcrypt. Email is globally unique.

## Sessions

Login posts `email` and `password` to `SessionController.create/2`. On success, `Accounts.generate_user_session_token/1` creates a `users_tokens` row and stores the raw token in the session under `user_token`.

The `:browser` pipeline runs `fetch_current_scope_for_user/2`. That loads the session user and assigns `current_scope`, a `ThamaniDawa.Accounts.Scope` struct containing the user and `organization_id`.

Logout deletes the session token and renews/clears the session.

## Route Guards

LiveView route groups use `ThamaniDawaWeb.UserAuth.on_mount/4`:

- `:mount_current_scope`: assign scope without requiring login.
- `:require_authenticated`: require any signed-in user.
- `:require_admin`: require `Scope.admin?/1`.
- `:require_pharmacy_access`: allow admins and pharmacists.
- `:require_lab_access`: allow admins and lab technicians.

Controllers receive `current_scope` from the browser pipeline.

## Role Mapping

| Role | Allowed routes |
| --- | --- |
| `admin` | `/org/*`, `/pharmacy/*`, `/lab/*` |
| `pharmacist` | `/pharmacy/*` |
| `lab_technician` | `/lab/*` |

After login, lab technicians are redirected to `/lab`; every other user is redirected to `/pharmacy`.

## Invites

Admins invite staff through `Accounts.invite_user/3`. The context:

1. Creates an unconfirmed user with name, email, role, and optional site.
2. Forces `organization_id` and `invited_by_id` from function arguments.
3. Validates that a chosen `site_id` belongs to the same organization.
4. Creates a one-time invite token.

`AcceptInviteLive` consumes the invite token and calls `Accounts.accept_invite/2` to set the password and invalidate outstanding invite tokens.

## PINs

`Accounts.set_user_pin/2` accepts only exactly four digits and stores `hashed_pin`. `Accounts.valid_pin?/2` verifies it. The current code defines the mechanism, but the router does not show a separate PIN-gated pipeline.

## Adding A Role

To add a role:

1. Add the atom to `@roles` in `ThamaniDawa.Accounts.User`.
2. Add helper predicates in `ThamaniDawa.Accounts.Scope` if needed.
3. Add or update `UserAuth.on_mount/4` guards.
4. Add routes in the proper `live_session`.
5. Update team invite UI role options and tests.
6. Create migrations only if the storage representation changes.
