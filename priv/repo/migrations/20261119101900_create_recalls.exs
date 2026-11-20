defmodule ThamaniDawa.Repo.Migrations.CreateRecalls do
  use Ecto.Migration

  def change do
    create table(:recalls) do
      add :gtin, :string, null: false
      add :batch_no, :string, null: false
      add :reference, :string, null: false
      add :classification, :string, null: false
      add :reason, :text
      add :status, :string, null: false, default: "open"
      add :initiated_by_id, references(:users, on_delete: :nilify_all)
      add :closed_at, :utc_datetime
      add :closed_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:recalls, [:gtin, :batch_no])
    create index(:recalls, [:status])
  end
end
