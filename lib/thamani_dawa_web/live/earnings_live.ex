defmodule ThamaniDawaWeb.EarningsLive do
  @moduledoc """
  Read-only, organization-wide money dashboard for admins: total and per-site earnings from
  completed payments only (successful ledger credits), plus the full transaction history
  behind those figures, filterable by site, payment method, status, and date — each filtered
  view is produced straight from `Payments.list_transactions/1`, so the rows shown are always
  exactly what the active filters describe, with no separate/duplicated filtering logic.

  Per-site totals include every site in the organization, not just ones that have earned
  anything yet, so a site with zero completed payments still shows up as KES 0 rather than
  being silently absent.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PaymentMethods
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  @default_filters %{site: "", method: "", status: "", date_from: "", date_to: "", search: ""}

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sites = Sites.list_sites(organization_id)
    multi_site? = length(sites) > 1

    {:ok,
     socket
     |> assign(:portal, portal_for(socket.assigns.live_action))
     |> assign(:sites_by_id, Map.new(sites, &{&1.id, &1}))
     |> assign(:site_options, Enum.map(sites, &{&1.name, &1.id}))
     |> assign(:method_options, PaymentMethods.all())
     |> assign(:status_options, Enum.map(Payment.statuses(), &{Phoenix.Naming.humanize(&1), &1}))
     |> assign(:multi_site?, multi_site?)
     |> assign(
       :show_site_filter?,
       multi_site? and is_nil(socket.assigns.current_scope.current_site_id)
     )
     |> assign(:filters, @default_filters)}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:portal, portal_for(socket.assigns.live_action))
      |> reload_transactions()

    {:noreply, load_selected(socket, socket.assigns.live_action, params)}
  end

  # Lab transaction detail (Doop 45FlJvpVyi) and receipt (VRY0p3ZE2z). The payment is looked
  # up through the same organization, site and portal scoping as the list, so an id from
  # another organization, site or portal is treated as not found.
  defp load_selected(socket, action, %{"id" => id}) when action in [:lab_show, :lab_receipt] do
    case Enum.find(scoped_transactions(socket), &(to_string(&1.id) == id)) do
      nil ->
        socket
        |> put_flash(:error, "That transaction could not be found.")
        |> push_navigate(to: ~p"/lab/transactions")

      payment ->
        assign(socket, :selected, transaction_detail(socket, payment))
    end
  end

  defp load_selected(socket, _action, _params), do: assign(socket, :selected, nil)

  defp scoped_transactions(socket) do
    socket.assigns.current_scope.organization_id
    |> Payments.list_transactions()
    |> SiteScoping.for_current_site(socket.assigns.current_scope)
    |> filter_by_portal(socket.assigns.portal)
  end

  defp transaction_detail(socket, payment) do
    organization_id = socket.assigns.current_scope.organization_id

    lab_order =
      payment.lab_order_id && LabOrders.get_lab_order!(organization_id, payment.lab_order_id)

    patient =
      lab_order &&
        organization_id
        |> PatientVisits.get_patient_visit!(lab_order.patient_visit_id)
        |> then(&Patients.get_patient!(organization_id, &1.patient_id))

    items =
      if lab_order do
        organization_id
        |> LabOrders.list_lab_order_results_for_order(lab_order.id)
        |> Enum.map(fn result ->
          %{
            name: (result.lab_test && result.lab_test.name) || "Lab test",
            qty: 1,
            amount: result.lab_test && result.lab_test.price
          }
        end)
      else
        []
      end

    %{
      payment: payment,
      lab_order: lab_order,
      patient: patient,
      items: items,
      site: Map.get(socket.assigns.sites_by_id, payment.site_id),
      time: payment.paid_at || payment.inserted_at
    }
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      site: Map.get(filter_params, "site", ""),
      method: Map.get(filter_params, "method", ""),
      status: Map.get(filter_params, "status", ""),
      date_from: Map.get(filter_params, "date_from", ""),
      date_to: Map.get(filter_params, "date_to", ""),
      search: socket.assigns.filters.search
    }

    {:noreply, socket |> assign(:filters, filters) |> reload_transactions()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_transactions()}
  end

  def handle_event("search_transactions", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | search: search})
     |> reload_transactions()}
  end

  def handle_event("clear_chip", %{"field" => field}, socket) do
    key = String.to_existing_atom(field)

    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | key => ""}) |> reload_transactions()}
  end

  defp reload_transactions(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    transactions =
      organization_id
      |> Payments.list_transactions()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)
      |> filter_by_portal(socket.assigns.portal)
      |> filter_by_site(socket.assigns.filters.site)
      |> filter_by_method(socket.assigns.filters.method)
      |> filter_by_status(socket.assigns.filters.status)
      |> filter_by_date_range(socket.assigns.filters.date_from, socket.assigns.filters.date_to)
      |> filter_by_search(
        Map.get(socket.assigns.filters, :search, ""),
        socket.assigns.sites_by_id
      )

    socket
    |> stream(:transactions, transactions, reset: true)
  end

  defp filter_by_portal(transactions, :pharmacy),
    do: Enum.filter(transactions, &(&1.order_type in [:prescription, :sale]))

  defp filter_by_portal(transactions, :lab),
    do: Enum.filter(transactions, &(&1.order_type == :lab_order))

  defp filter_by_portal(transactions, :organization), do: transactions

  defp portal_for(:pharmacy), do: :pharmacy
  defp portal_for(:lab), do: :lab
  defp portal_for(:lab_show), do: :lab
  defp portal_for(:lab_receipt), do: :lab
  defp portal_for(_), do: :organization

  defp portal_path(:pharmacy), do: "/pharmacy/transactions"
  defp portal_path(:lab), do: "/lab/transactions"
  defp portal_path(:organization), do: "/org/earnings"

  defp portal_title(:pharmacy), do: "Pharmacy transactions"
  defp portal_title(:lab), do: "Lab transactions"
  defp portal_title(:organization), do: "Transactions"

  defp portal_description(:pharmacy),
    do: "Review quick sale and prescription payments recorded at your pharmacy."

  defp portal_description(:lab),
    do: "Review payments recorded for laboratory orders at your site."

  defp portal_description(:organization),
    do: "Completed earnings by site and the full payment ledger behind your revenue."

  attr :portal, :atom, required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  slot :inner_block, required: true

  defp portal_shell(%{portal: :pharmacy} = assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={portal_path(@portal)}
    >
      {render_slot(@inner_block)}
    </Layouts.pharmacy_shell>
    """
  end

  defp portal_shell(%{portal: :lab} = assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={portal_path(@portal)}
    >
      {render_slot(@inner_block)}
    </Layouts.lab_shell>
    """
  end

  defp portal_shell(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={portal_path(@portal)}
    >
      {render_slot(@inner_block)}
    </Layouts.org_shell>
    """
  end

  defp filter_by_site(transactions, ""), do: transactions

  defp filter_by_site(transactions, site_id_str),
    do: Enum.filter(transactions, &(to_string(&1.site_id) == site_id_str))

  defp filter_by_method(transactions, ""), do: transactions

  defp filter_by_method(transactions, method),
    do: Enum.filter(transactions, &(&1.payment_type == method))

  defp filter_by_status(transactions, ""), do: transactions

  defp filter_by_status(transactions, status_str),
    do: Enum.filter(transactions, &(to_string(&1.status) == status_str))

  defp filter_by_date_range(transactions, "", ""), do: transactions

  defp filter_by_date_range(transactions, date_from, date_to) do
    from_date = parse_date(date_from)
    to_date = parse_date(date_to)

    Enum.filter(transactions, &date_in_range?(&1, from_date, to_date))
  end

  defp filter_by_search(transactions, search, _sites_by_id) when search in [nil, ""],
    do: transactions

  defp filter_by_search(transactions, search, sites_by_id) do
    query = search |> String.trim() |> String.downcase()

    if query == "" do
      transactions
    else
      Enum.filter(transactions, &matches_search?(&1, query, sites_by_id))
    end
  end

  defp matches_search?(payment, query, sites_by_id) do
    site = Map.get(sites_by_id, payment.site_id)

    [
      payment.provider_reference,
      payment.payment_type,
      payment.status,
      payment.order_type,
      payment.amount,
      payment.id,
      site && site.name
    ]
    |> Enum.any?(&search_value_matches?(&1, query))
  end

  defp search_value_matches?(value, query) do
    value
    |> to_string()
    |> String.downcase()
    |> String.contains?(query)
  end

  defp date_in_range?(transaction, from_date, to_date) do
    date = DateTime.to_date(transaction.inserted_at)

    (is_nil(from_date) or Date.compare(date, from_date) != :lt) and
      (is_nil(to_date) or Date.compare(date, to_date) != :gt)
  end

  defp parse_date(""), do: nil

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp active_filter_count(filters) do
    Enum.count(
      [
        filters.site != "",
        filters.method != "",
        filters.status != "",
        filters.date_from != "",
        filters.date_to != ""
      ],
      & &1
    )
  end

  defp filter_chips(filters, sites_by_id) do
    [
      filters.site != "" &&
        %{label: "Site: #{site_label(filters.site, sites_by_id)}", field: "site"},
      filters.method != "" && %{label: "Method: #{filters.method}", field: "method"},
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"},
      filters.date_from != "" && %{label: "From: #{filters.date_from}", field: "date_from"},
      filters.date_to != "" && %{label: "To: #{filters.date_to}", field: "date_to"}
    ]
    |> Enum.filter(& &1)
  end

  defp site_label(site_id_str, sites_by_id) do
    case sites_by_id[String.to_integer(site_id_str)] do
      nil -> site_id_str
      site -> site.name
    end
  end

  defp site_name(sites_by_id, site_id) do
    case sites_by_id[site_id] do
      nil -> "—"
      site -> site.name
    end
  end

  defp order_link(%Payment{order_type: :prescription, prescription_id: id})
       when is_integer(id),
       do: {"Prescription ##{id}", ~p"/pharmacy/prescriptions/#{id}"}

  defp order_link(%Payment{order_type: :lab_order, lab_order_id: id}) when is_integer(id),
    do: {"Lab order ##{id}", ~p"/lab/orders/#{id}"}

  defp order_link(%Payment{order_type: :sale, sale_id: id}) when is_integer(id),
    do: {"Quick sale ##{id}", nil}

  defp order_link(%Payment{id: id}), do: {"Payment ##{id}", nil}

  defp method_label(%{payment_type: type}) when is_binary(type) and type != "",
    do: Phoenix.Naming.humanize(type)

  defp method_label(_), do: "Payment"

  defp reference_label(%{payment_type: type}) when is_binary(type) do
    if String.contains?(String.downcase(type), ["mpesa", "m-pesa", "mobile"]),
      do: "M-Pesa reference",
      else: "Reference"
  end

  defp reference_label(_), do: "Reference"

  defp receipt_number(%{provider_reference: ref}) when is_binary(ref) and ref != "",
    do: "TD-R-" <> String.slice(String.upcase(ref), -6, 6)

  defp receipt_number(%{id: id}), do: "TD-R-" <> String.pad_leading(to_string(id), 6, "0")

  defp status_tone(:completed), do: "success"
  defp status_tone(:failed), do: "danger"
  defp status_tone(_), do: "warning"

  attr :selected, :map, required: true

  defp transaction_modal(assigns) do
    ~H"""
    <.modal
      id="transaction-modal"
      show
      class="td-txn-modal"
      title={"Payment #{ThamaniDawaWeb.Money.ksh(@selected.payment.amount)}"}
      subtitle={"#{method_label(@selected.payment)} · #{ThamaniDawaWeb.TimeFormat.datetime(@selected.time)}"}
      on_cancel={JS.patch(~p"/lab/transactions")}
    >
      <div class="td-modal-form">
        <div class="td-amt">
          <div class="flex flex-col gap-2">
            <span class="td-s12">Amount paid</span>
            <b class="td-amt-value">{ThamaniDawaWeb.Money.ksh(@selected.payment.amount)}</b>
          </div>
          <div class="pb-1">
            <.td_badge
              tone={status_tone(@selected.payment.status)}
              label={Phoenix.Naming.humanize(@selected.payment.status)}
            />
          </div>
        </div>

        <div :if={@selected.patient} class="td-card td-txn-party">
          <span class="td-person">
            <.td_orb seed={to_string(@selected.patient.id)} size={28} />
            <span class="flex flex-col gap-1">
              <b class="font-medium">{@selected.patient.full_name}</b>
              <span class="td-s12">Patient<span :if={@selected.patient.phone}> · {@selected.patient.phone}</span></span>
            </span>
          </span>
          <span class="flex-1"></span>
          <.link
            :if={@selected.lab_order}
            id="transaction-order-link"
            navigate={~p"/lab/orders/#{@selected.lab_order.id}"}
            class="td-link inline-flex items-center gap-1.5"
          >
            <span class="td-mono">{LabOrders.reference(@selected.lab_order)}</span>
            <.td_icon name="arrow-up-right" class="size-3.5" />
          </.link>
        </div>

        <dl class="td-kv-grid">
          <div class="td-kv">
            <dt class="td-kv-label">{reference_label(@selected.payment)}</dt>
            <dd class="td-kv-value is-mono">{@selected.payment.provider_reference || "—"}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Method</dt>
            <dd class="td-kv-value">{method_label(@selected.payment)}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Phone</dt>
            <dd class="td-kv-value">{(@selected.patient && @selected.patient.phone) || "—"}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Site</dt>
            <dd class="td-kv-value">{(@selected.site && @selected.site.name) || "—"}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Status</dt>
            <dd class="td-kv-value">{Phoenix.Naming.humanize(@selected.payment.status)}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Time</dt>
            <dd class="td-kv-value">{ThamaniDawaWeb.TimeFormat.datetime(@selected.time)}</dd>
          </div>
        </dl>

        <div :if={@selected.items != []} class="td-card">
          <table class="td-mini-table">
            <thead>
              <tr>
                <th>Item</th><th class="is-num">Qty</th><th class="is-num">Amount</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @selected.items}>
                <td>{item.name}</td>
                <td class="is-num">{item.qty}</td>
                <td class="is-num">{ThamaniDawaWeb.Money.ksh(item.amount)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <:footer>
        <div class="td-txn-more">
          <.td_icon_button
            id="transaction-more"
            label="More actions"
            aria-haspopup="menu"
            phx-click={JS.toggle(to: "#transaction-more-menu")}
          >
            <:icon><.td_icon name="dots-three" /></:icon>
          </.td_icon_button>
          <div
            id="transaction-more-menu"
            class="td-popover td-txn-menu"
            role="menu"
            hidden
            phx-click-away={JS.hide(to: "#transaction-more-menu")}
          >
            <button
              id="transaction-refund"
              type="button"
              role="menuitem"
              class="td-menu-item is-danger"
              disabled
              aria-disabled="true"
              title="Refunds are not available yet"
            >
              <.td_icon name="arrow-counter-clockwise" /> Refund
            </button>
            <p class="td-note px-2 pb-1">Refunds are not available yet.</p>
          </div>
        </div>
        <span class="flex-1"></span>
        <.td_button type="button" phx-click={JS.patch(~p"/lab/transactions")}>Close</.td_button>
        <.td_button
          id="print-receipt-button"
          variant="primary"
          type="button"
          glyph="printer"
          patch={~p"/lab/transactions/#{@selected.payment.id}/receipt"}
        >
          Print receipt
        </.td_button>
      </:footer>
    </.modal>
    """
  end

  attr :selected, :map, required: true

  defp receipt_sheet(assigns) do
    ~H"""
    <.modal
      id="receipt-modal"
      show
      size="confirm"
      class="td-receipt-modal"
      on_cancel={JS.patch(~p"/lab/transactions/#{@selected.payment.id}")}
    >
      <div id="lab-receipt" class="td-receipt">
        <div class="flex items-center justify-between">
          <img src={~p"/images/logo-transparent.png"} alt="Thamani Dawa" class="h-3.5" />
          <span class="td-s12">{(@selected.site && @selected.site.name) || ""}</span>
        </div>
        <div class="td-rc-ln">
          <span class="td-rc-muted">Receipt</span><span class="td-mono">{receipt_number(
            @selected.payment
          )}</span>
        </div>
        <div :if={@selected.lab_order} class="td-rc-ln">
          <span class="td-rc-muted">Order</span><span class="td-mono">{LabOrders.reference(
            @selected.lab_order
          )}</span>
        </div>
        <div :if={@selected.patient} class="td-rc-ln">
          <span class="td-rc-muted">Patient</span><span>{@selected.patient.full_name}</span>
        </div>
        <div class="td-rc-ln">
          <span class="td-rc-muted">Time</span><span>{ThamaniDawaWeb.TimeFormat.datetime(
            @selected.time
          )}</span>
        </div>
        <div class="td-rc-dash"></div>
        <div :for={item <- @selected.items} class="td-rc-ln">
          <span>{item.name} × {item.qty}</span><span>{ThamaniDawaWeb.Money.ksh(item.amount)}</span>
        </div>
        <div :if={@selected.items != []} class="td-rc-dash"></div>
        <div class="td-rc-ln is-total">
          <span>Total paid</span><span>{ThamaniDawaWeb.Money.ksh(@selected.payment.amount)}</span>
        </div>
        <div :if={@selected.payment.provider_reference} class="td-rc-ln">
          <span class="td-rc-muted">{method_label(@selected.payment)}</span><span class="td-mono">{@selected.payment.provider_reference}</span>
        </div>
        <span class="td-s12 td-rc-foot">Powered by Thamani Dawa</span>
      </div>
      <:footer>
        <.td_button type="button" phx-click={JS.patch(~p"/lab/transactions/#{@selected.payment.id}")}>
          Close
        </.td_button>
        <.td_button
          id="print-receipt"
          variant="primary"
          type="button"
          glyph="printer"
          onclick="window.print()"
        >
          Print
        </.td_button>
      </:footer>
    </.modal>
    """
  end

  def render(assigns) do
    ~H"""
    <.portal_shell portal={@portal} flash={@flash} current_scope={@current_scope}>
      <.header icon="hero-banknotes">
        {portal_title(@portal)}
        <:subtitle>
          {portal_description(@portal)}
        </:subtitle>
        <:toolbar>
          <form id="transaction-search-form" phx-change="search_transactions" class="min-w-0">
            <.search_input
              name="search"
              value={@filters.search}
              placeholder="Search method, reference, amount, or order"
            />
          </form>
          <.filter_drawer
            id="earnings-filters"
            title="Filter transactions"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group :if={@show_site_filter?} label="Site">
              <.input
                type="select"
                name="filters[site]"
                value={@filters.site}
                options={@site_options}
                prompt="All sites"
              />
            </:group>
            <:group label="Method">
              <.input
                type="select"
                name="filters[method]"
                value={@filters.method}
                options={@method_options}
                prompt="All methods"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={@status_options}
                prompt="All statuses"
              />
            </:group>
            <:group label="Date">
              <.date_range_picker
                id="earnings-filter-dates"
                from_name="filters[date_from]"
                from_value={@filters.date_from}
                to_name="filters[date_to]"
                to_value={@filters.date_to}
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @sites_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.table
        id="transactions"
        rows={@streams.transactions}
        row_click={
          if @portal == :lab,
            do: fn {_id, payment} -> JS.patch(~p"/lab/transactions/#{payment.id}") end
        }
      >
        <:col :let={{_id, payment}} label="Date">
          {ThamaniDawaWeb.TimeFormat.datetime(payment.inserted_at)}
        </:col>
        <:col :let={{_id, payment}} :if={@multi_site?} label="Site">
          {site_name(@sites_by_id, payment.site_id)}
        </:col>
        <:col :let={{_id, payment}} label="Method">{payment.payment_type}</:col>
        <:col :let={{_id, payment}} label="Amount">{ThamaniDawaWeb.Money.ksh(payment.amount)}</:col>
        <:col :let={{_id, payment}} label="Status">
          <.status_badge status={payment.status} />
        </:col>
        <:col :let={{_id, payment}} label="Order">
          <% {label, path} = order_link(payment) %>
          <%= if path do %>
            <.link navigate={path} class="link">{label}</.link>
          <% else %>
            <span>{label}</span>
          <% end %>
        </:col>
        <:empty_state>
          <.blank_state
            icon="hero-banknotes"
            title={
              if active_filter_count(@filters) > 0,
                do: "No transactions match your filters",
                else: "No transactions yet"
            }
          >
            {if active_filter_count(@filters) > 0,
              do: "Try a different date range, or clear the applied filters.",
              else: "Completed, pending, and failed payments will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.transaction_modal :if={@live_action == :lab_show && @selected} selected={@selected} />
      <.receipt_sheet :if={@live_action == :lab_receipt && @selected} selected={@selected} />
    </.portal_shell>
    """
  end
end
