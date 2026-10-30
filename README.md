# ThamaniDawa

ThamaniDawa is a Phoenix 1.8 application for running a tenant-scoped pharmacy and diagnostic lab operation. It gives an organization admin a team/site setup area, pharmacists a stock and prescription-dispensing portal, and lab technicians a lab-order/result-verification portal.

Major areas:

- Public home, login, signup, and invite-acceptance flows
- Organization admin for team invites and site management
- Organization catalogue, suppliers, central stock, dispatch, requisitions, sites, team, dashboards, and earnings
- Pharmacy stock receipt/browse/scan, requisitions, patients, prescriptions, FEFO dispensing, quick sales, payments, and receipts
- Lab test catalogue, stock receipt/browse/scan, requisitions, patients, orders, specimens, results/amendments, consumable usage, and payments

## Prerequisites

- Elixir: `~> 1.15` from `mix.exs`
- Erlang/OTP: no `.tool-versions` pin is committed; use an OTP release compatible with Elixir 1.15+
- PostgreSQL with local credentials from `config/dev.exs`: user `postgres`, password `postgres`, host `localhost`
- Node is only needed indirectly for Phoenix asset tooling; assets are built through the Mix-managed esbuild and Tailwind packages

## Setup

```sh
mix setup
```

This installs dependencies, creates/migrates the database, runs `priv/repo/seeds.exs`, installs asset tools if missing, and builds assets.

## Run

```sh
mix phx.server
```

Open http://localhost:4000. The runtime `PORT` env var can override the port; dev defaults to `4000`.

## Seeded Logins

All seeded users use PIN `1234` for secondary PIN checks.

| Email                    | Password       | Role             | Default area                         |
| ------------------------ | -------------- | ---------------- | ------------------------------------ |
| `admin@example.com`      | `password1234` | `admin`          | `/pharmacy`, plus `/org/*`, `/lab/*` |
| `pharmacist@example.com` | `password1234` | `pharmacist`     | `/pharmacy`                          |
| `lab@example.com`        | `password1234` | `lab_technician` | `/lab`                               |

## Common Commands

```sh
mix setup              # first-time setup
mix ecto.setup         # create, migrate, and seed the database
mix ecto.reset         # drop the database, then run ecto.setup
mix run priv/repo/seeds.exs
mix phx.server
mix test
mix format
mix credo --strict
mix assets.build
mix assets.deploy
mix precommit
```

`mix precommit` compiles with warnings as errors, checks unused deps, formats, runs Credo, and runs tests. There are no intentionally blocked destructive aliases in this project; `mix ecto.reset` is destructive because it drops the local database.

## Opening a Pull Request

Before opening a pull request:

1. Run `./scripts/check_linters.sh` and fix any formatting, Credo, or test failures.
2. Fill out the pull request summary, changes, and how-to-test sections.
3. Add screenshots or screen recordings for UI changes. Use `N/A` when there are no visual changes.
4. Complete the pull request checklist, including docs, migrations, seeds, and secrets checks when relevant.

### Commit Messages

Use the format `name/what-pr-does` for commit messages.

Examples:

```sh
michael/add-lab-order-filters
sarah/fix-prescription-validation
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Domains](docs/DOMAINS.md)
- [Portals](docs/PORTALS.md)
- [Authentication and Authorization](docs/AUTH.md)
- [Data Model](docs/DATA_MODEL.md)
- [Workflows](docs/WORKFLOWS.md)
- [Manual test playbook](docs/MANUAL_TEST_PLAYBOOK.md)
- [Real-world workflow gap analysis](docs/REAL_WORLD_WORKFLOW_GAP_ANALYSIS.md)
- [Environment](docs/ENVIRONMENT.md)
