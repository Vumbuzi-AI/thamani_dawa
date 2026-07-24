defmodule ThamaniDawa.Payments.WalletEntry do
  @moduledoc """
  An immutable site wallet credit, recorded exactly once per completed
  payment (enforced by a unique index on `payment_id`). There is no update
  changeset — a wallet entry is never edited or reversed, only inserted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_entries" do
    field :amount, :decimal

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :payment, ThamaniDawa.Payments.Payment

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:site_id, :payment_id, :amount])
    |> validate_required([:site_id, :payment_id, :amount])
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:payment_id)
    |> unique_constraint(:payment_id, message: "already has a wallet credit")
  end
end
