defmodule ThamaniDawa.Repo.Migrations.AddSerialToSerialSsccs do
  use Ecto.Migration

  def change do
    # A shipper (case) SSCC carries its own serial under AI (21) on the label
    # (ui.md §10, "Shipper label"). It is issued by GS1 alongside the case
    # code, so it is recorded here rather than derived at print time.
    alter table(:serial_ssccs) do
      add :serial, :string
    end
  end
end
