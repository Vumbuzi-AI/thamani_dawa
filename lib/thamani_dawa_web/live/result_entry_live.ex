defmodule ThamaniDawaWeb.ResultEntryLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTestTemplates

  def mount(%{"lab_order_id" => lab_order_id, "id" => id}, _session, socket) do
    {:ok, assign(socket, :lab_order_id, lab_order_id) |> load_test(id)}
  end

  defp load_test(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    test = LabOrders.get_lab_order_test!(organization_id, id)

    template =
      test.template_id &&
        LabTestTemplates.get_lab_test_template!(organization_id, test.template_id)

    assign(socket, test: test, template: template)
  end

  def handle_event("save", %{"values" => raw_values}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    performer_id = socket.assigns.current_scope.user.id

    case LabOrders.record_result(
           organization_id,
           socket.assigns.test.id,
           performer_id,
           raw_values
         ) do
      {:ok, test} ->
        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> assign(:test, test)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp current_value(test, key), do: get_in(test.results, [key, "value"])
  defp current_flag(test, key), do: get_in(test.results, [key, "flag"])

  defp flag_class("high"), do: "text-error"
  defp flag_class("low"), do: "text-error"
  defp flag_class("normal"), do: "text-success"
  defp flag_class(_), do: ""

  defp input_type(:numeric), do: "number"
  defp input_type(:text), do: "text"
  defp input_type(:select), do: "text"

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Result entry
        <:actions>
          <.button navigate={~p"/lab/orders/#{@lab_order_id}"}>Back to order</.button>
        </:actions>
      </.header>

      <form phx-submit="save">
        <div :for={field <- @template.field_definitions} :if={@template} class="mb-2">
          <label class="label">{field.label} <span :if={field.unit}>({field.unit})</span></label>
          <input
            type={input_type(field.data_type)}
            step={field.data_type == :numeric && "any"}
            name={"values[#{field.key}]"}
            value={current_value(@test, field.key)}
            class="input w-full"
          />
          <p :if={current_flag(@test, field.key)} class={flag_class(current_flag(@test, field.key))}>
            Flag: {current_flag(@test, field.key)}
          </p>
        </div>

        <div :if={is_nil(@template)} class="mb-2">
          <label class="label">Result</label>
          <input
            type="text"
            name="values[result]"
            value={current_value(@test, "result")}
            class="input w-full"
          />
        </div>

        <.button variant="primary" class="mt-2">Save results</.button>
      </form>
    </Layouts.app_shell>
    """
  end
end
