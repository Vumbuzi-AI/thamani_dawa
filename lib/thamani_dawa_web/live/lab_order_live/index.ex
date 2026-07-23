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
    {:noreply,
     socket
     |> update(:test_ids, &(&1 ++ [socket.assigns.next_test_id]))
     |> update(:next_test_id, &(&1 + 1))}
  end

  def handle_event("remove_test", %{"id" => id}, socket) do
    id = String.to_integer(id)
    test_ids = List.delete(socket.assigns.test_ids, id)
    test_ids = if test_ids == [], do: socket.assigns.test_ids, else: test_ids
    {:noreply, assign(socket, :test_ids, test_ids)}
  end

  def handle_event("validate", params, socket) do
    header_attrs = params["lab_order"] || %{}

    changeset =
      %LabOrder{}
      |> LabOrder.changeset(header_attrs)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:header_form, to_form(changeset, as: :lab_order))
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
        class="max-w-3xl"
        on_cancel={JS.patch(~p"/lab/orders")}
      >
        <h2 class="text-base font-medium mb-5" style="color: #373896;">New lab order</h2>

        <.form
          for={@header_form}
          id="new-lab-order-form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-4"
        >
          <div>
            <div class="flex items-center justify-between mb-1.5">
              <p class="text-sm font-medium" style="color: #373896;">Patient</p>
              <.button type="button" phx-click="toggle_new_patient">
                {if @use_new_patient, do: "Choose existing patient", else: "+ New patient"}
              </.button>
            </div>

            <.input
              :if={not @use_new_patient}
              field={@header_form[:patient_id]}
              type="select"
              options={Enum.map(@patients, &{&1.full_name, &1.id})}
              prompt="Choose a patient"
            />

            <div :if={@use_new_patient} class="rounded-xl p-4 space-y-3" style="background: #FFFFFF;">
              <.input field={@patient_form[:full_name]} label="Full name" required />
              <.input field={@patient_form[:gsrn]} type="number" label="GSRN" required />
              <.date_picker
                field={@patient_form[:date_of_birth]}
                label="Date of birth"
                placeholder="Choose date of birth"
                max="today"
                required
              />
              <div class="grid grid-cols-2 gap-3">
                <.input field={@patient_form[:gender]} label="Gender" required />
                <.input field={@patient_form[:phone]} label="Phone" required />
              </div>
              <.input field={@patient_form[:national_id]} label="National ID" />
            </div>
          </div>

          <.input :if={@site_locked} field={@header_form[:site_id]} type="hidden" />
          <.input
            :if={not @site_locked}
            field={@header_form[:site_id]}
            type="select"
            label="Site"
            options={Enum.map(@sites, &{&1.name, &1.id})}
            prompt="Choose a site"
            required
          />

          <div class="grid grid-cols-2 gap-3">
            <.input field={@header_form[:prescriber_name]} label="Prescriber name" />
            <.input
              field={@header_form[:urgency]}
              type="select"
              label="Urgency"
              options={Enum.map(@urgencies, &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose urgency"
            />
          </div>

          <.input field={@header_form[:lab_request]} type="textarea" label="Lab request" />

          <.input
            field={@header_form[:is_referral]}
            type="checkbox"
            label="This order was referred from another facility"
          />

          <div
            :if={Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:is_referral].value)}
            class="grid grid-cols-3 gap-3"
          >
            <.input field={@header_form[:referring_facility]} label="Referring facility" required />
            <.input field={@header_form[:referring_doctor]} label="Referring doctor" required />
            <.input field={@header_form[:referred_date]} type="date" label="Referred date" />
          </div>

          <%!-- Tests --%>
          <div>
            <div class="flex items-center justify-between mb-2">
              <p class="text-sm font-medium" style="color: #373896;">Tests</p>
              <.button type="button" phx-click="add_test">+ Add test</.button>
            </div>
            <div class="space-y-2">
              <div
                :for={id <- @test_ids}
                class="grid grid-cols-[1fr_1fr_auto] items-end gap-3 rounded-xl bg-thamani-snow p-3 [&>div]:mb-0"
              >
                <.input
                  type="select"
                  name={"tests[#{id}][lab_test_id]"}
                  label="Test"
                  value={nil}
                  options={Enum.map(@lab_tests, &{&1.name, &1.id})}
                  prompt="Choose a test"
                />
                <.input
                  type="select"
                  name={"tests[#{id}][sample_type]"}
                  label="Sample type"
                  value={nil}
                  options={@sample_types}
                  prompt="Choose sample type"
                />
                <.button
                  type="button"
                  variant="ghost-delete"
                  phx-click="remove_test"
                  phx-value-id={id}
                >
                  Remove
                </.button>
              </div>
            </div>
            <p class="text-sm text-right mt-3" style="color: #373896;">
              Total: <span class="font-medium">KES {@total_amount}</span>
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <.input
              field={@header_form[:payment_type]}
              type="select"
              label="Payment method"
              options={ThamaniDawa.PaymentMethods.all()}
              prompt="Choose a payment method"
            />
            <div class="flex items-end pb-1">
              <.input field={@header_form[:has_paid]} type="checkbox" label="Paid" />
            </div>
          </div>

          <div class="flex gap-3 pt-2">
            <.button variant="primary">Create order</.button>
            <.button patch={~p"/lab/orders"}>Cancel</.button>
          </div>
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
end
