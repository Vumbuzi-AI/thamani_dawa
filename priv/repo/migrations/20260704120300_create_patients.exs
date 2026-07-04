defmodule ThamaniDawa.Repo.Migrations.CreatePatients do
  use Ecto.Migration

  def change do
    create table(:patients) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :full_name, :string, null: false
      add :date_of_birth, :date
      add :age, :integer
      add :gender, :string
      add :phone, :string
      add :national_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:patients, [:organization_id])
  end
end
