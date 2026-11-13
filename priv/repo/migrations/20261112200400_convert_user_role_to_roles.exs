defmodule ThamaniDawa.Repo.Migrations.ConvertUserRoleToRoles do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :roles, {:array, :string}, null: false, default: []
    end

    execute """
    UPDATE users SET roles = CASE role
      WHEN 'pharma_lab' THEN ARRAY['pharmacist', 'lab_technician']
      ELSE ARRAY[role]
    END
    """

    alter table(:users) do
      remove :role
    end
  end

  def down do
    alter table(:users) do
      add :role, :string
    end

    execute """
    UPDATE users SET role = CASE
      WHEN 'pharmacist' = ANY(roles) AND 'lab_technician' = ANY(roles) THEN 'pharma_lab'
      ELSE roles[1]
    END
    """

    alter table(:users) do
      modify :role, :string, null: false
      remove :roles
    end
  end
end
