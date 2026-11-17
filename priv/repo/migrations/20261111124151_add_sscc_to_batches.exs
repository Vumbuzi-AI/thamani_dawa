defmodule ThamaniDawa.Repo.Migrations.AddSsccToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :sscc, :string
    end
  end
end
