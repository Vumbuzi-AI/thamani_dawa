defmodule ThamaniDawa.LabOrders.LabOrderResultAmendment do
  @moduledoc "An immutable snapshot of a `lab_order_results` row taken right before a completed result is overwritten."

  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_order_result_amendments" do
    field :previous_results, :map
    field :previous_test_performed_on, :date
    field :reason, :string

    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :lab_order_result, ThamaniDawa.LabOrders.LabOrderResult

    belongs_to :previous_performed_by, ThamaniDawa.Accounts.User,
      foreign_key: :previous_performed_by_id

    belongs_to :amended_by, ThamaniDawa.Accounts.User, foreign_key: :amended_by_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(amendment, attrs) do
    amendment
    |> cast(attrs, [
      :previous_results,
      :previous_test_performed_on,
      :previous_performed_by_id,
      :reason,
      :amended_by_id,
      :lab_order_result_id
    ])
    |> validate_required([:previous_results, :reason, :lab_order_result_id])
    |> foreign_key_constraint(:lab_order_result_id)
    |> foreign_key_constraint(:previous_performed_by_id)
    |> foreign_key_constraint(:amended_by_id)
  end
end
