defmodule ThamaniDawaWeb.PrescriptionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  @default_filters %{status: "", payment_type: "", paid: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign_prescriptions()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))

    socket =
      socket
      |> assign(:page, page)
      |> assign_prescriptions()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)
    initial_attrs = if site_id, do: %{site_id: site_id, items: []}, else: %{items: []}

    products =
      if site_id do
        ThamaniDawa.Products.list_active_products_with_stock_for_site(organization_id, site_id)
      else
        []
      end

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:products, products)
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:patient_mode, :existing)
    |> assign(:editing_items, MapSet.new())
    |> assign(
      :header_form,
      to_form(Prescription.changeset(%Prescription{}, initial_attrs), as: :prescription)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
  end

  defp apply_action(socket, :quick_sale) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)

    products =
      if site_id do
        ThamaniDawa.Products.list_active_products_with_stock_for_site(organization_id, site_id)
      else
        []
      end

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:products, products)
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:quick_sale_site_id, site_id)
    |> assign(:quick_sale_patient_id, "")
    |> assign(:quick_sale_payment_type, "")
    |> assign(:quick_sale_errors, %{})
    |> assign(:quick_sale_items, [%{"product_id" => "", "quantity" => "1", "scanned_gtin" => ""}])
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_patient_mode", %{"tab" => mode}, socket) do
    {:noreply, assign(socket, :patient_mode, String.to_existing_atom(mode))}
  end

  def handle_event("quick_sale_validate", params, socket) do
    {:noreply,
     socket
     |> assign(:quick_sale_items, quick_sale_items_from_params(params))
     |> assign(:quick_sale_patient_id, params["patient_id"] || "")
     |> assign(:quick_sale_payment_type, params["payment_type"] || "")
     |> assign(:quick_sale_errors, %{})
     |> maybe_reload_quick_sale_products(params["site_id"])}
  end

  def handle_event("add_quick_sale_item", _params, socket) do
    items =
      socket.assigns.quick_sale_items ++
        [%{"product_id" => "", "quantity" => "1", "scanned_gtin" => ""}]

    {:noreply, assign(socket, :quick_sale_items, items)}
  end

  def handle_event("remove_quick_sale_item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    items = List.delete_at(socket.assigns.quick_sale_items, index)

    items =
      if items == [],
        do: [%{"product_id" => "", "quantity" => "1", "scanned_gtin" => ""}],
        else: items

    {:noreply, assign(socket, :quick_sale_items, items)}
  end

  def handle_event("complete_quick_sale", params, socket) do
    complete_quick_sale(socket, params)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign_prescriptions()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      status: Map.get(filter_params, "status", ""),
      payment_type: Map.get(filter_params, "payment_type", ""),
      paid: Map.get(filter_params, "paid", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign_prescriptions()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> assign_prescriptions()}
  end

  def handle_event("clear_chip", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | key => ""})
     |> assign_prescriptions()}
  end

  def handle_event("validate", params, socket) do
    header_attrs = params["prescription"] || %{}
    patient_attrs = params["patient"] || %{}

    header_changeset =
      %Prescription{}
      |> Prescription.changeset(header_attrs)
      |> Map.put(:action, :validate)

    patient_changeset =
      %Patient{}
      |> Patient.changeset(patient_attrs)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:header_form, to_form(header_changeset, as: :prescription))
      |> assign(:patient_form, to_form(patient_changeset, as: :patient))
      |> maybe_reload_products(header_attrs["site_id"])

    {:noreply, socket}
  end

  def handle_event("add-item", _, socket) do
    changeset = socket.assigns.header_form.source
    items = items_value(socket.assigns.header_form)
    new_index = length(items)

    changeset =
      Ecto.Changeset.put_assoc(
        changeset,
        :items,
        items ++ [%ThamaniDawa.Prescriptions.PrescriptionItem{}]
      )

    editing_items = MapSet.put(socket.assigns.editing_items, new_index)

    {:noreply,
     assign(socket,
       header_form: to_form(changeset, as: :prescription),
       editing_items: editing_items
     )}
  end

  def handle_event("remove-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    changeset = socket.assigns.header_form.source
    items = List.delete_at(items_value(socket.assigns.header_form), index)
    changeset = Ecto.Changeset.put_assoc(changeset, :items, items)

    editing_items =
      socket.assigns.editing_items
      |> Enum.reject(&(&1 == index))
      |> Enum.map(fn i -> if i > index, do: i - 1, else: i end)
      |> MapSet.new()

    {:noreply,
     assign(socket,
       header_form: to_form(changeset, as: :prescription),
       editing_items: editing_items
     )}
  end

  def handle_event("edit-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    editing_items = MapSet.put(socket.assigns.editing_items, index)
    {:noreply, assign(socket, :editing_items, editing_items)}
  end

  def handle_event("collapse-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    editing_items = MapSet.delete(socket.assigns.editing_items, index)
    {:noreply, assign(socket, :editing_items, editing_items)}
  end

  def handle_event("save", params, socket) do
    %{"prescription" => header_attrs} = params

    site_id =
      case header_attrs["site_id"] do
        blank when blank in [nil, ""] -> SiteScoping.default_site_id(socket.assigns.current_scope)
        site_id -> site_id
      end

    cond do
      is_nil(site_id) ->
        {:noreply, put_flash(socket, :error, "Site is required.")}

      header_attrs["items"] in [nil, %{}] ->
        changeset =
          %Prescription{}
          |> Prescription.changeset(header_attrs)
          |> Ecto.Changeset.add_error(:items, "must have at least one item")
          |> Map.put(:action, :insert)

        handle_save_result({:error, changeset}, socket)

      true ->
        socket.assigns.patient_mode
        |> save_prescription(params, site_id, socket)
        |> handle_save_result(socket)
    end
  end

  defp quick_sale_items_from_params(%{"items" => items}) when is_map(items) do
    items
    |> Enum.sort_by(fn {index, _attrs} -> String.to_integer(index) end)
    |> Enum.map(fn {_index, attrs} -> attrs end)
  end

  defp quick_sale_items_from_params(_params),
    do: [%{"product_id" => "", "quantity" => "1", "scanned_gtin" => ""}]

  defp complete_quick_sale(socket, params) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    user_id = scope.user.id

    site_id =
      case params["site_id"] do
        blank when blank in [nil, ""] -> socket.assigns.quick_sale_site_id
        site_id -> String.to_integer(site_id)
      end

    items = quick_sale_items_from_params(params)

    cond do
      is_nil(site_id) ->
        {:noreply, put_flash(socket, :error, "Site is required.")}

      Enum.all?(items, &(&1["product_id"] in [nil, ""])) ->
        {:noreply, put_flash(socket, :error, "Add at least one item.")}

      not ThamaniDawa.PaymentMethods.valid?(params["payment_type"]) ->
        {:noreply,
         socket
         |> assign(:quick_sale_items, items)
         |> assign(:quick_sale_patient_id, params["patient_id"] || "")
         |> assign(:quick_sale_payment_type, params["payment_type"] || "")
         |> assign(:quick_sale_errors, %{payment_type: "Select a payment method."})}

      true ->
        attrs = quick_sale_attrs(params, items)
        result = Prescriptions.create_quick_sale(organization_id, site_id, user_id, attrs)

        handle_quick_sale_result(socket, items, result)
    end
  end

  defp quick_sale_attrs(params, items) do
    %{
      "patient_id" => params["patient_id"],
      "payment_type" => params["payment_type"],
      "items" =>
        Enum.map(items, fn item ->
          %{
            "product_id" => item["product_id"],
            "quantity_prescribed" => item["quantity"],
            "scanned_gtin" => item["scanned_gtin"]
          }
        end)
    }
  end

  defp handle_quick_sale_result(socket, _items, {:ok, prescription}) do
    {:noreply,
     socket
     |> put_flash(:info, "Sale completed.")
     |> push_navigate(to: ~p"/pharmacy/prescriptions/#{prescription.id}/receipt")}
  end

  defp handle_quick_sale_result(socket, items, {:error, {index, reason}}) do
    message = quick_sale_error_message(index, reason, items, socket.assigns.products)
    {:noreply, socket |> assign(:quick_sale_items, items) |> put_flash(:error, message)}
  end

  defp handle_quick_sale_result(socket, items, {:error, %Ecto.Changeset{} = changeset}) do
    message = "Couldn't complete the sale: #{changeset_error_summary(changeset)}"
    {:noreply, socket |> assign(:quick_sale_items, items) |> put_flash(:error, message)}
  end

  defp handle_quick_sale_result(socket, items, {:error, _reason}) do
    {:noreply,
     socket
     |> assign(:quick_sale_items, items)
     |> put_flash(:error, "Couldn't complete the sale.")}
  end

  defp maybe_reload_quick_sale_products(socket, nil), do: socket
  defp maybe_reload_quick_sale_products(socket, ""), do: socket

  defp maybe_reload_quick_sale_products(socket, site_id) when is_binary(site_id) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = String.to_integer(site_id)

    socket
    |> assign(:quick_sale_site_id, site_id)
    |> assign(
      :products,
      ThamaniDawa.Products.list_active_products_with_stock_for_site(organization_id, site_id)
    )
  end

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> flatten_changeset_errors()
    |> Enum.join("; ")
  end

  defp flatten_changeset_errors(errors) when is_map(errors) do
    Enum.flat_map(errors, fn
      {field, messages} when is_list(messages) ->
        case Enum.split_with(messages, &is_binary/1) do
          {[], nested} ->
            flatten_nested_errors(field, nested)

          {strings, []} ->
            ["#{field} #{Enum.join(strings, ", ")}"]

          {strings, nested} ->
            ["#{field} #{Enum.join(strings, ", ")}" | flatten_nested_errors(field, nested)]
        end
    end)
  end

  defp flatten_nested_errors(field, nested) do
    nested
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      entry
      |> flatten_changeset_errors()
      |> Enum.map(&"#{field} ##{index + 1}: #{&1}")
    end)
  end

  defp quick_sale_error_message(index, reason, items, products) do
    product_name =
      case items
           |> Enum.at(index)
           |> then(&(&1 && quick_sale_product(products, &1["product_id"]))) do
        nil -> "Line #{index + 1}"
        product -> product.generic_name
      end

    case reason do
      :out_of_stock -> "#{product_name}: not enough stock available."
      :gtin_mismatch -> "#{product_name}: scanned barcode doesn't match this product."
      :invalid_gtin -> "#{product_name}: invalid barcode scanned."
      :over_dispensed -> "#{product_name}: quantity exceeds what was prescribed."
      _ -> "#{product_name}: couldn't complete the sale."
    end
  end

  defp quick_sale_product(products, product_id) do
    case Integer.parse(to_string(product_id)) do
      {id, ""} -> Enum.find(products, &(&1.id == id))
      _ -> nil
    end
  end

  defp quick_sale_line_total(products, item) do
    with %{} = product <- quick_sale_product(products, item["product_id"]),
         {quantity, ""} <- Integer.parse(to_string(item["quantity"] || "")) do
      Decimal.mult(product.price, quantity)
    else
      _ -> Decimal.new(0)
    end
  end

  defp quick_sale_total(products, items) do
    Enum.reduce(items, Decimal.new(0), fn item, acc ->
      Decimal.add(acc, quick_sale_line_total(products, item))
    end)
  end

  defp maybe_reload_products(socket, nil), do: socket
  defp maybe_reload_products(socket, ""), do: socket

  defp maybe_reload_products(socket, site_id) when is_binary(site_id) do
    organization_id = socket.assigns.current_scope.organization_id

    assign(
      socket,
      :products,
      ThamaniDawa.Products.list_active_products_with_stock_for_site(
        organization_id,
        String.to_integer(site_id)
      )
    )
  end

  defp save_prescription(:new, params, site_id, socket) do
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

  defp save_prescription(:existing, params, site_id, socket) do
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

  defp save_prescription(:walk_in, params, site_id, socket) do
    %{"prescription" => header_attrs} = params
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    Prescriptions.create_prescription_without_patient(
      organization_id,
      site_id,
      user_id,
      header_attrs
    )
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
    page = socket.assigns.page

    page_result = Prescriptions.list_prescriptions_paginated(organization_id, page)
    prescriptions = page_result.entries

    filtered =
      prescriptions
      |> SiteScoping.for_current_site(socket.assigns.current_scope)
      |> filter_by_search(socket.assigns.search)
      |> filter_by_status(socket.assigns.filters.status)
      |> filter_by_payment_type(socket.assigns.filters.payment_type)
      |> filter_by_paid(socket.assigns.filters.paid)

    socket
    |> assign(:prescriptions, filtered)
    |> assign(:page_info, page_result)
  end

  defp filter_by_search(prescriptions, ""), do: prescriptions

  defp filter_by_search(prescriptions, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(prescriptions, fn prescription ->
      [prescription.patient_name, prescription.patient_phone]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_status(prescriptions, ""), do: prescriptions

  defp filter_by_status(prescriptions, status) do
    status = String.to_existing_atom(status)
    Enum.filter(prescriptions, &(&1.status == status))
  end

  defp filter_by_payment_type(prescriptions, ""), do: prescriptions

  defp filter_by_payment_type(prescriptions, payment_type),
    do: Enum.filter(prescriptions, &(&1.payment_type == payment_type))

  defp filter_by_paid(prescriptions, ""), do: prescriptions
  defp filter_by_paid(prescriptions, "true"), do: Enum.filter(prescriptions, & &1.has_paid)
  defp filter_by_paid(prescriptions, "false"), do: Enum.filter(prescriptions, &(!&1.has_paid))

  defp active_filter_count(filters) do
    Enum.count([filters.status != "", filters.payment_type != "", filters.paid != ""], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"},
      filters.payment_type != "" &&
        %{label: "Payment: #{filters.payment_type}", field: "payment_type"},
      filters.paid == "true" && %{label: "Paid", field: "paid"},
      filters.paid == "false" && %{label: "Unpaid", field: "paid"}
    ]
    |> Enum.filter(& &1)
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/prescriptions"
    >
      <.header icon="hero-document-text">
        Prescriptions
        <:subtitle>Search, filter, and manage prescriptions at your site.</:subtitle>
        <:actions>
          <.button variant="ghost" patch={~p"/pharmacy/prescriptions/quick-sale"}>
            + Quick sale
          </.button>
          <.button
            id="prescription-new-button"
            variant="primary"
            patch={~p"/pharmacy/prescriptions/new"}
          >
            <.icon name="hero-plus" class="size-4" /> New prescription
          </.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by patient name or phone"
            />
          </form>

          <.filter_drawer
            id="prescriptions-filters"
            title="Filter prescriptions"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={Enum.map(Prescription.statuses(), &{Phoenix.Naming.humanize(&1), &1})}
                prompt="All statuses"
              />
            </:group>
            <:group label="Payment">
              <.input
                type="select"
                name="filters[payment_type]"
                value={@filters.payment_type}
                options={ThamaniDawa.PaymentMethods.all()}
                prompt="All payment methods"
              />
              <.input
                type="select"
                name="filters[paid]"
                value={@filters.paid}
                options={[{"Paid", "true"}, {"Unpaid", "false"}]}
                prompt="Paid or unpaid"
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
        id="prescription-modal"
        show
        class="max-w-4xl"
        on_cancel={JS.patch(~p"/pharmacy/prescriptions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">New prescription</h2>

        <.form
          for={@header_form}
          id="prescription-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-5"
        >
          <%!-- Step 1: Patient information --%>
          <section class="rounded-xl ff-surface-card">
            <div class="flex flex-col gap-3 rounded-t-xl border-b border-thamani-stone bg-thamani-canvas px-4 py-3 sm:flex-row sm:items-center sm:justify-between">
              <h3 class="text-base font-semibold text-thamani-forest">1. Patient</h3>
              <.tab_group>
                <:tab
                  id="existing-patient-mode"
                  active={@patient_mode == :existing}
                  phx_click="toggle_patient_mode"
                  phx_value_tab="existing"
                >
                  Existing Patient
                </:tab>
                <:tab
                  id="new-patient-mode"
                  active={@patient_mode == :new}
                  phx_click="toggle_patient_mode"
                  phx_value_tab="new"
                >
                  New Patient
                </:tab>
                <:tab
                  id="walk-in-patient-mode"
                  active={@patient_mode == :walk_in}
                  phx_click="toggle_patient_mode"
                  phx_value_tab="walk_in"
                >
                  Walk-in (no patient)
                </:tab>
              </.tab_group>
            </div>
            <div class="p-4 sm:p-5">
              <div :if={@patient_mode == :existing}>
                <.input
                  field={@header_form[:patient_id]}
                  type="select"
                  label="Search and select patient"
                  options={Enum.map(@patients, &{patient_label(&1), &1.id})}
                  prompt="Select patient..."
                />
              </div>

              <div :if={@patient_mode == :new} class="grid grid-cols-1 md:grid-cols-2 gap-4">
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

              <p :if={@patient_mode == :walk_in} class="text-sm text-thamani-pewter italic">
                No patient will be recorded for this prescription.
              </p>
            </div>
          </section>

          <%!-- Step 2: Prescription items --%>
          <section class="rounded-xl ff-surface-card">
            <div class="flex items-center justify-between gap-3 rounded-t-xl border-b border-thamani-stone bg-thamani-canvas px-4 py-3">
              <h3 class="text-base font-semibold text-thamani-forest">2. Medication</h3>
              <.button id="add-prescription-item" type="button" phx-click="add-item" variant="ghost">
                + Add Item
              </.button>
            </div>
            <div class="space-y-4 p-4 sm:p-5">
              <.inputs_for :let={item_form} field={@header_form[:items]}>
                <% is_editing = MapSet.member?(@editing_items, item_form.index) %>
                <div class={[
                  "rounded-xl border p-4 transition-colors",
                  if(is_editing,
                    do: "border-thamani-accent/50 bg-thamani-canvas shadow-sm",
                    else: "border-thamani-stone bg-thamani-snow"
                  )
                ]}>
                  <div class={"flex justify-between items-center #{if is_editing, do: "mb-4"}"}>
                    <div class="flex items-center gap-2">
                      <span class="flex size-6 shrink-0 items-center justify-center rounded-full bg-thamani-lime text-xs font-semibold text-thamani-forest">
                        {item_form.index + 1}
                      </span>
                      <h4 class="font-medium text-sm text-thamani-forest">
                        Item {item_form.index + 1}
                      </h4>
                    </div>
                    <div class="flex items-center gap-2">
                      <%= if is_editing do %>
                        <% can_collapse =
                          not is_nil(Ecto.Changeset.get_field(item_form.source, :product_id)) and
                            not is_nil(
                              Ecto.Changeset.get_field(item_form.source, :quantity_prescribed)
                            ) %>
                        <.button
                          type="button"
                          phx-click="collapse-item"
                          phx-value-index={item_form.index}
                          variant="primary"
                          disabled={not can_collapse}
                        >
                          <.icon name="hero-check" class="w-4 h-4" /> Done
                        </.button>
                      <% else %>
                        <.button
                          type="button"
                          phx-click="edit-item"
                          phx-value-index={item_form.index}
                          variant="ghost-edit"
                        >
                          <.icon name="hero-pencil" class="w-4 h-4" /> Edit
                        </.button>
                      <% end %>
                      <.button
                        :if={
                          is_list(@header_form[:items].value) and
                            length(@header_form[:items].value) > 1
                        }
                        type="button"
                        phx-click="remove-item"
                        phx-value-index={item_form.index}
                        variant="ghost-delete"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" /> Remove
                      </.button>
                    </div>
                  </div>

                  <%= if is_editing do %>
                    <% selected_product_id = Ecto.Changeset.get_field(item_form.source, :product_id) %>
                    <% selected_product = Enum.find(@products, &(&1.id == selected_product_id)) %>
                    <% qty_value = Ecto.Changeset.get_field(item_form.source, :quantity_prescribed) %>
                    <% over_stock? =
                      selected_product && qty_value && qty_value > selected_product.stock %>
                    <div class="grid grid-cols-1 gap-4 md:grid-cols-6">
                      <div class="md:col-span-3">
                        <.input
                          field={item_form[:product_id]}
                          type="select"
                          label="Product"
                          options={
                            Enum.map(
                              @products,
                              &{"#{&1.generic_name}#{if &1.brand_name, do: " (" <> &1.brand_name <> ")"} — KES #{&1.price} — #{&1.stock} in stock",
                               &1.id}
                            )
                          }
                          prompt="Select product..."
                          required
                        />
                        <p
                          :if={selected_product}
                          class="mt-1.5 flex items-center gap-3 text-xs font-medium text-thamani-pewter"
                        >
                          <span class="flex items-center gap-1">
                            <.icon name="hero-cube" class="size-3.5" />
                            {selected_product.stock} unit{if selected_product.stock != 1, do: "s"} in stock
                          </span>
                          <span class="flex items-center gap-1">
                            <.icon name="hero-banknotes" class="size-3.5" />
                            KES {selected_product.price} per unit
                          </span>
                        </p>
                      </div>
                      <div class="md:col-span-1">
                        <.input
                          field={item_form[:quantity_prescribed]}
                          type="number"
                          label="Qty"
                          required
                          min="1"
                        />
                        <p
                          :if={over_stock?}
                          class="mt-1.5 flex items-center gap-1 text-xs font-medium text-thamani-error"
                        >
                          <.icon name="hero-exclamation-triangle" class="size-3.5" />
                          Exceeds stock ({selected_product.stock})
                        </p>
                      </div>
                      <div class="md:col-span-1">
                        <.input
                          field={item_form[:frequency]}
                          type="text"
                          label="Frequency"
                          placeholder="e.g. 1x3"
                        />
                      </div>
                      <div class="md:col-span-1">
                        <.input
                          field={item_form[:duration_in_days]}
                          type="number"
                          label="Days"
                          min="1"
                        />
                      </div>
                      <div class="md:col-span-6 md:grid md:grid-cols-6 md:gap-4">
                        <div class="md:col-span-1">
                          <.input
                            field={item_form[:route_of_administration]}
                            type="text"
                            label="Route"
                            placeholder="e.g. Oral"
                          />
                        </div>
                        <div class="md:col-span-5">
                          <.input
                            field={item_form[:dosage_instructions]}
                            type="text"
                            label="Instructions"
                            placeholder="e.g. Take after meals"
                          />
                        </div>
                      </div>
                    </div>
                  <% else %>
                    <% product_id = Ecto.Changeset.get_field(item_form.source, :product_id) %>
                    <% product = Enum.find(@products, &(&1.id == product_id)) %>
                    <% qty = Ecto.Changeset.get_field(item_form.source, :quantity_prescribed) %>
                    <% freq = Ecto.Changeset.get_field(item_form.source, :frequency) %>
                    <% days = Ecto.Changeset.get_field(item_form.source, :duration_in_days) %>

                    <div class="hidden">
                      <.input field={item_form[:product_id]} type="hidden" />
                      <.input field={item_form[:quantity_prescribed]} type="hidden" />
                      <.input field={item_form[:frequency]} type="hidden" />
                      <.input field={item_form[:duration_in_days]} type="hidden" />
                      <.input field={item_form[:route_of_administration]} type="hidden" />
                      <.input field={item_form[:dosage_instructions]} type="hidden" />
                    </div>

                    <div class="mt-2 flex flex-col sm:flex-row gap-4 justify-between items-start sm:items-center">
                      <div class="flex-1">
                        <div class="font-semibold text-base-content">
                          <%= if product do %>
                            {product.generic_name} {if product.brand_name,
                              do: "(#{product.brand_name})"}
                          <% else %>
                            <span class="italic text-base-content/50">No product selected</span>
                          <% end %>
                        </div>
                        <div class="text-sm text-base-content/70 mt-1">
                          Qty: {qty || "-"} {if freq && freq != "", do: " | #{freq}"} {if days,
                            do: " | #{days} days"}
                        </div>
                      </div>
                      <div
                        :if={product}
                        class="flex items-center gap-3 text-xs font-medium text-thamani-pewter"
                      >
                        <span class="flex items-center gap-1">
                          <.icon name="hero-cube" class="size-3.5" />
                          {product.stock} in stock
                        </span>
                        <span class="flex items-center gap-1">
                          <.icon name="hero-banknotes" class="size-3.5" /> KES {product.price}
                        </span>
                      </div>
                    </div>
                  <% end %>
                </div>
              </.inputs_for>
              <div
                :if={
                  not is_list(@header_form[:items].value) or Enum.empty?(@header_form[:items].value)
                }
                class="text-center text-base-content/50 py-4"
              >
                No items added. Click "+ Add Item" to prescribe medicine.
              </div>
              <p
                :for={msg <- Enum.map(@header_form[:items].errors, &translate_error/1)}
                class="mt-1.5 flex gap-2 items-center text-sm text-error"
              >
                <.icon name="hero-exclamation-circle" class="size-5" />{msg}
              </p>
            </div>
          </section>

          <%!-- Step 3: Prescription details --%>
          <section class="overflow-hidden rounded-xl ff-surface-card">
            <div class="border-b border-thamani-stone bg-thamani-canvas px-4 py-3">
              <h3 class="text-base font-semibold text-thamani-forest">3. Details and payment</h3>
            </div>
            <div class="space-y-4 p-4 sm:p-5">
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

              <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
                <p class="text-sm font-medium text-thamani-forest">Referral from another facility</p>
                <.input
                  field={@header_form[:is_external]}
                  type="checkbox"
                  label=""
                  class="size-5 rounded accent-thamani-forest cursor-pointer"
                />
              </div>

              <.input
                :if={Phoenix.HTML.Form.normalize_value("checkbox", @header_form[:is_external].value)}
                field={@header_form[:referring_doctor]}
                label="Referring doctor"
                required
              />

              <.input
                field={@header_form[:payment_type]}
                type="select"
                label="Payment Method"
                options={ThamaniDawa.PaymentMethods.all()}
                prompt="Select payment method"
                required
              />

              <.input field={@header_form[:notes]} type="textarea" label="Additional Notes" />
            </div>
          </section>

          <.button
            type="submit"
            variant="primary"
            phx-disable-with="Creating prescription…"
            class="w-full"
          >
            Create Prescription
          </.button>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :quick_sale}
        id="quick-sale-modal"
        show
        class="max-w-5xl"
        on_cancel={JS.patch(~p"/pharmacy/prescriptions")}
      >
        <h2 class="mb-1 text-2xl font-medium tracking-tight text-thamani-forest">Quick sale</h2>
        <p class="mb-5 text-sm leading-6 text-thamani-pewter">
          Pick product(s), scan to confirm, and take payment — stock is dispensed and the sale is
          marked paid immediately.
        </p>

        <.form
          for={%{}}
          id="quick-sale-form"
          phx-change="quick_sale_validate"
          phx-submit="complete_quick_sale"
          class="space-y-4"
        >
          <.input
            :if={not @site_locked}
            type="select"
            name="site_id"
            label="Site"
            value={@quick_sale_site_id}
            options={Enum.map(@sites, &{&1.name, &1.id})}
            prompt="Choose a site"
            required
          />

          <.input
            type="select"
            name="patient_id"
            label="Patient"
            value={@quick_sale_patient_id}
            options={Enum.map(@patients, &{patient_label(&1), &1.id})}
            prompt="Walk-in (no patient)"
          />

          <section
            id="quick-sale-items"
            class="relative rounded-2xl border border-thamani-stone bg-thamani-snow"
          >
            <div class="flex items-center justify-between gap-4 rounded-t-2xl border-b border-thamani-stone bg-thamani-canvas/70 px-4 py-3 sm:px-5">
              <div>
                <h3 class="text-sm font-semibold text-thamani-forest">Sale items</h3>
                <p class="mt-0.5 text-xs text-thamani-pewter">
                  Select a product and confirm its barcode.
                </p>
              </div>
              <.button
                type="button"
                variant="ghost"
                phx-click="add_quick_sale_item"
                id="btn-add-quick-sale-item"
                class="shrink-0 px-3 py-2 text-sm"
              >
                <.icon name="hero-plus" class="size-4" /> Add item
              </.button>
            </div>

            <div class="divide-y divide-thamani-stone">
              <div
                :for={{item, index} <- Enum.with_index(@quick_sale_items)}
                id={"quick-sale-item-#{index}"}
                class="grid grid-cols-1 gap-3 p-4 last:rounded-b-2xl sm:grid-cols-2 sm:p-5 lg:grid-cols-[minmax(0,1.7fr)_7rem_minmax(10rem,1.1fr)_auto_auto] lg:items-start"
              >
                <.input
                  type="select"
                  name={"items[#{index}][product_id]"}
                  label="Product"
                  value={item["product_id"]}
                  options={
                    Enum.map(
                      @products,
                      &{"#{&1.generic_name}#{if &1.brand_name, do: " (" <> &1.brand_name <> ")"} — KES #{&1.price} — #{&1.stock} in stock",
                       &1.id}
                    )
                  }
                  prompt="Select product..."
                />
                <.input
                  type="number"
                  name={"items[#{index}][quantity]"}
                  label="Qty"
                  value={item["quantity"]}
                  min="1"
                />
                <.input
                  type="text"
                  name={"items[#{index}][scanned_gtin]"}
                  label="Scan barcode"
                  value={item["scanned_gtin"]}
                  placeholder="Scan or type GTIN"
                  autocomplete="off"
                />
                <div class="flex h-[46px] min-w-24 flex-col justify-center text-left lg:mt-[25px] lg:text-right">
                  <span class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Line total</span>
                  <span class="mt-0.5 text-sm font-semibold whitespace-nowrap text-thamani-forest">
                    KES {quick_sale_line_total(@products, item)}
                  </span>
                </div>
                <div class="flex h-[46px] items-center justify-end sm:col-span-2 lg:col-span-1 lg:mt-[25px]">
                  <.button
                    type="button"
                    variant="ghost-delete"
                    phx-click="remove_quick_sale_item"
                    phx-value-index={index}
                    aria-label={"Remove item #{index + 1}"}
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </.button>
                </div>
              </div>
            </div>
          </section>

          <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3">
            <span class="text-sm font-medium text-thamani-forest">Total</span>
            <span class="text-lg font-semibold text-thamani-forest">
              KES {quick_sale_total(@products, @quick_sale_items)}
            </span>
          </div>

          <.input
            type="select"
            name="payment_type"
            label="Payment Method"
            value={@quick_sale_payment_type}
            options={ThamaniDawa.PaymentMethods.all()}
            prompt="Select payment method"
            errors={Map.get(@quick_sale_errors, :payment_type, []) |> List.wrap()}
            required
          />

          <.button
            type="submit"
            variant="primary"
            phx-disable-with="Completing sale…"
            class="w-full"
          >
            Complete sale
          </.button>
        </.form>
      </.modal>

      <.table
        id="prescriptions"
        rows={@prescriptions}
        row_click={&JS.navigate(~p"/pharmacy/prescriptions/#{&1.id}")}
      >
        <:col :let={prescription} label="ID">#{prescription.id}</:col>
        <:col :let={prescription} label="Patient">
          <div class="font-semibold">{prescription.patient_name || "Walk-in"}</div>
          <div class="text-xs text-base-content/70">{prescription.patient_phone}</div>
        </:col>
        <:col :let={prescription} label="Status">
          <.status_badge status={prescription.status} />
        </:col>
        <:col :let={prescription} label="Items">{prescription.items_count}</:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Prescriber">{prescription.referring_doctor}</:col>
        <:col :let={prescription} label="Created">
          {Calendar.strftime(prescription.inserted_at, "%b %d, %H:%M")}
        </:col>
        <:empty_state>
          <.blank_state
            icon="hero-clipboard-document-list"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No prescriptions match your search or filters",
                else: "No prescriptions yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Prescriptions created at your site will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={~p"/pharmacy/prescriptions"} />
    </Layouts.pharmacy_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.national_id || patient.phone || "Unknown ID"
    "#{patient.full_name} (#{id})"
  end

  defp items_value(form) do
    case form[:items].value do
      items when is_list(items) -> items
      _ -> []
    end
  end
end
