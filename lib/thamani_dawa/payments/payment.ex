defmodule ThamaniDawa.Payments.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  @order_types [:prescription, :lab_order, :sale]
  @statuses [:pending, :completed, :failed]

  schema "payments" do
    field :order_type, Ecto.Enum, values: @order_types
    field :amount, :decimal
    field :payment_type, :string
    field :provider_reference, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :failure_reason, :string
    field :paid_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :site, ThamaniDawa.Sites.Site
    belongs_to :prescription, ThamaniDawa.Prescriptions.Prescription
    belongs_to :lab_order, ThamaniDawa.LabOrders.LabOrder
    belongs_to :sale, ThamaniDawa.Sales.Sale

    has_many :wallet_entries, ThamaniDawa.Payments.WalletEntry

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for recording a new payment attempt. `site_id` and `order_type`
  are not accepted here — the context derives them from whichever of
  `prescription_id`/`lab_order_id` is given, so a caller can never record a
  payment against a site that doesn't match its own order.
  """
  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :prescription_id,
      :lab_order_id,
      :sale_id,
      :amount,
      :payment_type,
      :provider_reference
    ])
    |> validate_required([:amount, :payment_type])
    |> put_order_type()
    |> validate_number(:amount, greater_than: 0)
    |> validate_inclusion(:payment_type, ThamaniDawa.PaymentMethods.all(),
      message: "must be one of the approved payment methods"
    )
    |> foreign_key_constraint(:prescription_id)
    |> foreign_key_constraint(:lab_order_id)
    |> foreign_key_constraint(:sale_id)
    |> unique_constraint(:provider_reference,
      name: :payments_provider_reference_index,
      message: "has already been used for a payment"
    )
  end

  defp put_order_type(changeset) do
    case {get_field(changeset, :prescription_id), get_field(changeset, :lab_order_id),
          get_field(changeset, :sale_id)} do
      {nil, nil, nil} ->
        add_error(
          changeset,
          :order_type,
          "must reference exactly one order"
        )

      {_prescription_id, nil, nil} ->
        put_change(changeset, :order_type, :prescription)

      {nil, _lab_order_id, nil} ->
        put_change(changeset, :order_type, :lab_order)

      {nil, nil, _sale_id} ->
        put_change(changeset, :order_type, :sale)

      _ ->
        add_error(
          changeset,
          :order_type,
          "must reference exactly one order"
        )
    end
  end

  @doc "Changeset for marking a pending payment as completed."
  def complete_changeset(payment, attrs) do
    payment
    |> cast(attrs, [:paid_at])
    |> validate_required([:paid_at])
    |> put_change(:status, :completed)
    |> unique_constraint(:prescription_id,
      name: :payments_one_completed_per_prescription_index,
      message: "already has a completed payment"
    )
    |> unique_constraint(:lab_order_id,
      name: :payments_one_completed_per_lab_order_index,
      message: "already has a completed payment"
    )
    |> unique_constraint(:sale_id,
      name: :payments_one_completed_per_sale_index,
      message: "already has a completed payment"
    )
  end

  @doc "Changeset for marking a pending payment as failed."
  def fail_changeset(payment, attrs) do
    payment
    |> cast(attrs, [:failure_reason])
    |> validate_required([:failure_reason])
    |> put_change(:status, :failed)
  end

  @doc "The valid payment lifecycle statuses."
  def statuses, do: @statuses
end
