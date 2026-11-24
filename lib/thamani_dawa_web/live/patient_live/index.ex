defmodule ThamaniDawaWeb.PatientLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawaWeb.CarePortal

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
    {:noreply, push_patch(socket, to: CarePortal.patients_tab(socket.assigns.portal, tab, nil))}
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

    visit_opts =
      if socket.assigns.portal == :lab do
        [visit_type: :lab, site_id: site_id, search: search]
      else
        [site_id: site_id, search: search]
      end

    page_result =
      PatientVisits.list_patient_visits_paginated(
        organization_id,
        page,
        visit_opts
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
    <Layouts.care_shell
      portal={@portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={CarePortal.patients(@portal)}
    >
      <:search>
        <form phx-change="search" id="search-form" onsubmit="return false">
          <.td_search
            name="search"
            value={@search}
            placeholder={
              if @tab == "patients",
                do: "Search by name, phone, or national ID",
                else: "Search by patient name or phone"
            }
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <.td_list_page
        title="Patients"
        subtitle="Patients recognized by your organization, and their visits."
      >
        <:tabs>
          <button
            id="patients-tab"
            type="button"
            class={["td-tab", @tab == "patients" && "is-active"]}
            phx-click="switch_tab"
            phx-value-tab="patients"
            aria-current={@tab == "patients" && "page"}
          >
            Patients
          </button>
          <button
            id="visits-tab"
            type="button"
            class={["td-tab", @tab == "visits" && "is-active"]}
            phx-click="switch_tab"
            phx-value-tab="visits"
            aria-current={@tab == "visits" && "page"}
          >
            Patient visits
          </button>
        </:tabs>

        <.table
          :if={@tab == "patients"}
          id="patients"
          rows={@patients_rows}
          row_click={&JS.navigate(CarePortal.patient(@portal, &1.id))}
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
                else:
                  if(@portal == :lab,
                    do: "Patients created via lab orders will appear here.",
                    else: "Patients created via prescriptions will appear here."
                  )}
            </.blank_state>
          </:empty_state>
        </.table>

        <.table :if={@tab == "visits"} id="patient-visits" rows={@patient_visits}>
          <:col :let={visit} label="Patient">
            {if @portal == :lab, do: visit.patient_name, else: visit.patient_name || "Walk-in"}
          </:col>
          <:col :let={visit} label="Phone">{visit.patient_phone}</:col>
          <:col :let={visit} label="Site">{visit.site_name}</:col>
          <:col :let={visit} label="Seen by">{visit.user_name}</:col>
          <:col :let={visit} :if={@portal != :lab} label="Visit type">
            {Phoenix.Naming.humanize(visit.visit_type)}
          </:col>
          <:col :let={visit} label="Date">
            {ThamaniDawaWeb.TimeFormat.short_datetime(visit.inserted_at)}
          </:col>
          <:empty_state>
            <.blank_state
              icon="hero-user-group"
              title={
                if @search != "", do: "No visits match your search", else: "No patient visits yet"
              }
            >
              {if @search != "",
                do: "Try a different search term.",
                else: "Patients who visit your site will appear here."}
            </.blank_state>
          </:empty_state>
        </.table>

        <.pagination page={@page_info} path={CarePortal.patients_tab(@portal, @tab, @search)} />
      </.td_list_page>
    </Layouts.care_shell>
    """
  end
end
