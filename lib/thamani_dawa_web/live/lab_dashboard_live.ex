defmodule ThamaniDawaWeb.LabDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Patients
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    lab_orders =
      organization_id |> LabOrders.list_lab_orders() |> SiteScoping.for_current_site(scope)

    patients_by_id = organization_id |> Patients.list_patients() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:patients_by_id, patients_by_id)
     |> assign(:pending, Enum.filter(lab_orders, &(&1.status == :pending)))
     |> assign(:incomplete, Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress])))}
  end

  defp patient_name(patients_by_id, patient_id) do
    case patients_by_id[patient_id] do
      nil -> "(unknown patient)"
      patient -> patient.full_name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab">
      <.header>Lab dashboard</.header>

      <.header class="mt-4">Pending orders</.header>
      <.table id="pending-orders" rows={@pending} row_click={&~p"/lab/orders/#{&1.id}"}>
        <:col :let={lab_order} label="Patient">
          {patient_name(@patients_by_id, lab_order.patient_id)}
        </:col>
        <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
      </.table>

      <.header class="mt-6">Incomplete reports</.header>
      <.table id="incomplete-orders" rows={@incomplete} row_click={&~p"/lab/orders/#{&1.id}"}>
        <:col :let={lab_order} label="Patient">
          {patient_name(@patients_by_id, lab_order.patient_id)}
        </:col>
        <:col :let={lab_order} label="Status">{Phoenix.Naming.humanize(lab_order.status)}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
