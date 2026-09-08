defmodule ThamaniDawa.Serialisation.SerializationLog do
  @moduledoc """
  An audit row per generation event (§2.4.11). Distinct from
  `ThamaniDawa.Gs1Api.Request`, which audits the *call*: this records what was
  generated, and survives even when the shipment is later deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(sscc serialised)a

  schema "serialization_logs" do
    field :type, Ecto.Enum, values: @types
    field :gtin, :string
    field :batch, :string
    field :count, :integer, default: 0

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User
    belongs_to :shipment, ThamaniDawa.Serialisation.Shipment

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of generation event that get logged."
  def types, do: @types

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:type, :gtin, :batch, :count, :organization_id, :user_id, :shipment_id])
    |> validate_required([:type, :organization_id])
    |> validate_number(:count, greater_than_or_equal_to: 0)
  end
end
