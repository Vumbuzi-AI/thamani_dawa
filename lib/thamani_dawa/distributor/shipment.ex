defmodule ThamaniDawa.Distributor.Shipment do
  @moduledoc """
  A distributor shipment: an order moving from one of the organization's own
  sites (origin GLN) to a customer (destination GLN). Its state machine is
  owned entirely by `ThamaniDawa.Distributor`:

      draft --submit--> submitted --approve--> approved
                            |
                         reject (+ reason)
                            v
                         rejected --reopen--> draft

  Origin/destination company, address and P.O. box are snapshotted onto the
  row when the shipment is saved, so it keeps its own copy even if the site
  or customer record changes later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft submitted approved rejected)

  schema "distributor_shipments" do
    field :reference, :string
    field :order_number, :string
    field :status, :string, default: "draft"

    field :origin_gln, :string
    field :origin_company, :string
    field :origin_address, :string
    field :origin_po_box, :string

    field :destination_gln, :string
    field :destination_company, :string
    field :destination_address, :string
    field :destination_po_box, :string

    field :submitted_at, :utc_datetime
    field :approved_at, :utc_datetime
    field :rejected_at, :utc_datetime
    field :rejection_reason, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :origin_site, ThamaniDawa.Sites.Site
    belongs_to :destination_customer, ThamaniDawa.DistributorCustomers.Customer
    belongs_to :created_by, ThamaniDawa.Accounts.User
    belongs_to :approved_by, ThamaniDawa.Accounts.User
    belongs_to :rejected_by, ThamaniDawa.Accounts.User
    belongs_to :assigned_to, ThamaniDawa.Distributor.MobileUser,
      foreign_key: :assigned_mobile_user_id

    belongs_to :submitted_by, ThamaniDawa.Distributor.MobileUser,
      foreign_key: :submitted_by_mobile_user_id

    has_many :shippers, ThamaniDawa.Distributor.Shipper, preload_order: [asc: :sequence]
    has_many :items, ThamaniDawa.Distributor.ShipmentItem
    has_many :events, ThamaniDawa.Distributor.ShipmentEvent, preload_order: [desc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc "Changeset for the fields a portal administrator enters on a draft."
  def changeset(shipment, attrs) do
    shipment
    |> cast(attrs, [:order_number, :origin_gln, :destination_gln])
    |> update_change(:order_number, &trim/1)
    |> update_change(:origin_gln, &trim/1)
    |> update_change(:destination_gln, &trim/1)
    |> validate_required([:order_number], message: "Enter the order number")
    |> validate_required([:origin_gln], message: "Choose an origin GLN")
    |> validate_required([:destination_gln], message: "Choose a destination GLN")
    |> validate_format(:origin_gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    |> validate_format(:destination_gln, ~r/^\d{13}$/, message: "must be a 13-digit GLN")
    |> validate_different_glns()
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp validate_different_glns(changeset) do
    if get_field(changeset, :origin_gln) &&
         get_field(changeset, :origin_gln) == get_field(changeset, :destination_gln) do
      add_error(changeset, :destination_gln, "must be different from the origin GLN")
    else
      changeset
    end
  end
end
