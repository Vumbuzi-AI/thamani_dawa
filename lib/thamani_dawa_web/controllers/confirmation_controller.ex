defmodule ThamaniDawaWeb.ConfirmationController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user(token) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Email confirmed successfully.")
        |> redirect(to: ~p"/login")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "That confirmation link is invalid or has expired.")
        |> redirect(to: ~p"/login")
    end
  end
end
