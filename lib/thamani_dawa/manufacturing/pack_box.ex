defmodule ThamaniDawa.Manufacturing.PackBox do
  @moduledoc """
  A manufacturer packer's draft or saved shipper, owned by one PIN user.
  Serial claims live on `PackBoxScan` until Save mints the SSCC.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :id

  schema "manufacturer_pack_boxes" do
    field :status, :string, default: "draft"
    field :idempotency_key, :string
    field :from_gln, :string
    field :from_name, :string
    field :to_gln, :string
    field :to_name, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :mobile_user, ThamaniDawa.Distributor.MobileUser
    belongs_to :batch, ThamaniDawa.Manufacturing.Batch, foreign_key: :manufacturer_batch_id

    belongs_to :shipper_sscc, ThamaniDawa.Manufacturing.ShipperSscc,
      foreign_key: :manufacturer_shipper_sscc_id

    has_many :scans, ThamaniDawa.Manufacturing.PackBoxScan, foreign_key: :box_id

    timestamps(type: :utc_datetime)
  end

  def changeset(box, attrs) do
    box
    |> cast(attrs, [
      :status,
      :idempotency_key,
      :from_gln,
      :from_name,
      :to_gln,
      :to_name,
      :manufacturer_shipper_sscc_id
    ])
    |> validate_inclusion(:status, ~w(draft saved))
    |> unique_constraint([:mobile_user_id, :manufacturer_batch_id],
      name: :manufacturer_pack_boxes_one_draft_per_user_batch
    )
    |> unique_constraint(:idempotency_key, name: :manufacturer_pack_boxes_idempotency_key_index)
  end
end
