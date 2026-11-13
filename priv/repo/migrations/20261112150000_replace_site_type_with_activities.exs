defmodule ThamaniDawa.Repo.Migrations.ReplaceSiteTypeWithActivities do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :activities, {:array, :string}, null: false, default: []
    end

    execute("""
    UPDATE sites SET activities = CASE site_type
      WHEN 'pharmacy' THEN ARRAY['pharmacy']::text[]
      WHEN 'lab' THEN ARRAY['laboratory']::text[]
      WHEN 'pharmacy_lab' THEN ARRAY['pharmacy', 'laboratory']::text[]
      WHEN 'warehouse' THEN ARRAY['distribution']::text[]
      ELSE ARRAY[]::text[]
    END;
    """)

    alter table(:sites) do
      remove :site_type
    end
  end
end
