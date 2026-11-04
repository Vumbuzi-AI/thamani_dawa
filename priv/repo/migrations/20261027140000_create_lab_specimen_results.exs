defmodule ThamaniDawa.Repo.Migrations.CreateLabSpecimenResults do
  use Ecto.Migration

  def up do
    create table(:lab_specimen_results) do
      add :lab_specimen_id, references(:lab_specimens, on_delete: :delete_all), null: false

      add :lab_order_result_id, references(:lab_order_results, on_delete: :delete_all),
        null: false

      add :organization_id, references(:organizations, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lab_specimen_results, [:lab_specimen_id, :lab_order_result_id])
    create index(:lab_specimen_results, [:lab_order_result_id])
    create index(:lab_specimen_results, [:organization_id])

    execute """
    INSERT INTO lab_specimen_results (
      lab_specimen_id,
      lab_order_result_id,
      organization_id,
      inserted_at,
      updated_at
    )
    SELECT id, lab_order_result_id, organization_id, NOW(), NOW()
    FROM lab_specimens
    WHERE lab_order_result_id IS NOT NULL
    """

    drop unique_index(:lab_specimens, [:lab_order_result_id])
    execute "ALTER TABLE lab_specimens ALTER COLUMN lab_order_result_id DROP NOT NULL"
    execute "ALTER TABLE lab_order_results ALTER COLUMN sample_type DROP NOT NULL"
  end

  def down do
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM lab_specimens AS specimen
        LEFT JOIN lab_specimen_results AS link
          ON link.lab_specimen_id = specimen.id
        GROUP BY specimen.id
        HAVING COUNT(link.id) <> 1
      ) OR EXISTS (
        SELECT 1
        FROM lab_specimen_results
        GROUP BY lab_order_result_id
        HAVING COUNT(*) > 1
      ) THEN
        RAISE EXCEPTION 'cannot roll back lab specimen results: the legacy one-to-one relationship cannot be restored without data loss';
      END IF;

      IF EXISTS (SELECT 1 FROM lab_order_results WHERE sample_type IS NULL) THEN
        RAISE EXCEPTION 'cannot roll back lab specimen results: lab order results contain null sample types';
      END IF;
    END
    $$
    """

    execute """
    UPDATE lab_specimens AS specimen
    SET lab_order_result_id = link.lab_order_result_id
    FROM lab_specimen_results AS link
    WHERE link.lab_specimen_id = specimen.id
    """

    execute "ALTER TABLE lab_order_results ALTER COLUMN sample_type SET NOT NULL"
    execute "ALTER TABLE lab_specimens ALTER COLUMN lab_order_result_id SET NOT NULL"
    create unique_index(:lab_specimens, [:lab_order_result_id])

    drop table(:lab_specimen_results)
  end
end
