defmodule ThamaniDawa.Serialisation.SerialisedCode do
  @moduledoc """
  One serialised trade item: a GTIN plus the unique serial GS1 issued for it.

  The serial is unique per organization, which is the guard against a
  double-write replaying an issued run into duplicate rows. The Data Matrix
  payload itself is deterministic once the serial is known (§2.5), so it is
  rendered rather than stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "serialised_codes" do
    field :gtin, :string
    field :serial, :string
    field :image, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Serialisation.Shipment
    belongs_to :sscc, ThamaniDawa.Serialisation.Sscc

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(code, attrs) do
    code
    |> cast(attrs, [:gtin, :serial, :image, :organization_id, :shipment_id, :sscc_id])
    |> validate_required([:gtin, :serial, :organization_id, :shipment_id])
    |> unique_constraint([:organization_id, :serial],
      name: :serialised_codes_organization_id_serial_index
    )
  end
end
