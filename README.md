# ThamaniDawa

ThamaniDawa is a Phoenix 1.8 application for running a tenant-scoped pharmacy and diagnostic lab operation. It gives an organization admin a team/site setup area, pharmacists a stock and prescription-dispensing portal, and lab technicians a lab-order/result-verification portal.

Major areas:

- Public home, login, signup, and invite-acceptance flows
- Organization admin for team invites and site management
- Pharmacy dashboard, products, stock receiving, prescriptions, controlled-drug register, logs, and GS1 scan lookup
- Lab dashboard, lab orders, result entry, verification queue, test templates/categories, stock receiving/consumption, QA charts, and GS1 scan lookup

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

| Email | Password | Role | Default area |
| --- | --- | --- | --- |
| `admin@example.com` | `password1234` | `admin` | `/pharmacy`, plus `/org/*`, `/lab/*` |
| `pharmacist@example.com` | `password1234` | `pharmacist` | `/pharmacy` |
| `lab@example.com` | `password1234` | `lab_technician` | `/lab` |

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

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Domains](docs/DOMAINS.md)
- [Portals](docs/PORTALS.md)
- [Authentication and Authorization](docs/AUTH.md)
- [Data Model](docs/DATA_MODEL.md)
- [Workflows](docs/WORKFLOWS.md)
- [Environment](docs/ENVIRONMENT.md)
