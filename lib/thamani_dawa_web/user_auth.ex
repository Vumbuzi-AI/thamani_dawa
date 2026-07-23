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
  `:require_pharmacy_access` (admin or pharmacist), and `:require_lab_access`
  (admin or lab_technician) — the pharmacy and lab portals are each open to
  admins in addition to their own staff role, per §7.
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

        if Scope.pharmacy_access?(scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You don't have access to the pharmacy portal.")
            |> Phoenix.LiveView.redirect(to: ~p"/")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  def on_mount(:require_lab_access, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        scope = socket.assigns.current_scope

        if Scope.lab_access?(scope) do
          {:cont, socket}
        else
          socket =
            socket
            |> Phoenix.LiveView.put_flash(:error, "You don't have access to the lab portal.")
            |> Phoenix.LiveView.redirect(to: ~p"/")

          {:halt, socket}
        end

      {:halt, socket} ->
        {:halt, socket}
    end
  end

  defp scope_for_session(session) do
    user =
      case session[@user_token_key] do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    Scope.for_user(user)
  end
end
