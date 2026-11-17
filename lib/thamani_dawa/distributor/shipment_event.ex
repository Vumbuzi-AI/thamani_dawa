defmodule ThamaniDawa.Distributor.ShipmentEvent do
  @moduledoc """
  Append-only audit trail for a shipment: `created`, `updated`, `selected`,
  `released`, `submitted`, `approved`, `rejected`, `reopened`, and
  `item_removed`. The actor is either a portal user or a mobile user.
  """

  use Ecto.Schema

  schema "distributor_shipment_events" do
    field :event, :string
    field :details, :map, default: %{}

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Distributor.Shipment
    belongs_to :user, ThamaniDawa.Accounts.User
    belongs_to :mobile_user, ThamaniDawa.Distributor.MobileUser

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
