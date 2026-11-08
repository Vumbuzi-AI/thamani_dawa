defmodule ThamaniDawa.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ThamaniDawaWeb.Telemetry,
      ThamaniDawa.Repo,
      ThamaniDawa.LoginRateLimiter,
      {DNSCluster, query: Application.get_env(:thamani_dawa, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ThamaniDawa.PubSub},
      # Start a worker by calling: ThamaniDawa.Worker.start_link(arg)
      # {ThamaniDawa.Worker, arg},
      # Start to serve requests, typically the last entry
      ThamaniDawaWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ThamaniDawa.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ThamaniDawaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
