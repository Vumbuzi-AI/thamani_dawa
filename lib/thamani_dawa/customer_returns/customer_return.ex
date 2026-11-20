defmodule ThamaniDawa.CustomerReturns.CustomerReturn do
  use Ecto.Schema
  import Ecto.Changeset

  alias ThamaniDawa.CustomerReturns.CustomerReturnAttachment
  alias ThamaniDawa.CustomerReturns.CustomerReturnItem

  @statuses [:draft, :received, :inspected, :completed]
  @reasons [:damaged, :wrong_item, :overstock, :other]

  schema "customer_returns" do
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :reason, Ecto.Enum, values: @reasons
    field :notes, :string
    field :document_reference, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :customer, ThamaniDawa.Customers.Customer
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :shipment, ThamaniDawa.Distributor.Shipment
    belongs_to :received_by, ThamaniDawa.Accounts.User

    has_many :items, CustomerReturnItem
    has_many :attachments, CustomerReturnAttachment

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def reasons, do: @reasons

  @doc false
  def changeset(customer_return, attrs) do
    customer_return
    |> cast(attrs, [
      :reason,
      :notes,
      :document_reference,
      :organization_id,
      :customer_id,
      :site_id,
      :shipment_id,
      :received_by_id
    ])
    |> update_change(:document_reference, &trim/1)
    |> validate_required([:organization_id, :customer_id, :site_id], message: "can't be blank")
    |> foreign_key_constraint(:organization_id)
    |> foreign_key_constraint(:customer_id)
    |> foreign_key_constraint(:site_id)
    |> foreign_key_constraint(:shipment_id)
  end

  @doc "Changeset applied when a draft return is marked received."
  def receive_changeset(customer_return, attrs) do
    customer_return
    |> cast(attrs, [:received_by_id])
    |> change(status: :received)
    |> validate_status(:draft)
  end

  @doc "Changeset applied once every item has an assigned condition."
  def inspect_changeset(customer_return) do
    customer_return
    |> change(status: :inspected)
    |> validate_status(:received)
  end

  @doc "Changeset applied once stock has been put away and recorded."
  def complete_changeset(customer_return) do
    customer_return
    |> change(status: :completed)
    |> validate_status(:inspected)
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  defp validate_status(changeset, expected) do
    if changeset.data.status == expected do
      changeset
    else
      add_error(changeset, :status, "must be #{expected}")
    end
  end
end
