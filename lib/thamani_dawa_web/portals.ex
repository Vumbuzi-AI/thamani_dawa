defmodule ThamaniDawaWeb.Portals do
  @moduledoc """
  The portals a signed-in account can reach, derived from the roles it holds.

  Login lands an account on exactly one portal (see
  `ThamaniDawaWeb.SessionController.redirect_path_for/1`), but a multi-role
  account — an org admin who also dispenses, say — can reach more than one.
  This module is the single source of truth both ask: the login redirect and
  the sidebar's portal switcher, so the two can never disagree about which
  portal a given set of roles lands in.
  """

  use ThamaniDawaWeb, :verified_routes

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.UserAuth

  @doc """
  The portals the scope's roles grant, as `{label, icon, path}` tuples.

  A pharmacist + lab technician pair yields a *single* entry: the site the
  user is stationed at decides whether that is the pharmacy or the lab,
  exactly as it does at login. Single-role staff get exactly one entry, so
  the sidebar's portal switcher stays hidden for them.
  """
  def list_for(%Scope{} = scope) do
    admin_entry(scope) ++ distributor_entry(scope) ++ operations_entry(scope)
  end

  def list_for(_scope), do: []

  @doc """
  The portal a combined pharmacy + lab technician lands in: the lab when the
  current site is lab-only, the pharmacy otherwise. Shared with the login
  redirect so the sidebar switcher and a fresh sign-in always agree.
  """
  def combined_path(%Scope{current_site_id: nil}), do: ~p"/pharmacy"

  def combined_path(%Scope{current_site_id: site_id, organization_id: organization_id}) do
    site = Sites.get_site!(organization_id, site_id)

    if Site.lab?(site) and not Site.pharmacy?(site) do
      ~p"/lab"
    else
      ~p"/pharmacy"
    end
  rescue
    Ecto.NoResultsError -> ~p"/pharmacy"
  end

  @doc """
  The portal root a path belongs to — `/org/dashboard` is the `/org` portal,
  every other portal path is its own root.
  """
  def portal_root("/org/dashboard"), do: "/org"
  def portal_root(path), do: path

  @doc "The human label for a portal root, e.g. `/lab` is \"Lab\"."
  def root_label("/org"), do: "Organization"
  def root_label("/pharmacy"), do: "Pharmacy"
  def root_label("/lab"), do: "Lab"
  def root_label("/distributor"), do: "Distributor"
  def root_label(_root), do: "Portal"

  defp admin_entry(scope) do
    if Scope.admin?(scope) do
      [{"Admin", "hero-squares-2x2", ~p"/org/dashboard"}]
    else
      []
    end
  end

  defp distributor_entry(scope) do
    if Scope.distributor_access?(scope) and UserAuth.distributor_organization?(scope) do
      [{"Distributor", "hero-truck", ~p"/distributor"}]
    else
      []
    end
  end

  # Pharmacy and lab are one operational portal family: combined staff hold
  # both roles and the site they are stationed at decides which side they
  # work, so they get a single entry rather than two.
  defp operations_entry(scope) do
    case operations_path(scope) do
      "/lab" -> [{"Lab", "hero-beaker", ~p"/lab"}]
      "/pharmacy" -> [{"Pharmacy", "hero-building-storefront", ~p"/pharmacy"}]
      nil -> []
    end
  end

  defp operations_path(scope) do
    cond do
      Scope.pharmacist?(scope) and Scope.lab_technician?(scope) -> combined_path(scope)
      Scope.pharmacist?(scope) -> ~p"/pharmacy"
      Scope.lab_technician?(scope) -> ~p"/lab"
      true -> nil
    end
  end
end
