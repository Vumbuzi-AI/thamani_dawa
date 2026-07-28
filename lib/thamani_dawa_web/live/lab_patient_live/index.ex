defmodule ThamaniDawaWeb.LabPatientLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})}
  end

  def handle_params(params, _url, socket) do
    tab = if Map.get(params, "tab") == "visits", do: "visits", else: "patients"
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", Map.get(params, "q", socket.assigns.search || ""))

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:page, page)
      |> assign(:search, search)
      |> reload_tab()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, _action), do: socket

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/lab/patients?tab=#{tab}")}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, 1)
     |> reload_tab()}
  end

  defp reload_tab(%{assigns: %{tab: "visits"}} = socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = socket.assigns.current_scope.current_site_id
    page = socket.assigns.page
    search = socket.assigns.search

    page_result =
      PatientVisits.list_patient_visits_paginated(
        organization_id,
        page,
        visit_type: :lab,
        site_id: site_id,
        search: search
      )

    socket
    |> assign(:patient_visits, page_result.entries)
    |> assign(:page_info, page_result)
  end

  defp reload_tab(%{assigns: %{tab: "patients"}} = socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page
    search = socket.assigns.search

    page_result =
      Patients.list_patients_paginated(
        organization_id,
        page,
        search: search
      )

    socket
    |> assign(:patients_rows, page_result.entries)
    |> assign(:page_info, page_result)
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab/patients">
      <.header icon="hero-user-group">
        Patients
        <:subtitle>Patients recognized by your organization, and their visits.</:subtitle>
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

      <.table
        :if={@tab == "patients"}
        id="patients"
        rows={@patients_rows}
        row_click={&JS.navigate(~p"/lab/patients/#{&1.id}")}
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
              else: "Patients created via lab orders will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.table :if={@tab == "visits"} id="patient-visits" rows={@patient_visits}>
        <:col :let={visit} label="Patient">{visit.patient_name}</:col>
        <:col :let={visit} label="Phone">{visit.patient_phone}</:col>
        <:col :let={visit} label="Site">{visit.site_name}</:col>
        <:col :let={visit} label="Seen by">{visit.user_name}</:col>
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

      <.pagination page={@page_info} path={pagination_path(@tab, @search)} />
    </Layouts.lab_shell>
    """
  end

  defp pagination_path(tab, search) do
    search = String.trim(search || "")

    if search != "" do
      ~p"/lab/patients?tab=#{tab}&search=#{search}"
    else
      ~p"/lab/patients?tab=#{tab}"
    end
  end
end
