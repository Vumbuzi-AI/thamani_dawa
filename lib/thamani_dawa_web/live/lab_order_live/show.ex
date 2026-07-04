defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.Patients

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:lab_tests, LabTests.list_lab_tests(organization_id))
      |> assign(:templates, LabTestTemplates.list_lab_test_templates(organization_id))
      |> load_lab_order(id)

    {:ok, socket}
  end

  defp load_lab_order(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = LabOrders.get_lab_order!(organization_id, id)
    patient = Patients.get_patient!(organization_id, lab_order.patient_id)

    tests =
      organization_id
      |> LabOrders.list_lab_order_tests()
      |> Enum.filter(&(&1.lab_order_id == lab_order.id))

    user_ids =
      tests
      |> Enum.flat_map(&[&1.performed_by_id, &1.verified_by_id])
      |> Enum.filter(& &1)
      |> Enum.uniq()

    users_by_id = Map.new(user_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:tests, tests)
    |> assign(:users_by_id, users_by_id)
  end

  def handle_event("mark_collected", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    LabOrders.mark_sample_collected(organization_id, String.to_integer(id))
    {:noreply, load_lab_order(socket, socket.assigns.lab_order.id)}
  end

  def handle_event("add_test", %{"lab_test_id" => lab_test_id} = attrs, socket) when lab_test_id != "" do
    organization_id = socket.assigns.current_scope.organization_id
    attrs = Map.update(attrs, "template_id", nil, fn value -> if value == "", do: nil, else: value end)

    case LabOrders.create_lab_order_test(organization_id, socket.assigns.lab_order.id, attrs) do
      {:ok, _test} -> {:noreply, load_lab_order(socket, socket.assigns.lab_order.id)}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Couldn't add that test.")}
    end
  end

  def handle_event("add_test", _attrs, socket) do
    {:noreply, put_flash(socket, :error, "Choose a test to add.")}
  end

  defp test_name(lab_tests, lab_test_id) do
    case Enum.find(lab_tests, &(&1.id == lab_test_id)) do
      nil -> "(unknown test)"
      test -> test.name
    end
  end

  defp template_name(_templates, nil), do: "—"

  defp template_name(templates, template_id) do
    case Enum.find(templates, &(&1.id == template_id)) do
      nil -> "—"
      template -> template.name
    end
  end

  defp user_name(users_by_id, id), do: id && Map.get(users_by_id, id, %{name: "—"}).name

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Lab order for {@patient.full_name}
        <:actions>
          <.button navigate={~p"/lab/orders"}>Back</.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Status">{Phoenix.Naming.humanize(@lab_order.status)}</:item>
        <:item title="Urgency">{@lab_order.urgency}</:item>
        <:item title="Prescriber">{@lab_order.prescriber_name}</:item>
        <:item title="Sample collection">{@lab_order.sample_collection_description}</:item>
      </.list>

      <.header class="mt-4">Tests</.header>
      <.table id="lab-order-tests" rows={@tests}>
        <:col :let={test} label="Test">{test_name(@lab_tests, test.lab_test_id)}</:col>
        <:col :let={test} label="Template">{template_name(@templates, test.template_id)}</:col>
        <:col :let={test} label="Status">{Phoenix.Naming.humanize(test.status)}</:col>
        <:col :let={test} label="Sample collected">{test.sample_collected_on}</:col>
        <:col :let={test} label="Performed by">{user_name(@users_by_id, test.performed_by_id)}</:col>
        <:col :let={test} label="Verified by">{user_name(@users_by_id, test.verified_by_id)}</:col>
        <:action :let={test}>
          <.button
            :if={is_nil(test.sample_collected_on)}
            type="button"
            phx-click="mark_collected"
            phx-value-id={test.id}
          >
            Mark collected
          </.button>
          <.link
            :if={test.status == :pending}
            navigate={~p"/lab/orders/#{@lab_order.id}/tests/#{test.id}/results"}
            class="link"
          >
            Enter results
          </.link>
        </:action>
      </.table>

      <div class="card bg-base-200 mt-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Add a test</h2>
          <form phx-submit="add_test" class="flex flex-wrap gap-2 items-end">
            <select name="lab_test_id" class="select">
              <option value="">Choose a test</option>
              <option :for={t <- @lab_tests} value={t.id}>{t.name}</option>
            </select>
            <select name="template_id" class="select">
              <option value="">No template</option>
              <option :for={t <- @templates} value={t.id}>{t.name}</option>
            </select>
            <.button variant="primary">Add test</.button>
          </form>
        </div>
      </div>
    </Layouts.app_shell>
    """
  end
end
