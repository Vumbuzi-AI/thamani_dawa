defmodule ThamaniDawa.Manufacturing.Pallet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_pallets" do
    field :code, :string
    field :from_gln, :string
    field :from_company_name, :string
    field :from_address, :string
    field :to_gln, :string
    field :to_company_name, :string
    field :to_address, :string
    field :status, :string, default: "draft"
    field :allocated_at, :utc_datetime
    field :label_prepared_at, :utc_datetime
    field :label_print_requested_at, :utc_datetime
    field :verified_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :trackiq_status, :string, default: "not_started"

    belongs_to :organization, ThamaniDawa.Organizations.Organization

    has_many :shipper_ssccs, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_pallet_id

    timestamps(type: :utc_datetime)
  end

  @fields [
    :code,
    :from_gln,
    :from_company_name,
    :from_address,
    :to_gln,
    :to_company_name,
    :to_address,
    :status,
    :allocated_at,
    :label_prepared_at,
    :label_print_requested_at,
    :verified_at,
    :completed_at,
    :trackiq_status
  ]

  @doc false
  def changeset(pallet, attrs) do
    pallet
    |> cast(attrs, @fields)
    |> update_change(:code, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([:code])
    |> validate_inclusion(:status, ~w(draft loading awaiting_verification completed in_transit))
    |> validate_inclusion(
      :trackiq_status,
      ~w(not_started pending submitted acknowledged accepted rejected blocked)
    )
    |> unique_constraint(:code)
  end
end
