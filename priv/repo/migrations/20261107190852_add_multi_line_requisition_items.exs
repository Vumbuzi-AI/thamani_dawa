defmodule ThamaniDawa.Repo.Migrations.AddMultiLineRequisitionItems do
  use Ecto.Migration

  def up do
    alter table(:requisitions) do
      modify :product_id, :bigint, null: true
      modify :quantity, :integer, null: true
    end

    create table(:requisition_lines) do
      add :requisition_id, references(:requisitions, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :product_id, references(:products, on_delete: :restrict), null: false
      add :requested_quantity, :integer, null: false
      add :approved_quantity, :integer
      add :status, :string, null: false, default: "pending"
      add :rejection_reason, :text
      add :reviewed_by_id, references(:users, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:requisition_lines, [:requisition_id])
    create index(:requisition_lines, [:organization_id, :status])
    create index(:requisition_lines, [:product_id])

    create constraint(:requisition_lines, :requisition_lines_requested_positive,
             check: "requested_quantity > 0"
           )

    create constraint(:requisition_lines, :requisition_lines_approved_in_range,
             check:
               "approved_quantity IS NULL OR (approved_quantity >= 0 AND approved_quantity <= requested_quantity)"
           )

    create table(:requisition_fulfillments) do
      add :requisition_line_id, references(:requisition_lines, on_delete: :restrict), null: false
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :source_batch_id, references(:batches, on_delete: :restrict), null: false
      add :dispatched_batch_id, references(:batches, on_delete: :restrict), null: false
      add :dispatched_quantity, :integer, null: false
      add :received_quantity, :integer
      add :dispatched_by_id, references(:users, on_delete: :nilify_all)
      add :received_by_id, references(:users, on_delete: :nilify_all)
      add :received_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:requisition_fulfillments, [:requisition_line_id])
    create index(:requisition_fulfillments, [:organization_id])
    create unique_index(:requisition_fulfillments, [:dispatched_batch_id])

    create constraint(:requisition_fulfillments, :requisition_fulfillments_dispatched_positive,
             check: "dispatched_quantity > 0"
           )

    create constraint(:requisition_fulfillments, :requisition_fulfillments_received_nonnegative,
             check: "received_quantity IS NULL OR received_quantity >= 0"
           )

    # Preserve every existing single-item request and its external requisition ID.
    execute """
    INSERT INTO requisition_lines
      (requisition_id, organization_id, product_id, requested_quantity, approved_quantity,
       status, rejection_reason, reviewed_by_id, reviewed_at, inserted_at, updated_at)
    SELECT id, organization_id, product_id, quantity,
      CASE WHEN status IN ('approved', 'partially_fulfilled', 'fulfilled') THEN quantity
           WHEN status = 'rejected' THEN 0 ELSE NULL END,
      CASE WHEN status = 'approved' THEN 'approved'
           WHEN status IN ('partially_fulfilled', 'fulfilled') THEN 'approved'
           WHEN status = 'rejected' THEN 'rejected' ELSE 'pending' END,
      rejection_reason, reviewed_by_id, reviewed_at, inserted_at, updated_at
    FROM requisitions
    """

    # Historical received batch.quantity may differ from the originally dispatched quantity;
    # retain the quantity available on the batch at migration time as the best available value.
    execute """
    INSERT INTO requisition_fulfillments
      (requisition_line_id, organization_id, source_batch_id, dispatched_batch_id,
       dispatched_quantity, received_quantity, received_by_id, received_at, inserted_at, updated_at)
    SELECT l.id, b.organization_id, b.source_batch_id, b.id, b.quantity,
      CASE WHEN b.received_at IS NOT NULL THEN b.quantity ELSE NULL END,
      b.approver_id, b.received_at, b.inserted_at, b.updated_at
    FROM batches b
    JOIN requisition_lines l ON l.requisition_id = b.requisition_id
    WHERE b.requisition_id IS NOT NULL AND b.source_batch_id IS NOT NULL
    """
  end

  def down do
    drop_if_exists table(:requisition_fulfillments)
    drop_if_exists table(:requisition_lines)

    alter table(:requisitions) do
      modify :product_id, :bigint, null: false
      modify :quantity, :integer, null: false
    end
  end
end
