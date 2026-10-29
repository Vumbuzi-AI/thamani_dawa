defmodule ThamaniDawaWeb.SessionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User

  import Phoenix.Component, only: [to_form: 2]
  import ThamaniDawaWeb.UserAuth, only: [log_in_user: 2, log_out_user: 1]

  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :root}] when action in [:new, :create]

  def new(conn, _params) do
    if Phoenix.Flash.get(conn.assigns.flash, :invite_accepted) do
      conn
      |> log_out_user()
      |> put_flash(:info, "Password set — log in with your new account below.")
      |> render_login(%{"email" => "", "password" => ""})
    else
      if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
        redirect(conn, to: redirect_path_for(conn.assigns.current_scope.user))
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
    case Accounts.get_user_by_email_and_password(email, password) do
      %User{} = user ->
        first_staff_login? = user.role != :admin and is_nil(user.last_logged_in_at)

        conn
        |> log_in_user(user)
        |> redirect(to: login_redirect_path(user, start_tour? or first_staff_login?))

      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render_login(%{"email" => email, "password" => ""})
    end
  end

  def delete(conn, _params) do
    conn
    |> log_out_user()
    |> redirect(to: ~p"/")
  end

  defp redirect_path_for(%User{role: :admin}), do: ~p"/org/dashboard"
  defp redirect_path_for(%User{role: :pharmacist}), do: ~p"/pharmacy"
  defp redirect_path_for(%User{role: :lab_technician}), do: ~p"/lab"

  defp redirect_path_for(%User{role: :pharma_lab, current_site_id: nil}), do: ~p"/pharmacy"

  defp redirect_path_for(%User{role: :pharma_lab} = user) do
    site = ThamaniDawa.Sites.get_site!(user.organization_id, user.current_site_id)

    if ThamaniDawa.Sites.Site.lab?(site) and not ThamaniDawa.Sites.Site.pharmacy?(site) do
      ~p"/lab"
    else
      ~p"/pharmacy"
    end
  rescue
    Ecto.NoResultsError -> ~p"/pharmacy"
  end

  defp login_redirect_path(user, true), do: redirect_path_for(user) <> "?tour=1"
  defp login_redirect_path(user, false), do: redirect_path_for(user)

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
      Map.put(
        account,
        :form,
        to_form(%{"email" => account.email, "password" => "password"}, as: nil)
      )
    end)
  end
end
