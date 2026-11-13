defmodule ThamaniDawa.Repo.Migrations.AddRequisitionNumbers do
  use Ecto.Migration

  def up do
    alter table(:organizations) do
      add :next_requisition_number, :integer, null: false, default: 0
    end

    alter table(:requisitions) do
      add :number, :string
    end

    execute """
    WITH numbered AS (
      SELECT id, organization_id,
             row_number() OVER (PARTITION BY organization_id ORDER BY inserted_at, id) AS rn
      FROM requisitions
    )
    UPDATE requisitions
    SET number = 'REQ-' || lpad(numbered.rn::text, 6, '0')
    FROM numbered
    WHERE requisitions.id = numbered.id
    """

    execute """
    UPDATE organizations
    SET next_requisition_number = coalesce(
      (SELECT count(*) FROM requisitions WHERE requisitions.organization_id = organizations.id),
      0
    )
    """

    alter table(:requisitions) do
      modify :number, :string, null: false
    end

    create unique_index(:requisitions, [:organization_id, :number])
  end

  def down do
    drop_if_exists index(:requisitions, [:organization_id, :number])

    alter table(:requisitions) do
      remove :number
    end

    alter table(:organizations) do
      remove :next_requisition_number
    end
  end
end
