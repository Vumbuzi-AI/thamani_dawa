defmodule ThamaniDawa.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :generic_name, :string
      add :brand_name, :string
      add :name, :string
      add :product_type, :string, null: false
      add :category, :string
      add :uom, :string
      add :gtin, :string
      add :is_otc, :boolean, null: false, default: false
      add :is_dangerous_drug, :boolean, null: false, default: false
      add :reorder_level, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:products, [:organization_id])
    create unique_index(:products, [:organization_id, :gtin])
  end
end
