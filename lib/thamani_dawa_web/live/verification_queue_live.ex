defmodule ThamaniDawaWeb.VerificationQueueLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawaWeb.SiteScoping

  @default_filters %{lab_test_id: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign_queue()}
  end

  def handle_event("verify", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    result_id = String.to_integer(id)

    case LabOrders.verify_result(scope.organization_id, result_id, scope.user.id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Result verified.")
         |> assign_queue()}

      {:error, :cannot_self_verify} ->
        {:noreply, put_flash(socket, :error, "You cannot verify your own results.")}
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_queue()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{lab_test_id: Map.get(filter_params, "lab_test_id", "")}
    {:noreply, socket |> assign(:filters, filters) |> assign_queue()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_queue()}
  end

  def handle_event("clear_chip", %{"field" => "lab_test_id"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | lab_test_id: ""}) |> assign_queue()}
  end

  defp assign_queue(socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    lab_orders = LabOrders.list_lab_orders(organization_id)
    lab_orders_by_id = Map.new(lab_orders, &{&1.id, &1})

    allowed_lab_order_ids =
      lab_orders |> SiteScoping.for_current_site(scope) |> MapSet.new(& &1.id)

    pending_verification =
      organization_id
      |> LabOrders.list_results_pending_verification()
      |> Enum.filter(&MapSet.member?(allowed_lab_order_ids, &1.lab_order_id))

    lab_tests = LabTests.list_lab_tests(organization_id)
    lab_tests_by_id = Map.new(lab_tests, &{&1.id, &1})

    performer_ids =
      pending_verification
      |> Enum.map(& &1.performed_by_id)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    users_by_id = Map.new(performer_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    patient_ids =
      pending_verification
      |> Enum.map(&lab_orders_by_id[&1.lab_order_id].patient_id)
      |> Enum.filter(& &1)
      |> Enum.uniq()

    patients_by_id = Map.new(patient_ids, &{&1, Patients.get_patient!(organization_id, &1)})

    pending_verification =
      pending_verification
      |> filter_by_search(socket.assigns.search, patients_by_id, lab_orders_by_id)
      |> filter_by_lab_test(socket.assigns.filters.lab_test_id)

    socket
    |> assign(:pending_verification, pending_verification)
    |> assign(:lab_orders_by_id, lab_orders_by_id)
    |> assign(:lab_tests, lab_tests)
    |> assign(:lab_tests_by_id, lab_tests_by_id)
    |> assign(:users_by_id, users_by_id)
    |> assign(:patients_by_id, patients_by_id)
  end

  defp filter_by_search(results, "", _patients_by_id, _lab_orders_by_id), do: results

  defp filter_by_search(results, search, patients_by_id, lab_orders_by_id) do
    search = String.downcase(String.trim(search))

    Enum.filter(results, fn result ->
      case patients_by_id[lab_orders_by_id[result.lab_order_id].patient_id] do
        nil -> false
        patient -> String.contains?(String.downcase(patient.full_name), search)
      end
    end)
  end

  defp filter_by_lab_test(results, ""), do: results

  defp filter_by_lab_test(results, lab_test_id) do
    lab_test_id = String.to_integer(lab_test_id)
    Enum.filter(results, &(&1.lab_test_id == lab_test_id))
  end

  defp active_filter_count(filters) do
    Enum.count([filters.lab_test_id != ""], & &1)
  end

  defp filter_chips(filters, lab_tests_by_id) do
    [
      filters.lab_test_id != "" &&
        %{
          label: "Test: #{test_name(lab_tests_by_id, String.to_integer(filters.lab_test_id))}",
          field: "lab_test_id"
        }
    ]
    |> Enum.filter(& &1)
  end

  defp patient_name(patients_by_id, lab_orders_by_id, result) do
    patient_id = lab_orders_by_id[result.lab_order_id].patient_id

    case patients_by_id[patient_id] do
      nil -> "—"
      patient -> patient.full_name
    end
  end

  defp test_name(lab_tests_by_id, lab_test_id) do
    case lab_tests_by_id[lab_test_id] do
      nil -> "(unknown test)"
      test -> test.name
    end
  end

  defp performer_name(_users_by_id, nil), do: "—"
  defp performer_name(users_by_id, id), do: Map.get(users_by_id, id, %{name: "—"}).name

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/lab/verification-queue"}
    >
      <.header icon="hero-check-badge">
        Results pending verification
        <:subtitle>Search and filter results awaiting a second-person check.</:subtitle>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by patient name" />
          </form>

          <.filter_drawer
            id="verification-queue-filters"
            title="Filter results"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Test">
              <.input
                type="select"
                name="filters[lab_test_id]"
                value={@filters.lab_test_id}
                options={Enum.map(@lab_tests, &{&1.name, &1.id})}
                prompt="All tests"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @lab_tests_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.table id="verification-queue" rows={@pending_verification}>
        <:col :let={result} label="Patient">
          {patient_name(@patients_by_id, @lab_orders_by_id, result)}
        </:col>
        <:col :let={result} label="Test">{test_name(@lab_tests_by_id, result.lab_test_id)}</:col>
        <:col :let={result} label="Performed by">
          {performer_name(@users_by_id, result.performed_by_id)}
        </:col>
        <:col :let={result} label="Performed on">{result.test_performed_on}</:col>
        <:action :let={result}>
          <.button
            :if={result.performed_by_id != @current_scope.user.id}
            type="button"
            variant="primary"
            phx-click="verify"
            phx-value-id={result.id}
          >
            Verify
          </.button>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-check-circle"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No results match your search or filters",
                else: "Nothing pending verification"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Results awaiting a second-person check will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
