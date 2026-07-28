defmodule ThamaniDawaWeb.LabOrderLive.Show do
  use ThamaniDawaWeb, :live_view

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
      |> assign(:collecting_result_id, nil)
      |> assign(:editing_result, nil)
      |> assign(:editing_lab_test, nil)
      |> assign(:payment_form, nil)
      |> load_lab_order(id)

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  # Opening the result-entry modal: load the result being edited and its
  # template so the form can render one input per defined field.
  defp apply_action(socket, :edit_result, %{"result_id" => result_id}) do
    organization_id = socket.assigns.current_scope.organization_id
    result = LabOrders.get_lab_order_result!(organization_id, String.to_integer(result_id))
    lab_test = LabTests.get_lab_test!(organization_id, result.lab_test_id)

    socket
    |> assign(:editing_result, result)
    |> assign(:editing_lab_test, lab_test)
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
    |> assign(:editing_result, nil)
    |> assign(:editing_lab_test, nil)
    |> assign(:payment_form, to_form(changeset, as: :payment))
  end

  defp apply_action(socket, _action, _params) do
    socket
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

    socket
    |> assign(:lab_order, lab_order)
    |> assign(:patient, patient)
    |> assign(:results, results)
  end

  def handle_event("start_collect", %{"id" => id}, socket) do
    {:noreply, assign(socket, :collecting_result_id, String.to_integer(id))}
  end

  def handle_event("cancel_collect", _params, socket) do
    {:noreply, assign(socket, :collecting_result_id, nil)}
  end

  def handle_event("confirm_collected", %{"result_id" => id} = attrs, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    case LabOrders.mark_sample_collected(organization_id, String.to_integer(id), user_id, attrs) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:collecting_result_id, nil)
          |> load_lab_order(socket.assigns.lab_order.id)

        {:noreply, socket}

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

  def handle_event("save_result", %{"values" => raw_values}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    performer_id = socket.assigns.current_scope.user.id

    case LabOrders.record_result(
           organization_id,
           socket.assigns.editing_result.id,
           performer_id,
           raw_values
         ) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Results recorded.")
         |> push_navigate(to: ~p"/lab/orders/#{socket.assigns.lab_order.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record results: #{inspect(reason)}")}
    end
  end

  defp test_name(%{lab_test: %{name: name}}), do: name
  defp test_name(_), do: "(unknown test)"

  defp user_name(%{name: name}), do: name
  defp user_name(_), do: "—"

  defp result_unit(%{lab_test: %{field_definitions: defs}}, key) when is_map(defs),
    do: get_in(defs, [key, "unit"]) || ""

  defp result_unit(_result, _key), do: ""

  defp current_value(result, key), do: get_in(result.results, [key, "value"])

  defp input_type(%{"type" => "select"}), do: "select"
  defp input_type(%{"type" => "number"}), do: "number"
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

  # A pill's copy + colours for each lifecycle state, all inside the Thamani
  # palette. The progression reads at a glance: neutral grey (not started) →
  # stone (collected) → filled forest (completed / terminal).
  defp status_meta(:result, :pending), do: {"Not started", "#F1F2F5", "#687083"}
  defp status_meta(:result, :collected), do: {"Sample collected", "#E6EDF8", "#373896"}
  defp status_meta(:result, :completed), do: {"Completed", "#373896", "#FFFFFF"}
  defp status_meta(:order, :pending), do: {"Pending", "#F1F2F5", "#687083"}
  defp status_meta(:order, :in_progress), do: {"In progress", "#E6EDF8", "#373896"}
  defp status_meta(:order, :completed), do: {"Completed", "#373896", "#FFFFFF"}
  defp status_meta(:order, :cancelled), do: {"Cancelled", "#FBEAE9", "#C21F17"}
  defp status_meta(_kind, other), do: {Phoenix.Naming.humanize(other), "#F1F2F5", "#687083"}

  defp can_collect?(result, collecting_id),
    do: is_nil(result.sample_collected_on) and collecting_id != result.id

  defp can_enter?(result), do: result.status in [:pending, :collected]

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
      <span class="size-1.5 rounded-full" style={"background: #{@fg};"} /> {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-[11px] font-semibold uppercase tracking-wider" style="color: #9AA3B5;">
        {@label}
      </dt>
      <dd class="mt-1 text-sm break-words" style="color: #1F2430;">{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/orders"}>
      <.modal
        :if={@live_action == :new_payment}
        id="payment-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="mb-1 font-semibold text-slate-900">Record payment</h2>
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
          <div class="mt-4 flex gap-2">
            <.button variant="primary" phx-disable-with="Saving…">Record payment</.button>
            <.button patch={~p"/lab/orders/#{@lab_order.id}"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

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
          <.button navigate={~p"/lab/orders"}>Back to orders</.button>
        </:actions>
      </.header>

      <section class="rounded-2xl p-6" style="background: #FFFFFF; border: 1px solid #EDF0F8;">
        <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-5">
          <.field label="Urgency">{Phoenix.Naming.humanize(@lab_order.urgency || "routine")}</.field>
          <.field label="Prescriber">{@lab_order.prescriber_name || "—"}</.field>
          <.field label="Payment">
            {if @lab_order.has_paid, do: "Paid", else: "Unpaid"}<span
              :if={@lab_order.payment_type}
              style="color: #9AA3B5;"
            > · {Phoenix.Naming.humanize(@lab_order.payment_type)}</span>
          </.field>
          <.field label="Total">KES {total_price(@results)}</.field>
          <.field :if={@lab_order.is_referral} label="Referring facility">
            {@lab_order.referring_facility || "—"}
          </.field>
          <.field :if={@lab_order.is_referral} label="Referring doctor">
            {@lab_order.referring_doctor || "—"}
          </.field>
        </dl>
      </section>

      <div class="flex items-center justify-between mt-8 mb-4">
        <h2 class="text-base font-semibold" style="color: #1F2430;">
          Tests & results
          <span class="ml-1 font-normal" style="color: #9AA3B5;">({length(@results)})</span>
        </h2>
      </div>

      <div
        :if={@results == []}
        class="rounded-2xl p-8 text-center text-sm"
        style="background: #F8FAFC; border: 1px dashed #C7CFE0; color: #687083;"
      >
        No tests on this order yet. Use "Add test" above to begin.
      </div>

      <div class="space-y-4">
        <article
          :for={result <- @results}
          class="rounded-2xl overflow-hidden"
          style="background: #FFFFFF; border: 1px solid #EDF0F8; box-shadow: 0 1px 3px oklch(0 0 0 / 0.04);"
        >
          <%!-- Card header --%>
          <div class="flex items-start justify-between gap-4 px-5 pt-5 pb-4 sm:px-6">
            <div>
              <h3 class="text-base font-semibold" style="color: #1F2430;">
                {test_name(result)}
              </h3>
              <span class="text-sm" style="color: #9AA3B5;">KES {result.lab_test &&
                result.lab_test.price}</span>
            </div>
            <.status_pill kind={:result} status={result.status} />
          </div>

          <%!-- Step 1: Sample Collection --%>
          <div style="border-top: 1px solid #EDF0F8;">
            <div class="px-5 pt-4 pb-1 sm:px-6">
              <div class="flex items-center gap-2 mb-3">
                <span
                  class="inline-flex items-center justify-center w-5 h-5 rounded-full text-[10px] font-bold"
                  style={
                    if result.sample_collected_on,
                      do: "background: #373896; color: #fff;",
                      else: "background: #E6EDF8; color: #373896;"
                  }
                >
                  1
                </span>
                <span class="text-xs font-semibold uppercase tracking-wider" style="color: #687083;">Sample collection</span>
                <%= if result.sample_collected_on do %>
                  <span class="text-xs" style="color: #22C55E;">✓ Done</span>
                <% end %>
              </div>

              <dl class="grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3 mb-4">
                <.field label="Sample type">
                  {if result.sample_type, do: Phoenix.Naming.humanize(result.sample_type), else: "—"}
                </.field>
                <.field label="Collected on">
                  {format_date(result.sample_collected_on)}<span
                    :if={result.collected_by_id}
                    style="color: #9AA3B5;"
                  > · {user_name(result.collected_by)}</span>
                </.field>
                <.field :if={result.collection_notes not in [nil, ""]} label="Collection notes">
                  {result.collection_notes}
                </.field>
              </dl>
            </div>

            <%!-- Inline sample collection form --%>
            <div
              :if={@collecting_result_id == result.id}
              class="mx-5 mb-4 rounded-xl p-4 sm:mx-6"
              style="background: #E6EDF8;"
            >
              <p class="text-xs font-semibold mb-3" style="color: #373896;">
                Record collection details
              </p>
              <.form
                for={%{}}
                id="collect-sample-form"
                phx-submit="confirm_collected"
                class="flex flex-wrap gap-3 items-end [&>div]:mb-0"
              >
                <input type="hidden" name="result_id" value={result.id} />
                <.input
                  type="date"
                  name="collection_date"
                  label="Collected on"
                  value={to_string(Date.utc_today())}
                />
                <.input type="text" name="collection_notes" label="Notes (optional)" value="" />
                <div class="flex gap-2 items-end">
                  <.button type="submit" variant="primary" class="h-11">Save collection</.button>
                  <.button type="button" phx-click="cancel_collect" class="h-11">Cancel</.button>
                </div>
              </.form>
            </div>

            <%!-- Mark collected CTA --%>
            <div
              :if={can_collect?(result, @collecting_result_id)}
              class="px-5 pb-4 sm:px-6"
            >
              <.button
                type="button"
                phx-click="start_collect"
                phx-value-id={result.id}
                class="h-11 px-5 active:scale-[0.96] transition-transform"
              >
                <.icon name="hero-beaker" class="size-4 mr-1.5" /> Mark collected
              </.button>
            </div>
          </div>

          <%!-- Step 2: Results Entry --%>
          <div style="border-top: 1px solid #EDF0F8;">
            <div class="px-5 pt-4 pb-5 sm:px-6">
              <div class="flex items-center gap-2 mb-3">
                <span
                  class="inline-flex items-center justify-center w-5 h-5 rounded-full text-[10px] font-bold"
                  style={
                    if result.status == :completed,
                      do: "background: #373896; color: #fff;",
                      else: "background: #F1F2F5; color: #687083;"
                  }
                >
                  2
                </span>
                <span class="text-xs font-semibold uppercase tracking-wider" style="color: #687083;">Results</span>
                <%= if result.status == :completed do %>
                  <span class="text-xs" style="color: #22C55E;">✓ Done</span>
                <% end %>
              </div>

              <%!-- Results values grid --%>
              <div
                :if={result.results != %{}}
                class="rounded-xl p-4 grid grid-cols-2 sm:grid-cols-3 gap-x-6 gap-y-3 mb-4"
                style="background: #F8FAFC;"
              >
                <div :for={{key, %{"value" => value}} <- result.results}>
                  <div
                    class="text-[11px] font-semibold uppercase tracking-wider"
                    style="color: #9AA3B5;"
                  >
                    {key}
                  </div>
                  <div class="mt-0.5 text-sm font-medium" style="color: #1F2430;">
                    {value}
                    <span class="font-normal" style="color: #9AA3B5;">
                      {result_unit(result, key)}
                    </span>
                  </div>
                </div>
              </div>

              <.field label="Performed by">
                {user_name(result.performed_by)}
              </.field>

              <%!-- Enter results CTA --%>
              <div :if={can_enter?(result)} class="mt-4">
                <.button
                  patch={~p"/lab/orders/#{@lab_order.id}/results/#{result.id}/edit"}
                  variant="primary"
                  class="h-11 px-5 active:scale-[0.96] transition-transform"
                >
                  <.icon name="hero-pencil-square" class="size-4 mr-1.5" /> Enter results
                </.button>
              </div>
            </div>
          </div>
        </article>
      </div>

      <.modal
        :if={@live_action == :add_test}
        id="add-test-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="mb-4 font-semibold text-slate-900">Add a test</h2>
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
          <div class="mt-4 flex gap-2">
            <.button variant="primary">Add test</.button>
            <.button type="button" patch={~p"/lab/orders/#{@lab_order.id}"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :edit_result && @editing_result}
        id="result-entry-modal"
        show
        on_cancel={JS.patch(~p"/lab/orders/#{@lab_order.id}")}
      >
        <h2 class="mb-4 font-semibold text-slate-900">Enter results — {@editing_lab_test.name}</h2>

        <.form for={%{}} id="result-entry-form" phx-submit="save_result">
          <div class="flex flex-col gap-4">
            <.input
              :for={{key, definition} <- @editing_lab_test.field_definitions}
              type={input_type(definition)}
              name={"values[#{key}]"}
              label={field_label(key, definition)}
              value={current_value(@editing_result, key)}
              options={field_options(definition)}
            />
          </div>
          <.button variant="primary" class="mt-4">Save results</.button>
        </.form>
      </.modal>
    </Layouts.lab_shell>
    """
  end
end
