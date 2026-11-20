defmodule ThamaniDawa.Repo.Migrations.AddSerialsToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :serials, {:array, :string}, default: [], null: false
    end
  end
end
