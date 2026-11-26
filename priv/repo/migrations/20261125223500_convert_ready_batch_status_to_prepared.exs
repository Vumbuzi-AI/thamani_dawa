defmodule ThamaniDawa.Repo.Migrations.ConvertReadyBatchStatusToPrepared do
  use Ecto.Migration

  def up do
    execute("UPDATE manufacturer_batches SET status = 'prepared' WHERE status = 'ready'")
  end

  def down do
    # The old "ready" rows cannot be distinguished from other "prepared"
    # batches once they have been merged, so this data fix is one-way.
    :ok
  end
end
