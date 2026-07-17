defmodule ThamaniDawaWeb.SiteScoping do
  @moduledoc """
  Filters an org-scoped list down to the current user's home site, for
  LiveViews backing site-scoped screens (Dashboard, Receive stock,
  Prescriptions, Dangerous drug register, Pharmacy logs, Lab orders, Quality
  assurance). Admins have `site_id: nil` and see every site's rows; staff
  have a home `site_id` and only see their own site's rows. Site-filtering is
  deliberately done here (LiveView-side), not in the context layer, since
  `list_*` context functions stay org-scoped only.
  """

  alias ThamaniDawa.Accounts.Scope

  @doc "Filters `rows` (each with a `:site_id` field) to the scope's home site, or all rows for an org-wide user."
  def for_current_site(rows, %Scope{user: %{site_id: nil}}), do: rows

  def for_current_site(rows, %Scope{user: %{site_id: site_id}}) do
    Enum.filter(rows, &(&1.site_id == site_id))
  end

  @doc "The site_id to default a new record's site picker to: the user's home site, or nil for an org-wide admin (who must then pick explicitly)."
  def default_site_id(%Scope{user: %{site_id: site_id}}), do: site_id

  @doc "Filters `rows` (each with a `:site_id` field) down to exactly one given site_id — for an admin drilling into a specific site's detail, as opposed to their own home site."
  def for_site(rows, site_id), do: Enum.filter(rows, &(&1.site_id == site_id))
end
