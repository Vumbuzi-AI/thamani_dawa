defmodule ThamaniDawaWeb.PasswordResetController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts

  import Phoenix.Component, only: [to_form: 2]

  plug :put_layout, html: {ThamaniDawaWeb.Layouts, :root}

  def new(conn, _params), do: render_request(conn, %{"email" => ""})

  def create(conn, %{"email" => email}) do
    _ = Accounts.deliver_password_reset_instructions(email, &url(~p"/reset-password/#{&1}"))

    conn
    |> put_flash(:info, "If that email belongs to an active account, a reset link has been sent.")
    |> redirect(to: ~p"/login")
  end

  def edit(conn, %{"token" => token}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "That reset link is invalid or has expired.")
        |> redirect(to: ~p"/reset-password")

      _user ->
        render(conn, :edit, token: token, form: to_form(%{"password" => ""}, as: :user))
    end
  end

  def update(conn, %{"token" => token, "user" => attrs}) do
    case Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "That reset link is invalid or has expired.")
        |> redirect(to: ~p"/reset-password")

      user ->
        case Accounts.reset_password(user, attrs) do
          {:ok, _user} ->
            conn
            |> put_flash(:info, "Password reset. You can now log in.")
            |> redirect(to: ~p"/login")

          {:error, changeset} ->
            render(conn, :edit, token: token, form: to_form(changeset, as: :user))
        end
    end
  end

  defp render_request(conn, attrs), do: render(conn, :new, form: to_form(attrs, as: nil))
end
