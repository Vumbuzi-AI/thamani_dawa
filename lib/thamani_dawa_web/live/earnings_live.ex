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
     |> assign(:organization_total, Payments.organization_earnings(organization_id))
     |> assign(:site_totals, if(multi_site?, do: site_totals(organization_id, sites), else: []))
     |> assign(:multi_site?, multi_site?)
     |> assign(
       :show_site_filter?,
       multi_site? and is_nil(socket.assigns.current_scope.current_site_id)
     )
     |> assign(:filters, @default_filters)
     |> reload_transactions()}
  end

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:portal, portal_for(socket.assigns.live_action))
     |> reload_transactions()}
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

  defp site_totals(organization_id, sites) do
    totals_by_site_id = Payments.site_earnings_by_site(organization_id)

    sites
    |> Enum.map(&%{site: &1, amount: Map.get(totals_by_site_id, &1.id, Decimal.new(0))})
    |> Enum.sort_by(& &1.site.name)
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

    earned =
      transactions
      |> Enum.filter(&(&1.status == :completed))
      |> Enum.reduce(Decimal.new(0), &Decimal.add(&2, &1.amount))

    socket
    |> assign(:transaction_count, length(transactions))
    |> assign(:filtered_earned, earned)
    |> stream(:transactions, transactions, reset: true)
  end

  defp filter_by_portal(transactions, :pharmacy),
    do: Enum.filter(transactions, &(&1.order_type == :prescription))

  defp filter_by_portal(transactions, :lab),
    do: Enum.filter(transactions, &(&1.order_type == :lab_order))

  defp filter_by_portal(transactions, :organization), do: transactions

  defp portal_for(:pharmacy), do: :pharmacy
  defp portal_for(:lab), do: :lab
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

  defp order_link(%Payment{order_type: :prescription, prescription_id: id}),
    do: {"Prescription ##{id}", ~p"/pharmacy/prescriptions/#{id}"}

  defp order_link(%Payment{order_type: :lab_order, lab_order_id: id}),
    do: {"Lab order ##{id}", ~p"/lab/orders/#{id}"}

  def render(assigns) do
    ~H"""
    <.portal_shell portal={@portal} flash={@flash} current_scope={@current_scope}>
      <.header icon="hero-banknotes">
        {portal_title(@portal)}
        <:subtitle>
          {portal_description(@portal)}
        </:subtitle>
      </.header>

      <div :if={@portal == :organization} class="mb-5">
        <h2 class="text-lg font-semibold text-thamani-forest">Financial activity</h2>
        <p class="mt-1 text-sm text-thamani-pewter">
          <%= if @multi_site? do %>
            Completed earnings by site and the full payment ledger.
          <% else %>
            Completed earnings and the full payment ledger.
          <% end %>
        </p>
      </div>

      <section id="earnings-summary" class="dashboard-stat-grid mb-6">
        <.stat_tile
          :if={@portal == :organization}
          icon="hero-banknotes"
          label="Total earned"
          value={"KES #{@organization_total}"}
          sublabel={if @multi_site?, do: "All sites combined", else: "Completed earnings"}
        />
        <div
          :for={site_total <- @site_totals}
          :if={@portal == :organization}
          id={"site-earnings-#{site_total.site.id}"}
        >
          <.stat_tile
            icon="hero-building-office-2"
            label={site_total.site.name}
            value={"KES #{site_total.amount}"}
            sublabel="Completed earnings"
          />
        </div>
        <.stat_tile
          :if={@portal != :organization}
          icon="hero-banknotes"
          label="Collected"
          value={"KES #{@filtered_earned}"}
          sublabel="Completed payments in this view"
        />
        <.stat_tile
          :if={@portal != :organization}
          icon="hero-receipt-percent"
          label="Transactions"
          value={@transaction_count}
          sublabel="Payments in this view"
        />
      </section>

      <.header>
        Transaction history
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
            <:group label="From date">
              <.input type="date" name="filters[date_from]" value={@filters.date_from} />
            </:group>
            <:group label="To date">
              <.input type="date" name="filters[date_to]" value={@filters.date_to} />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @sites_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.table id="transactions" rows={@streams.transactions}>
        <:col :let={{_id, payment}} label="Date">
          {Calendar.strftime(payment.inserted_at, "%Y-%m-%d %H:%M")}
        </:col>
        <:col :let={{_id, payment}} :if={@multi_site?} label="Site">
          {site_name(@sites_by_id, payment.site_id)}
        </:col>
        <:col :let={{_id, payment}} label="Method">{payment.payment_type}</:col>
        <:col :let={{_id, payment}} label="Amount">KES {payment.amount}</:col>
        <:col :let={{_id, payment}} label="Status">
          <.status_badge status={payment.status} />
        </:col>
        <:col :let={{_id, payment}} label="Order">
          <% {label, path} = order_link(payment) %>
          <.link navigate={path} class="link">{label}</.link>
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
    </.portal_shell>
    """
  end
end
