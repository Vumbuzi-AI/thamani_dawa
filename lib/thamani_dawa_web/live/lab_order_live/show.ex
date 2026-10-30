defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabOrders.LabSpecimen
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PaymentMethods
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.LabReportComponent
  alias ThamaniDawaWeb.SpecimenLabelComponent

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:lab_tests, LabTests.list_active_lab_tests(organization_id))
      |> assign(:detail_tab, "samples")
      |> assign(:editing_result, nil)
      |> assign(:editing_lab_test, nil)
      |> assign(:consumable_search, "")
      |> assign(:selected_consumable_product_id, nil)
      |> assign(:payment_form, nil)
      |> assign(:printing_specimen, nil)
      |> load_lab_order(id)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit_result, %{"result_id" => result_id}) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, String.to_integer(result_id))
    lab_test = LabTests.get_lab_test!(organization_id, result.lab_test_id)

    socket
    |> reset_modals()
    |> assign(:editing_result, result)
    |> assign(:editing_lab_test, lab_test)
  end

  defp apply_action(socket, :print_specimen_label, %{"specimen_id" => specimen_id}) do
    specimen_id = String.to_integer(specimen_id)
    specimen = Enum.find(socket.assigns.specimens, &(&1.id == specimen_id))

    socket
    |> reset_modals()
    |> assign(:printing_specimen, specimen)
  end

  defp apply_action(socket, :new_payment, _params) do
    lab_order = socket.assigns.lab_order

    changeset =
      Payment.changeset(%Payment{}, %{
        "lab_order_id" => lab_order.id,
        "amount" => lab_order.total_amount
      })

    socket |> reset_modals() |> assign(:payment_form, to_form(changeset, as: :payment))
  end

  defp apply_action(socket, _action, _params), do: reset_modals(socket)

  defp reset_modals(socket) do
    socket
    |> assign(:editing_result, nil)
    |> assign(:editing_lab_test, nil)
    |> assign(:consumable_search, "")
    |> assign(:selected_consumable_product_id, nil)
    |> assign(:payment_form, nil)
    |> assign(:printing_specimen, nil)
  end

  defp load_lab_order(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = LabOrders.get_lab_order!(organization_id, id)
    visit = PatientVisits.get_patient_visit!(organization_id, lab_order.patient_visit_id)
    patient = Patients.get_patient!(organization_id, visit.patient_id)
    results = LabOrders.list_lab_order_results_for_order(organization_id, lab_order.id)

    amendments =
      Map.new(results, &{&1.id, LabOrders.list_amendments_for_result(organization_id, &1.id)})

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:site, Sites.get_site!(organization_id, lab_order.site_id))
    |> assign(:results, results)
    |> assign(:specimens, LabOrders.list_specimens_for_order(organization_id, lab_order.id))
    |> assign(
      :collectable_results,
      LabOrders.list_collectable_results(organization_id, lab_order.id)
    )
    |> assign(
      :consumable_usages,
      LabOrders.list_consumable_usages_for_order(organization_id, lab_order.id)
    )
    |> assign(:amendments, amendments)
    |> assign(
      :active_batches,
      Batches.list_active_lab_consumable_batches_for_site(organization_id, lab_order.site_id)
    )
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket)
      when tab in ~w(samples results consumables) do
    {:noreply, assign(socket, :detail_tab, tab)}
  end

  def handle_event("search_consumable_products", %{"product_query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:consumable_search, query)
     |> assign(:selected_consumable_product_id, nil)}
  end

  def handle_event("select_consumable_product", %{"product_id" => product_id}, socket) do
    case Integer.parse(product_id) do
      {product_id, ""} ->
        available_product_ids =
          socket.assigns.active_batches
          |> Enum.map(& &1.product_id)
          |> Enum.uniq()

        if product_id in available_product_ids do
          {:noreply,
           socket
           |> assign(:selected_consumable_product_id, product_id)
           |> assign(:consumable_search, "")}
        else
          {:noreply, put_flash(socket, :error, "Choose a product with stock at this site.")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a valid product.")}
    end
  end

  def handle_event("change_consumable_product", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_consumable_product_id, nil)
     |> assign(:consumable_search, "")}
  end

  def handle_event("collect_specimen", params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id
    lab_order_id = socket.assigns.lab_order.id

    result_ids =
      params
      |> Map.get("result_ids", [])
      |> List.wrap()
      |> Enum.map(&String.to_integer/1)

    case LabOrders.collect_specimen(organization_id, lab_order_id, result_ids, user_id, params) do
      {:ok, _specimen} ->
        {:noreply,
         socket
         |> put_flash(:info, "Specimen collected.")
         |> load_lab_order(lab_order_id)
         |> assign(:detail_tab, "samples")
         |> push_patch(to: ~p"/lab/orders/#{lab_order_id}")}

      {:error, :no_results_selected} ->
        {:noreply, put_flash(socket, :error, "Select at least one test for this specimen.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not collect the specimen.")}
    end
  end

  def handle_event(
        "record_consumable",
        %{"batch_id" => batch_id, "product_id" => product_id, "usage_quantity" => qty} = params,
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id
    lab_order_id = socket.assigns.lab_order.id
    result_id = parse_optional_int(params["lab_order_result_id"])

    with {batch_id, ""} <- Integer.parse(batch_id),
         {product_id, ""} <- Integer.parse(product_id),
         {qty, ""} <- Integer.parse(qty),
         true <- qty > 0,
         true <-
           batch_available_for_product?(socket.assigns.active_batches, batch_id, product_id),
         {:ok, _usage} <-
           LabOrders.record_consumable_usage(organization_id, batch_id, user_id, qty,
             lab_order_id: lab_order_id,
             lab_order_result_id: result_id
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Consumable recorded.")
       |> load_lab_order(lab_order_id)
       |> assign(:detail_tab, "consumables")
       |> push_patch(to: ~p"/lab/orders/#{lab_order_id}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a product, batch, and valid quantity.")}
    end
  end

  def handle_event("validate_payment", %{"payment" => attrs}, socket) do
    lab_order = socket.assigns.lab_order

    changeset =
      attrs
      |> Map.put("lab_order_id", lab_order.id)
      |> then(&Payment.changeset(%Payment{}, &1))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, payment_form: to_form(changeset, as: :payment))}
  end

  def handle_event("save_payment", %{"payment" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = socket.assigns.lab_order

    attrs = Map.put(attrs, "lab_order_id", lab_order.id)

    with {:ok, payment} <- Payments.create_payment(organization_id, attrs),
         {:ok, _completed} <- Payments.complete_payment(payment) do
      {:noreply,
       socket
       |> put_flash(:info, "Payment recorded and completed.")
       |> push_patch(to: ~p"/lab/orders/#{lab_order.id}")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, payment_form: to_form(changeset, as: :payment))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Payment saved but could not be completed.")}
    end
  end

  def handle_event("add_result", %{"lab_test_id" => lab_test_id} = attrs, socket)
      when lab_test_id != "" do
    organization_id = socket.assigns.current_scope.organization_id

    case LabOrders.create_lab_order_result(organization_id, socket.assigns.lab_order.id, attrs) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> load_lab_order(socket.assigns.lab_order.id)
         |> assign(:detail_tab, "results")
         |> push_patch(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_lab_test?(changeset) do
          {:noreply, put_flash(socket, :error, "This test is already on the order.")}
        else
          {:noreply,
           put_flash(
             socket,
             :error,
             "Couldn't add that test. Check the test selection and try again."
           )}
        end
    end
  end

  def handle_event("add_result", _attrs, socket) do
    {:noreply, put_flash(socket, :error, "Choose a test to add.")}
  end

  def handle_event("save_result", %{"values" => raw_values} = params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    performer_id = socket.assigns.current_scope.user.id
    reason = Map.get(params, "amendment_reason")

    case LabOrders.record_result(
           organization_id,
           socket.assigns.editing_result.id,
           performer_id,
           raw_values,
           reason: reason
         ) do
      {:ok, _recorded_result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> load_lab_order(socket.assigns.lab_order.id)
         |> assign(:detail_tab, "results")
         |> push_patch(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, :reason_required} ->
        {:noreply,
         put_flash(socket, :error, "A reason is required to amend an already-completed result.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp duplicate_lab_test?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, options}} ->
      Keyword.get(options, :constraint) == :unique
    end)
  end

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_optional_int(_), do: nil

  defp test_name(%{lab_test: %{name: name}}), do: name
  defp test_name(_), do: "(unknown test)"

  defp user_name(%{name: name}), do: name
  defp user_name(_), do: "—"

  defp result_unit(%{lab_test: %{field_definitions: defs}}, key) when is_map(defs),
    do: get_in(defs, [key, "unit"]) || ""

  defp result_unit(_result, _key), do: ""

  defp current_value(result, key), do: get_in(result.results, [key, "value"])

  defp option_description(option) when is_binary(option) do
    case String.downcase(option) do
      "negative" -> "Target not detected"
      "positive" -> "Target detected"
      _ -> nil
    end
  end

  defp option_description(_option), do: nil

  defp checkbox_checked?(value, opt) when is_list(value), do: opt in value

  defp checkbox_checked?(value, opt) when is_binary(value) do
    selected = value |> String.split(",") |> Enum.map(&String.trim/1)
    opt in selected
  end

  defp checkbox_checked?(_value, _opt), do: false

  defp single_checkbox_checked?(value), do: value in [true, "true", "on", 1, "1"]

  defp get_field_definition(%{lab_test: %{field_definitions: defs}}, key) when is_map(defs),
    do: Map.get(defs, key, %{})

  defp get_field_definition(_result, _key), do: %{}

  attr :key, :string, required: true
  attr :value, :any, required: true
  attr :unit, :string, default: ""
  attr :field_definition, :map, default: %{}

  defp render_result_preview(assigns) do
    field_type = Map.get(assigns.field_definition || %{}, "type")

    items =
      cond do
        is_list(assigns.value) ->
          assigns.value

        is_binary(assigns.value) and field_type == "checkbox" and
            String.contains?(assigns.value, ",") ->
          assigns.value |> String.split(",") |> Enum.map(&String.trim/1)

        true ->
          nil
      end

    assigns = assign(assigns, field_type: field_type, items: items)

    ~H"""
    <%= cond do %>
      <% @items != nil -> %>
        <div class="flex flex-wrap gap-1.5 mt-1">
          <span
            :for={item <- @items}
            class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-thamani-accent/10 text-thamani-forest border border-thamani-accent/20"
          >
            <.icon name="hero-check" class="w-3 h-3" />
            {item}
          </span>
          <span :if={@items == []} class="text-xs text-thamani-pewter">None selected</span>
        </div>
      <% @field_type == "checkbox" or @value in [true, false, "true", "false"] -> %>
        <% is_checked = single_checkbox_checked?(@value) %>
        <div class="mt-1">
          <%= if is_checked do %>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-emerald-50 text-emerald-700 border border-emerald-200">
              <.icon name="hero-check-circle" class="w-3.5 h-3.5" /> Positive / Present
            </span>
          <% else %>
            <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-stone-100 text-stone-600 border border-stone-200">
              <.icon name="hero-x-circle" class="w-3.5 h-3.5 text-stone-400" /> Negative / Not present
            </span>
          <% end %>
        </div>
      <% true -> %>
        <div class="text-sm font-medium" style="color: #1F2430;">
          {to_string(@value)}
          <span :if={@unit != ""} class="font-normal" style="color: #9AA3B5;">{@unit}</span>
        </div>
    <% end %>
    """
  end

  defp input_type(%{"type" => "select"}), do: "select"
  defp input_type(%{"type" => "number"}), do: "number"
  defp input_type(%{"type" => "checkbox"}), do: "checkbox"
  defp input_type(_), do: "text"

  defp field_options(%{"type" => "select", "options" => options}) when is_list(options),
    do: options

  defp field_options(_), do: nil

  defp field_label(key, %{"unit" => unit}) when is_binary(unit) and unit != "",
    do: "#{Phoenix.Naming.humanize(key)} (#{unit})"

  defp field_label(key, _definition), do: Phoenix.Naming.humanize(key)

  defp total_price(results) do
    Enum.reduce(results, Decimal.new(0), fn result, acc ->
      case result.lab_test do
        %{price: %Decimal{} = price} -> Decimal.add(acc, price)
        _ -> acc
      end
    end)
  end

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
  defp format_date(other), do: to_string(other)

  defp status_meta(:result, :pending), do: {"Not started", "#F1F2F5", "#687083"}
  defp status_meta(:result, :collected), do: {"Sample collected", "#d3fa99", "#1c3a13"}
  defp status_meta(:result, :completed), do: {"Completed", "#1c3a13", "#fcfcf7"}
  defp status_meta(:order, :pending), do: {"Pending", "#eeeee9", "#666666"}
  defp status_meta(:order, :in_progress), do: {"In progress", "#d3fa99", "#1c3a13"}
  defp status_meta(:order, :completed), do: {"Completed", "#1c3a13", "#fcfcf7"}
  defp status_meta(:order, :cancelled), do: {"Cancelled", "#FBEAE9", "#C21F17"}

  defp status_meta(:specimen, :pending_collection),
    do: {"Awaiting collection", "#F1F2F5", "#687083"}

  defp status_meta(:specimen, :collected), do: {"Collected", "#d3fa99", "#1c3a13"}
  defp status_meta(:specimen, :received), do: {"Received at lab", "#1c3a13", "#fcfcf7"}
  defp status_meta(:specimen, :rejected), do: {"Rejected", "#FBEAE9", "#C21F17"}
  defp status_meta(_kind, other), do: {Phoenix.Naming.humanize(other), "#F1F2F5", "#687083"}

  defp can_enter?(result), do: result.status in [:collected, :completed]

  defp specimen_tests(specimen) do
    Enum.map_join(specimen.lab_order_results, ", ", &test_name/1)
  end

  defp usage_test_name(results, usage) do
    case Enum.find(results, &(&1.id == usage.lab_order_result_id)) do
      nil -> "—"
      result -> test_name(result)
    end
  end

  defp batch_label(batch) do
    product_name =
      case batch.product do
        %{generic_name: name} when is_binary(name) and name != "" -> name
        %{brand_name: name} when is_binary(name) and name != "" -> name
        _ -> "Batch"
      end

    "#{product_name} — #{batch.batch_no || "##{batch.id}"} (#{batch.remaining_quantity} left)"
  end

  defp batch_available_for_product?(batches, batch_id, product_id) do
    Enum.any?(batches, fn batch ->
      batch.id == batch_id and batch.product_id == product_id
    end)
  end

  defp consumable_search_results(batches, query) do
    query = query |> String.trim() |> String.downcase()

    if query == "" do
      []
    else
      batches
      |> Enum.map(& &1.product)
      |> Enum.uniq_by(& &1.id)
      |> Enum.filter(fn product ->
        [product.generic_name, product.brand_name, product.gtin]
        |> Enum.reject(&is_nil/1)
        |> Enum.any?(&String.contains?(String.downcase(&1), query))
      end)
      |> Enum.sort_by(&String.downcase(&1.generic_name || &1.brand_name || ""))
    end
  end

  defp batches_for_product(batches, product_id),
    do: Enum.filter(batches, &(&1.product_id == product_id))

  defp selected_product(batches, product_id) do
    case Enum.find(batches, &(&1.product_id == product_id)) do
      nil -> nil
      batch -> batch.product
    end
  end

  defp specimen_type_options do
    Enum.map(LabSpecimen.specimen_types(), &{Phoenix.Naming.humanize(&1), &1})
  end

  attr :kind, :atom, required: true
  attr :status, :atom, required: true

  defp status_pill(assigns) do
    {label, bg, fg} = status_meta(assigns.kind, assigns.status)
    assigns = assign(assigns, label: label, bg: bg, fg: fg)

    ~H"""
    <span
      class="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium whitespace-nowrap"
      style={"background: #{@bg}; color: #{@fg};"}
    >
      <span class="size-1.5 rounded-full" style={"background: #{@fg};"} />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp meta_field(assigns) do
    ~H"""
    <div>
      <dt class="text-[11px] font-medium uppercase tracking-wider" style="color: #9AA3B5;">
        {@label}
      </dt>
      <dd class="mt-1 text-sm" style="color: #1F2430;">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  attr :tab, :string, required: true
  attr :active, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  defp tab_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "inline-flex min-w-max flex-1 items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium outline-none transition",
        @active == @tab && "bg-thamani-forest text-white shadow-sm",
        @active != @tab && "text-thamani-pewter hover:bg-white hover:text-thamani-forest"
      ]}
    >
      <.icon name={@icon} class="size-4" /> {@label}
    </button>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
      <%!-- Payment modal --%>
      <.modal
        :if={@live_action == :new_payment}
        id="payment-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">Record payment</h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          Record and immediately complete a payment for this lab order.
        </p>
        <.form
          for={@payment_form}
          id="payment-form"
          phx-submit="save_payment"
          phx-change="validate_payment"
        >
          <.input
            field={@payment_form[:payment_type]}
            type="select"
            label="Payment method"
            options={PaymentMethods.all()}
            prompt="Choose a method"
            required
          />
          <.input
            field={@payment_form[:amount]}
            type="number"
            label="Amount (KES)"
            step="0.01"
            min="0.01"
            required
          />
          <.input field={@payment_form[:provider_reference]} label="Reference / receipt no." />
          <div class="pt-4">
            <.button variant="primary" phx-disable-with="Saving…" class="w-full">
              Record payment
            </.button>
          </div>
        </.form>
      </.modal>

      <%!-- Add test modal --%>
      <.modal
        :if={@live_action == :add_test}
        id="add-test-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">Add a test</h2>
        <.form for={%{}} id="add-test-form" phx-submit="add_result">
          <.input
            type="select"
            name="lab_test_id"
            label="Test"
            value={nil}
            options={Enum.map(@lab_tests, &{"#{&1.name} — KES #{&1.price}", &1.id})}
            prompt="Choose a test"
          />
          <div class="pt-4">
            <.button variant="primary" class="w-full">Add test</.button>
          </div>
        </.form>
      </.modal>

      <%!-- Collect specimen modal --%>
      <.modal
        :if={@live_action == :collect_specimen}
        id="collect-specimen-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-1">
          Collect specimen
        </h2>
        <p class="mb-5 text-sm text-thamani-pewter">
          One specimen can serve several tests — tick each test this sample is for.
        </p>
        <.form for={%{}} id="collect-specimen-form" phx-submit="collect_specimen">
          <.input
            type="select"
            name="specimen_type"
            label="Specimen type"
            options={specimen_type_options()}
            prompt="Choose type"
            required
          />
          <.input
            type="date"
            name="collection_date"
            label="Collected on"
            value={to_string(Date.utc_today())}
          />
          <.input type="text" name="collection_notes" label="Notes (optional)" value="" />

          <div class="mt-2">
            <span class="block text-sm font-medium text-thamani-forest mb-2">Tests covered</span>
            <div class="flex flex-col gap-2">
              <label
                :for={result <- @collectable_results}
                class="inline-flex items-center gap-2 text-sm text-thamani-forest cursor-pointer rounded-lg border border-thamani-stone bg-thamani-snow px-3 py-2 hover:border-thamani-accent/50 transition-colors"
              >
                <input
                  type="checkbox"
                  name="result_ids[]"
                  value={result.id}
                  class="checkbox checkbox-sm accent-thamani-forest"
                /> {test_name(result)}
              </label>
            </div>
            <p :if={@collectable_results == []} class="text-sm text-thamani-pewter">
              Every test already has a specimen.
            </p>
          </div>

          <div class="mt-5">
            <.button
              type="submit"
              variant="primary"
              phx-disable-with="Saving…"
              class="w-full"
              disabled={@collectable_results == []}
            >
              Collect specimen
            </.button>
          </div>
        </.form>
      </.modal>

      <%!-- Specimen label modal --%>
      <SpecimenLabelComponent.specimen_label_modal
        :if={@live_action == :print_specimen_label && @printing_specimen}
        specimen={@printing_specimen}
        patient={@patient}
        on_close={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      />

      <%!-- Lab report modal --%>
      <LabReportComponent.lab_report_modal
        :if={@live_action == :print_report}
        lab_order={@lab_order}
        patient={@patient}
        site={@site}
        results={@results}
        on_close={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      />

      <%!-- Record consumable modal --%>
      <.modal
        :if={@live_action == :record_consumable}
        id="record-consumable-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-1">
          Record consumable
        </h2>
        <p class="mb-5 text-sm text-thamani-pewter">
          Drawn directly from this site's stock.
        </p>
        <%= if is_nil(@selected_consumable_product_id) do %>
          <form id="consumable-product-search" phx-change="search_consumable_products">
            <.input
              id="consumable-product-query"
              type="text"
              name="product_query"
              label="Product"
              value={@consumable_search}
              placeholder="Type a product name, brand, or GTIN"
              autocomplete="off"
            />
          </form>
          <div
            :if={String.trim(@consumable_search) != ""}
            id="consumable-product-results"
            class="mt-2 max-h-56 overflow-y-auto rounded-xl border border-thamani-stone bg-white p-1"
          >
            <% results = consumable_search_results(@active_batches, @consumable_search) %>
            <button
              :for={product <- results}
              id={"consumable-product-option-#{product.id}"}
              type="button"
              phx-click="select_consumable_product"
              phx-value-product_id={product.id}
              class="flex w-full items-center justify-between gap-3 rounded-lg px-3 py-2.5 text-left transition hover:bg-thamani-canvas"
            >
              <span>
                <span class="block text-sm font-medium text-slate-900">{product.generic_name ||
                  product.brand_name}</span>
                <span
                  :if={product.brand_name && product.brand_name != product.generic_name}
                  class="block text-xs text-thamani-pewter"
                >{product.brand_name}</span>
              </span>
              <span class="text-xs text-thamani-pewter">{Enum.count(
                @active_batches,
                &(&1.product_id == product.id)
              )} batches</span>
            </button>
            <p :if={results == []} class="px-3 py-4 text-sm text-thamani-pewter">
              No in-stock products match that search.
            </p>
          </div>
          <p :if={@active_batches == []} class="mt-2 text-sm text-thamani-pewter">
            No active consumable stock is available at this site.
          </p>
        <% else %>
          <% product = selected_product(@active_batches, @selected_consumable_product_id) %>
          <div class="mb-4 flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas/50 px-3 py-3">
            <div>
              <p class="text-xs uppercase tracking-wide text-thamani-subtle">Selected product</p>
              <p class="mt-1 text-sm font-medium text-slate-900">
                {product.generic_name || product.brand_name}
                <span
                  :if={product.brand_name && product.brand_name != product.generic_name}
                  class="font-normal text-thamani-pewter"
                >· {product.brand_name}</span>
              </p>
            </div>
            <button
              id="change-consumable-product"
              type="button"
              phx-click="change_consumable_product"
              class="text-sm font-medium text-thamani-forest hover:underline"
            >Change</button>
          </div>
          <.form for={%{}} id="record-consumable-form" phx-submit="record_consumable">
            <input type="hidden" name="product_id" value={@selected_consumable_product_id} />
            <.input
              type="select"
              name="batch_id"
              label="Batch / lot"
              options={
                Enum.map(
                  batches_for_product(@active_batches, @selected_consumable_product_id),
                  fn batch -> {batch_label(batch), batch.id} end
                )
              }
              prompt="Choose a batch"
              required
            />
            <.input type="number" name="usage_quantity" label="Quantity used" min="1" required />
            <.input
              type="select"
              name="lab_order_result_id"
              label="For test (optional)"
              value=""
              options={[{"— none —", ""} | Enum.map(@results, &{test_name(&1), &1.id})]}
            />
            <div class="mt-5">
              <.button type="submit" variant="primary" phx-disable-with="Saving…" class="w-full">
                Record consumable
              </.button>
            </div>
          </.form>
        <% end %>
      </.modal>

      <%!-- Result entry modal --%>
      <.modal
        :if={@live_action == :edit_result && @editing_result}
        id="result-entry-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
        class="max-w-2xl"
      >
        <div class="mb-6 flex items-start gap-4 pr-8">
          <div class="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-thamani-lime/25 text-thamani-forest">
            <.icon name="hero-beaker" class="size-7" />
          </div>
          <div>
            <h2
              id="result-entry-modal-title"
              class="text-2xl font-semibold tracking-tight text-thamani-forest"
            >
              Enter test results
            </h2>
            <p id="result-entry-modal-description" class="mt-1 text-sm text-thamani-pewter">
              {@editing_lab_test.name}
            </p>
          </div>
        </div>

        <.form for={%{}} id="result-entry-form" phx-submit="save_result">
          <div class="flex flex-col gap-5">
            <%= for {key, definition} <- @editing_lab_test.field_definitions do %>
              <%= cond do %>
                <% definition["type"] == "checkbox" and is_list(definition["options"]) and definition["options"] != [] -> %>
                  <% curr_val = current_value(@editing_result, key) %>
                  <fieldset class="space-y-2.5">
                    <legend class="mb-2 block text-sm font-semibold text-thamani-forest">
                      {field_label(key, definition)}
                    </legend>
                    <div class="flex flex-wrap gap-3">
                      <%= for opt <- definition["options"] do %>
                        <label class="inline-flex cursor-pointer items-center gap-2 rounded-xl border border-thamani-stone bg-thamani-snow px-3 py-2.5 text-sm text-thamani-forest transition-colors hover:border-thamani-accent/50 has-[:checked]:border-thamani-forest has-[:checked]:bg-thamani-lime/20">
                          <input
                            type="checkbox"
                            name={"values[#{key}][]"}
                            value={opt}
                            checked={checkbox_checked?(curr_val, opt)}
                            class="size-4 accent-thamani-forest"
                          />
                          <span>{opt}</span>
                        </label>
                      <% end %>
                    </div>
                  </fieldset>
                <% definition["type"] == "checkbox" -> %>
                  <% curr_val = current_value(@editing_result, key) %>
                  <.input
                    type="checkbox"
                    name={"values[#{key}]"}
                    label={field_label(key, definition)}
                    value="true"
                    checked={single_checkbox_checked?(curr_val)}
                  />
                <% definition["type"] == "select" and is_list(definition["options"]) and definition["options"] != [] -> %>
                  <% curr_val = current_value(@editing_result, key) %>
                  <fieldset class="space-y-2.5">
                    <legend class="block text-sm font-medium text-thamani-forest">
                      {field_label(key, definition)}
                    </legend>
                    <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
                      <%= for opt <- definition["options"] do %>
                        <label class="group flex min-h-20 cursor-pointer items-start gap-3 rounded-2xl border border-thamani-stone bg-white px-4 py-3.5 text-thamani-forest transition-[border-color,background-color,box-shadow] hover:border-thamani-accent/60 has-[:checked]:border-thamani-forest has-[:checked]:bg-thamani-lime/15 has-[:checked]:shadow-sm">
                          <input
                            type="radio"
                            name={"values[#{key}]"}
                            value={opt}
                            checked={to_string(curr_val) == opt}
                            class="mt-0.5 size-5 shrink-0 accent-thamani-forest focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-thamani-accent"
                          />
                          <span class="min-w-0">
                            <span class="block text-sm font-semibold">{opt}</span>
                            <span
                              :if={option_description(opt)}
                              class="mt-1 block text-xs leading-5 text-thamani-pewter"
                            >
                              {option_description(opt)}
                            </span>
                          </span>
                        </label>
                      <% end %>
                    </div>
                  </fieldset>
                <% true -> %>
                  <.input
                    type={input_type(definition)}
                    name={"values[#{key}]"}
                    label={field_label(key, definition)}
                    value={current_value(@editing_result, key)}
                    options={field_options(definition)}
                  />
              <% end %>
            <% end %>
          </div>

          <div
            :if={@editing_result.status == :completed}
            class="mt-5 rounded-xl bg-thamani-canvas p-4"
          >
            <.input
              type="text"
              name="amendment_reason"
              label="Reason for amending this result"
              value=""
              required
            />
          </div>

          <div class="mt-6 flex flex-col-reverse gap-3 border-t border-thamani-stone pt-5 sm:flex-row sm:justify-end">
            <.link
              patch={~p"/lab/orders/#{@lab_order.id}"}
              class="inline-flex min-h-11 items-center justify-center rounded-xl border border-thamani-stone px-5 text-sm font-semibold text-thamani-forest transition-colors hover:bg-thamani-canvas"
            >
              Cancel
            </.link>
            <.button
              id="save-result-button"
              type="submit"
              variant="primary"
              phx-disable-with="Saving…"
              class="min-h-11 sm:min-w-44"
            >
              <.icon name="hero-bookmark-square" class="mr-2 size-4" /> Save results
            </.button>
          </div>
        </.form>
      </.modal>

      <%!-- Page header --%>
      <.header>
        <div class="flex flex-wrap items-center gap-3">
          <span>{@patient.full_name}</span>
          <.status_pill kind={:order} status={@lab_order.status} />
        </div>
        <:subtitle>
          Lab order #{@lab_order.id} · {Phoenix.Naming.humanize(@lab_order.urgency || "routine")}
        </:subtitle>
        <:actions>
          <.button
            :if={not @lab_order.has_paid}
            variant="primary"
            patch={~p"/lab/orders/#{@lab_order.id}/payments/new"}
            class="gap-2"
          >
            <.icon name="hero-banknotes" class="size-4" /> Record payment
          </.button>
        </:actions>
      </.header>

      <%!-- Order overview --%>
      <section class="rounded-2xl p-5 sm:p-6" style="background: #FFFFFF; border: 1px solid #EDF0F8;">
        <dl class="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-5">
          <.meta_field label="Urgency">
            {Phoenix.Naming.humanize(@lab_order.urgency || "routine")}
          </.meta_field>
          <.meta_field label="Prescriber">
            {@lab_order.prescriber_name || "—"}
          </.meta_field>
          <.meta_field label="Payment">
            <span class="inline-flex items-center gap-1.5">
              {if @lab_order.has_paid, do: "Paid", else: "Unpaid"}
              <span :if={@lab_order.payment_type} style="color: #9AA3B5;">
                · {Phoenix.Naming.humanize(@lab_order.payment_type)}
              </span>
            </span>
          </.meta_field>
          <.meta_field label="Total">KES {total_price(@results)}</.meta_field>
          <.meta_field :if={@lab_order.is_referral} label="Referring facility">
            {@lab_order.referring_facility || "—"}
          </.meta_field>
          <.meta_field :if={@lab_order.is_referral} label="Referring doctor">
            {@lab_order.referring_doctor || "—"}
          </.meta_field>
        </dl>
      </section>

      <%!-- Detail tabs --%>
      <nav
        id="lab-order-tabs"
        role="tablist"
        class="mt-8 mb-5 flex gap-1 overflow-x-auto rounded-xl border border-thamani-stone bg-thamani-canvas p-1"
      >
        <.tab_button tab="samples" active={@detail_tab} label="Samples" icon="hero-beaker" />
        <.tab_button
          tab="results"
          active={@detail_tab}
          label="Results"
          icon="hero-clipboard-document-check"
        />
        <.tab_button tab="consumables" active={@detail_tab} label="Consumables" icon="hero-cube" />
      </nav>

      <%!-- Samples tab --%>
      <div :if={@detail_tab == "samples"}>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-medium" style="color: #1F2430;">
            Specimens
            <span class="ml-1 font-normal" style="color: #9AA3B5;">({length(@specimens)})</span>
          </h2>
          <.button
            :if={@collectable_results != []}
            variant="primary"
            patch={~p"/lab/orders/#{@lab_order.id}/collect"}
            class="gap-1.5"
          >
            <.icon name="hero-beaker" class="size-4" /> Collect specimen
          </.button>
        </div>

        <.table id="specimens" rows={@specimens}>
          <:col :let={specimen} label="Specimen">
            <div class="font-medium" style="color: #1F2430;">{specimen.specimen_number}</div>
            <div class="mt-0.5 text-xs" style="color: #9AA3B5;">
              {Phoenix.Naming.humanize(specimen.specimen_type || "sample")}
            </div>
          </:col>
          <:col :let={specimen} label="Tests">{specimen_tests(specimen)}</:col>
          <:col :let={specimen} label="Collected on">
            {format_date(specimen.collected_at && DateTime.to_date(specimen.collected_at))}
            <div :if={specimen.collected_by} class="mt-0.5 text-xs" style="color: #9AA3B5;">
              {user_name(specimen.collected_by)}
            </div>
          </:col>
          <:col :let={specimen} label="Status">
            <.status_pill kind={:specimen} status={specimen.status} />
            <div :if={specimen.status == :rejected} class="mt-1 text-xs" style="color: #9AA3B5;">
              {specimen.rejection_reason} · {user_name(specimen.rejected_by)}
            </div>
          </:col>
          <:action :let={specimen}>
            <.button
              variant="ghost-edit"
              patch={~p"/lab/orders/#{@lab_order.id}/specimens/#{specimen.id}/label"}
              class="gap-1.5 py-1.5 px-3 text-xs"
            >
              <.icon name="hero-printer" class="size-3.5" /> Print label
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-beaker" title="No specimens collected yet">
              Collect a specimen to start tracking samples for this order.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <%!-- Results tab --%>
      <div :if={@detail_tab == "results"}>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-medium" style="color: #1F2430;">
            Tests <span class="ml-1 font-normal" style="color: #9AA3B5;">({length(@results)})</span>
          </h2>
          <div class="flex items-center gap-2">
            <.button
              :if={@results != []}
              variant="ghost-edit"
              patch={~p"/lab/orders/#{@lab_order.id}/report"}
              class="gap-1.5"
            >
              <.icon name="hero-printer" class="size-4" /> Print results
            </.button>
            <.button patch={~p"/lab/orders/#{@lab_order.id}/tests/new"} class="gap-1.5">
              <.icon name="hero-plus" class="size-4" /> Add test
            </.button>
          </div>
        </div>

        <.table id="results" rows={@results}>
          <:col :let={result} label="Test">
            <div class="font-medium" style="color: #1F2430;">{test_name(result)}</div>
            <div class="mt-0.5 text-xs" style="color: #9AA3B5;">
              KES {result.lab_test && result.lab_test.price}
            </div>
          </:col>
          <:col :let={result} label="Result">
            <div :if={result.results == %{}} class="text-sm" style="color: #9AA3B5;">
              No results recorded yet.
            </div>
            <div :if={result.results != %{}} class="flex flex-col gap-2">
              <div :for={{key, %{"value" => value}} <- result.results}>
                <div
                  class="text-[11px] font-medium uppercase tracking-wider"
                  style="color: #9AA3B5;"
                >
                  {key}
                </div>
                <.render_result_preview
                  key={key}
                  value={value}
                  unit={result_unit(result, key)}
                  field_definition={get_field_definition(result, key)}
                />
              </div>
            </div>

            <% result_amendments = Map.get(@amendments, result.id, []) %>
            <div :if={result_amendments != []} class="mt-3">
              <p
                class="text-[11px] font-medium uppercase tracking-wider mb-1"
                style="color: #9AA3B5;"
              >
                Amendment history
              </p>
              <ul class="space-y-1">
                <li :for={amendment <- result_amendments} class="text-xs" style="color: #1F2430;">
                  <span style="color: #9AA3B5;">
                    {Calendar.strftime(amendment.inserted_at, "%d %b %Y %H:%M")} · {user_name(
                      amendment.amended_by
                    )} —
                  </span>
                  {amendment.reason}
                </li>
              </ul>
            </div>
          </:col>
          <:col :let={result} label="Performed by">{user_name(result.performed_by)}</:col>
          <:col :let={result} label="Status">
            <.status_pill kind={:result} status={result.status} />
          </:col>
          <:action :let={result}>
            <.button
              :if={can_enter?(result)}
              variant="primary"
              patch={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/edit"}
              class="gap-1.5 py-1.5 px-3 text-xs"
            >
              <.icon name="hero-pencil-square" class="size-3.5" /> Enter results
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-clipboard-document-check" title="No tests on this order yet">
              Use "Add test" above to add the first test.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <%!-- Consumables tab --%>
      <div :if={@detail_tab == "consumables"}>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-medium" style="color: #1F2430;">
            Consumables
            <span class="ml-1 font-normal" style="color: #9AA3B5;">
              ({length(@consumable_usages)})
            </span>
          </h2>
          <.button
            :if={@active_batches != []}
            variant="primary"
            patch={~p"/lab/orders/#{@lab_order.id}/consumables/new"}
            class="gap-1.5"
          >
            <.icon name="hero-plus" class="size-4" /> Record consumable
          </.button>
          <span
            :if={@active_batches == []}
            class="inline-flex cursor-not-allowed items-center gap-1.5 rounded-lg px-4 py-2 text-sm font-medium opacity-50"
            style="background: #F1F2F5; color: #687083;"
            title="No lab consumable stock at this site yet"
          >
            <.icon name="hero-plus" class="size-4" /> Record consumable
          </span>
        </div>

        <p :if={@active_batches == []} class="mb-4 -mt-2 text-sm" style="color: #9AA3B5;">
          No lab consumable stock has been received at this site yet.
          <.link navigate={~p"/lab/receive-stock"} class="underline hover:no-underline">
            Receive stock
          </.link>
          to start recording usage.
        </p>

        <div
          :if={@consumable_usages == []}
          class="rounded-2xl p-8 text-center text-sm"
          style="background: #F8FAFC; border: 1px dashed #C7CFE0; color: #687083;"
        >
          No consumables recorded for this order yet.
        </div>

        <.table :if={@consumable_usages != []} id="consumable-usages" rows={@consumable_usages}>
          <:col :let={usage} label="Item">
            {case usage.batch.product do
              %{generic_name: n} when is_binary(n) and n != "" -> n
              %{brand_name: n} when is_binary(n) and n != "" -> n
              _ -> "Batch"
            end}
          </:col>
          <:col :let={usage} label="Batch">{usage.batch.batch_no || "##{usage.batch.id}"}</:col>
          <:col :let={usage} label="Quantity">{usage.quantity}</:col>
          <:col :let={usage} label="For test">{usage_test_name(@results, usage)}</:col>
          <:col :let={usage} label="Recorded by">{user_name(usage.used_by)}</:col>
        </.table>
      </div>
    </Layouts.lab_shell>
    """
  end
end
