defmodule ThamaniDawaWeb.PatientLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})}
  end

  def handle_params(params, _url, socket) do
    tab = if Map.get(params, "tab") == "visits", do: "visits", else: "patients"
    page = String.to_integer(Map.get(params, "page", "1"))

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> reload_tab()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)
    initial_attrs = %{visit_type: :pharmacy}
    initial_attrs = if site_id, do: Map.put(initial_attrs, :site_id, site_id), else: initial_attrs

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:use_new_patient, false)
    |> assign(
      :visit_form,
      to_form(PatientVisit.changeset(%PatientVisit{}, initial_attrs), as: :patient_visit)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/pharmacy/patients?tab=#{tab}")}
  end

  def handle_event("toggle_patient_mode", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_tab()}
  end

  def handle_event("validate", params, socket) do
    visit_attrs = params["patient_visit"] || %{}
    patient_attrs = params["patient"] || %{}

    visit_changeset =
      %PatientVisit{}
      |> PatientVisit.changeset(visit_attrs)
      |> Map.put(:action, :validate)

    patient_changeset =
      %Patient{}
      |> Patient.changeset(patient_attrs)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:visit_form, to_form(visit_changeset, as: :patient_visit))
     |> assign(:patient_form, to_form(patient_changeset, as: :patient))}
  end

  def handle_event("save", params, socket) do
    %{"patient_visit" => visit_attrs} = params

    site_id =
      case visit_attrs["site_id"] do
        blank when blank in [nil, ""] -> SiteScoping.default_site_id(socket.assigns.current_scope)
        site_id -> site_id
      end

    if is_nil(site_id) do
      {:noreply, put_flash(socket, :error, "Site is required.")}
    else
      socket.assigns.use_new_patient
      |> save_patient_visit(params, site_id, socket)
      |> handle_save_result(socket)
    end
  end

  defp save_patient_visit(true = _new_patient, params, site_id, socket) do
    patient_attrs = Map.get(params, "patient", %{})
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    visit_attrs = %{site_id: site_id, user_id: user_id, visit_type: :pharmacy}

    PatientVisits.create_patient_visit_with_new_patient(
      organization_id,
      patient_attrs,
      visit_attrs
    )
  end

  defp save_patient_visit(false = _new_patient, params, site_id, socket) do
    %{"patient_visit" => visit_attrs} = params
    patient_id = visit_attrs["patient_id"]
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    if is_nil(patient_id) or patient_id == "" do
      changeset =
        %PatientVisit{}
        |> PatientVisit.changeset(visit_attrs)
        |> Ecto.Changeset.add_error(:patient_id, "can't be blank")
        |> Map.put(:action, :insert)

      {:error, changeset}
    else
      PatientVisits.create_patient_visit(organization_id, %{
        patient_id: patient_id,
        site_id: site_id,
        user_id: user_id,
        visit_type: :pharmacy
      })
    end
  end

  defp handle_save_result({:ok, _visit}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Patient visit logged.")
     |> reload_tab()
     |> push_patch(to: ~p"/pharmacy/patients?tab=#{socket.assigns.tab}")}
  end

  defp handle_save_result({:error, %Ecto.Changeset{data: %Patient{}} = changeset}, socket) do
    {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}
  end

  defp handle_save_result({:error, changeset}, socket) do
    {:noreply, assign(socket, :visit_form, to_form(changeset, as: :patient_visit))}
  end

  defp reload_tab(%{assigns: %{tab: "visits"}} = socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = PatientVisits.list_patient_visits_paginated(organization_id, page)
    visits = page_result.entries

    filtered =
      visits
      |> SiteScoping.for_current_site(socket.assigns.current_scope)
      |> filter_visits_by_search(socket.assigns.search)

    socket
    |> assign(:patient_visits, filtered)
    |> assign(:page_info, page_result)
  end

  defp reload_tab(%{assigns: %{tab: "patients"}} = socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = Patients.list_patients_paginated(organization_id, page)

    filtered = filter_patients_by_search(page_result.entries, socket.assigns.search)

    socket
    |> assign(:patients_rows, filtered)
    |> assign(:page_info, page_result)
  end

  defp filter_visits_by_search(visits, ""), do: visits

  defp filter_visits_by_search(visits, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(visits, fn visit ->
      [visit.patient_name, visit.patient_phone]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_patients_by_search(patients, ""), do: patients

  defp filter_patients_by_search(patients, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(patients, fn patient ->
      [patient.full_name, patient.phone, patient.national_id]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/patients"
    >
      <.header icon="hero-user-group">
        Patients
        <:subtitle>Patients recognized by your organization, and their visits.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/pharmacy/patients/new?tab=#{@tab}"}>
            + Log visit
          </.button>
        </:actions>
        <:toolbar>
          <.tab_group>
            <:tab
              id="patients-tab"
              active={@tab == "patients"}
              phx_click="switch_tab"
              phx_value_tab="patients"
            >
              Patients
            </:tab>
            <:tab
              id="visits-tab"
              active={@tab == "visits"}
              phx_click="switch_tab"
              phx_value_tab="visits"
            >
              Patient visits
            </:tab>
          </.tab_group>

          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder={
                if @tab == "patients",
                  do: "Search by name, phone, or national ID",
                  else: "Search by patient name or phone"
              }
            />
          </form>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="patient-visit-modal"
        show
        on_cancel={JS.patch(~p"/pharmacy/patients?tab=#{@tab}")}
      >
        <h2 class="font-semibold mb-2">Log a patient visit</h2>

        <.form
          for={@visit_form}
          id="patient-visit-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.tab_group>
            <:tab
              id="existing-patient-mode"
              active={not @use_new_patient}
              phx_click="toggle_patient_mode"
            >
              Existing Patient
            </:tab>
            <:tab id="new-patient-mode" active={@use_new_patient} phx_click="toggle_patient_mode">
              New Patient
            </:tab>
          </.tab_group>

          <div :if={not @use_new_patient}>
            <.input
              field={@visit_form[:patient_id]}
              type="select"
              label="Search and select patient"
              options={Enum.map(@patients, &{patient_label(&1), &1.id})}
              prompt="Select patient..."
            />
          </div>

          <div :if={@use_new_patient} class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@patient_form[:full_name]} label="Full Name" required />
            <.input field={@patient_form[:gsrn]} type="text" label="GSRN (Identifier)" required />
            <.input
              field={@patient_form[:date_of_birth]}
              type="date"
              label="Date of birth"
              required
              max={Date.utc_today()}
            />
            <.input
              field={@patient_form[:gender]}
              type="select"
              label="Gender"
              options={["Male", "Female", "Other"]}
              prompt="Select gender"
              required
            />
            <.input field={@patient_form[:phone]} label="Phone" required />
            <.input field={@patient_form[:national_id]} label="National ID" />
          </div>

          <.input :if={@site_locked} field={@visit_form[:site_id]} type="hidden" />
          <.input
            :if={not @site_locked}
            field={@visit_form[:site_id]}
            type="select"
            label="Site"
            options={Enum.map(@sites, &{&1.name, &1.id})}
            prompt="Choose a site"
            required
          />

          <div class="flex gap-2 mt-2">
            <.button variant="primary" phx-disable-with="Logging visit…">Log visit</.button>
            <.button patch={~p"/pharmacy/patients?tab=#{@tab}"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.table
        :if={@tab == "patients"}
        id="patients"
        rows={@patients_rows}
        row_click={&JS.navigate(~p"/pharmacy/patients/#{&1.id}")}
      >
        <:col :let={patient} label="Name">{patient.full_name}</:col>
        <:col :let={patient} label="Phone">{patient.phone}</:col>
        <:col :let={patient} label="Gender">{patient.gender}</:col>
        <:col :let={patient} label="Age">{Patient.age(patient)}</:col>
        <:col :let={patient} label="National ID">{patient.national_id}</:col>
        <:empty_state>
          <.blank_state
            icon="hero-user-group"
            title={if @search != "", do: "No patients match your search", else: "No patients yet"}
          >
            {if @search != "",
              do: "Try a different search term.",
              else: "Patients logged for a visit will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.table :if={@tab == "visits"} id="patient-visits" rows={@patient_visits}>
        <:col :let={visit} label="Patient">{visit.patient_name}</:col>
        <:col :let={visit} label="Phone">{visit.patient_phone}</:col>
        <:col :let={visit} label="Site">{visit.site_name}</:col>
        <:col :let={visit} label="Seen by">{visit.user_name}</:col>
        <:col :let={visit} label="Visit type">{Phoenix.Naming.humanize(visit.visit_type)}</:col>
        <:col :let={visit} label="Date">
          {Calendar.strftime(visit.inserted_at, "%b %d, %H:%M")}
        </:col>
        <:empty_state>
          <.blank_state
            icon="hero-user-group"
            title={if @search != "", do: "No visits match your search", else: "No patient visits yet"}
          >
            {if @search != "",
              do: "Try a different search term.",
              else: "Patients who visit your site will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={~p"/pharmacy/patients?tab=#{@tab}"} />
    </Layouts.pharmacy_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.national_id || patient.phone || "Unknown ID"
    "#{patient.full_name} (#{id})"
  end
end
