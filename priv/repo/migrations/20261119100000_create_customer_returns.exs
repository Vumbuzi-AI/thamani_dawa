defmodule ThamaniDawa.Repo.Migrations.CreateCustomerReturns do
  use Ecto.Migration

  def change do
    create table(:customer_returns) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false
      add :customer_id, references(:customers, on_delete: :restrict), null: false
      add :site_id, references(:sites, on_delete: :restrict), null: false
      add :status, :string, null: false, default: "draft"
      add :reason, :string
      add :notes, :text
      add :received_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:customer_returns, [:organization_id])
    create index(:customer_returns, [:customer_id])
    create index(:customer_returns, [:site_id])

    create table(:customer_return_items) do
      add :organization_id, references(:organizations, on_delete: :restrict), null: false

      add :customer_return_id, references(:customer_returns, on_delete: :delete_all), null: false

      add :product_id, references(:products, on_delete: :restrict), null: false
      add :quantity, :integer, null: false
      add :batch_no, :string
      add :expiry_date, :date
      add :condition, :string
      add :batch_id, references(:batches, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:customer_return_items, [:customer_return_id])
    create index(:customer_return_items, [:batch_id])
  end
end
