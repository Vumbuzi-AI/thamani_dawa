defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:lab_tests, LabTests.list_lab_tests(organization_id))
      |> load_lab_order(id)

    {:ok, socket}
  end

  defp load_lab_order(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = LabOrders.get_lab_order!(organization_id, id)
    patient = Patients.get_patient!(organization_id, lab_order.patient_id)

    results =
      organization_id
      |> LabOrders.list_lab_order_results()
      |> Enum.filter(&(&1.lab_order_id == lab_order.id))

    user_ids =
      results
      |> Enum.map(& &1.performed_by_id)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    users_by_id = Map.new(user_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:results, results)
    |> assign(:users_by_id, users_by_id)
  end

  def handle_event("mark_collected", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    LabOrders.mark_sample_collected(organization_id, String.to_integer(id))
    {:noreply, load_lab_order(socket, socket.assigns.lab_order.id)}
  end

  def handle_event("add_result", %{"lab_test_id" => lab_test_id} = attrs, socket)
      when lab_test_id != "" do
    organization_id = socket.assigns.current_scope.organization_id

    case LabOrders.create_lab_order_result(organization_id, socket.assigns.lab_order.id, attrs) do
      {:ok, _result} -> {:noreply, load_lab_order(socket, socket.assigns.lab_order.id)}
      {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Couldn't add that test.")}
    end
  end

  def handle_event("add_result", _attrs, socket) do
    {:noreply, put_flash(socket, :error, "Choose a test to add.")}
  end

  defp test_name(lab_tests, lab_test_id) do
    case Enum.find(lab_tests, &(&1.id == lab_test_id)) do
      nil -> "(unknown test)"
      test -> test.name
    end
  end

  defp user_name(users_by_id, id), do: id && Map.get(users_by_id, id, %{name: "—"}).name

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
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
        <:item title="Referring facility">{@lab_order.referring_facility}</:item>
        <:item title="Referring doctor">{@lab_order.referring_doctor}</:item>
      </.list>

      <.header class="mt-4">Results</.header>
      <.table id="lab-order-results" rows={@results}>
        <:col :let={result} label="Test">{test_name(@lab_tests, result.lab_test_id)}</:col>
        <:col :let={result} label="Status">{Phoenix.Naming.humanize(result.status)}</:col>
        <:col :let={result} label="Sample collected">{result.sample_collected_on}</:col>
        <:col :let={result} label="Performed by">
          {user_name(@users_by_id, result.performed_by_id)}
        </:col>
        <:action :let={result}>
          <.button
            :if={is_nil(result.sample_collected_on)}
            type="button"
            phx-click="mark_collected"
            phx-value-id={result.id}
          >
            Mark collected
          </.button>
          <.link
            :if={result.status == :pending}
            navigate={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/edit"}
            class="link"
          >
            Enter results
          </.link>
        </:action>
      </.table>

      <div class="rounded-2xl p-6 mt-4" style="background: #eeeee9;">
        <h2 class="text-base font-medium mb-4" style="color: #1c3a13;">Add a test</h2>
        <.form
          for={%{}}
          id="add-test-form"
          phx-submit="add_result"
          class="flex flex-wrap gap-3 items-end"
        >
          <.input
            type="select"
            name="lab_test_id"
            label="Test"
            value={nil}
            options={Enum.map(@lab_tests, &{&1.name, &1.id})}
            prompt="Choose a test"
          />
          <.button variant="primary">Add test</.button>
        </.form>
      </div>
    </Layouts.lab_shell>
    """
  end
end
