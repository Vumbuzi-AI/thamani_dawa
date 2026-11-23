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
  @default_filters %{status: "", urgency: "", paid: "", created: ""}
  @page_size 25

  @filter_options %{
    urgency: [{"", "Any"}, {"routine", "Routine"}, {"urgent", "Urgent"}, {"stat", "Stat"}],
    paid: [{"", "Any"}, {"paid", "Paid"}, {"unpaid", "Unpaid"}],
    created: [
      {"", "Any time"},
      {"today", "Today"},
      {"7d", "Last 7 days"},
      {"30d", "Last 30 days"}
    ]
  }

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:urgencies, @urgencies)
     |> assign(:filter_options, @filter_options)
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
    |> assign(
      :lab_tests,
      organization_id |> LabTests.list_active_lab_tests() |> ThamaniDawa.Repo.preload(:category)
    )
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:urgencies, @urgencies)
    |> assign(:use_new_patient, false)
    |> assign(:step, 1)
    |> assign(:total_amount, Decimal.new(0))
    |> assign(
      :header_form,
      to_form(LabOrder.changeset(%LabOrder{}, initial_attrs), as: :lab_order)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
    # Doop AZQrJLFBy5: one test picker plus the list of tests already added.
    # The picker is `tests[<next_test_id>]`; Add test commits it to the list.
    |> assign(:test_ids, [])
    |> assign(:next_test_id, 0)
    |> assign(:tests_params, %{})
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_new_patient", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("goto_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, :step, step |> String.to_integer() |> max(1) |> min(3))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> assign_lab_orders()}
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    {:noreply, set_filter(socket, :status, status)}
  end

  def handle_event("set_filter", %{"field" => field, "value" => value}, socket)
      when field in ~w(urgency paid created) do
    {:noreply, set_filter(socket, String.to_existing_atom(field), value)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:filters, @default_filters)
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign_lab_orders()}
  end

  def handle_event("page", %{"to" => to}, socket) do
    {:noreply, socket |> assign(:page, String.to_integer(to)) |> assign_lab_orders()}
  end

  def handle_event("add_test", _params, socket) do
    picker = to_string(socket.assigns.next_test_id)

    case get_in(socket.assigns.tests_params, [picker, "lab_test_id"]) do
      id when id in [nil, ""] ->
        {:noreply, socket}

      _id ->
        {:noreply,
         socket
         |> update(:test_ids, &(&1 ++ [socket.assigns.next_test_id]))
         |> update(:next_test_id, &(&1 + 1))}
    end
  end

  def handle_event("remove_test", %{"id" => id}, socket) do
    id = String.to_integer(id)

    socket =
      socket
      |> update(:test_ids, &List.delete(&1, id))
      |> update(:tests_params, &Map.delete(&1, to_string(id)))

    {:noreply,
     assign(
       socket,
       :total_amount,
       compute_total(%{"tests" => socket.assigns.tests_params}, socket.assigns.lab_tests)
     )}
  end

  def handle_event("validate", params, socket) do
    header_attrs = params["lab_order"] || %{}
    patient_attrs = params["patient"] || %{}
    tests_params = Map.merge(socket.assigns.tests_params, params["tests"] || %{})

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
     |> assign(:total_amount, compute_total(%{"tests" => tests_params}, socket.assigns.lab_tests))}
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
    filters = socket.assigns.filters

    patients_by_id = organization_id |> Patients.list_patients() |> Map.new(&{&1.id, &1})

    patient_by_visit_id =
      organization_id
      |> PatientVisits.list_patient_visits()
      |> Map.new(&{&1.id, patients_by_id[&1.patient_id]})

    site_orders =
      organization_id
      |> LabOrders.list_lab_orders()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)

    # Tab counts follow the search and chips but not the status tab itself.
    scoped =
      site_orders
      |> filter_by_search(socket.assigns.search, patient_by_visit_id)
      |> filter_by_urgency(filters.urgency)
      |> filter_by_paid(filters.paid)
      |> filter_by_created(filters.created)

    lab_orders = filter_by_status(scoped, filters.status)
    total = length(lab_orders)
    last_page = max(div(total + @page_size - 1, @page_size), 1)
    page = socket.assigns.page |> max(1) |> min(last_page)

    socket
    |> assign(:patient_by_visit_id, patient_by_visit_id)
    |> assign(:status_counts, status_counts(scoped))
    |> assign(:site_order_count, length(site_orders))
    |> assign(:total_orders, total)
    |> assign(:page, page)
    |> assign(:last_page, last_page)
    |> assign(
      :lab_orders,
      lab_orders |> Enum.drop((page - 1) * @page_size) |> Enum.take(@page_size)
    )
  end

  defp set_filter(socket, key, value) do
    socket
    |> assign(:filters, Map.put(socket.assigns.filters, key, value))
    |> assign(:page, 1)
    |> assign_lab_orders()
  end

  defp status_counts(orders) do
    counts = Enum.frequencies_by(orders, & &1.status)
    Map.put(counts, :all, length(orders))
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

  defp filter_by_paid(lab_orders, ""), do: lab_orders
  defp filter_by_paid(lab_orders, "paid"), do: Enum.filter(lab_orders, & &1.has_paid)
  defp filter_by_paid(lab_orders, "unpaid"), do: Enum.reject(lab_orders, & &1.has_paid)

  defp filter_by_created(lab_orders, ""), do: lab_orders

  defp filter_by_created(lab_orders, range) do
    days = %{"today" => 0, "7d" => 6, "30d" => 29}[range]
    from = Date.add(Date.utc_today(), -days)
    Enum.filter(lab_orders, &(Date.compare(to_date(&1.inserted_at), from) != :lt))
  end

  defp to_date(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date(%NaiveDateTime{} = dt), do: NaiveDateTime.to_date(dt)

  defp filtered?(search, filters), do: search != "" or filters != @default_filters

  defp option_label(options, value) do
    Enum.find_value(options, "Any", fn {v, label} -> if v == value, do: label end)
  end

  defp created_label(dt), do: ThamaniDawaWeb.TimeFormat.short_datetime(dt)

  defp ksh(amount), do: ThamaniDawaWeb.Money.ksh(amount)

  defp patient_name(patient_by_visit_id, visit_id) do
    case patient_by_visit_id[visit_id] do
      nil -> "(unknown patient)"
      patient -> patient.full_name
    end
  end

  defp selected_patient(form, patients) do
    id = to_string(form[:patient_id].value || "")
    Enum.find(patients, &(to_string(&1.id) == id))
  end

  defp modal_subtitle(1, _patient, _count),
    do: "Choose the patient, add tests, then confirm details."

  defp modal_subtitle(2, nil, _count), do: "Add the tests requested."
  defp modal_subtitle(2, patient, _count), do: "#{patient.full_name} · add the tests requested."
  defp modal_subtitle(3, nil, count), do: "#{count} #{tests_word(count)}."

  defp modal_subtitle(3, patient, count),
    do: "#{patient.full_name} · #{count} #{tests_word(count)}."

  defp category_name(%{category: %{name: name}}), do: name
  defp category_name(_test), do: nil

  defp tests_word(1), do: "test"
  defp tests_word(_), do: "tests"

  defp added_tests(test_ids, tests_params, lab_tests) do
    for id <- test_ids,
        test_id = get_in(tests_params, [to_string(id), "lab_test_id"]),
        test = Enum.find(lab_tests, &(to_string(&1.id) == to_string(test_id))),
        do: {id, test}
  end

  defp step_state(step, current) when step < current, do: "done"
  defp step_state(step, step), do: "current"
  defp step_state(_step, _current), do: "todo"

  attr :field, :atom, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp filter_chip(assigns) do
    ~H"""
    <div class="td-chip-wrap">
      <button
        type="button"
        id={"lab-orders-chip-#{@field}"}
        class="td-chip"
        phx-click={JS.toggle(to: "#lab-orders-menu-#{@field}")}
        phx-click-away={JS.hide(to: "#lab-orders-menu-#{@field}")}
        aria-haspopup="menu"
      >
        <span class="td-chip-label">{@label}</span>
        <span class="td-chip-value">{option_label(@options, @value)}</span>
        <.td_icon name="caret-down" />
      </button>
      <div id={"lab-orders-menu-#{@field}"} class="td-popover td-filter-menu hidden" role="menu">
        <p class="td-popover-label">{@label}</p>
        <button
          :for={{value, label} <- @options}
          type="button"
          id={"lab-orders-#{@field}-#{if value == "", do: "any", else: value}"}
          class={["td-menu-item", value == @value && "is-selected"]}
          phx-click={
            JS.push("set_filter", value: %{field: @field, value: value})
            |> JS.hide(to: "#lab-orders-menu-#{@field}")
          }
          role="menuitemradio"
          aria-checked={to_string(value == @value)}
        >
          <span>{label}</span>
          <.td_icon :if={value == @value} name="check" class="size-4 td-menu-check" />
        </button>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/lab/orders"}
      crumb="Lab orders"
    >
      <:tools>
        <.td_button id="new-lab-order" variant="primary" label="New order" patch={~p"/lab/orders/new"}>
          <:icon><.td_icon name="plus" /></:icon>
        </.td_button>
      </:tools>

      <section class="td-recipe td-list-page">
        <.td_page_header
          title="Lab orders"
          subtitle="Search, filter, and manage lab orders at your site."
        />

        <nav class="td-tabs" aria-label="Order status">
          <button
            :for={
              {value, label} <- [
                {"", "All"},
                {"pending", "Pending"},
                {"in_progress", "In progress"},
                {"completed", "Completed"},
                {"cancelled", "Cancelled"}
              ]
            }
            type="button"
            id={"lab-orders-tab-#{if value == "", do: "all", else: value}"}
            class={["td-tab", @filters.status == value && "is-active"]}
            phx-click="set_status"
            phx-value-status={value}
            aria-current={@filters.status == value && "page"}
          >
            <span>{label}</span>
            <span class="td-count">
              {Map.get(
                @status_counts,
                if(value == "", do: :all, else: String.to_existing_atom(value)),
                0
              )}
            </span>
          </button>
        </nav>

        <div class="td-toolbar">
          <form phx-change="search" id="search-form" onsubmit="return false">
            <label class="td-search">
              <.td_icon name="magnifying-glass" />
              <input
                type="search"
                name="search"
                value={@search}
                placeholder="Search by patient name"
                phx-debounce="200"
                autocomplete="off"
              />
              <kbd>/</kbd>
            </label>
          </form>
          <.filter_chip
            field={:urgency}
            label="Urgency"
            value={@filters.urgency}
            options={@filter_options.urgency}
          />
          <.filter_chip
            field={:paid}
            label="Paid"
            value={@filters.paid}
            options={@filter_options.paid}
          />
          <.filter_chip
            field={:created}
            label="Created"
            value={@filters.created}
            options={@filter_options.created}
          />
        </div>

        <div :if={@lab_orders == []} class="td-pad td-empty-wrap">
          <div id="lab-orders-empty" class="td-card td-empty-card">
            <%= if filtered?(@search, @filters) do %>
              <p class="td-empty-title">No lab orders match</p>
              <p class="td-note">
                Try another status or clear the search to see every order at your site.
              </p>
              <.td_button
                id="clear-lab-order-filters"
                label="Clear filters"
                phx-click="clear_filters"
              />
            <% else %>
              <p class="td-empty-title">No lab orders yet</p>
              <p class="td-note">
                Orders created at your site appear here. Start with a patient and the tests they need.
              </p>
              <.td_button
                id="empty-new-lab-order"
                variant="primary"
                label="New order"
                patch={~p"/lab/orders/new"}
              >
                <:icon><.td_icon name="plus" /></:icon>
              </.td_button>
            <% end %>
          </div>
        </div>

        <div :if={@lab_orders != []} class="td-data td-list-table">
          <table>
            <thead>
              <tr>
                <th>Order</th>
                <th>Patient</th>
                <th>Status</th>
                <th>Urgency</th>
                <th>Paid</th>
                <th>Created</th>
              </tr>
            </thead>
            <tbody id="lab-orders">
              <tr
                :for={lab_order <- @lab_orders}
                id={"lab-orders-#{lab_order.id}"}
                phx-click={JS.navigate(~p"/lab/orders/#{lab_order}")}
              >
                <td><span class="td-mono">{LabOrders.reference(lab_order)}</span></td>
                <td>
                  <span class="td-person">
                    <.td_orb
                      seed={patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
                      size={20}
                    />
                    <span>{patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}</span>
                  </span>
                </td>
                <td><.status_badge status={lab_order.status} /></td>
                <td>
                  <.td_badge
                    :if={lab_order.urgency in ["urgent", "stat"]}
                    tone="danger"
                    label={Phoenix.Naming.humanize(lab_order.urgency)}
                  />
                  <span :if={lab_order.urgency not in ["urgent", "stat"]} class="td-muted">
                    {Phoenix.Naming.humanize(lab_order.urgency || "routine")}
                  </span>
                </td>
                <td>
                  <span :if={lab_order.has_paid}>Paid</span>
                  <span :if={!lab_order.has_paid} class="td-muted">Unpaid</span>
                </td>
                <td>{created_label(lab_order.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@lab_orders != []} class="td-tfoot">
          <span>
            <b>{(@page - 1) * 25 + 1} to {(@page - 1) * 25 + length(@lab_orders)}</b>
            of {@total_orders} orders
          </span>
          <span class="td-tfoot-pager">
            <button
              type="button"
              class="td-icon-btn"
              aria-label="Previous page"
              disabled={@page == 1}
              phx-click="page"
              phx-value-to={@page - 1}
            >
              <.td_icon name="caret-left" />
            </button>
            <button
              type="button"
              class="td-icon-btn"
              aria-label="Next page"
              disabled={@page >= @last_page}
              phx-click="page"
              phx-value-to={@page + 1}
            >
              <.td_icon name="caret-right" />
            </button>
          </span>
        </div>
      </section>

      <.modal
        :if={@live_action == :new}
        id="lab-order-modal"
        show
        size="wide"
        title="New lab order"
        subtitle={
          modal_subtitle(
            @step,
            selected_patient(@header_form, @patients),
            length(added_tests(@test_ids, @tests_params, @lab_tests))
          )
        }
        on_cancel={JS.patch(~p"/lab/orders")}
      >
        <div class="td-steps" aria-label="Steps">
          <%= for {n, label} <- [{1, "Patient"}, {2, "Tests"}, {3, "Details and payment"}] do %>
            <span :if={n > 1} class="td-sdash"></span>
            <span
              class="td-st"
              data-state={step_state(n, @step)}
              phx-click={n < @step && "goto_step"}
              phx-value-step={n}
            >
              <span class="td-st-n">{n}</span>
              <span>{label}</span>
            </span>
          <% end %>
        </div>

        <.form
          for={@header_form}
          id="new-lab-order-form"
          phx-submit="save"
          phx-change="validate"
          class="td-form-steps"
        >
          <%!-- Step 1: Patient (IGb-vyGRK9 existing, AZQrJLFBy5 new) --%>
          <section class="td-step-pane" hidden={@step != 1}>
            <div class="td-row-between">
              <span class="td-sec">Patient</span>
              <div class="td-segmented" role="group">
                <button
                  type="button"
                  id="existing-patient-mode"
                  class={["td-segment", not @use_new_patient && "is-active"]}
                  phx-click={@use_new_patient && "toggle_new_patient"}
                >
                  Existing patient
                </button>
                <button
                  type="button"
                  id="new-patient-mode"
                  class={["td-segment", @use_new_patient && "is-active"]}
                  phx-click={!@use_new_patient && "toggle_new_patient"}
                >
                  New patient
                </button>
              </div>
            </div>

            <div :if={not @use_new_patient} class="td-stack">
              <.input
                field={@header_form[:patient_id]}
                type="select"
                label="Search and select patient"
                options={Enum.map(@patients, &{patient_label(&1), &1.id})}
                prompt="Select patient..."
              />
              <% patient = selected_patient(@header_form, @patients) %>
              <div :if={patient} class="td-card">
                <div class="td-kv-grid is-pad">
                  <.td_key_value label="GSRN" value={patient.gsrn || "—"} mono />
                  <.td_key_value
                    label="Date of birth"
                    value={
                      if patient.date_of_birth,
                        do: Calendar.strftime(patient.date_of_birth, "%d %b %Y"),
                        else: "—"
                    }
                  />
                  <.td_key_value
                    label="Gender"
                    value={
                      if patient.gender, do: String.capitalize(to_string(patient.gender)), else: "—"
                    }
                  />
                </div>
              </div>
            </div>

            <div :if={@use_new_patient} class="td-fgrid is-2">
              <.input field={@patient_form[:full_name]} label="Full name" required />
              <.input field={@patient_form[:gsrn]} type="text" label="GSRN (identifier)" required />
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
          </section>

          <%!-- Step 2: Tests (gBcldzvNa3) --%>
          <section class="td-step-pane" hidden={@step != 2}>
            <div class="td-fgrid is-picker">
              <.input
                type="select"
                name={"tests[#{@next_test_id}][lab_test_id]"}
                id={"lab-test-picker-#{@next_test_id}"}
                label="Test"
                value={get_in(@tests_params, [to_string(@next_test_id), "lab_test_id"])}
                options={Enum.map(@lab_tests, &{"#{&1.name} · #{ksh(&1.price)}", &1.id})}
                prompt="Choose a test"
              />
              <.td_button id="add-lab-test" type="button" label="Add test" phx-click="add_test">
                <:icon><.td_icon name="plus" /></:icon>
              </.td_button>
            </div>

            <% added = added_tests(@test_ids, @tests_params, @lab_tests) %>
            <div :if={added != []} class="td-card">
              <div class="td-list" id="lab-order-tests">
                <div :for={{id, test} <- added} class="td-li" id={"lab-order-test-#{id}"}>
                  <input type="hidden" name={"tests[#{id}][lab_test_id]"} value={test.id} />
                  <div class="td-li-g">
                    <b>{test.name}</b>
                    <span :if={category_name(test)}>{category_name(test)}</span>
                  </div>
                  <span class="td-num">{ksh(test.price)}</span>
                  <button
                    type="button"
                    class="td-icon-btn"
                    phx-click="remove_test"
                    phx-value-id={id}
                    aria-label={"Remove #{test.name}"}
                  >
                    <.td_icon name="x" />
                  </button>
                </div>
              </div>
            </div>
            <div class="td-tot">
              <span>{length(added)} {tests_word(length(added))}</span>
              <b>{ksh(@total_amount)}</b>
            </div>
          </section>

          <%!-- Step 3: Details and payment (ORIy7H5PbC) --%>
          <section class="td-step-pane" hidden={@step != 3}>
            <.input :if={@site_locked} field={@header_form[:site_id]} type="hidden" />
            <div class="td-fgrid is-2">
              <.input
                :if={@site_locked}
                type="select"
                name="site_display"
                id="lab-order-site-display"
                label="Site"
                value={@header_form[:site_id].value}
                options={Enum.map(@sites, &{&1.name, &1.id})}
                disabled
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
              <.input
                field={@header_form[:prescriber_name]}
                label="Prescriber name"
                placeholder="e.g. Dr. Jane Doe"
              />
            </div>

            <div class="td-segmented is-radio" role="radiogroup" aria-label="Urgency">
              <label
                :for={u <- @urgencies}
                class={[
                  "td-segment",
                  to_string(@header_form[:urgency].value || "routine") == u && "is-active"
                ]}
              >
                <input
                  type="radio"
                  name="lab_order[urgency]"
                  value={u}
                  checked={to_string(@header_form[:urgency].value || "routine") == u}
                  class="sr-only"
                />
                {Phoenix.Naming.humanize(u)}
              </label>
            </div>

            <.input
              field={@header_form[:lab_request]}
              type="textarea"
              label="Lab request / notes"
              placeholder="Instructions or clinical history"
            />

            <label class="td-cb">
              <input type="hidden" name="lab_order[is_referral]" value="false" />
              <input
                type="checkbox"
                name="lab_order[is_referral]"
                value="true"
                checked={
                  Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:is_referral].value)
                }
              />
              <span>Referred from another facility</span>
            </label>

            <div
              :if={Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:is_referral].value)}
              class="td-fgrid is-3"
            >
              <.input field={@header_form[:referring_facility]} label="Referring facility" required />
              <.input field={@header_form[:referring_doctor]} label="Referring doctor" required />
              <.date_picker
                field={@header_form[:referred_date]}
                label="Referred date"
                placeholder="Choose date"
              />
            </div>

            <div class="td-fgrid is-2 is-end">
              <.input
                field={@header_form[:payment_type]}
                type="select"
                label="Payment method"
                options={ThamaniDawa.PaymentMethods.all()}
                prompt="Select payment method"
              />
              <label class="td-cb">
                <input type="hidden" name="lab_order[has_paid]" value="false" />
                <input
                  type="checkbox"
                  name="lab_order[has_paid]"
                  value="true"
                  checked={
                    Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:has_paid].value)
                  }
                />
                <span>Paid</span>
              </label>
            </div>

            <div class="td-tot is-big">
              <span>Total</span>
              <b>{ksh(@total_amount)}</b>
            </div>
          </section>
        </.form>

        <:footer>
          <.td_button
            :if={@step == 1}
            id="lab-order-cancel"
            label="Cancel"
            phx-click={JS.patch(~p"/lab/orders")}
          />
          <.td_button
            :if={@step > 1}
            id="lab-order-back"
            label="Back"
            phx-click="goto_step"
            phx-value-step={@step - 1}
          />
          <.td_button
            :if={@step < 3}
            id="lab-order-continue"
            variant="primary"
            label="Continue"
            phx-click="goto_step"
            phx-value-step={@step + 1}
          />
          <.td_button
            :if={@step == 3}
            id="lab-order-create"
            type="submit"
            form="new-lab-order-form"
            variant="primary"
            label="Create order"
            phx-disable-with="Creating order…"
          />
        </:footer>
      </.modal>
    </Layouts.lab_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.phone || patient.national_id || "Unknown ID"
    "#{patient.full_name} · #{id}"
  end
end
