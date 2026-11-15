defmodule ThamaniDawa.Repo.Migrations.ReplacePharmaLabRole do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE users
    SET roles =
      array_remove(roles, 'pharma_lab')
      || CASE
           WHEN NOT ('pharmacist' = ANY(roles)) THEN ARRAY['pharmacist']::varchar[]
           ELSE ARRAY[]::varchar[]
         END
      || CASE
           WHEN NOT ('lab_technician' = ANY(roles)) THEN ARRAY['lab_technician']::varchar[]
           ELSE ARRAY[]::varchar[]
         END
    WHERE 'pharma_lab' = ANY(roles)
    """)
  end

  # Reversing this would conflate legacy hybrid users with users who were
  # intentionally assigned both underlying roles.
  def down, do: :ok
end
