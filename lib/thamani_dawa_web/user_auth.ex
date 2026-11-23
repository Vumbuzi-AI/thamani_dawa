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
  alias ThamaniDawaWeb.Portals

  # The router imports this module, dragging it into the first wave of
  # compilation — ahead of `Portals`, which every guard below delegates to.
  # Make that ordering explicit so no xref warning can fire for the calls.
  Code.ensure_compiled!(Portals)

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
    token = get_session(conn, @user_token_key)

    user =
      case token do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    if user do
      Accounts.touch_user_session(token)
      ThamaniDawa.Repo.put_audit_actor(user)
    else
      ThamaniDawa.Repo.clear_audit_actor()
    end

    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc """
  Plug counterpart of `on_mount(:require_distributor_access, ...)` for plain
  controller routes (e.g. the shipment CSV export).
  """
  def require_distributor_user(conn, _opts) do
    scope = conn.assigns[:current_scope]

    if scope && Portals.portal_access?(scope, :distributor) do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(:error, "You don't have access to the distributor portal.")
      |> Phoenix.Controller.redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  Plug counterpart of `on_mount(:require_manufacturer_access, ...)` for plain
  controller routes (e.g. a manufacturer CSV export).
  """
  def require_manufacturer_user(conn, _opts) do
    scope = conn.assigns[:current_scope]

    if scope && Portals.portal_access?(scope, :manufacturer) do
      conn
    else
      conn
      |> Phoenix.Controller.put_flash(
        :error,
        "You don't have access to the manufacturer portal."
      )
      |> Phoenix.Controller.redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc """
  `on_mount` callback assigning `current_scope` from the LiveView session.
  Usage: `live_session :foo, on_mount: [{ThamaniDawaWeb.UserAuth, :mount_current_scope}]`.
  Also supports `:require_authenticated` (halts unless a user is signed in),
  `:require_admin` (halts unless the signed-in user is an org admin, §7),
  `:require_superadmin` (halts unless the signed-in user is a platform superadmin),
  `:require_pharmacy_access`, `:require_lab_access`, `:require_distributor_access`,
  `:require_distributor_admin_access` (distributor access, plus org admin —
  gates Billing/Mobile users/Org settings/PPB reporting within the
  distributor portal), and `:require_confirmed_email` (halts unless the
  signed-in admin has confirmed their email — see its doc below).

  The portal guards delegate to `ThamaniDawaWeb.Portals.portal_access?/2`:
  role grants (§7 — admins pass every role check) AND the current site
  actually offering that portal's operations, so a user can only reach the
  panel their *stationed site* offers. A denied request is redirected to
  the scope's default portal (`Portals.default_path/1`) — the other side
  of a combined site when the role+site combination supports it, and `/`
  otherwise (e.g. a warehouse-only site, or no accessible portal at all).
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn -> scope_for_session(session) end)

    set_audit_actor(socket)

    {:cont, socket}
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn -> scope_for_session(session) end)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :current_scope, fn -> scope_for_session(session) end)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      socket = socket |> set_audit_actor() |> attach_session_guard(session)
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

  # Blocks a self-signed-up admin whose email isn't confirmed yet from every
  # other `:organization` route, redirecting to `/confirm-email`. Must be
  # listed *after* `:require_admin` in a live_session's `on_mount` so
  # `current_scope.user` is already populated — see `ConfirmEmailLive`
  # (exempt from this hook itself, to avoid a redirect loop) and
  # `ConfirmationController` for the token-link that sets `confirmed_at`.
  # Invited staff are auto-confirmed on accepting their invite
  # (`Accounts.accept_invite/2`), so they never hit this gate.
  def on_mount(:require_confirmed_email, _params, _session, socket) do
    if socket.assigns.current_scope.user.confirmed_at do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/confirm-email")}
    end
  end

  def on_mount(:require_superadmin, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if Scope.superadmin?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(
              :error,
              "You don't have access to the platform console."
            )
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

        if Portals.portal_access?(scope, :pharmacy) do
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

        if Portals.portal_access?(scope, :lab) do
          {:cont, socket}
        else
          {:halt, deny_portal(socket, scope, :lab)}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:require_distributor_access, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if Portals.portal_access?(scope, :distributor) do
          {:cont, socket}
        else
          {:halt, deny_portal(socket, scope, :distributor)}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  # Admin-only pages within the distributor portal — Billing, Mobile users,
  # Org settings, PPB reporting — gated on top of `:require_distributor_access`'s
  # checks, same composition `:require_confirmed_email` uses on top of
  # `:require_admin` for the organization portal. Denied staff land back in
  # their own portal (`/distributor`), not logged out of it entirely.
  def on_mount(:require_distributor_admin_access, params, session, socket) do
    case on_mount(:require_distributor_access, params, session, socket) do
      {:cont, socket} ->
        if Scope.admin?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
            |> Phoenix.LiveView.redirect(to: ~p"/distributor")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:require_manufacturer_access, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if Portals.portal_access?(scope, :manufacturer) do
          {:cont, socket}
        else
          {:halt, deny_portal(socket, scope, :manufacturer)}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  # Admin-only pages within the manufacturer portal, same composition the
  # distributor portal uses for its own admin-only pages.
  def on_mount(:require_manufacturer_admin_access, params, session, socket) do
    case on_mount(:require_manufacturer_access, params, session, socket) do
      {:cont, socket} ->
        if Scope.admin?(socket.assigns.current_scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You must be an admin to access this page.")
            |> Phoenix.LiveView.redirect(to: ~p"/manufacturer")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  @doc """
  Whether the scope's organization operates as a distributor — the
  equivalent of ErpLive's "Healthcare Distributor" sector check. Demoting an
  organization out of the distributor model locks its users (and its mobile
  app users) out of the distributor workflow. Delegates to
  `ThamaniDawaWeb.Portals`, the single source of truth for portal access.
  """
  def distributor_organization?(scope), do: Portals.distributor_organization?(scope)

  @doc """
  Whether the scope's organization operates as a manufacturer. Delegates to
  `ThamaniDawaWeb.Portals`, the single source of truth for portal access.
  """
  def manufacturer_organization?(scope), do: Portals.manufacturer_organization?(scope)

  # Denied portal access lands the user on the portal their scope *can*
  # reach (the other side of a combined site, their own site's panel, or
  # the org dashboard) — never logged out for a wrong-portal URL.
  defp deny_portal(socket, scope, denied_portal) do
    denied_label = denied_portal |> Portals.portal_label() |> String.downcase()

    socket
    |> Phoenix.LiveView.put_flash(:error, "You don't have access to the #{denied_label} portal.")
    |> Phoenix.LiveView.redirect(to: Portals.default_path(scope))
  end

  defp scope_for_session(session) do
    token = session[@user_token_key]

    user =
      case token do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    if user, do: Accounts.touch_user_session(token)

    Scope.for_user(user)
  end

  defp set_audit_actor(%{assigns: %{current_scope: %{user: user}}} = socket)
       when not is_nil(user) do
    ThamaniDawa.Repo.put_audit_actor(user)
    socket
  end

  defp set_audit_actor(socket), do: socket

  defp attach_session_guard(socket, session) do
    if Phoenix.LiveView.connected?(socket) do
      token = session[@user_token_key]

      Phoenix.LiveView.attach_hook(
        socket,
        :enforce_session_timeout,
        :handle_event,
        &enforce_session_timeout(&1, &2, &3, token)
      )
    else
      socket
    end
  end

  defp enforce_session_timeout(_event, _params, socket, token) do
    case Accounts.get_user_by_session_token(token) do
      nil ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :error,
           "Your session expired due to inactivity. Please log in again."
         )
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      user ->
        Accounts.touch_user_session(token)
        ThamaniDawa.Repo.put_audit_actor(user)
        {:cont, socket}
    end
  end
end
