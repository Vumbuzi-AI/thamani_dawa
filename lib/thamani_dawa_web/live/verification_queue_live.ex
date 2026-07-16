defmodule ThamaniDawaWeb.VerificationQueueLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    {:ok, assign_queue(socket)}
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

    lab_tests_by_id = organization_id |> LabTests.list_lab_tests() |> Map.new(&{&1.id, &1})

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

    socket
    |> assign(:pending_verification, pending_verification)
    |> assign(:lab_orders_by_id, lab_orders_by_id)
    |> assign(:lab_tests_by_id, lab_tests_by_id)
    |> assign(:users_by_id, users_by_id)
    |> assign(:patients_by_id, patients_by_id)
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
      <.header>Results pending verification</.header>

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
          <button
            :if={result.performed_by_id != @current_scope.user.id}
            phx-click="verify"
            phx-value-id={result.id}
            class="text-sm font-semibold text-green-600 hover:text-green-800"
          >
            Verify
          </button>
        </:action>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
