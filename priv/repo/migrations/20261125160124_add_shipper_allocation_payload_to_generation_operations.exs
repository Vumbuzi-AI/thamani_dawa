defmodule ThamaniDawa.Repo.Migrations.AddShipperAllocationPayloadToGenerationOperations do
  use Ecto.Migration

  def change do
    alter table(:manufacturer_generation_operations) do
      add :sscc_request_payload, :map
      add :sscc_attempted_at, :utc_datetime
    end
  end
end
