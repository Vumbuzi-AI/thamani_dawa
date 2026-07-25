defmodule ThamaniDawaWeb.SiteSwitchController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Accounts

  def update(conn, params) do
    scope = conn.assigns.current_scope
    return_to = safe_return_to(params["return_to"])

    if scope && scope.user do
      site_id = to_site_id(params["site_id"])

      case Accounts.switch_current_site(scope, site_id) do
        {:ok, _user} ->
          redirect(conn, to: return_to)

        {:error, :not_assigned} ->
          conn
          |> put_flash(:error, "You're not assigned to that site.")
          |> redirect(to: return_to)
      end
    else
      redirect(conn, to: ~p"/login")
    end
  end

  defp to_site_id(nil), do: nil
  defp to_site_id(""), do: nil
  defp to_site_id(id) when is_binary(id), do: String.to_integer(id)

  defp safe_return_to("/" <> _ = path), do: path
  defp safe_return_to(_), do: ~p"/"
end
