defmodule ThamaniDawa.Manufacturing.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_batches" do
    field :batch_no, :string
    field :production_date, :date
    field :expiry_date, :date

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :product, ThamaniDawa.Manufacturing.Product, foreign_key: :manufacturer_product_id

    has_many :serials, ThamaniDawa.Manufacturing.Serial, foreign_key: :manufacturer_batch_id

    has_many :sscc_batches, ThamaniDawa.Manufacturing.SsccBatch,
      foreign_key: :manufacturer_batch_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(batch, attrs) do
    batch
    |> cast(attrs, [:batch_no, :production_date, :expiry_date])
    |> update_change(:batch_no, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:batch_no, :production_date, :expiry_date])
    |> validate_dates()
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
end
