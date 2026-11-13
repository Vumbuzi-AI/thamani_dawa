defmodule ThamaniDawa.Distributor.SerialReservation do
  @moduledoc """
  The concurrency guard behind the shipment workflow: the unique
  `(barcode, serial)` index guarantees a serialised unit is held by at most
  one submitted or approved shipment. Reservations are taken on submit,
  released on reject, and made permanent (`committed_at`) on approval.
  """

  use Ecto.Schema

  schema "distributor_serial_reservations" do
    field :barcode, :string
    field :serial, :string
    field :committed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Distributor.Shipment

    timestamps(type: :utc_datetime)
  end
end
