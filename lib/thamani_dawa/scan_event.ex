defmodule ThamaniDawa.ScanEvent do
  @moduledoc "An immutable record of a barcode scan being matched to a stock-affecting action (§4.6)."

  use Ecto.Schema
  import Ecto.Changeset

  @event_types [:receipt, :dispense, :lab_consumption, :transfer_out, :transfer_in]

  schema "scan_events" do
    field :gtin, :string
    field :batch_no, :string
    field :gln, :string
    field :event_type, Ecto.Enum, values: @event_types
    field :reference_id, :integer

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(scan_event, attrs) do
    scan_event
    |> cast(attrs, [
      :gtin,
      :batch_no,
      :gln,
      :event_type,
      :reference_id,
      :user_id,
      :organization_id
    ])
    |> validate_required([:gtin, :event_type, :organization_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end

  @doc "The valid scan event types."
  def event_types, do: @event_types
end
