defmodule ThamaniDawa.Serialisation.Sscc do
  @moduledoc """
  A logistics unit identifier issued by GS1 (§5).

  Never generated locally. The code, and the extension digit GS1 chose for it
  (`1` for a pallet, `2` for a case — §2.4.3), are both recorded exactly as the
  API returned them so local records stay faithful to the issuing system.

  A case belongs to the pallet it was packed onto via `parent_sscc_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @levels ~w(pallet case)a

  schema "serial_ssccs" do
    field :code, :string
    field :level, Ecto.Enum, values: @levels
    field :extension_digit, :string
    field :image, :string
    field :issued_at, :utc_datetime

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :shipment, ThamaniDawa.Serialisation.Shipment
    belongs_to :parent_sscc, __MODULE__, foreign_key: :parent_sscc_id

    has_many :items, ThamaniDawa.Serialisation.SsccItem, foreign_key: :sscc_id
    has_many :children, __MODULE__, foreign_key: :parent_sscc_id

    timestamps(type: :utc_datetime)
  end

  @doc "The hierarchy levels an SSCC can sit at."
  def levels, do: @levels

  @doc false
  def changeset(sscc, attrs) do
    sscc
    |> cast(attrs, [
      :code,
      :level,
      :extension_digit,
      :image,
      :issued_at,
      :organization_id,
      :shipment_id,
      :parent_sscc_id
    ])
    |> validate_required([:code, :level, :organization_id, :shipment_id])
    |> validate_format(:code, ~r/^\d{18}$/, message: "must be 18 digits")
    |> unique_constraint(:code)
  end
end
