defmodule ThamaniDawa.Repo.Migrations.AddNetContentToProducts do
  use Ecto.Migration

  def change do
    alter table(:products) do
      add :net_content_quantity, :integer
      add :net_content_uom, :string
    end
  end
end
