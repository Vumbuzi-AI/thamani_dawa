defmodule ThamaniDawa.Repo.Migrations.AddFromPartyToManufacturerBatches do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_batches) do
      add_if_not_exists :from_company_name, :string
      add_if_not_exists :from_address, :string
    end
  end
end
