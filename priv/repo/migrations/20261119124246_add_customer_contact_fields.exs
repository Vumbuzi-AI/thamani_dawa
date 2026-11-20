defmodule ThamaniDawa.Repo.Migrations.AddCustomerContactFields do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :contact_name, :string
      add :contact_email, :string
      add :contact_phone, :string
    end
  end
end
