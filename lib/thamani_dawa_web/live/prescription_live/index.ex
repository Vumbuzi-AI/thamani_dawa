defmodule ThamaniDawaWeb.PrescriptionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    {:ok, assign_prescriptions(socket)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)
    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:use_new_patient, false)
    |> assign(
      :header_form,
      to_form(Prescription.changeset(%Prescription{}, initial_attrs), as: :prescription)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_patient_mode", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("save", params, socket) do
    %{"prescription" => header_attrs} = params
    site_id = header_attrs["site_id"] || socket.assigns.current_scope.site_id

    if is_nil(site_id) do
      {:noreply, put_flash(socket, :error, "Site is required.")}
    else
      socket.assigns.use_new_patient
      |> save_prescription(params, site_id, socket)
      |> handle_save_result(socket)
    end
  end

  defp save_prescription(true = _new_patient, params, site_id, socket) do
    %{"prescription" => header_attrs} = params
    patient_attrs = Map.get(params, "patient", %{})
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    Prescriptions.create_prescription_with_new_patient(
      organization_id,
      patient_attrs,
      site_id,
      user_id,
      header_attrs
    )
  end

  defp save_prescription(false = _new_patient, params, site_id, socket) do
    %{"prescription" => header_attrs} = params
    patient_id = header_attrs["patient_id"]
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    if is_nil(patient_id) or patient_id == "" do
      changeset =
        %Prescription{}
        |> Prescription.changeset(header_attrs)
        |> Ecto.Changeset.add_error(:patient_id, "can't be blank")
        |> Map.put(:action, :insert)

      {:error, changeset}
    else
      Prescriptions.create_prescription_for_patient(
        organization_id,
        patient_id,
        site_id,
        user_id,
        header_attrs
      )
    end
  end

  defp handle_save_result({:ok, prescription}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Prescription created.")
     |> assign_prescriptions()
     |> push_navigate(to: ~p"/pharmacy/prescriptions/#{prescription.id}")}
  end

  defp handle_save_result({:error, %Ecto.Changeset{data: %Patient{}} = changeset}, socket) do
    {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}
  end

  defp handle_save_result({:error, changeset}, socket) do
    {:noreply, assign(socket, :header_form, to_form(changeset, as: :prescription))}
  end

  defp assign_prescriptions(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    prescriptions =
      organization_id
      |> Prescriptions.list_prescriptions()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)

    assign(socket, :prescriptions, prescriptions)
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/prescriptions"
    >
      <.header>
        Prescriptions
        <:actions>
          <.button variant="primary" patch={~p"/pharmacy/prescriptions/new"}>+ New prescription</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">New prescription</h2>

          <form phx-submit="save" class="space-y-6">
            <!-- Step 1: Patient Information -->
            <div class="border rounded-box border-base-300 overflow-hidden">
              <div class="bg-base-300/50 px-4 py-3 border-b border-base-300 flex justify-between items-center">
                <h3 class="font-semibold text-lg">1. Patient Information</h3>
                <div class="tabs tabs-boxed tabs-sm">
                  <a
                    class={["tab", not @use_new_patient && "tab-active"]}
                    phx-click="toggle_patient_mode"
                  >Existing Patient</a>
                  <a class={["tab", @use_new_patient && "tab-active"]} phx-click="toggle_patient_mode">New Patient</a>
                </div>
              </div>
              <div class="p-4 bg-base-100">
                <div :if={not @use_new_patient}>
                  <.input
                    field={@header_form[:patient_id]}
                    type="select"
                    label="Search and select patient"
                    options={Enum.map(@patients, &{patient_label(&1), &1.id})}
                    prompt="Select patient..."
                  />
                </div>

                <div :if={@use_new_patient} class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input field={@patient_form[:full_name]} label="Full Name" required />
                  <.input field={@patient_form[:gsrn]} type="text" label="GSRN (Identifier)" required />
                  <.input field={@patient_form[:age]} type="number" label="Age" />
                  <.input
                    field={@patient_form[:gender]}
                    type="select"
                    label="Gender"
                    options={["Male", "Female", "Other"]}
                    prompt="Select gender"
                  />
                  <.input field={@patient_form[:phone]} label="Phone" />
                  <.input field={@patient_form[:national_id]} label="National ID" />
                </div>
              </div>
            </div>

            <!-- Step 2: Prescription Details -->
            <div class="border rounded-box border-base-300 overflow-hidden">
              <div class="bg-base-300/50 px-4 py-3 border-b border-base-300">
                <h3 class="font-semibold text-lg">2. Prescription Details</h3>
              </div>
              <div class="p-4 bg-base-100 space-y-4">
                <.input
                  :if={@site_locked}
                  field={@header_form[:site_id]}
                  type="hidden"
                />
                <.input
                  :if={not @site_locked}
                  field={@header_form[:site_id]}
                  type="select"
                  label="Site"
                  options={Enum.map(@sites, &{&1.name, &1.id})}
                  prompt="Choose a site"
                  required
                />

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={@header_form[:referring_doctor]}
                    label="Prescriber (Doctor)"
                    required
                  />
                  <.input
                    field={@header_form[:payment_type]}
                    type="select"
                    label="Payment Method"
                    options={["Cash", "Mobile Money", "Insurance"]}
                    prompt="Select payment method"
                    required
                  />
                </div>

                <.input field={@header_form[:notes]} type="textarea" label="Additional Notes" />
              </div>
            </div>

            <div class="flex gap-2 justify-end">
              <.button type="button" patch={~p"/pharmacy/prescriptions"} variant="ghost">Cancel</.button>
              <.button type="submit" variant="primary">Create Prescription</.button>
            </div>
          </form>
        </div>
      </div>

      <.table
        :if={@live_action != :new}
        id="prescriptions"
        rows={@prescriptions}
        row_click={&JS.navigate(~p"/pharmacy/prescriptions/#{&1.id}")}
      >
        <:col :let={prescription} label="ID">#{prescription.id}</:col>
        <:col :let={prescription} label="Patient">
          <div class="font-semibold">{prescription.patient_name}</div>
          <div class="text-xs text-base-content/70">{prescription.patient_phone}</div>
        </:col>
        <:col :let={prescription} label="Status">{Phoenix.Naming.humanize(prescription.status)}</:col>
        <:col :let={prescription} label="Items">{prescription.items_count}</:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Prescriber">{prescription.referring_doctor}</:col>
        <:col :let={prescription} label="Created">
          {Calendar.strftime(prescription.inserted_at, "%b %d, %H:%M")}
        </:col>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.national_id || patient.phone || "Unknown ID"
    "#{patient.full_name} (#{id})"
  end
end
