defmodule ThamaniDawaWeb.DistributorStockLive.Index do
  use ThamaniDawaWeb, :live_view

  @moduledoc """
  The warehouse board now lives on Inventory. These routes keep old links
  and the dashboard's former address working.
  """

  @expiry_filters ~w(all near critical warning watch expired)

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply, push_navigate(socket, to: inventory_path(socket.assigns.live_action, params))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/products"}
    >
    </Layouts.distributor_shell>
    """
  end

  defp inventory_path(:expiry, _params) do
    ~p"/distributor/products?#{%{view: "batches", expiry: "near"}}"
  end

  defp inventory_path(_action, params) do
    query =
      %{"view" => "batches"}
      |> maybe_put_expiry(Map.get(params, "expiry"))
      |> maybe_put_hold(Map.get(params, "hold"))

    ~p"/distributor/products?#{query}"
  end

  defp maybe_put_expiry(query, expiry) when expiry in @expiry_filters and expiry != "all" do
    Map.put(query, "expiry", expiry)
  end

  defp maybe_put_expiry(query, _expiry), do: query

  defp maybe_put_hold(query, "quarantine"), do: Map.put(query, "hold", "quarantine")
  defp maybe_put_hold(query, _hold), do: query
end
