defmodule ThamaniDawa.Accounts.UserSite do
  @moduledoc "Join row assigning a staff member to a site they can work at (many-to-many)."

  use Ecto.Schema
  import Ecto.Changeset

  schema "user_sites" do
    belongs_to :organization, ThamaniDawa.Organizations.Organization
    belongs_to :user, ThamaniDawa.Accounts.User
    belongs_to :site, ThamaniDawa.Sites.Site

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_site, attrs) do
    user_site
    |> cast(attrs, [:organization_id, :user_id, :site_id])
    |> validate_required([:organization_id, :user_id, :site_id])
    |> unique_constraint([:user_id, :site_id])
  end
end
