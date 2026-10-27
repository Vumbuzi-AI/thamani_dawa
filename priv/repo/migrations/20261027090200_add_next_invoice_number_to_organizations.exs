defmodule ThamaniDawa.Repo.Migrations.AddNextInvoiceNumberToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :next_invoice_number, :integer, null: false, default: 0
    end
  end
end
