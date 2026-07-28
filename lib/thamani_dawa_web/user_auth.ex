defmodule ThamaniDawaWeb.UserAuth do
  @moduledoc """
  Resolves the signed-in user for a request/socket and assigns
  `current_scope` — see `ThamaniDawa.Accounts.Scope`. Every LiveView that
  needs `current_organization_id` picks this up via
  `on_mount {ThamaniDawaWeb.UserAuth, :mount_current_scope}` rather than
  re-deriving it.
  """

  use ThamaniDawaWeb, :verified_routes

  import Plug.Conn

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @user_token_key "user_token"

  @doc "Stores the user's session token and starts a fresh session."
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    Accounts.update_user_last_logged_in(user)
    Accounts.create_login_session(user.id)

    conn
    |> renew_session()
    |> put_session(@user_token_key, token)
    |> configure_session(renew: true)
  end

  @doc "Deletes the session token and ends the session."
  def log_out_user(conn) do
    user_token = get_session(conn, @user_token_key)

    if user_token do
      if user = Accounts.get_user_by_session_token(user_token) do
        Accounts.update_user_last_logged_out(user)
        Accounts.record_logout_session(user.id)
      end

      Accounts.delete_user_session_token(user_token)
    end

    conn
    |> renew_session()
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc "Plug that assigns `current_scope` on the conn for every browser request."
  def fetch_current_scope_for_user(conn, _opts) do
    user =
      case get_session(conn, @user_token_key) do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc """
  `on_mount` callback assigning `current_scope` from the LiveView session.
  Usage: `live_session :foo, on_mount: [{ThamaniDawaWeb.UserAuth, :mount_current_scope}]`.
  Also supports `:require_authenticated` (halts unless a user is signed in),
  `:require_admin` (halts unless the signed-in user is an org admin, §7),
  `:require_pharmacy_access`, and `:require_lab_access`.

  The pharmacy/lab guards check two things: role (per §7 — admin, or the
  matching staff role, or `pharma_lab`) AND, for every non-admin, that the
  user's *current site* actually offers that portal's operations
  (`Site.pharmacy?/1` / `Site.lab?/1`). Admins are exempt from the site
  check — they operate org-wide and their `current_site_id` is `nil` by
  design. A denied request is redirected to the other portal when the
  user's role+current-site combination supports it, and to `/` otherwise
  (e.g. a warehouse-only site, or no current site at all).
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn -> scope_for_session(session) end)

    {:cont, socket}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn -> scope_for_session(session) end)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/")

      {:halt, socket}
    end
  end

  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if Scope.admin?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
            |> Phoenix.LiveView.redirect(to: ~p"/")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:require_pharmacy_access, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if portal_access?(scope, :pharmacy) do
          {:cont, socket}
        else
          {:halt, deny_portal(socket, scope, :pharmacy)}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:require_lab_access, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if portal_access?(scope, :lab) do
          {:cont, socket}
        else
          {:halt, deny_portal(socket, scope, :lab)}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  defp portal_access?(scope, :pharmacy),
    do:
      Scope.pharmacy_access?(scope) and
        (Scope.admin?(scope) or current_site_offers?(scope, :pharmacy))

  defp portal_access?(scope, :lab),
    do: Scope.lab_access?(scope) and (Scope.admin?(scope) or current_site_offers?(scope, :lab))

  # No home site picked yet is an existing, intentional state (e.g. a
  # pharmacist invited without a site) — those pages handle it themselves
  # with an inline site picker/flash, so the router guard lets them through
  # rather than blocking entry. Only an *actual* site of the wrong type
  # should deny access.
  defp current_site_offers?(%Scope{current_site_id: nil}, _portal), do: true

  defp current_site_offers?(
         %Scope{current_site_id: site_id, organization_id: organization_id},
         portal
       ) do
    case portal do
      :pharmacy -> Site.pharmacy?(Sites.get_site!(organization_id, site_id))
      :lab -> Site.lab?(Sites.get_site!(organization_id, site_id))
    end
  rescue
    Ecto.NoResultsError -> true
  end

  defp deny_portal(socket, scope, denied_portal) do
    other = if denied_portal == :pharmacy, do: :lab, else: :pharmacy

    if portal_access?(scope, other) do
      socket
      |> Phoenix.LiveView.put_flash(
        :info,
        "Your current site doesn't offer #{denied_portal} services — redirected you to the #{other} portal."
      )
      |> Phoenix.LiveView.redirect(to: portal_path(other))
    else
      socket
      |> Phoenix.LiveView.put_flash(
        :error,
        "You don't have access to the #{denied_portal} portal."
      )
      |> Phoenix.LiveView.redirect(to: ~p"/")
    end
  end

  defp portal_path(:pharmacy), do: ~p"/pharmacy"
  defp portal_path(:lab), do: ~p"/lab"

  defp scope_for_session(session) do
    user =
      case session[@user_token_key] do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    Scope.for_user(user)
  end
end
