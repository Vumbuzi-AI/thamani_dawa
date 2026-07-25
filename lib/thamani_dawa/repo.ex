defmodule ThamaniDawa.Repo do
  use Ecto.Repo,
    otp_app: :thamani_dawa,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 8
end
