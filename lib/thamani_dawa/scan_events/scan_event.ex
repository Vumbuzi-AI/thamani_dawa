defmodule ThamaniDawa.ScanEvents.ScanEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @event_types [:receipt, :dispense, :lab_consumption, :transfer_out, :transfer_in]

  schema "scan_events" do
    field :organization_id, :id
    field :gtin, :string
    field :batch_no, :string
    field :gln, :string
    field :event_type, Ecto.Enum, values: @event_types
    field :reference_id, :id
    field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(scan_event, attrs) do
    scan_event
    |> cast(attrs, [:gtin, :batch_no, :gln, :event_type, :reference_id, :user_id])
    |> validate_required([:gtin, :batch_no, :event_type])
    |> foreign_key_constraint(:user_id)
  end

  @doc "The valid scan event types (§4.6 of project.md)."
  def event_types, do: @event_types
end
