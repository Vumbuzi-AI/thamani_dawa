defmodule ThamaniDawa.DistributorShipments.Carton do
  use Ecto.Schema
  import Ecto.Changeset

  schema "distributor_cartons" do
    field :sscc, :string
    field :sequence_in_shipment, :integer

    belongs_to :shipment, ThamaniDawa.DistributorShipments.Shipment
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    has_many :lines, ThamaniDawa.DistributorShipments.ShipmentLine, foreign_key: :carton_id

    timestamps(type: :utc_datetime)
  end

  def changeset(carton, attrs) do
    carton
    |> cast(attrs, [:sscc, :sequence_in_shipment, :shipment_id, :organization_id])
    |> validate_required([:sscc, :sequence_in_shipment, :shipment_id, :organization_id])
    |> unique_constraint(:sscc)
    |> foreign_key_constraint(:shipment_id)
    |> foreign_key_constraint(:organization_id)
  end
end
