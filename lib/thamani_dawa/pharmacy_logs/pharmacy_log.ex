defmodule ThamaniDawa.PharmacyLogs.PharmacyLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pharmacy_logs" do
    field :organization_id, :id
    field :site_id, :id
    field :log_type, :string
    field :month, :integer
    field :year, :integer
    field :daily_entries, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(pharmacy_log, attrs) do
    pharmacy_log
    |> cast(attrs, [:site_id, :log_type, :month, :year, :daily_entries])
    |> validate_required([:site_id, :log_type, :month, :year])
    |> validate_number(:month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint([:organization_id, :log_type, :month, :year])
  end
end
