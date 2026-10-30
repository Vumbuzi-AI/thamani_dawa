defmodule ThamaniDawa.AuditLog do
  @moduledoc "An immutable record of a successful business-data change."

  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_logs" do
    belongs_to :user, ThamaniDawa.Accounts.User
    belongs_to :organization, ThamaniDawa.Organizations.Organization

    field :action, :string
    field :table_name, :string
    field :record_id, :integer
    field :previous_state, :map
    field :new_state, :map
    field :changed_fields, {:array, :string}, default: []

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [
      :user_id,
      :organization_id,
      :action,
      :table_name,
      :record_id,
      :previous_state,
      :new_state,
      :changed_fields
    ])
    |> validate_required([:action, :table_name, :record_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:organization_id)
  end
end
