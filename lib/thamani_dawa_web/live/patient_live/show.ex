defmodule ThamaniDawaWeb.PatientLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    patient = Patients.get_patient!(organization_id, id)
    visits = PatientVisits.list_patient_visits_for_patient(organization_id, patient.id)

    {:ok,
     socket
     |> assign(:patient, patient)
     |> assign(:visits, visits)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/patients"
    >
      <.header icon="hero-user">
        {@patient.full_name}
        <:subtitle>Patient details and visit history.</:subtitle>
        <:actions>
          <.button patch={~p"/pharmacy/patients"} variant="ghost">
            <.icon name="hero-arrow-left" class="size-4" /> Back to patients
          </.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <div class="rounded-xl border border-thamani-stone bg-thamani-snow p-4">
          <div class="text-xs text-thamani-pewter">Phone</div>
          <div class="font-semibold">{@patient.phone}</div>
        </div>
        <div class="rounded-xl border border-thamani-stone bg-thamani-snow p-4">
          <div class="text-xs text-thamani-pewter">Gender</div>
          <div class="font-semibold">{@patient.gender}</div>
        </div>
        <div class="rounded-xl border border-thamani-stone bg-thamani-snow p-4">
          <div class="text-xs text-thamani-pewter">Age</div>
          <div class="font-semibold">{Patient.age(@patient)}</div>
        </div>
        <div class="rounded-xl border border-thamani-stone bg-thamani-snow p-4">
          <div class="text-xs text-thamani-pewter">National ID</div>
          <div class="font-semibold">{@patient.national_id || "-"}</div>
        </div>
      </div>

      <h3 class="text-base font-semibold text-thamani-forest mb-2">Visit history</h3>

      <.table id="patient-visit-history" rows={@visits}>
        <:col :let={visit} label="Site">{visit.site_name}</:col>
        <:col :let={visit} label="Seen by">{visit.user_name}</:col>
        <:col :let={visit} label="Visit type">{Phoenix.Naming.humanize(visit.visit_type)}</:col>
        <:col :let={visit} label="Date">
          {Calendar.strftime(visit.inserted_at, "%b %d, %H:%M")}
        </:col>
        <:empty_state>
          <.blank_state icon="hero-user-group" title="No visits yet">
            This patient hasn't been logged for a visit yet.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
