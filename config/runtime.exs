import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Load local secrets from a .env file (dev/test only — never committed).
# Production should set real environment variables on the host/platform.
if config_env() in [:dev, :test] do
  env_path = Path.join(File.cwd!(), ".env")

  if File.exists?(env_path) do
    env_path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
    |> Enum.each(fn line ->
      case String.split(line, "=", parts: 2) do
        [key, value] -> System.put_env(String.trim(key), String.trim(value))
        _ -> :ok
      end
    end)
  end
end

# Mail provider: MailSafi Postal, the same provider used by the medic app.
# Swoosh's Postal adapter appends /api/v1/send/message itself, so accept either
# medic's full send endpoint or the bare server base URL in POSTAL_API_URL.
if config_env() != :test do
  postal_api_key =
    case System.get_env("POSTAL_API_KEY") do
      key when is_binary(key) and key != "" ->
        key

      _ ->
        if config_env() == :prod do
          raise """
          environment variable POSTAL_API_KEY is missing.
          Create a MailSafi Postal server API key and expose it to the release.
          """
        end
    end

  postal_api_url =
    case System.get_env("POSTAL_API_URL") do
      url when is_binary(url) and url != "" -> url
      _ -> "https://postalmail.mailsafi.com/api/v1/send/message"
    end

  postal_base_url =
    postal_api_url
    |> String.trim_trailing("/")
    |> String.replace_suffix("/api/v1/send/message", "")

  # Dev falls back to the local mailbox until a key is supplied; production
  # always sends through Postal.
  if config_env() == :prod or not is_nil(postal_api_key) do
    config :thamani_dawa, ThamaniDawa.Mailer,
      adapter: Swoosh.Adapters.Postal,
      api_key: postal_api_key,
      base_url: postal_base_url

    config :swoosh, api_client: Swoosh.ApiClient.Req
  end

  sender_email =
    case System.get_env("POSTAL_FROM_ADDRESS") do
      address when is_binary(address) and address != "" -> address
      _ -> "noreply@thamanidawa.example"
    end

  sender_name =
    case System.get_env("POSTAL_FROM_NAME") do
      name when is_binary(name) and name != "" -> name
      _ -> "Thamani Dawa"
    end

  config :thamani_dawa, ThamaniDawa.Accounts.UserNotifier,
    sender_email: sender_email,
    sender_name: sender_name
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/thamani_dawa start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :thamani_dawa, ThamaniDawaWeb.Endpoint, server: true
end

config :thamani_dawa, ThamaniDawa.GtinLookup, api_key: System.get_env("GS1_GRP_API_KEY")

config :thamani_dawa, :google_maps, api_key: System.get_env("GOOGLE_MAPS_API_KEY")

daraja_enabled = System.get_env("DARAJA_ENABLED", "false") in ~w(true 1 yes)
config :thamani_dawa, :daraja_enabled, daraja_enabled

if daraja_enabled do
  config :thamani_dawa, ThamaniDawa.Daraja,
    base_url: System.get_env("DARAJA_BASE_URL", "https://sandbox.safaricom.co.ke"),
    consumer_key: System.get_env("DARAJA_CONSUMER_KEY"),
    consumer_secret: System.get_env("DARAJA_CONSUMER_SECRET"),
    shortcode: System.get_env("DARAJA_SHORTCODE"),
    passkey: System.get_env("DARAJA_PASSKEY"),
    callback_url: System.get_env("DARAJA_CALLBACK_URL"),
    callback_token: System.get_env("DARAJA_CALLBACK_TOKEN"),
    retry: false
end

epcis_cred_key =
  if config_env() == :prod do
    System.get_env("EPCIS_CRED_ENCRYPTION_KEY") ||
      raise """
      environment variable EPCIS_CRED_ENCRYPTION_KEY is missing.
      You can generate one by calling: 32 |> :crypto.strong_rand_bytes() |> Base.encode64()
      """
  else
    # Fixed, non-secret key for dev/test only — every developer's local org-level
    # EPCIS credentials are encrypted with the same key, which is fine since none
    # of this data is real outside of a deployed environment.
    System.get_env("EPCIS_CRED_ENCRYPTION_KEY") ||
      "9ibsDRVZhhbMjD1hJ47dCv+tZZm+171DJvIW2hdz/wg="
  end

config :thamani_dawa, ThamaniDawa.Vault,
  json_library: Jason,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!(epcis_cred_key)}
  ]

config :thamani_dawa, ThamaniDawa.Epcis.Client,
  base_url: System.get_env("PPB_TNT_BASE_URL"),
  capture_path: System.get_env("PPB_TNT_CAPTURE_PATH", "/api/integration/facility/events"),
  api_key: System.get_env("PPB_TNT_API_KEY"),
  distributor_capture_path:
    System.get_env("PPB_TNT_DISTRIBUTOR_CAPTURE_PATH", "/api/integration/supplier/events"),
  distributor_api_key: System.get_env("PPB_TNT_DISTRIBUTOR_API_KEY"),
  manufacturer_capture_path:
    System.get_env("PPB_TNT_MANUFACTURER_CAPTURE_PATH", "/api/integration/manufacturer/events"),
  manufacturer_api_key: System.get_env("PPB_TNT_MANUFACTURER_API_KEY"),
  # Always disabled under `mix test`, regardless of a developer's local
  # `.env` — the test suite must stay deterministic and never depend on
  # live credentials meant for manual `mix run` verification.
  enabled: config_env() != :test and System.get_env("PPB_TNT_ENABLED", "false") == "true"

member_api = [
  base_url: System.get_env("GS1_MEMBER_API_BASE_URL")
]

member_api =
  if config_env() == :test do
    Keyword.put(member_api, :client, ThamaniDawa.GS1.MemberApiStub)
  else
    member_api
  end

config :thamani_dawa, ThamaniDawa.GS1.MemberApi, member_api

company_prefix = System.get_env("GS1_COMPANY_PREFIX")

if company_prefix not in [nil, ""] do
  config :thamani_dawa, ThamaniDawa.Gln, company_prefix: company_prefix
end

config :thamani_dawa, ThamaniDawaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "5780"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :thamani_dawa, ThamaniDawa.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :thamani_dawa, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :thamani_dawa, ThamaniDawaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :thamani_dawa, ThamaniDawaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :thamani_dawa, ThamaniDawaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :thamani_dawa, ThamaniDawa.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
