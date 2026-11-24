defmodule ThamaniDawaWeb.SessionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.LoginRateLimiter
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.Portals

  import Phoenix.Component, only: [to_form: 2]
  import ThamaniDawaWeb.UserAuth, only: [log_in_user: 2, log_out_user: 1]

  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :root}] when action in [:new, :create]

  def new(conn, _params) do
    if Phoenix.Flash.get(conn.assigns.flash, :invite_accepted) do
      conn
      |> log_out_user()
      |> put_flash(:info, "Password set. Log in with your new account below.")
      |> render_login(%{"email" => "", "password" => ""})
    else
      if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
        redirect(conn, to: login_redirect_path(conn.assigns.current_scope.user, false, false))
      else
        render_login(conn, %{"email" => "", "password" => ""})
      end
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    authenticate(conn, email, password, false)
  end

  # Signup submits its validated LiveView form through a regular browser POST
  # so the session cookie can be established after the organization commits.
  def create(conn, %{
        "user" => %{"email" => email, "password" => password},
        "start_tour" => "true"
      }) do
    authenticate(conn, email, password, true)
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    authenticate(conn, email, password, false)
  end

  defp authenticate(conn, email, password, start_tour?) do
    rate_keys = ["ip:" <> remote_ip(conn), "email:" <> String.downcase(String.trim(email))]

    case LoginRateLimiter.allow?(rate_keys) do
      :ok ->
        case Accounts.get_user_by_email_and_password(email, password) do
          %User{} = user ->
            LoginRateLimiter.reset(rate_keys)

            first_staff_login? =
              :admin not in user.roles and :superadmin not in user.roles and
                is_nil(user.last_logged_in_at)

            conn
            |> log_in_user(user)
            |> redirect(to: login_redirect_path(user, start_tour?, first_staff_login?))

          nil ->
            invalid_login(conn, email)
        end

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, "Too many login attempts. Please wait before trying again.")
        |> render_login(%{"email" => email, "password" => ""})
    end
  end

  defp invalid_login(conn, email) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> render_login(%{"email" => email, "password" => ""})
  end

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  def delete(conn, _params) do
    conn
    |> log_out_user()
    |> redirect(to: ~p"/")
  end

  # The portal a fresh sign-in lands in is inherited from context, not
  # chosen: the account's current site decides which panel exists there
  # and its roles decide which of the site's panels they can work. An
  # admin in org context (no current site) lands on the org dashboard.
  defp redirect_path_for(%User{} = user), do: Portals.default_path(Scope.for_user(user))

  # A fresh self-signup starts the full-screen checklist and then the product
  # tour. Returning admins also resume the checklist while database-backed
  # setup tasks remain; invited staff continue to their own portal tour.
  def login_redirect_path(user, true, _first_staff_login?) do
    if :admin in user.roles and onboarding_incomplete?(user) do
      ~p"/onboarding"
    else
      redirect_path_for(user) <> "?tour=1"
    end
  end

  def login_redirect_path(user, false, first_staff_login?) do
    cond do
      :admin in user.roles and onboarding_incomplete?(user) ->
        ~p"/onboarding"

      first_staff_login? ->
        redirect_path_for(user) <> "?tour=1"

      true ->
        redirect_path_for(user)
    end
  end

  defp onboarding_incomplete?(user) do
    organization = Organizations.get_organization!(user.organization_id)
    primary_site = user.organization_id |> Sites.list_sites() |> List.first()

    organization
    |> Organizations.onboarding_checklist(primary_site)
    |> Enum.any?(&(not &1.done?))
  end

  defp render_login(conn, params) do
    render(conn, :new,
      form: to_form(params, as: nil),
      demo_accounts: demo_accounts()
    )
  end

  defp demo_accounts do
    :thamani_dawa
    |> Application.get_env(:demo_login_accounts, [])
    |> Enum.map(fn account ->
      account
      |> Map.put(
        :form,
        to_form(%{"email" => account.email, "password" => account.password}, as: nil)
      )
      |> Map.put(:icon, demo_account_icon(account.id))
    end)
  end

  defp demo_account_icon("superadmin"), do: "hero-shield-check"
  defp demo_account_icon("admin"), do: "hero-cog-6-tooth"
  defp demo_account_icon("pharmacist"), do: "hero-clipboard-document-check"
  defp demo_account_icon("lab"), do: "hero-beaker"
  defp demo_account_icon("pharma-lab"), do: "hero-user-group"
  defp demo_account_icon("distributor"), do: "hero-cube"
  defp demo_account_icon("manufacturer"), do: "hero-cog-8-tooth"
  defp demo_account_icon("manufacturer-distributor"), do: "hero-cog-8-tooth"
  defp demo_account_icon(_), do: "hero-user"
end
