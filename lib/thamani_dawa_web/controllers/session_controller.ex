defmodule ThamaniDawaWeb.SessionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Accounts.User

  import Phoenix.Component, only: [to_form: 2]
  import ThamaniDawaWeb.UserAuth, only: [log_in_user: 2, log_out_user: 1]

  plug :put_layout, [html: {ThamaniDawaWeb.Layouts, :root}] when action in [:new, :create]

  def new(conn, _params) do
    render(conn, :new, form: to_form(%{"email" => "", "password" => ""}, as: nil))
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      %User{} = user ->
        conn
        |> log_in_user(user)
        |> redirect(to: redirect_path_for(user))

      nil ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:new, form: to_form(%{"email" => email, "password" => ""}, as: nil))
    end
  end

  def delete(conn, _params) do
    conn
    |> log_out_user()
    |> redirect(to: ~p"/")
  end

  defp redirect_path_for(%User{role: :admin}), do: ~p"/org/sites"
  defp redirect_path_for(%User{role: :pharmacist}), do: ~p"/pharmacy"
  defp redirect_path_for(%User{role: :lab_technician}), do: ~p"/lab"
  defp redirect_path_for(%User{role: :pharma_lab}), do: ~p"/pharmacy"
end
