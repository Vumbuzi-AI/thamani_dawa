defmodule ThamaniDawa.Repo.Migrations.CreateLogisticUnits do
  use Ecto.Migration

  def up do
    create table(:logistic_units) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :sscc, :string, null: false
      add :kind, :string, null: false, default: "case"
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "inbound"
      add :site_id, references(:sites, on_delete: :nilify_all)
      add :goods_receipt_id, references(:goods_receipts, on_delete: :nilify_all)
      add :parent_logistic_unit_id, references(:logistic_units, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:logistic_units, [:organization_id, :sscc])
    create index(:logistic_units, [:organization_id])
    create index(:logistic_units, [:goods_receipt_id])
    create index(:logistic_units, [:parent_logistic_unit_id])

    alter table(:batches) do
      add :logistic_unit_id, references(:logistic_units, on_delete: :nilify_all)
    end

    create index(:batches, [:logistic_unit_id])

    # Backfill: one logistic unit per distinct (organization_id, sscc) among
    # batches that carry an SSCC. Loose stock (sscc IS NULL) stays unit-less.
    execute("""
    INSERT INTO logistic_units
      (organization_id, sscc, kind, status, source, site_id, goods_receipt_id, inserted_at, updated_at)
    SELECT DISTINCT ON (organization_id, sscc)
      organization_id, sscc, 'case', 'active', 'inbound', site_id, goods_receipt_id, now(), now()
    FROM batches
    WHERE sscc IS NOT NULL
    ORDER BY organization_id, sscc, id
    """)

    execute("""
    UPDATE batches b
    SET logistic_unit_id = lu.id
    FROM logistic_units lu
    WHERE b.sscc = lu.sscc AND b.organization_id = lu.organization_id
    """)

    # Previously-minted children (broken off a parent batch) become `:minted`
    # units and point back at the parent's unit where that parent carried an SSCC.
    execute("""
    UPDATE logistic_units child
    SET parent_logistic_unit_id = parent_lu.id, source = 'minted'
    FROM batches cb
    JOIN batches pb ON cb.source_batch_id = pb.id
    JOIN logistic_units parent_lu ON parent_lu.id = pb.logistic_unit_id
    WHERE child.id = cb.logistic_unit_id AND cb.source_batch_id IS NOT NULL
    """)
  end

  def down do
    alter table(:batches) do
      remove :logistic_unit_id
    end

    drop table(:logistic_units)
  end
end
