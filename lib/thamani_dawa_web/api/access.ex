defmodule ThamaniDawaWeb.Api.Access do
  @moduledoc """
  Portal checks for the JSON API. The rules match `ThamaniDawaWeb.UserAuth`.
  """

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.Portals

  def portal?(%Scope{} = scope, :org), do: Scope.admin?(scope)

  def portal?(%Scope{} = scope, :pharmacy) do
    Scope.pharmacy_access?(scope) and (Scope.admin?(scope) or site_offers?(scope, :pharmacy))
  end

  def portal?(%Scope{} = scope, :lab) do
    Scope.lab_access?(scope) and (Scope.admin?(scope) or site_offers?(scope, :lab))
  end

  # The distributor portal also depends on the organization's operating
  # model, so it uses the web's check as-is.
  def portal?(%Scope{} = scope, :distributor), do: Portals.portal_access?(scope, :distributor)

  # Like the distributor portal, the manufacturer portal also checks the
  # organization's operating model.
  def portal?(%Scope{} = scope, :manufacturer), do: Portals.portal_access?(scope, :manufacturer)

  # The manufacturer portal's admin pages (`require_manufacturer_admin_access`).
  def portal?(%Scope{} = scope, :manufacturer_admin),
    do: portal?(scope, :manufacturer) and Scope.admin?(scope)

  def portal?(_scope, _portal), do: false

  def portals(%Scope{} = scope) do
    Enum.filter([:org, :pharmacy, :lab, :distributor, :manufacturer], &portal?(scope, &1))
  end

  def same_site?(%Scope{} = scope, site_id) do
    Scope.admin?(scope) or scope.current_site_id == site_id
  end

  defp site_offers?(%Scope{current_site_id: nil}, _portal), do: true

  defp site_offers?(%Scope{current_site_id: site_id, organization_id: organization_id}, portal) do
    site = Sites.get_site!(organization_id, site_id)

    case portal do
      :pharmacy -> Site.pharmacy?(site)
      :lab -> Site.lab?(site)
    end
  rescue
    Ecto.NoResultsError -> false
  end
end
