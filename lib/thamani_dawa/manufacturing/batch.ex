defmodule ThamaniDawa.Manufacturing.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_batches" do
    field :batch_no, :string
    field :production_date, :date
    field :expiry_date, :date
    field :status, :string, default: "prepared"
    field :pack_quantity, :integer
    field :packs_per_shipper, :integer
    field :expected_shipper_count, :integer
    field :shipper_preparation_method, :string
    field :from_gln, :string
    field :from_company_name, :string
    field :from_address, :string
    field :to_gln, :string
    field :to_company_name, :string
    field :to_address, :string
    field :order_number, :string
    field :aggregation_started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Manufacturing.Product, foreign_key: :manufacturer_product_id

    has_many :serials, ThamaniDawa.Manufacturing.Serial, foreign_key: :manufacturer_batch_id

    has_many :sscc_batches, ThamaniDawa.Manufacturing.SsccBatch,
      foreign_key: :manufacturer_batch_id

    has_many :generation_operations, ThamaniDawa.Manufacturing.GenerationOperation,
      foreign_key: :manufacturer_batch_id

    has_many :aggregation_sessions, ThamaniDawa.Manufacturing.AggregationSession,
      foreign_key: :manufacturer_batch_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [
      :batch_no,
      :production_date,
      :expiry_date,
      :status,
      :pack_quantity,
      :packs_per_shipper,
      :expected_shipper_count,
      :shipper_preparation_method,
      :from_gln,
      :from_company_name,
      :from_address,
      :to_gln,
      :to_company_name,
      :to_address,
      :order_number,
      :aggregation_started_at,
      :completed_at
    ])
    |> update_change(:batch_no, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:batch_no, :production_date, :expiry_date])
    |> validate_dates()
    |> validate_packaging()
    |> validate_inclusion(:status, ~w(prepared allocating aggregating completed cancelled))
    |> validate_inclusion(:shipper_preparation_method, ~w(during_packing))
    |> unique_constraint([:manufacturer_product_id, :batch_no])
  end

  defp validate_dates(changeset) do
    production = get_field(changeset, :production_date)
    expiry = get_field(changeset, :expiry_date)

    if production && expiry && Date.compare(expiry, production) != :gt do
      add_error(changeset, :expiry_date, "must be after the production date")
    else
      changeset
    end
  end

  defp validate_packaging(changeset) do
    quantity = get_field(changeset, :pack_quantity)
    per_shipper = get_field(changeset, :packs_per_shipper)

    changeset
    |> validate_number(:pack_quantity, greater_than: 0)
    |> validate_number(:packs_per_shipper, greater_than: 0)
    |> validate_change(:packs_per_shipper, fn :packs_per_shipper, _value ->
      if is_integer(quantity) and is_integer(per_shipper) and rem(quantity, per_shipper) != 0 do
        [packs_per_shipper: "must divide the number of packs to serialize evenly"]
      else
        []
      end
    end)
  end
end
