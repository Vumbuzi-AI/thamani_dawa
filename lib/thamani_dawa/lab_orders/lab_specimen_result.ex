defmodule ThamaniDawa.LabOrders.LabSpecimenResult do
  use Ecto.Schema
  import Ecto.Changeset

  schema "lab_specimen_results" do
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :lab_specimen, ThamaniDawa.LabOrders.LabSpecimen
    belongs_to :lab_order_result, ThamaniDawa.LabOrders.LabOrderResult

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(lab_specimen_result, attrs) do
    lab_specimen_result
    |> cast(attrs, [:lab_specimen_id, :lab_order_result_id, :organization_id])
    |> validate_required([:lab_specimen_id, :lab_order_result_id, :organization_id])
    |> unique_constraint([:lab_specimen_id, :lab_order_result_id])
    |> foreign_key_constraint(:lab_specimen_id)
    |> foreign_key_constraint(:lab_order_result_id)
  end
end
