defmodule ThamaniDawaWeb.ResultEntryLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests

  def mount(%{"lab_order_id" => lab_order_id, "id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, id)
    lab_test = LabTests.get_lab_test!(organization_id, result.lab_test_id)

    socket =
      socket
      |> assign(:lab_order_id, lab_order_id)
      |> assign(:result, result)
      |> assign(:lab_test, lab_test)

    {:ok, socket}
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
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> push_navigate(to: ~p"/lab/orders/#{socket.assigns.lab_order_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp current_value(result, key), do: get_in(result.results, [key, "value"])

  defp input_type(%{"type" => "number"}), do: "number"
  defp input_type(_), do: "text"

  defp field_label(key, %{"unit" => unit}) when is_binary(unit) and unit != "",
    do: "#{key} (#{unit})"

  defp field_label(key, _definition), do: key

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
      <.header>
        Enter results — {@lab_test.name}
        <:actions>
          <.button navigate={~p"/lab/orders/#{@lab_order_id}"}>Back to order</.button>
        </:actions>
      </.header>

      <div class="rounded-2xl p-6" style="background: #eeeee9;">
        <.form for={%{}} id="result-entry-form" phx-submit="save">
          <div class="flex flex-col gap-4">
            <%= for {key, definition} <- @lab_test.field_definitions do %>
              <.input
                type={input_type(definition)}
                name={"values[#{key}]"}
                label={field_label(key, definition)}
                value={current_value(@result, key)}
              />
            <% end %>
          </div>
          <.button variant="primary" class="mt-4">Save results</.button>
        </.form>
      </div>
    </Layouts.lab_shell>
    """
  end
end
