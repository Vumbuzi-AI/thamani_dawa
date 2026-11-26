defmodule ThamaniDawa.Manufacturing.PackBoxScan do
  @moduledoc """
  Exclusive claim of one primary serial onto a packer's draft (or saved) box.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "manufacturer_pack_box_scans" do
    field :serial, :string
    field :claimed_at, :utc_datetime

    belongs_to :box, ThamaniDawa.Manufacturing.PackBox, foreign_key: :box_id, type: :binary_id
    belongs_to :organization, ThamaniDawa.Organizations.Organization

    belongs_to :product, ThamaniDawa.Manufacturing.Product, foreign_key: :manufacturer_product_id

    timestamps(type: :utc_datetime)
  end

  def changeset(scan, attrs) do
    scan
    |> cast(attrs, [:serial, :claimed_at, :box_id, :organization_id, :manufacturer_product_id])
    |> update_change(:serial, fn
      value when is_binary(value) -> String.trim(value)
      value -> value
    end)
    |> validate_required([
      :serial,
      :claimed_at,
      :box_id,
      :organization_id,
      :manufacturer_product_id
    ])
    |> unique_constraint([:organization_id, :manufacturer_product_id, :serial],
      name: :manufacturer_pack_box_scans_claim_index
    )
  end
end
