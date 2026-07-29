defmodule ThamaniDawaWeb.LabOrderLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  @urgencies ~w(routine urgent stat)
  @sample_types [{"Blood", :blood}, {"Urine", :urine}, {"Stool", :stool}, {"Swab", :swab}]
  @default_filters %{status: "", urgency: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:urgencies, @urgencies)
     |> assign_lab_orders()}
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
    |> assign(:lab_tests, LabTests.list_active_lab_tests(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:urgencies, @urgencies)
    |> assign(:sample_types, @sample_types)
    |> assign(:use_new_patient, false)
    |> assign(:total_amount, Decimal.new(0))
    |> assign(
      :header_form,
      to_form(LabOrder.changeset(%LabOrder{}, initial_attrs), as: :lab_order)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
    |> assign(:test_ids, [0])
    |> assign(:next_test_id, 1)
    |> assign(:tests_params, %{})
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_new_patient", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_lab_orders()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      status: Map.get(filter_params, "status", ""),
      urgency: Map.get(filter_params, "urgency", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign_lab_orders()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_lab_orders()}
  end

  def handle_event("clear_chip", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | key => ""})
     |> assign_lab_orders()}
  end

  def handle_event("add_test", _params, socket) do
    next_id = socket.assigns.next_test_id

    {:noreply,
     socket
     |> update(:test_ids, &(&1 ++ [next_id]))
     |> update(:next_test_id, &(&1 + 1))}
  end

  def handle_event("remove_test", %{"id" => id}, socket) do
    id = String.to_integer(id)

    {:noreply,
     socket
     |> update(:test_ids, &List.delete(&1, id))
     |> update(:tests_params, &Map.delete(&1, to_string(id)))}
  end

  def handle_event("validate", params, socket) do
    header_attrs = params["lab_order"] || %{}
    patient_attrs = params["patient"] || %{}
    tests_params = params["tests"] || %{}

    changeset =
      %LabOrder{}
      |> LabOrder.changeset(header_attrs)
      |> Map.put(:action, :validate)

    patient_changeset =
      %Patient{}
      |> Patient.changeset(patient_attrs)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:header_form, to_form(changeset, as: :lab_order))
     |> assign(:patient_form, to_form(patient_changeset, as: :patient))
     |> assign(:tests_params, tests_params)
     |> assign(:total_amount, compute_total(params, socket.assigns.lab_tests))}
  end

  def handle_event("save", params, socket) do
    %{"lab_order" => header_attrs} = params
    results_attrs = selected_tests(params)

    if results_attrs == [] do
      {:noreply, put_flash(socket, :error, "Add at least one test to the order.")}
    else
      organization_id = socket.assigns.current_scope.organization_id
      user_id = socket.assigns.current_scope.user.id
      total = compute_total(params, socket.assigns.lab_tests)

      header_attrs =
        header_attrs
        |> Map.put("ordered_by_id", user_id)
        |> Map.put("total_amount", total)

      with {:ok, header_attrs} <- resolve_patient(socket, organization_id, header_attrs, params),
           visit_attrs = %{
             patient_id: header_attrs["patient_id"],
             site_id: header_attrs["site_id"],
             user_id: user_id,
             visit_type: :lab
           },
           {:ok, _} <-
             LabOrders.create_lab_order_with_results(
               organization_id,
               header_attrs,
               results_attrs,
               visit_attrs
             ) do
        {:noreply,
         socket
         |> put_flash(:info, "Lab order created.")
         |> assign_lab_orders()
         |> push_patch(to: ~p"/lab/orders")}
      else
        {:error, %Ecto.Changeset{data: %Patient{}} = changeset} ->
          {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}

        {:error, %Ecto.Changeset{data: %PatientVisit{}}} ->
          {:noreply, put_flash(socket, :error, "Please select or create a patient.")}

        {:error, changeset} ->
          {:noreply, assign(socket, :header_form, to_form(changeset, as: :lab_order))}
      end
    end
  end

  defp resolve_patient(%{assigns: %{use_new_patient: true}}, organization_id, header_attrs, %{
         "patient" => patient_attrs
       }) do
    case Patients.create_patient(organization_id, patient_attrs) do
      {:ok, patient} -> {:ok, Map.put(header_attrs, "patient_id", patient.id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp resolve_patient(_socket, _organization_id, header_attrs, _params), do: {:ok, header_attrs}

  defp selected_tests(params) do
    params
    |> Map.get("tests", %{})
    |> Map.values()
    |> Enum.reject(&(&1["lab_test_id"] in ["", nil]))
  end

  defp compute_total(params, lab_tests) do
    selected_ids =
      params
      |> Map.get("tests", %{})
      |> Map.values()
      |> Enum.map(& &1["lab_test_id"])
      |> Enum.reject(&(&1 in ["", nil]))
      |> MapSet.new()

    lab_tests
    |> Enum.filter(&(to_string(&1.id) in selected_ids))
    |> Enum.reduce(Decimal.new(0), fn test, acc ->
      Decimal.add(acc, test.price || Decimal.new(0))
    end)
  end

  defp assign_lab_orders(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    patients_by_id = organization_id |> Patients.list_patients() |> Map.new(&{&1.id, &1})

    patient_by_visit_id =
      organization_id
      |> PatientVisits.list_patient_visits()
      |> Map.new(&{&1.id, patients_by_id[&1.patient_id]})

    lab_orders =
      organization_id
      |> LabOrders.list_lab_orders()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)
      |> filter_by_search(socket.assigns.search, patient_by_visit_id)
      |> filter_by_status(socket.assigns.filters.status)
      |> filter_by_urgency(socket.assigns.filters.urgency)

    socket
    |> assign(:patient_by_visit_id, patient_by_visit_id)
    |> assign(:lab_orders, lab_orders)
  end

  defp filter_by_search(lab_orders, "", _patient_by_visit_id), do: lab_orders

  defp filter_by_search(lab_orders, search, patient_by_visit_id) do
    search = String.downcase(String.trim(search))

    Enum.filter(lab_orders, fn lab_order ->
      case patient_by_visit_id[lab_order.patient_visit_id] do
        nil -> false
        patient -> String.contains?(String.downcase(patient.full_name), search)
      end
    end)
  end

  defp filter_by_status(lab_orders, ""), do: lab_orders

  defp filter_by_status(lab_orders, status) do
    status = String.to_existing_atom(status)
    Enum.filter(lab_orders, &(&1.status == status))
  end

  defp filter_by_urgency(lab_orders, ""), do: lab_orders

  defp filter_by_urgency(lab_orders, urgency),
    do: Enum.filter(lab_orders, &(&1.urgency == urgency))

  defp active_filter_count(filters) do
    Enum.count([filters.status != "", filters.urgency != ""], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"},
      filters.urgency != "" &&
        %{label: "Urgency: #{Phoenix.Naming.humanize(filters.urgency)}", field: "urgency"}
    ]
    |> Enum.filter(& &1)
  end

  defp patient_name(patient_by_visit_id, visit_id) do
    case patient_by_visit_id[visit_id] do
      nil -> "(unknown patient)"
      patient -> patient.full_name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
      <.header icon="hero-clipboard-document-list">
        Lab orders
        <:subtitle>Search, filter, and manage lab orders at your site.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/lab/orders/new"}>+ New order</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by patient name" />
          </form>

          <.filter_drawer
            id="lab-orders-filters"
            title="Filter lab orders"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={Enum.map(LabOrder.statuses(), &{Phoenix.Naming.humanize(&1), &1})}
                prompt="All statuses"
              />
            </:group>
            <:group label="Urgency">
              <.input
                type="select"
                name="filters[urgency]"
                value={@filters.urgency}
                options={Enum.map(@urgencies, &{Phoenix.Naming.humanize(&1), &1})}
                prompt="All urgencies"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="lab-order-modal"
        show
        class="max-w-4xl"
        on_cancel={JS.patch(~p"/lab/orders")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">New lab order</h2>

        <.form
          for={@header_form}
          id="new-lab-order-form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-5"
        >
          <%!-- Step 1: Patient information --%>
          <section class="rounded-xl ff-surface-card">
            <div class="flex flex-col gap-3 rounded-t-xl border-b border-thamani-stone bg-thamani-canvas px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <h3 class="text-base font-semibold text-thamani-forest">1. Patient</h3>
              <.tab_group>
                <:tab
                  id="existing-patient-mode"
                  active={not @use_new_patient}
                  phx_click="toggle_new_patient"
                >
                  Existing Patient
                </:tab>
                <:tab id="new-patient-mode" active={@use_new_patient} phx_click="toggle_new_patient">
                  New Patient
                </:tab>
              </.tab_group>
            </div>
            <div class="p-4 sm:p-5">
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
                <.date_picker
                  field={@patient_form[:date_of_birth]}
                  label="Date of birth"
                  placeholder="Choose date of birth"
                  max="today"
                  required
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
            </div>
          </section>

          <%!-- Step 2: Tests --%>
          <.form_block title="2. Tests">
            <:actions>
              <.button
                id="add-lab-test"
                type="button"
                phx-click="add_test"
                variant="ghost"
                class="text-xs py-1 px-2.5 h-auto min-h-0"
              >
                + Add Test
              </.button>
            </:actions>

            <div class="space-y-4">
              <%= for {id, idx} <- Enum.with_index(@test_ids) do %>
                <% test_param = Map.get(@tests_params, to_string(id), %{}) %>
                <% selected_test_id = test_param["lab_test_id"] %>
                <% selected_sample_type = test_param["sample_type"] %>
                <% selected_test =
                  Enum.find(@lab_tests, &(to_string(&1.id) == to_string(selected_test_id))) %>
                <div class="rounded-xl border border-thamani-stone bg-thamani-canvas p-4 space-y-3">
                  <div class="flex justify-between items-center">
                    <div class="flex items-center gap-2">
                      <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-thamani-lime text-xs font-semibold text-thamani-forest">
                        {idx + 1}
                      </span>
                      <h4 class="font-medium text-sm text-thamani-forest">
                        Test {idx + 1}
                      </h4>
                      <span
                        :if={selected_test}
                        class="text-xs font-semibold text-thamani-forest bg-thamani-snow px-2 py-0.5 rounded border border-thamani-stone"
                      >
                        KES {selected_test.price}
                      </span>
                    </div>
                    <button
                      :if={length(@test_ids) > 1}
                      type="button"
                      phx-click="remove_test"
                      phx-value-id={id}
                      class="flex size-7 shrink-0 items-center justify-center rounded-md text-thamani-error hover:bg-thamani-error/10 transition-colors"
                      aria-label="Remove test"
                    >
                      <.icon name="hero-trash" class="w-4 h-4" />
                    </button>
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <.input
                      type="select"
                      name={"tests[#{id}][lab_test_id]"}
                      label="Test"
                      value={selected_test_id}
                      options={Enum.map(@lab_tests, &{"#{&1.name} — KES #{&1.price}", &1.id})}
                      prompt="Choose a test"
                      required
                    />
                    <.input
                      type="select"
                      name={"tests[#{id}][sample_type]"}
                      label="Sample type"
                      value={selected_sample_type}
                      options={@sample_types}
                      prompt="Choose sample type"
                      required
                    />
                  </div>
                </div>
              <% end %>

              <div :if={@test_ids == []} class="text-center text-thamani-pewter py-4">
                No tests added. Click "+ Add Test" to select lab tests.
              </div>
            </div>

            <div class="flex justify-end pt-3 border-t border-thamani-stone/60">
              <span class="text-sm font-semibold text-thamani-forest">
                Total: KES {@total_amount}
              </span>
            </div>
          </.form_block>

          <%!-- Step 3: Details and payment --%>
          <.form_block title="3. Details and payment">
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
                field={@header_form[:prescriber_name]}
                label="Prescriber name"
                placeholder="e.g. Dr. Jane Doe"
              />
              <.input
                field={@header_form[:urgency]}
                type="select"
                label="Urgency"
                options={Enum.map(@urgencies, &{Phoenix.Naming.humanize(&1), &1})}
                prompt="Choose urgency"
              />
            </div>

            <.input
              field={@header_form[:lab_request]}
              type="textarea"
              label="Lab request / notes"
              placeholder="Instructions or clinical history"
            />

            <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
              <p class="text-sm font-medium text-thamani-forest">Referred from another facility</p>
              <.input
                field={@header_form[:is_referral]}
                type="checkbox"
                label=""
                class="size-5 rounded accent-thamani-forest cursor-pointer"
              />
            </div>

            <div
              :if={Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:is_referral].value)}
              class="grid grid-cols-1 md:grid-cols-3 gap-4"
            >
              <.input field={@header_form[:referring_facility]} label="Referring facility" required />
              <.input field={@header_form[:referring_doctor]} label="Referring doctor" required />
              <.date_picker
                field={@header_form[:referred_date]}
                label="Referred date"
                placeholder="Choose date"
              />
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 pt-2 border-t border-thamani-stone">
              <.input
                field={@header_form[:payment_type]}
                type="select"
                label="Payment Method"
                options={ThamaniDawa.PaymentMethods.all()}
                prompt="Select payment method"
              />
              <div class="flex items-end pb-3">
                <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 w-full">
                  <p class="text-sm font-medium text-thamani-forest">Paid</p>
                  <.input
                    field={@header_form[:has_paid]}
                    type="checkbox"
                    label=""
                    class="size-5 rounded accent-thamani-forest cursor-pointer"
                  />
                </div>
              </div>
            </div>
          </.form_block>

          <.button type="submit" variant="primary" phx-disable-with="Creating order…" class="w-full">
            Create Order
          </.button>
        </.form>
      </.modal>

      <.table
        id="lab-orders"
        rows={@lab_orders}
        row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
      >
        <:col :let={lab_order} label="Patient">
          {patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
        </:col>
        <:col :let={lab_order} label="Status">
          <.status_badge status={lab_order.status} />
        </:col>
        <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
        <:col :let={lab_order} label="Paid">{if lab_order.has_paid, do: "Yes", else: "No"}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        <:empty_state>
          <.blank_state
            icon="hero-beaker"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No lab orders match your search or filters",
                else: "No lab orders yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Lab orders created at your site will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.national_id || patient.phone || "Unknown ID"
    "#{patient.full_name} (#{id})"
  end
end
