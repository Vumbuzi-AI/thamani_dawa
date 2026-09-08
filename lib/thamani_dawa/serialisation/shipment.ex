defmodule ThamaniDawa.Serialisation.Shipment do
  @moduledoc """
  One generation run: the consignment a set of SSCCs or serialised codes was
  minted for (serialisation.md §5).

  This is the normalised replacement for `gs1_admin`'s wide `tdhcode` table —
  the batch/date/address/order fields that were repeated on every code row live
  here once, and the codes themselves hang off it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(sscc serialised)a
  @statuses ~w(draft submitted issued failed)a

  schema "serial_shipments" do
    field :type, Ecto.Enum, values: @types
    field :status, Ecto.Enum, values: @statuses, default: :draft

    field :batch, :string
    field :production_date, :date
    field :expiry_date, :date

    field :order_number, :string
    field :customer_part_number, :string
    field :material_description, :string

    field :from_gln_id, :string
    field :to_gln_id, :string
    field :from_address, :string
    field :to_address, :string
    field :from_po_box, :string
    field :from_company_name, :string
    field :to_po_box, :string
    field :to_company_name, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User
    belongs_to :gs1_request, ThamaniDawa.Gs1Api.Request

    has_many :lines, ThamaniDawa.Serialisation.ShipmentLine, foreign_key: :shipment_id
    has_many :ssccs, ThamaniDawa.Serialisation.Sscc, foreign_key: :shipment_id

    has_many :serialised_codes, ThamaniDawa.Serialisation.SerialisedCode,
      foreign_key: :shipment_id

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of generation run a shipment can represent."
  def types, do: @types

  @doc "The lifecycle states of a shipment."
  def statuses, do: @statuses

  @doc false
  def changeset(shipment, attrs) do
    shipment
    |> cast(attrs, [
      :type,
      :status,
      :batch,
      :production_date,
      :expiry_date,
      :order_number,
      :customer_part_number,
      :material_description,
      :from_gln_id,
      :to_gln_id,
      :from_address,
      :to_address,
      :from_po_box,
      :from_company_name,
      :to_po_box,
      :to_company_name,
      :organization_id,
      :user_id,
      :gs1_request_id
    ])
    |> validate_required([:type, :organization_id])
    |> validate_expiry_after_production()
  end

  defp validate_expiry_after_production(changeset) do
    production = get_field(changeset, :production_date)
    expiry = get_field(changeset, :expiry_date)

    if production && expiry && Date.compare(expiry, production) == :lt do
      add_error(changeset, :expiry_date, "must be on or after the production date")
    else
      changeset
    end
  end
end
