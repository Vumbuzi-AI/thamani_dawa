defmodule ThamaniDawa.Repo.Migrations.AddOrderNumberToManufacturerShipperSsccs do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_shipper_ssccs) do
      add :order_number, :string
    end
  end
end
