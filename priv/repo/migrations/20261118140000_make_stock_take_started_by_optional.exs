defmodule ThamaniDawa.Repo.Migrations.MakeStockTakeStartedByOptional do
  @moduledoc """
  `started_by_id` is superseded by `requested_by_id`/`admin_id` and is no
  longer set by the application, but new stock takes must still be
  insertable.
  """

  use Ecto.Migration

  def up do
    execute "ALTER TABLE stock_takes ALTER COLUMN started_by_id DROP NOT NULL"
  end

  def down do
    execute "ALTER TABLE stock_takes ALTER COLUMN started_by_id SET NOT NULL"
  end
end
