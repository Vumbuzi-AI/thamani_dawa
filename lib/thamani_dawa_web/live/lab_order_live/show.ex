defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PaymentMethods
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment

  @sample_types [{"Blood", :blood}, {"Urine", :urine}, {"Stool", :stool}, {"Swab", :swab}]

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    socket =
      socket
      |> assign(:lab_tests, LabTests.list_active_lab_tests(organization_id))
      |> assign(:sample_types, @sample_types)
      |> assign(:collecting_result, nil)
      |> assign(:editing_result, nil)
      |> assign(:editing_lab_test, nil)
      |> assign(:payment_form, nil)
      |> assign(:active_batches, [])
      |> load_lab_order(id)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :collect_sample, %{"result_id" => result_id}) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, String.to_integer(result_id))

    socket
    |> assign(:collecting_result, result)
    |> assign(:editing_result, nil)
    |> assign(:editing_lab_test, nil)
    |> assign(:payment_form, nil)
  end

  defp apply_action(socket, :edit_result, %{"result_id" => result_id}) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, String.to_integer(result_id))
    lab_test = LabTests.get_lab_test!(organization_id, result.lab_test_id)

    active_batches =
      Batches.list_active_batches_for_site_with_product(
        organization_id,
        socket.assigns.lab_order.site_id
      )

    socket
    |> assign(:collecting_result, nil)
    |> assign(:editing_result, result)
    |> assign(:editing_lab_test, lab_test)
    |> assign(:active_batches, active_batches)
    |> assign(:payment_form, nil)
  end

  defp apply_action(socket, :new_payment, _params) do
    lab_order = socket.assigns.lab_order

    changeset =
      Payment.changeset(%Payment{}, %{
        "lab_order_id" => lab_order.id,
        "amount" => lab_order.total_amount
      })

    socket
    |> assign(:collecting_result, nil)
    |> assign(:editing_result, nil)
    |> assign(:editing_lab_test, nil)
    |> assign(:payment_form, to_form(changeset, as: :payment))
  end

  defp apply_action(socket, _action, _params) do
    socket
    |> assign(:collecting_result, nil)
    |> assign(:editing_result, nil)
    |> assign(:editing_lab_test, nil)
    |> assign(:payment_form, nil)
  end

  defp load_lab_order(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    lab_order = LabOrders.get_lab_order!(organization_id, id)
    visit = PatientVisits.get_patient_visit!(organization_id, lab_order.patient_visit_id)
    patient = Patients.get_patient!(organization_id, visit.patient_id)
    results = LabOrders.list_lab_order_results_for_order(organization_id, lab_order.id)

    consumable_usages =
      organization_id
      |> LabOrders.list_consumable_usages_for_order(lab_order.id)
      |> Enum.group_by(& &1.lab_order_result_id)

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:results, results)
    |> assign(:consumable_usages, consumable_usages)
  end

  def handle_event("confirm_collected", %{"result_id" => id} = attrs, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    case LabOrders.mark_sample_collected(organization_id, String.to_integer(id), user_id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_lab_order(socket.assigns.lab_order.id)
         |> push_patch(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not record sample collection.")}
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
         |> push_patch(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't add that test.")}
    end
  end

  def handle_event("add_result", _attrs, socket) do
    {:noreply, put_flash(socket, :error, "Choose a test to add.")}
  end

  def handle_event("save_result", %{"values" => raw_values} = params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    performer_id = socket.assigns.current_scope.user.id

    case LabOrders.record_result(
           organization_id,
           socket.assigns.editing_result.id,
           performer_id,
           raw_values
         ) do
      {:ok, recorded_result} ->
        maybe_record_consumable(socket, organization_id, performer_id, recorded_result.id, params)

        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> push_navigate(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp maybe_record_consumable(socket, organization_id, user_id, result_id, %{
         "batch_id" => batch_id,
         "usage_quantity" => qty_str
       })
       when batch_id != "" and qty_str != "" do
    with {batch_id, ""} <- Integer.parse(batch_id),
         {qty, ""} <- Integer.parse(qty_str),
         true <- qty > 0 do
      LabOrders.record_consumable_usage(
        organization_id,
        batch_id,
        user_id,
        qty,
        lab_order_id: socket.assigns.lab_order.id,
        lab_order_result_id: result_id
      )
    end
  end

  defp maybe_record_consumable(_, _, _, _, _), do: :ok

  defp test_name(%{lab_test: %{name: name}}), do: name
  defp test_name(_), do: "(unknown test)"

  defp user_name(%{name: name}), do: name
  defp user_name(_), do: "—"

  defp result_unit(%{lab_test: %{field_definitions: defs}}, key) when is_map(defs),
    do: get_in(defs, [key, "unit"]) || ""

  defp result_unit(_result, _key), do: ""

  defp current_value(result, key), do: get_in(result.results, [key, "value"])

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
  defp status_meta(_kind, other), do: {Phoenix.Naming.humanize(other), "#F1F2F5", "#687083"}

  defp can_collect?(result), do: is_nil(result.sample_collected_on)
  defp can_enter?(result), do: result.status in [:pending, :collected]

  defp batch_label(batch) do
    product_name =
      case batch.product do
        %{generic_name: name} when is_binary(name) and name != "" -> name
        %{brand_name: name} when is_binary(name) and name != "" -> name
        _ -> "Batch"
      end

    "#{product_name} — #{batch.batch_no || "##{batch.id}"} (#{batch.remaining_quantity} left)"
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
          <.input
            type="select"
            name="sample_type"
            label="Sample type"
            value={:blood}
            options={@sample_types}
          />
          <div class="pt-4">
            <.button variant="primary" class="w-full">Add test</.button>
          </div>
        </.form>
      </.modal>

      <%!-- Collect sample modal --%>
      <.modal
        :if={@live_action == :collect_sample && @collecting_result}
        id="collect-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-1">
          Record sample collection
        </h2>
        <p class="mb-5 text-sm text-thamani-pewter">
          {test_name(@collecting_result)} · {Phoenix.Naming.humanize(
            @collecting_result.sample_type || "sample"
          )}
        </p>
        <.form for={%{}} id="collect-sample-form" phx-submit="confirm_collected">
          <input type="hidden" name="result_id" value={@collecting_result.id} />
          <.input
            type="date"
            name="collection_date"
            label="Collected on"
            value={to_string(Date.utc_today())}
          />
          <.input type="text" name="collection_notes" label="Notes (optional)" value="" />
          <div class="mt-5">
            <.button type="submit" variant="primary" phx-disable-with="Saving…" class="w-full">
              Save collection
            </.button>
          </div>
        </.form>
      </.modal>

      <%!-- Result entry modal --%>
      <.modal
        :if={@live_action == :edit_result && @editing_result}
        id="result-entry-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-1">
          Enter results
        </h2>
        <p class="mb-5 text-sm text-thamani-pewter">{@editing_lab_test.name}</p>

        <.form for={%{}} id="result-entry-form" phx-submit="save_result">
          <div class="flex flex-col gap-4">
            <%= for {key, definition} <- @editing_lab_test.field_definitions do %>
              <%= cond do %>
                <% definition["type"] == "checkbox" and is_list(definition["options"]) and definition["options"] != [] -> %>
                  <% curr_val = current_value(@editing_result, key) %>
                  <div class="space-y-2">
                    <label class="block text-sm font-medium text-thamani-forest">
                      {field_label(key, definition)}
                    </label>
                    <div class="flex flex-wrap gap-3">
                      <%= for opt <- definition["options"] do %>
                        <label class="inline-flex items-center gap-2 text-sm text-thamani-forest cursor-pointer bg-thamani-snow border border-thamani-stone px-3 py-1.5 rounded-lg hover:border-thamani-accent/50 transition-colors">
                          <input
                            type="checkbox"
                            name={"values[#{key}][]"}
                            value={opt}
                            checked={checkbox_checked?(curr_val, opt)}
                            class="checkbox checkbox-sm accent-thamani-forest"
                          />
                          <span>{opt}</span>
                        </label>
                      <% end %>
                    </div>
                  </div>
                <% definition["type"] == "checkbox" -> %>
                  <% curr_val = current_value(@editing_result, key) %>
                  <.input
                    type="checkbox"
                    name={"values[#{key}]"}
                    label={field_label(key, definition)}
                    value="true"
                    checked={single_checkbox_checked?(curr_val)}
                  />
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
            :if={@active_batches != []}
            class="mt-6 rounded-xl border border-thamani-stone p-4"
            style="background: #F8FAFC;"
          >
            <p class="text-xs font-medium uppercase tracking-wide mb-3" style="color: #687083;">
              Consumable used (optional)
            </p>
            <div class="flex flex-wrap gap-3 items-end">
              <div class="flex-1 min-w-48 [&>div]:mb-0">
                <.input
                  type="select"
                  name="batch_id"
                  label="Reagent / batch"
                  value=""
                  options={[{"— none —", ""} | Enum.map(@active_batches, &{batch_label(&1), &1.id})]}
                />
              </div>
              <div class="w-28 [&>div]:mb-0">
                <.input
                  type="number"
                  name="usage_quantity"
                  label="Qty used"
                  value=""
                  min="1"
                />
              </div>
            </div>
          </div>

          <.button variant="primary" class="mt-5">Save results</.button>
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
          <.button patch={~p"/lab/orders/#{@lab_order.id}/tests/new"} class="gap-2">
            <.icon name="hero-plus" class="size-4" /> Add test
          </.button>
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

      <%!-- Tests & results --%>
      <div class="flex items-center justify-between mt-8 mb-4">
        <h2 class="text-base font-medium" style="color: #1F2430;">
          Tests <span class="ml-1 font-normal" style="color: #9AA3B5;">({length(@results)})</span>
        </h2>
      </div>

      <div
        :if={@results == []}
        class="rounded-2xl p-8 text-center text-sm"
        style="background: #F8FAFC; border: 1px dashed #C7CFE0; color: #687083;"
      >
        No tests on this order yet — use "Add test" above.
      </div>

      <div class="space-y-4">
        <article
          :for={result <- @results}
          class="rounded-2xl overflow-hidden"
          style="background: #FFFFFF; border: 1px solid #EDF0F8;"
        >
          <%!-- Card header: test name, price, status, primary CTAs --%>
          <div class="flex items-center justify-between gap-4 px-5 py-4 sm:px-6">
            <div class="min-w-0">
              <h3 class="text-base font-medium" style="color: #1F2430;">
                {test_name(result)}
              </h3>
              <p class="text-sm mt-0.5" style="color: #9AA3B5;">
                KES {result.lab_test && result.lab_test.price}
                <span :if={result.sample_type}>
                  · {Phoenix.Naming.humanize(result.sample_type)}
                </span>
              </p>
            </div>
            <.status_pill kind={:result} status={result.status} />
          </div>

          <%!-- Sample collection section --%>
          <div class="px-5 py-4 sm:px-6" style="border-top: 1px solid #EDF0F8;">
            <div class="flex items-center justify-between gap-4 mb-3">
              <span
                class="text-[11px] font-medium uppercase tracking-wider"
                style="color: #9AA3B5;"
              >
                Sample collection
              </span>
              <.button
                :if={can_collect?(result)}
                patch={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/collect"}
                class="gap-1.5 py-1.5 px-3 text-xs active:scale-[0.96] transition-transform"
              >
                <.icon name="hero-beaker" class="size-3.5" /> Mark collected
              </.button>
            </div>
            <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3">
              <.meta_field label="Collected on">
                {format_date(result.sample_collected_on)}
                <span :if={result.collected_by_id} style="color: #9AA3B5;">
                  · {user_name(result.collected_by)}
                </span>
              </.meta_field>
              <.meta_field :if={result.collection_notes not in [nil, ""]} label="Notes">
                {result.collection_notes}
              </.meta_field>
            </dl>
          </div>

          <%!-- Results section --%>
          <div class="px-5 py-4 sm:px-6" style="border-top: 1px solid #EDF0F8;">
            <div class="flex items-center justify-between gap-4 mb-3">
              <span
                class="text-[11px] font-medium uppercase tracking-wider"
                style="color: #9AA3B5;"
              >
                Results
              </span>
              <.button
                :if={can_enter?(result)}
                variant="primary"
                patch={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/edit"}
                class="gap-1.5 py-1.5 px-3 text-xs active:scale-[0.96] transition-transform"
              >
                <.icon name="hero-pencil-square" class="size-3.5" /> Enter results
              </.button>
            </div>

            <%!-- Recorded result values --%>
            <div
              :if={result.results != %{}}
              class="rounded-xl p-4 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3 mb-4"
              style="background: #F8FAFC;"
            >
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

            <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3">
              <.meta_field label="Performed by">{user_name(result.performed_by)}</.meta_field>
            </dl>

            <%!-- Consumable usage for this result --%>
            <% usages = Map.get(@consumable_usages, result.id, []) %>
            <div :if={usages != []} class="mt-4">
              <p
                class="text-[11px] font-medium uppercase tracking-wider mb-2"
                style="color: #9AA3B5;"
              >
                Consumables used
              </p>
              <ul class="space-y-1">
                <li
                  :for={usage <- usages}
                  class="flex items-center justify-between text-sm"
                  style="color: #1F2430;"
                >
                  <span>
                    {case usage.batch.product do
                      %{generic_name: n} when is_binary(n) and n != "" -> n
                      %{brand_name: n} when is_binary(n) and n != "" -> n
                      _ -> "Batch"
                    end}
                    <span style="color: #9AA3B5;">
                      · {usage.batch.batch_no || "##{usage.batch.id}"}
                      {if usage.used_by, do: " · #{user_name(usage.used_by)}"}
                    </span>
                  </span>
                  <span class="font-medium">{usage.quantity} units</span>
                </li>
              </ul>
            </div>
          </div>
        </article>
      </div>
    </Layouts.lab_shell>
    """
  end
end
