defmodule ThamaniDawa.Repo.Migrations.AddStrengthToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :strength, :string
    end
  end
end
