defmodule ThamaniDawa.Manufacturing.Batch do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_batches" do
    field :batch_no, :string
    field :production_date, :date
    field :expiry_date, :date
    field :from_gln, :string
    field :from_name, :string
    field :to_gln, :string
    field :to_name, :string
    field :issued_count, :integer, default: 0
    field :packed_count, :integer, default: 0

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

  def parties_changeset(batch, attrs) do
    batch
    |> cast(attrs, [:from_gln, :from_name, :to_gln, :to_name])
    |> update_change(:from_gln, &trim_gln/1)
    |> update_change(:to_gln, &trim_gln/1)
    |> update_change(:from_name, &trim_name/1)
    |> update_change(:to_name, &trim_name/1)
    |> validate_required([:from_gln, :to_gln])
    |> validate_format(:from_gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_format(:to_gln, ~r/^\d{13}$/, message: "must be 13 digits")
    |> validate_distinct_parties()
  end

  defp trim_gln(value) when is_binary(value), do: String.trim(value)
  defp trim_gln(value), do: value

  defp trim_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      name -> name
    end
  end

  defp trim_name(value), do: value

  defp validate_distinct_parties(changeset) do
    from_gln = get_field(changeset, :from_gln)
    to_gln = get_field(changeset, :to_gln)

    if is_binary(from_gln) and from_gln == to_gln do
      add_error(changeset, :to_gln, "must be different from the origin")
    else
      changeset
    end
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
