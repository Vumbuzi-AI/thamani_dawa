# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :thamani_dawa,
  ecto_repos: [ThamaniDawa.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :thamani_dawa, ThamaniDawaWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThamaniDawaWeb.ErrorHTML, json: ThamaniDawaWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ThamaniDawa.PubSub,
  live_view: [signing_salt: "mRZDJjbN"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :thamani_dawa, ThamaniDawa.Mailer, adapter: Swoosh.Adapters.Local

# Configure the "from" address used on outgoing account emails.
config :thamani_dawa, ThamaniDawa.Accounts.UserNotifier,
  sender_name: "Thamani Dawa",
  sender_email: "noreply@thamanidawa.example"

# Configure how long each kind of auth token stays valid. Centralized here
# so the windows can be tuned per environment without touching code.
config :thamani_dawa, ThamaniDawa.Accounts.UserToken,
  session_validity_in_days: 60,
  invite_validity_in_days: 7,
  reset_password_validity_in_days: 1

config :thamani_dawa, ThamaniDawa.GtinLookup, base_url: "https://grp.gs1.org"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  thamani_dawa: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  thamani_dawa: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
