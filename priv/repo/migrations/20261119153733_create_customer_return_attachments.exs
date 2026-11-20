defmodule ThamaniDawa.Repo.Migrations.CreateCustomerReturnAttachments do
  use Ecto.Migration

  def change do
    create table(:customer_return_attachments) do
      add :customer_return_id, references(:customer_returns, on_delete: :delete_all), null: false
      add :doc_type, :string, null: false
      add :filename, :string, null: false
      add :path, :string, null: false
      add :content_type, :string
      add :byte_size, :integer
      add :uploaded_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:customer_return_attachments, [:customer_return_id])
  end
end
