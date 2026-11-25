defmodule ThamaniDawaWeb.Portals do
  @moduledoc """
  The single source of truth for portal access and landing paths.

  A portal is never chosen by the user — it is inherited from context:
  the *site* decides which panels exist (a distribution site offers
  distribution operations, a combined pharmacy+lab site offers both), and
  the user's *roles* decide which of the site's panels they can work.
  Admins additionally hold an organization context (org management and
  cross-site reporting) reachable whenever their current site is unset.

  Shared by the login redirect (`ThamaniDawaWeb.SessionController`), the
  site switcher (`ThamaniDawaWeb.SiteSwitchController`), the route guards
  (`ThamaniDawaWeb.UserAuth`) and the sidebar's nav builder
  (`ThamaniDawaWeb.Layouts`), so all four agree on what a given
  scope × site × role combination may reach.
  """

  # Plain path strings rather than verified routes on purpose: this module
  # is referenced by UserAuth (imported by the router), so a compile-time
  # router dependency here would force an arbitrary compile order and
  # xref warnings. The paths are static.

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @org_dashboard "/org/dashboard"
  @distributor_root "/distributor"
  @manufacturer_root "/manufacturer"
  @pharmacy_root "/pharmacy"
  @lab_root "/lab"
  @platform_root "/platform"
  @app_root "/"

  @portals [:org, :pharmacy, :lab, :distributor, :manufacturer]

  @doc "Every portal a scope can be granted or denied access to."
  def portals, do: @portals

  @doc """
  Whether the scope may enter the given portal *right now*: role grants
  (§7 — admins pass every check) AND the current site actually offering
  that portal's operations. An unset current site imposes no site
  constraint (the page itself handles the missing-site state), and the
  distributor portal additionally requires the organization to operate
  under the distributor model.
  """
  def portal_access?(%Scope{} = scope, :org), do: Scope.admin?(scope)

  def portal_access?(%Scope{} = scope, :pharmacy),
    do: Scope.pharmacy_access?(scope) and site_offers?(scope, :pharmacy)

  def portal_access?(%Scope{} = scope, :lab),
    do: Scope.lab_access?(scope) and site_offers?(scope, :lab)

  def portal_access?(%Scope{} = scope, :distributor),
    do:
      Scope.distributor_access?(scope) and distributor_organization?(scope) and
        site_offers?(scope, :distributor)

  def portal_access?(%Scope{} = scope, :manufacturer),
    do:
      Scope.manufacturer_access?(scope) and manufacturer_organization?(scope) and
        site_offers?(scope, :manufacturer)

  @doc """
  The path a signed-in scope should land on: the organization dashboard
  for an admin in org context (no current site), otherwise the panel the
  current site offers that their roles grant. A staff member without a
  current site falls back to their strongest role, mirroring pre-site
  behavior. Superadmins are tenant-less and go to the platform console.
  """
  def default_path(%Scope{} = scope) do
    cond do
      Scope.superadmin?(scope) -> @platform_root
      Scope.admin?(scope) and is_nil(scope.current_site_id) -> @org_dashboard
      site = current_site(scope) -> site_default_path(scope, site)
      true -> role_default_path(scope)
    end
  end

  defp site_default_path(%Scope{} = scope, site) do
    cond do
      Site.distribution?(site) and portal_access?(scope, :distributor) -> @distributor_root
      Site.manufacturer?(site) and portal_access?(scope, :manufacturer) -> @manufacturer_root
      Site.pharmacy?(site) and portal_access?(scope, :pharmacy) -> @pharmacy_root
      Site.lab?(site) and portal_access?(scope, :lab) -> @lab_root
      Scope.admin?(scope) -> @org_dashboard
      # Role grants exist but the current site doesn't support any of them
      # (can't arise through the invite flow anymore, but a site's activities
      # can change after assignment): land on home, whose inline site picker
      # lets the user move to a usable site. Never fall back to a role-only
      # panel here — the guard would deny it again and bounce in a loop.
      true -> @app_root
    end
  end

  defp role_default_path(%Scope{} = scope) do
    cond do
      Scope.admin?(scope) ->
        @org_dashboard

      Scope.distributor_access?(scope) and distributor_organization?(scope) ->
        @distributor_root

      Scope.manufacturer_access?(scope) and manufacturer_organization?(scope) ->
        @manufacturer_root

      Scope.pharmacist?(scope) and Scope.lab_technician?(scope) ->
        @pharmacy_root

      Scope.pharmacist?(scope) ->
        @pharmacy_root

      Scope.lab_technician?(scope) ->
        @lab_root

      true ->
        @app_root
    end
  end

  @doc """
  Whether a site may be offered to the scope in the site picker: admins are
  stationed anywhere (they fall back to the org dashboard for sites they
  can't operate); staff need at least one role that the site's activities
  support — including the distributor model check for the distributor role,
  so nobody is offered a site they'd land in with an empty nav.
  """
  def site_usable?(%Scope{} = scope, %Site{} = site) do
    Scope.admin?(scope) or
      Enum.any?([:pharmacy, :lab, :distributor, :manufacturer], fn portal ->
        site_offers_portal?(site, portal) and portal_role?(scope, portal) and
          (portal != :distributor or distributor_organization?(scope)) and
          (portal != :manufacturer or manufacturer_organization?(scope))
      end)
  end

  @doc "Role-only check (no site): whether the scope's roles grant the portal (§7 — admins pass all)."
  def portal_role?(scope, :org), do: Scope.admin?(scope)
  def portal_role?(scope, :pharmacy), do: Scope.pharmacy_access?(scope)
  def portal_role?(scope, :lab), do: Scope.lab_access?(scope)
  def portal_role?(scope, :distributor), do: Scope.distributor_access?(scope)
  def portal_role?(scope, :manufacturer), do: Scope.manufacturer_access?(scope)

  @doc """
  Whether the scope's *roles* may open the page at `path` (no site or
  organization-model checks), judged by the very `on_mount` guards the router
  declares on the `live_session` that serves it. Navigation uses this to hide
  links the guard would only bounce ("You must be an admin to access this
  page."), so the sidebar, account menu and command palette cannot drift from
  `ThamaniDawaWeb.Router`.

  A path the router does not know, or one with no role guard, is allowed.
  """
  def path_accessible?(scope, path) when is_binary(path) do
    path
    |> required_guards()
    |> Enum.all?(&guard_allows?(scope, &1))
  end

  defp required_guards(path) do
    case Phoenix.Router.route_info(ThamaniDawaWeb.Router, "GET", path, "") do
      %{phoenix_live_view: {_view, _action, _opts, %{extra: %{on_mount: hooks}}}} ->
        for %{id: {ThamaniDawaWeb.UserAuth, guard}} <- hooks, do: guard

      _other ->
        []
    end
  end

  defp guard_allows?(scope, guard)
       when guard in [
              :require_admin,
              :require_distributor_admin_access,
              :require_manufacturer_admin_access
            ],
       do: Scope.admin?(scope)

  defp guard_allows?(scope, :require_superadmin), do: Scope.superadmin?(scope)
  defp guard_allows?(scope, :require_pharmacy_access), do: portal_role?(scope, :pharmacy)
  defp guard_allows?(scope, :require_lab_access), do: portal_role?(scope, :lab)
  defp guard_allows?(scope, :require_distributor_access), do: portal_role?(scope, :distributor)
  defp guard_allows?(scope, :require_manufacturer_access), do: portal_role?(scope, :manufacturer)
  defp guard_allows?(_scope, _guard), do: true

  @doc "Which of a site's activity panels the given portal maps to."
  def site_offers_portal?(%Site{} = site, :pharmacy), do: Site.pharmacy?(site)
  def site_offers_portal?(%Site{} = site, :lab), do: Site.lab?(site)
  def site_offers_portal?(%Site{} = site, :distributor), do: Site.distribution?(site)
  def site_offers_portal?(%Site{} = site, :manufacturer), do: Site.manufacturer?(site)
  def site_offers_portal?(_site, :org), do: true

  @doc """
  Human label for a portal, used for nav group headings when a sidebar
  flattens more than one operations panel.
  """
  def portal_label(:org), do: "Organization"
  def portal_label(:pharmacy), do: "Pharmacy"
  def portal_label(:lab), do: "Lab"
  def portal_label(:distributor), do: "Distributor"
  def portal_label(:manufacturer), do: "Manufacturer"

  @doc """
  Whether the scope's organization operates as a distributor — the
  equivalent of ErpLive's "Healthcare Distributor" sector check. Demoting an
  organization out of the distributor model locks its users (and its mobile
  app users) out of the distributor workflow.
  """
  def distributor_organization?(%Scope{organization_id: organization_id})
      when is_integer(organization_id) do
    organization_id
    |> ThamaniDawa.Organizations.get_organization!()
    |> ThamaniDawa.Organizations.Organization.distributor?()
  end

  def distributor_organization?(_scope), do: false

  @doc """
  Whether the scope's organization operates as a manufacturer. Demoting an
  organization out of the manufacturer model locks its users out of the
  manufacturer workflow.
  """
  def manufacturer_organization?(%Scope{organization_id: organization_id})
      when is_integer(organization_id) do
    organization_id
    |> ThamaniDawa.Organizations.get_organization!()
    |> ThamaniDawa.Organizations.Organization.manufacturer?()
  end

  def manufacturer_organization?(_scope), do: false

  # The scope's current site as a %Site{}, or nil when unset/unknown.
  # Used by the nav builder and guards; staff always have their current
  # site among the preloaded `user.sites`, so only admins pay a query.
  def current_site(%Scope{current_site_id: nil}), do: nil

  def current_site(%Scope{current_site_id: site_id, organization_id: organization_id}) do
    Sites.get_site!(organization_id, site_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  # No home site picked yet is an existing, intentional state (e.g. a
  # pharmacist invited without a site) — those pages handle it themselves
  # with an inline site picker/flash, so access isn't site-constrained
  # until a site is actually picked. Only an *actual* site of the wrong
  # type should deny access.
  defp site_offers?(%Scope{current_site_id: nil}, _portal), do: true

  defp site_offers?(%Scope{} = scope, portal) do
    case current_site(scope) do
      nil -> true
      site -> site_offers_portal?(site, portal)
    end
  end
end
