defmodule ThamaniDawaWeb.ResultEntryLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders

  def mount(%{"lab_order_id" => lab_order_id, "id" => id}, _session, socket) do
    socket = assign(socket, :lab_order_id, lab_order_id)
    {:ok, load_result(socket, id)}
  end

  defp load_result(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, id)

    assign(socket, result: result)
  end

  def handle_event("save", %{"values" => raw_values}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    performer_id = socket.assigns.current_scope.user.id

    case LabOrders.record_result(
           organization_id,
           socket.assigns.result.id,
           performer_id,
           raw_values
         ) do
      {:ok, result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> assign(:result, result)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp current_value(result, key), do: get_in(result.results, [key, "value"])

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
      <.header>
        Result entry
        <:actions>
          <.button navigate={~p"/lab/orders/#{@lab_order_id}"}>Back to order</.button>
        </:actions>
      </.header>

      <div class="rounded-2xl p-6" style="background: #eeeee9;">
        <.form for={%{}} id="result-entry-form" phx-submit="save">
          <.input
            type="text"
            name="values[result]"
            label="Result"
            value={current_value(@result, "result")}
          />
          <.button variant="primary" class="mt-4">Save results</.button>
        </.form>
      </div>
    </Layouts.lab_shell>
    """
  end
end
