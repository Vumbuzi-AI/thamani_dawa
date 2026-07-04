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
    allowed_lab_order_ids = lab_orders |> SiteScoping.for_current_site(scope) |> MapSet.new(& &1.id)

    completed_tests =
      organization_id
      |> LabOrders.list_lab_order_tests()
      |> Enum.filter(&(&1.status == :completed and MapSet.member?(allowed_lab_order_ids, &1.lab_order_id)))

    lab_tests_by_id = organization_id |> LabTests.list_lab_tests() |> Map.new(&{&1.id, &1})

    performer_ids = completed_tests |> Enum.map(& &1.performed_by_id) |> Enum.filter(& &1) |> Enum.uniq()
    users_by_id = Map.new(performer_ids, &{&1, Accounts.get_user!(organization_id, &1)})

    patient_ids = completed_tests |> Enum.map(&lab_orders_by_id[&1.lab_order_id].patient_id) |> Enum.uniq()
    patients_by_id = Map.new(patient_ids, &{&1, Patients.get_patient!(organization_id, &1)})

    socket
    |> assign(:completed_tests, completed_tests)
    |> assign(:lab_orders_by_id, lab_orders_by_id)
    |> assign(:lab_tests_by_id, lab_tests_by_id)
    |> assign(:users_by_id, users_by_id)
    |> assign(:patients_by_id, patients_by_id)
  end

  def handle_event("verify", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    verifier_id = socket.assigns.current_scope.user.id

    case LabOrders.verify_lab_order_test(organization_id, String.to_integer(id), verifier_id) do
      {:ok, _test} ->
        {:noreply,
         socket
         |> put_flash(:info, "Result verified.")
         |> assign_queue()}

      {:error, :same_technician} ->
        {:noreply, put_flash(socket, :error, "A different technician must verify this result.")}

      {:error, :not_completed} ->
        {:noreply, put_flash(socket, :error, "This result hasn't been entered yet.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't verify that result: #{inspect(reason)}")}
    end
  end

  defp patient_name(patients_by_id, lab_orders_by_id, test) do
    patients_by_id[lab_orders_by_id[test.lab_order_id].patient_id].full_name
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
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>Verification queue</.header>

      <.table id="verification-queue" rows={@completed_tests}>
        <:col :let={test} label="Patient">{patient_name(@patients_by_id, @lab_orders_by_id, test)}</:col>
        <:col :let={test} label="Test">{test_name(@lab_tests_by_id, test.lab_test_id)}</:col>
        <:col :let={test} label="Performed by">{performer_name(@users_by_id, test.performed_by_id)}</:col>
        <:col :let={test} label="Performed on">{test.test_performed_on}</:col>
        <:action :let={test}>
          <.button type="button" variant="primary" phx-click="verify" phx-value-id={test.id}>Verify</.button>
        </:action>
      </.table>
    </Layouts.app_shell>
    """
  end
end
