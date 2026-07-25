defmodule ThamaniDawa.Repo.Migrations.BackfillUserSitesFromUsersSiteId do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO user_sites (organization_id, user_id, site_id, inserted_at, updated_at)
    SELECT organization_id, id, site_id, NOW(), NOW()
    FROM users
    WHERE site_id IS NOT NULL
    """

    execute """
    UPDATE users SET current_site_id = site_id WHERE site_id IS NOT NULL
    """
  end

  def down do
    execute "UPDATE users SET current_site_id = NULL"
    execute "DELETE FROM user_sites"
  end
end
