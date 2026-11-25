defmodule ThamaniDawaWeb.SiteLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)

    socket =
      socket
      |> assign(:site, site)
      |> assign(:near_expiry_days, @near_expiry_days)
      |> assign(:staff, Accounts.list_users_for_site(organization_id, site.id))
      |> assign(:top_products, Dashboards.top_dispensed_products(organization_id, site.id, 8))
      |> assign(:sales_by_method, Payments.sales_by_payment_method(organization_id, site.id))
      |> assign(:return_to, ~p"/org/sites")
      |> assign(:back_label, "Back to Sites")
      |> assign_range("today")
      |> load_pharmacy(organization_id, site)
      |> load_lab(organization_id, site)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    default = ~p"/org/sites"
    return_to = ThamaniDawaWeb.ReturnTo.safe(params["return_to"], default)

    back_label =
      if return_to == ~p"/org/dashboard", do: "Back to Dashboard", else: "Back to Sites"

    {:noreply,
     socket
     |> assign(:tab, tab_from_params(params, socket.assigns.site))
     |> assign(:return_to, return_to)
     |> assign(:back_label, back_label)}
  end

  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign_range(socket, range)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = socket.assigns.site.id
    dates = socket.assigns.dates

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_active, true)
     |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, query))
     |> assign(
       :search_results,
       Dashboards.search_admin_dashboard(organization_id, query, dates, site_id)
     )}
  end

  def handle_event("activate_search", _params, socket) do
    {:noreply, assign(socket, :search_active, true)}
  end

  def handle_event("dismiss_search", _params, socket) do
    {:noreply, assign(socket, :search_active, false)}
  end

  def handle_event("clear_search", _params, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = socket.assigns.site.id
    dates = socket.assigns.dates

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_active, false)
     |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, ""))
     |> assign(:search_results, %{patients: [], sites: [], staff: [], visits: []})}
  end

  def handle_event("toggle_filters", _params, socket) do
    {:noreply, update(socket, :show_filters, &(!&1))}
  end

  def handle_event("reset_filters", _params, socket) do
    {:noreply, assign_range(socket, "this_month")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign_range(socket, "this_month")}
  end

  def handle_event("apply_custom_range", %{"from" => from_str, "to" => to_str}, socket) do
    with {:ok, from_date} <- parse_date(from_str),
         {:ok, to_date} <- parse_date(to_str),
         {:ok, dates} <- Dashboards.validate_custom_range(from_date, to_date) do
      scope = socket.assigns.current_scope
      organization_id = scope.organization_id
      site_id = socket.assigns.site.id
      search_query = socket.assigns.search_query

      {:noreply,
       socket
       |> assign(:range, "custom")
       |> assign(:dates, dates)
       |> assign(:show_filters, false)
       |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, search_query))
       |> assign(
         :search_results,
         Dashboards.search_admin_dashboard(organization_id, search_query, dates, site_id)
       )
       |> assign(
         :daily_revenue,
         Dashboards.daily_revenue(organization_id, site_id, elem(dates, 0), elem(dates, 1))
       )
       |> assign(:monthly_revenue, Dashboards.monthly_revenue(organization_id, site_id))}
    else
      {:error, :reversed} ->
        {:noreply, put_flash(socket, :error, "Date From must be on or before Date To.")}

      {:error, :future} ->
        {:noreply, put_flash(socket, :error, "Date range cannot include future dates.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Enter a valid from and to date")}
    end
  end

  def handle_event("apply_custom_range", _params, socket) do
    {:noreply, put_flash(socket, :error, "Enter a valid from and to date")}
  end

  defp tab_from_params(%{"tab" => "lab"}, site),
    do: if(Site.lab?(site), do: :lab, else: default_tab(site))

  defp tab_from_params(%{"tab" => "pharmacy"}, site),
    do: if(Site.pharmacy?(site), do: :pharmacy, else: default_tab(site))

  defp tab_from_params(_params, site), do: default_tab(site)

  defp default_tab(site) do
    cond do
      Site.pharmacy?(site) -> :pharmacy
      Site.lab?(site) -> :lab
      true -> nil
    end
  end

  defp assign_range(socket, range) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = socket.assigns.site.id
    dates = Dashboards.range_dates(range)
    search_query = Map.get(socket.assigns, :search_query, "")

    socket
    |> assign(:range, range)
    |> assign(:dates, dates)
    |> assign(:show_filters, false)
    |> assign(:search_query, search_query)
    |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, search_query))
    |> assign(
      :search_results,
      Dashboards.search_admin_dashboard(organization_id, search_query, dates, site_id)
    )
    |> assign(
      :daily_revenue,
      Dashboards.daily_revenue(organization_id, site_id, elem(dates, 0), elem(dates, 1))
    )
    |> assign(:monthly_revenue, Dashboards.monthly_revenue(organization_id, site_id))
  end

  defp parse_date(date_str) when is_binary(date_str) do
    cond do
      date_str == "" ->
        {:error, :empty}

      String.match?(date_str, ~r/^\d{4}-\d{2}-\d{2}$/) ->
        Date.from_iso8601(date_str)

      String.match?(date_str, ~r/^\d{2}\/\d{2}\/\d{4}$/) ->
        case String.split(date_str, "/") do
          [m, d, y] -> Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d))
          _ -> {:error, :invalid}
        end

      true ->
        Date.from_iso8601(date_str)
    end
  end

  defp parse_date(%Date{} = d), do: {:ok, d}
  defp parse_date(_), do: {:error, :invalid}

  defp clinical?(site), do: Site.pharmacy?(site) or Site.lab?(site)

  defp money(amount), do: ThamaniDawaWeb.Money.ksh(amount)

  defp day_axis(date), do: ThamaniDawaWeb.TimeFormat.month_day(date)

  defp amount_to_decimal(%Decimal{} = d), do: d
  defp amount_to_decimal(n) when is_number(n), do: Decimal.new(n)
  defp amount_to_decimal(_), do: Decimal.new(0)

  defp humanize_method(value) when is_atom(value), do: Phoenix.Naming.humanize(value)
  defp humanize_method(value), do: to_string(value)

  defp method_rows(rows) do
    total =
      rows
      |> Enum.map(&(&1 |> elem(1) |> amount_to_decimal()))
      |> Enum.reduce(Decimal.new(0), &Decimal.add/2)

    Enum.map(rows, fn {label, amount} ->
      amount = amount_to_decimal(amount)

      pct =
        if Decimal.compare(total, 0) == :eq do
          0
        else
          amount
          |> Decimal.div(total)
          |> Decimal.mult(Decimal.new(100))
          |> Decimal.round(0)
          |> Decimal.to_integer()
        end

      %{label: humanize_method(label), amount: amount, pct: pct}
    end)
  end

  defp load_pharmacy(socket, organization_id, site) do
    if Site.pharmacy?(site) do
      products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})
      batches = Batches.list_active_batches_for_site(organization_id, site.id)

      pending_prescriptions =
        organization_id
        |> Prescriptions.list_prescriptions()
        |> SiteScoping.for_site(site.id)
        |> Enum.filter(&(&1.status in [:pending, :partially_dispensed]))

      socket
      |> assign(:products_by_id, products_by_id)
      |> assign(:low_stock, low_stock(batches, products_by_id))
      |> assign(:near_expiry, near_expiry(batches))
      |> assign(:pending_prescriptions, pending_prescriptions)
    else
      socket
    end
  end

  defp load_lab(socket, organization_id, site) do
    if Site.lab?(site) do
      lab_orders =
        organization_id
        |> LabOrders.list_lab_orders_with_patient()
        |> SiteScoping.for_site(site.id)

      socket
      |> assign(:pending_orders, Enum.filter(lab_orders, &(&1.status == :pending)))
      |> assign(
        :incomplete_orders,
        Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress]))
      )
      |> assign(:lab_orders_by_day, Dashboards.lab_orders_by_day(organization_id, site.id))
    else
      socket
    end
  end

  defp low_stock(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, total} ->
      product && product.reorder_level && total <= product.reorder_level
    end)
  end

  defp near_expiry(batches) do
    today = Date.utc_today()

    batches
    |> Enum.filter(&(Date.diff(&1.expiry_date, today) in 0..@near_expiry_days))
    |> Enum.sort_by(& &1.expiry_date, Date)
  end

  defp product_name(products_by_id, product_id) do
    product_display_name(products_by_id[product_id])
  end

  defp product_display_name(nil), do: "(unknown product)"

  defp product_display_name(product),
    do: product.generic_name || product.brand_name || "(unnamed)"

  defp patient_name(%{patient_visit: %{patient: patient}}) when not is_nil(patient),
    do: patient.full_name

  defp patient_name(_lab_order), do: "(unknown patient)"

  defp activity_labels(site) do
    Enum.map_join(site.activities, ", ", &Phoenix.Naming.humanize/1)
  end

  defp tab_path(site, tab, return_to) do
    path = ~p"/org/sites/#{site.id}?tab=#{tab}"

    if return_to in [nil, "", ~p"/org/sites"],
      do: path,
      else: ThamaniDawaWeb.ReturnTo.with_query(path, return_to)
  end

  defp site_subtitle(site) do
    gln = if is_binary(site.gln) and site.gln != "", do: site.gln, else: "—"
    address = site.address |> to_string() |> String.trim()
    parts = [activity_labels(site), "GLN #{gln}"]
    parts = if address != "", do: parts ++ [address], else: parts
    Enum.join(parts, " · ")
  end

  defp range_chip_label("custom", {from, to}) do
    "#{ThamaniDawaWeb.TimeFormat.date(from)} – #{ThamaniDawaWeb.TimeFormat.date(to)}"
  end

  defp range_chip_label(range, _dates) do
    Dashboards.ranges() |> Enum.into(%{}) |> Map.get(range, "Today")
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:range_label, range_chip_label(assigns.range, assigns.dates))
      |> assign(
        :daily_bars,
        chart_bars(Map.get(assigns, :daily_revenue, []),
          label_fun: &day_axis/1,
          tick_every: 7,
          grain: :day,
          format: :money
        )
      )
      |> assign(:daily_y, chart_y_labels(Map.get(assigns, :daily_revenue, [])))
      |> assign(:method_rows, method_rows(Map.get(assigns, :sales_by_method, [])))
      |> assign(:clinical?, clinical?(assigns.site))

    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/sites"}
      back={@return_to}
      back_label={@back_label}
      crumb={@site.name}
      crumb_parent="Sites"
    >
      <.td_dashboard id="site-dashboard" title={@site.name} subtitle={site_subtitle(@site)}>
        <:status>
          <.td_badge :if={@site.is_active} tone="success" label="Active" />
          <.td_badge :if={!@site.is_active} tone="neutral" label="Inactive" />
        </:status>
        <:actions>
          <div id="site-dashboard-range-filter" class="td-view-menu">
            <button
              type="button"
              id="site-dashboard-range-filter-trigger"
              class="td-chip td-view-menu-trigger"
              aria-haspopup="menu"
              aria-expanded="false"
              phx-click={
                JS.toggle(to: "#site-dashboard-range-filter-menu")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"},
                  to: "#site-dashboard-range-filter-trigger"
                )
              }
            >
              <.td_icon name="calendar-blank" class="size-3.5" />
              <span>Date range</span>
              <span class="td-chip-value">{@range_label}</span>
              <.td_icon name="caret-down" class="size-3.5" />
            </button>
            <div
              id="site-dashboard-range-filter-menu"
              class="td-popover td-view-menu-pop hidden"
              role="menu"
              phx-click-away={JS.hide(to: "#site-dashboard-range-filter-menu")}
            >
              <p class="td-popover-label">Date range</p>
              <button
                :for={{key, label} <- Dashboards.ranges()}
                type="button"
                role="menuitem"
                class={["td-menu-item", key == @range && "is-selected"]}
                phx-click={
                  JS.hide(to: "#site-dashboard-range-filter-menu")
                  |> JS.push("set_range", value: %{range: key})
                }
              >
                <span class="flex-1">{label}</span>
                <.td_icon :if={key == @range} name="check" class="size-3.5" />
              </button>
              <form phx-submit="apply_custom_range" class="td-date-filter-custom">
                <p class="td-popover-label">Custom</p>
                <.date_range_picker
                  id="site-filter-dates"
                  from_name="from"
                  from_value={elem(@dates, 0)}
                  to_name="to"
                  to_value={elem(@dates, 1)}
                  max="today"
                />
                <div class="td-date-filter-ft">
                  <span class="flex-1"></span>
                  <button type="submit" class="td-btn is-primary">Apply</button>
                </div>
              </form>
            </div>
          </div>
          <.td_button
            id="btn-edit-site"
            variant="secondary"
            navigate={~p"/org/sites/#{@site.id}/edit"}
            label="Edit site"
          >
            <:icon><.td_icon name="note-pencil" /></:icon>
          </.td_button>
        </:actions>

        <:strip :if={@clinical?} id="site-dashboard-stats">
          <.td_glance_cell
            id="total-patients-stat"
            value={@stats.total_patients}
            caption="total patients"
            tone="success"
          >
            <:icon><.td_icon name="users" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="patient-visits-stat"
            value={@stats.patient_visits}
            caption="patient visits"
            tone="info"
          >
            <:icon><.td_icon name="calendar-check" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="revenue-collected-stat"
            value={money(@stats.revenue_collected)}
            caption="revenue collected"
            tone="warning"
          >
            <:icon><.td_icon name="wallet" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="staff-assigned-stat"
            value={@stats.active_staff}
            caption="staff assigned"
            tone="neutral"
          >
            <:icon><.td_icon name="identification-badge" /></:icon>
          </.td_glance_cell>
        </:strip>

        <:strip :if={@clinical? and (Site.pharmacy?(@site) or Site.lab?(@site))} id="site-ops-stats">
          <.td_glance_cell
            :if={Site.pharmacy?(@site)}
            id="prescriptions-stat"
            value={@stats.prescriptions}
            caption="prescriptions"
            tone="info"
          >
            <:icon><.td_icon name="clipboard-text" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            :if={Site.pharmacy?(@site)}
            id="pending-prescriptions-stat"
            value={@stats.pending_prescriptions}
            caption="pending prescriptions"
            tone="warning"
          >
            <:icon><.td_icon name="clock" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            :if={Site.lab?(@site)}
            id="lab-orders-stat"
            value={@stats.lab_tests_done}
            caption="lab orders completed"
            tone="success"
          >
            <:icon><.td_icon name="flask" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            :if={Site.lab?(@site)}
            id="pending-lab-orders-stat"
            value={@stats.pending_lab_orders}
            caption="pending lab orders"
            tone="warning"
          >
            <:icon><.td_icon name="clipboard-text" /></:icon>
          </.td_glance_cell>
        </:strip>

        <:strip :if={!@clinical?} id="site-dashboard-stats">
          <.td_glance_cell
            id="staff-assigned-stat"
            value={@stats.active_staff}
            caption="staff assigned"
            tone="neutral"
          >
            <:icon><.td_icon name="identification-badge" /></:icon>
          </.td_glance_cell>
        </:strip>

        <div :if={@clinical?} id="site-analytics-charts">
          <.td_dash_row>
            <.td_dash_card
              id="site-daily-revenue-chart"
              title="Daily revenue"
              subtitle={"Wallet credits collected per day at #{@site.name}"}
            >
              <.td_bars
                id="site-daily-revenue-bars"
                label={"Daily revenue at #{@site.name}"}
                y_labels={@daily_y}
                bars={@daily_bars}
              />
            </.td_dash_card>
            <.td_dash_card
              id={
                if @method_rows == [],
                  do: "site-payment-methods-empty",
                  else: "site-payment-methods-chart"
              }
              title="Payment methods"
              subtitle={"Completed payments at #{@site.name}"}
              width={380}
            >
              <div :if={@method_rows == []} class="td-dash-empty">
                No completed sales yet.
              </div>
              <div :for={row <- @method_rows} class="td-status-row">
                <span class="td-status-copy">
                  <b>{row.label}</b>
                  <span>{money(row.amount)} · {row.pct}%</span>
                </span>
                <.td_ticks count={row.pct} max={100} tone="success" />
              </div>
            </.td_dash_card>
          </.td_dash_row>
        </div>

        <.td_dash_row>
          <.td_dash_card
            :if={Site.pharmacy?(@site)}
            id="pharmacy-stock-overview"
            title="Stock attention"
            subtitle="Inventory that may need action soon"
          >
            <div class="td-card-header">
              <div>
                <h2>Low stock</h2>
                <p>At or below reorder level</p>
              </div>
            </div>
            <table id="site-low-stock" class="td-rows">
              <thead>
                <tr>
                  <th>Product</th>
                  <th class="is-num">Reorder level</th>
                  <th class="is-num">Remaining</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@low_stock == []}>
                  <td colspan="3" class="td-muted">No products are at their reorder level.</td>
                </tr>
                <tr :for={{product, total} <- @low_stock}>
                  <td>{product_display_name(product)}</td>
                  <td class="is-num">{product && product.reorder_level}</td>
                  <td class="is-num">{total}</td>
                </tr>
              </tbody>
            </table>
            <div :if={@near_expiry != []} class="td-card-header">
              <div>
                <h2>Near-expiry batches</h2>
                <p>Expiring within {@near_expiry_days} days</p>
              </div>
            </div>
            <table :if={@near_expiry != []} id="site-near-expiry" class="td-rows">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Batch no.</th>
                  <th>Expiry</th>
                  <th class="is-num">Remaining</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={batch <- @near_expiry}
                  class="is-link"
                  phx-click={JS.navigate(~p"/org/batches/#{batch.id}")}
                >
                  <td>{product_name(@products_by_id, batch.product_id)}</td>
                  <td>{batch.batch_no}</td>
                  <td>{batch.expiry_date}</td>
                  <td class="is-num">{batch.remaining_quantity}</td>
                </tr>
              </tbody>
            </table>
          </.td_dash_card>

          <.td_dash_card
            id="site-team"
            title="Site team"
            subtitle="People currently assigned to this location"
            width={if Site.pharmacy?(@site), do: 380, else: nil}
          >
            <table id="site-staff" class="td-rows">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Role</th>
                </tr>
              </thead>
              <tbody>
                <tr :if={@staff == []}>
                  <td colspan="2" class="td-muted">Staff assigned to this site will appear here.</td>
                </tr>
                <tr :for={user <- @staff}>
                  <td>
                    <span class="td-person">
                      <.td_orb seed={to_string(user.id)} size={24} />
                      {user.name}
                    </span>
                  </td>
                  <td>{Accounts.User.humanize_roles(user.roles)}</td>
                </tr>
              </tbody>
            </table>
          </.td_dash_card>
        </.td_dash_row>
      </.td_dashboard>

      <div
        :if={Site.pharmacy?(@site) and Site.lab?(@site)}
        class="tabs tabs-boxed w-fit mt-6 mb-2 p-1 bg-base-200"
      >
        <.link
          patch={tab_path(@site, :pharmacy, @return_to)}
          class={["tab px-6 font-medium", @tab == :pharmacy && "tab-active"]}
        >
          Pharmacy
        </.link>
        <.link
          patch={tab_path(@site, :lab, @return_to)}
          class={["tab px-6 font-medium", @tab == :lab && "tab-active"]}
        >
          Lab
        </.link>
      </div>

      <div :if={@tab == :pharmacy}>
        <div class="mt-6">
          <.td_card_header
            title="Pending prescriptions"
            subtitle="Prescriptions waiting for pharmacy action"
          />
        </div>
        <.table
          id="site-pending-prescriptions"
          rows={@pending_prescriptions}
          row_click={
            fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end
          }
        >
          <:col :let={prescription} label="Status">
            <.status_badge status={prescription.status} />
          </:col>
          <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
          <:col :let={prescription} label="Paid">
            {if prescription.has_paid, do: "Yes", else: "No"}
          </:col>
          <:empty_state>
            <.blank_state icon="hero-clipboard-document-check" title="No pending prescriptions">
              Prescriptions awaiting dispensing at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@tab == :lab}>
        <div class="mt-6">
          <.td_card_header title="Pending orders" />
        </div>
        <.table
          id="site-pending-orders"
          rows={@pending_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No pending orders">
              New lab orders at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>

        <div class="mt-6">
          <.td_card_header title="Incomplete reports" />
        </div>
        <.table
          id="site-incomplete-orders"
          rows={@incomplete_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Status">
            <.status_badge status={lab_order.status} />
          </:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No incomplete reports">
              Orders still awaiting collection or results will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>
    </Layouts.org_shell>
    """
  end
end
