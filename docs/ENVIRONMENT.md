# Environment

## Development

Configuration source: `config/dev.exs`.

| Setting | Value | Required | Notes |
| --- | --- | --- | --- |
| Database username | `postgres` | Yes | Local Postgres user |
| Database password | `postgres` | Yes | Local Postgres password |
| Database host | `localhost` | Yes | Local Postgres host |
| Database name | `thamani_dawa_dev` | Yes | Created by `mix ecto.setup` |
| Endpoint IP | `127.0.0.1` | Yes | Loopback only |
| Endpoint port | `4000` | No | Set in `runtime.exs` through `PORT`, defaults to `4000` |
| `secret_key_base` | committed dev secret | Yes | Dev only |
| `dev_routes` | `true` | No | Enables LiveDashboard and mailbox |

Dev uses file watchers for Mix-managed esbuild and Tailwind.

## Test

Configuration source: `config/test.exs`.

| Setting | Value | Required | Notes |
| --- | --- | --- | --- |
| Database name | `thamani_dawa_test#{MIX_TEST_PARTITION}` | Yes | Supports partitioned tests |
| Endpoint port | `4002` | No | Server disabled by default |
| Mailer | `Swoosh.Adapters.Test` | Yes | No real email delivery |
| `MIX_TEST_PARTITION` | unset by default | Optional | Used by CI/test partitioning |

## Production Runtime

Configuration source: `config/runtime.exs` when `config_env() == :prod`.

| Env var | Required | Default | Purpose |
| --- | --- | --- | --- |
| `DATABASE_URL` | Yes | none | Ecto database URL, e.g. `ecto://USER:PASS@HOST/DATABASE` |
| `SECRET_KEY_BASE` | Yes | none | Signs/encrypts cookies and LiveView data |
| `PHX_HOST` | No | `example.com` | Host used in endpoint URL |
| `PORT` | No | `4000` | HTTP listen port |
| `POOL_SIZE` | No | `10` | Repo connection pool size |
| `ECTO_IPV6` | No | false | Enables IPv6 socket options when `true` or `1` |
| `DNS_CLUSTER_QUERY` | No | nil | DNS clustering query |
| `PHX_SERVER` | No | false | Starts endpoint server in releases |

Production also enables SSL forcing in `config/prod.exs`, configures Swoosh to use `Swoosh.ApiClient.Req`, and expects static assets to be digested with `mix assets.deploy`.

## Mix Aliases

| Alias | Commands |
| --- | --- |
| `mix setup` | `deps.get`, `ecto.setup`, `assets.setup`, `assets.build` |
| `mix ecto.setup` | `ecto.create`, `ecto.migrate`, `run priv/repo/seeds.exs` |
| `mix ecto.reset` | `ecto.drop`, `ecto.setup` |
| `mix test` | `ecto.create --quiet`, `ecto.migrate --quiet`, `test` |
| `mix assets.setup` | install Tailwind and esbuild if missing |
| `mix assets.build` | compile, Tailwind build, esbuild build |
| `mix assets.deploy` | minified Tailwind/esbuild and `phx.digest` |
| `mix precommit` | warnings-as-errors compile, unused dep check, format, Credo, tests |

No aliases are intentionally blocked or overridden. `mix ecto.reset` is intentionally destructive because it drops the local database before rebuilding it.
