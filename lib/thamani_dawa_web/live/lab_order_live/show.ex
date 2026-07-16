defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:lab_tests, LabTests.list_active_lab_tests(organization_id))
      |> assign(:collecting_result_id, nil)
      |> load_lab_order(id)

    {:ok, socket}
  end

  defp load_lab_order(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = LabOrders.get_lab_order!(organization_id, id)
    visit = PatientVisits.get_patient_visit!(organization_id, lab_order.patient_visit_id)
    patient = Patients.get_patient!(organization_id, visit.patient_id)

    results =
      organization_id
      |> LabOrders.list_lab_order_results()
      |> Enum.filter(&(&1.lab_order_id == lab_order.id))

    user_ids =
      results
      |> Enum.flat_map(&[&1.performed_by_id, &1.collected_by_id])
      |> Enum.filter(& &1)
      |> Enum.uniq()

    users_by_id = Map.new(user_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:results, results)
    |> assign(:users_by_id, users_by_id)
  end

  def handle_event("start_collect", %{"id" => id}, socket) do
    {:noreply, assign(socket, :collecting_result_id, String.to_integer(id))}
  end

  def handle_event("cancel_collect", _params, socket) do
    {:noreply, assign(socket, :collecting_result_id, nil)}
  end

  def handle_event("confirm_collected", %{"result_id" => id} = attrs, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    case LabOrders.mark_sample_collected(organization_id, String.to_integer(id), user_id, attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:collecting_result_id, nil)
          |> load_lab_order(socket.assigns.lab_order.id)

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record sample collection.")}
    end
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

  defp result_unit(lab_tests, lab_test_id, key) do
    case Enum.find(lab_tests, &(&1.id == lab_test_id)) do
      nil -> ""
      test -> get_in(test.field_definitions, [key, "unit"]) || ""
    end
  end

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
        <:col :let={result} label="Collection notes">{result.collection_notes}</:col>
        <:col :let={result} label="Collected by">
          {user_name(@users_by_id, result.collected_by_id)}
        </:col>
        <:col :let={result} label="Performed by">
          {user_name(@users_by_id, result.performed_by_id)}
        </:col>
        <:col :let={result} label="Results">
          <div :if={result.results != %{}} class="space-y-0.5 text-sm">
            <div :for={{key, %{"value" => value}} <- result.results}>
              <span class="font-medium">{key}</span>
              {" #{value} #{result_unit(@lab_tests, result.lab_test_id, key)}"}
            </div>
          </div>
          <span :if={result.results == %{}}>—</span>
        </:col>
        <:action :let={result}>
          <.button
            :if={is_nil(result.sample_collected_on) and @collecting_result_id != result.id}
            type="button"
            phx-click="start_collect"
            phx-value-id={result.id}
          >
            Mark collected
          </.button>
          <.link
            :if={result.status in [:pending, :collected]}
            navigate={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/edit"}
            class="link"
          >
            Enter results
          </.link>
        </:action>
      </.table>

      <div :if={@collecting_result_id} class="rounded-2xl p-6 mt-4" style="background: #eeeee9;">
        <h2 class="text-base font-medium mb-4" style="color: #1c3a13;">Record sample collection</h2>
        <.form
          for={%{}}
          id="collect-sample-form"
          phx-submit="confirm_collected"
          class="flex flex-wrap gap-3 items-end"
        >
          <input type="hidden" name="result_id" value={@collecting_result_id} />
          <.input
            type="date"
            name="collection_date"
            label="Collected on"
            value={to_string(Date.utc_today())}
          />
          <.input type="text" name="collection_notes" label="Notes (optional)" value="" />
          <.button type="submit" variant="primary">Save</.button>
          <.button type="button" phx-click="cancel_collect">Cancel</.button>
        </.form>
      </div>

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
