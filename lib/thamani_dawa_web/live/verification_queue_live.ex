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

  defp assign_queue(socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    lab_orders = LabOrders.list_lab_orders(organization_id)
    lab_orders_by_id = Map.new(lab_orders, &{&1.id, &1})

    allowed_lab_order_ids =
      lab_orders |> SiteScoping.for_current_site(scope) |> MapSet.new(& &1.id)

    completed_results =
      organization_id
      |> LabOrders.list_lab_order_results()
      |> Enum.filter(
        &(&1.status == :completed and MapSet.member?(allowed_lab_order_ids, &1.lab_order_id))
      )

    lab_tests_by_id = organization_id |> LabTests.list_lab_tests() |> Map.new(&{&1.id, &1})

    performer_ids =
      completed_results |> Enum.map(& &1.performed_by_id) |> Enum.filter(& &1) |> Enum.uniq()

    users_by_id = Map.new(performer_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    patient_ids =
      completed_results
      |> Enum.map(&lab_orders_by_id[&1.lab_order_id].patient_id)
      |> Enum.uniq()

    patients_by_id = Map.new(patient_ids, &{&1, Patients.get_patient!(organization_id, &1)})

    socket
    |> assign(:completed_results, completed_results)
    |> assign(:lab_orders_by_id, lab_orders_by_id)
    |> assign(:lab_tests_by_id, lab_tests_by_id)
    |> assign(:users_by_id, users_by_id)
    |> assign(:patients_by_id, patients_by_id)
  end

  defp patient_name(patients_by_id, lab_orders_by_id, result) do
    patients_by_id[lab_orders_by_id[result.lab_order_id].patient_id].full_name
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
      <.header>Completed results</.header>

      <.table id="verification-queue" rows={@completed_results}>
        <:col :let={result} label="Patient">
          {patient_name(@patients_by_id, @lab_orders_by_id, result)}
        </:col>
        <:col :let={result} label="Test">{test_name(@lab_tests_by_id, result.lab_test_id)}</:col>
        <:col :let={result} label="Performed by">
          {performer_name(@users_by_id, result.performed_by_id)}
        </:col>
        <:col :let={result} label="Performed on">{result.test_performed_on}</:col>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
