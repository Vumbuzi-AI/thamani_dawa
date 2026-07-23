defmodule ThamaniDawaWeb.LabDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    lab_orders =
      organization_id |> LabOrders.list_lab_orders() |> SiteScoping.for_current_site(scope)

    patients_by_id = organization_id |> Patients.list_patients() |> Map.new(&{&1.id, &1})

    patient_by_visit_id =
      organization_id
      |> PatientVisits.list_patient_visits()
      |> Map.new(&{&1.id, patients_by_id[&1.patient_id]})

    {:ok,
     socket
     |> assign(:patient_by_visit_id, patient_by_visit_id)
     |> assign(:pending, Enum.filter(lab_orders, &(&1.status == :pending)))
     |> assign(:incomplete, Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress])))}
  end

  defp patient_name(patient_by_visit_id, visit_id) do
    case patient_by_visit_id[visit_id] do
      nil -> "(unknown patient)"
      patient -> patient.full_name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab">
      <.header icon="hero-squares-2x2">
        Lab dashboard
        <:subtitle>Pending orders and incomplete reports at your site.</:subtitle>
      </.header>

      <.header class="mt-4">Pending orders</.header>
      <.table
        id="pending-orders"
        rows={@pending}
        row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
      >
        <:col :let={lab_order} label="Patient">
          {patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
        </:col>
        <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="No pending orders">
            New lab orders at your site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>

      <.header class="mt-6">Incomplete reports</.header>
      <.table
        id="incomplete-orders"
        rows={@incomplete}
        row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
      >
        <:col :let={lab_order} label="Patient">
          {patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
        </:col>
        <:col :let={lab_order} label="Status">
          <.status_badge status={lab_order.status} />
        </:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="No incomplete reports">
            Orders still awaiting collection or results will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
