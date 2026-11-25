defmodule ThamaniDawa.Repo.Migrations.AddSerialCountsToManufacturerBatches do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_batches) do
      add :issued_count, :integer, null: false, default: 0
      add :packed_count, :integer, null: false, default: 0
    end

    execute(
      """
      UPDATE manufacturer_batches AS b
      SET
        issued_count = s.issued,
        packed_count = s.packed
      FROM (
        SELECT
          manufacturer_batch_id,
          COUNT(*)::int AS issued,
          COUNT(*) FILTER (WHERE manufacturer_shipper_sscc_id IS NOT NULL)::int AS packed
        FROM manufacturer_serials
        GROUP BY manufacturer_batch_id
      ) AS s
      WHERE b.id = s.manufacturer_batch_id
      """,
      "UPDATE manufacturer_batches SET issued_count = 0, packed_count = 0"
    )
  end
end
