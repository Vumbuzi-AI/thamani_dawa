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
    back_label = if return_to == ~p"/org/dashboard", do: "Back to Dashboard", else: "Back to Sites"

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

  defp to_date_val(%DateTime{} = dt), do: DateTime.to_date(dt)
  defp to_date_val(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_date(ndt)
  defp to_date_val(%Date{} = d), do: d

  defp money(amount) do
    grouped =
      amount
      |> round()
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

    "KSh " <> grouped
  end

  defp combined_search_items(results) do
    patients =
      Enum.map(Map.get(results, :patients, []), fn p ->
        %{
          type: :patient,
          title: p.full_name,
          subtitle: "Phone: #{p.phone} • DOB: #{p.date_of_birth}",
          badge: "GSRN: #{p.gsrn}",
          icon: "hero-user"
        }
      end)

    staff =
      Enum.map(Map.get(results, :staff, []), fn u ->
        %{
          type: :staff,
          title: u.name,
          subtitle: u.email,
          badge: Accounts.User.humanize_roles(u),
          icon: "hero-users"
        }
      end)

    visits =
      Enum.map(Map.get(results, :visits, []), fn v ->
        %{
          type: :visit,
          title: v.patient_name,
          subtitle: "Date: #{ThamaniDawaWeb.TimeFormat.date(v.inserted_at)}",
          badge: String.capitalize(to_string(v.visit_type)),
          icon: "hero-document-text"
        }
      end)

    patients ++ staff ++ visits
  end

  defp daily_revenue_chart_data(daily_revenue) do
    %{
      labels: Enum.map(daily_revenue, fn {date, _amount} -> ThamaniDawaWeb.TimeFormat.month_day(date) end),
      datasets: [
        %{
          label: "KSh Collected",
          data: Enum.map(daily_revenue, fn {_date, amount} -> amount end),
          borderColor: "#17302a",
          backgroundColor: "rgba(28, 58, 19, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 3
        }
      ]
    }
  end

  defp monthly_revenue_chart_data(monthly_revenue) do
    %{
      labels: Enum.map(monthly_revenue, fn {date, _n} -> ThamaniDawaWeb.TimeFormat.month_year(date) end),
      datasets: [
        %{
          label: "Revenue",
          data: Enum.map(monthly_revenue, fn {_date, n} -> n end),
          backgroundColor: "#707371",
          borderRadius: 4
        }
      ]
    }
  end

  defp chart_options do
    %{
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{legend: %{display: false}},
      scales: %{y: %{beginAtZero: true}}
    }
  end

  defp legend_chart_options do
    %{
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{legend: %{display: true, position: "bottom"}}
    }
  end

  defp horizontal_bar_options do
    %{
      indexAxis: "y",
      responsive: true,
      maintainAspectRatio: false,
      plugins: %{legend: %{display: false}},
      scales: %{x: %{beginAtZero: true, ticks: %{precision: 0}}}
    }
  end

  defp method_chart_data(rows) do
    %{
      labels: Enum.map(rows, &elem(&1, 0)),
      datasets: [
        %{
          data: Enum.map(rows, &Decimal.to_float(elem(&1, 1))),
          backgroundColor: ["#31572c", "#84cc16", "#f59e0b", "#0ea5e9", "#8b5cf6"]
        }
      ]
    }
  end

  defp top_products_chart_data(rows) do
    %{
      labels: Enum.map(rows, &elem(&1, 0)),
      datasets: [
        %{
          label: "Quantity dispensed",
          data: Enum.map(rows, &elem(&1, 1)),
          backgroundColor: "rgba(132, 204, 22, 0.72)",
          borderColor: "#4d7c0f",
          borderWidth: 1,
          borderRadius: 6
        }
      ]
    }
  end

  defp lab_volume_chart_data(rows) do
    %{
      labels: Enum.map(rows, fn {date, _} -> ThamaniDawaWeb.TimeFormat.month_day(date) end),
      datasets: [
        %{
          label: "Lab orders",
          data: Enum.map(rows, fn {_, count} -> count end),
          borderColor: "#6667ab",
          backgroundColor: "rgba(102, 103, 171, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 2
        }
      ]
    }
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
    if return_to in [nil, "", ~p"/org/sites"], do: path, else: ThamaniDawaWeb.ReturnTo.with_query(path, return_to)
  end

  defp site_subtitle(site) do
    gln = if is_binary(site.gln) and site.gln != "", do: site.gln, else: "—"
    "#{activity_labels(site)} · GLN #{gln}"
  end

  defp range_chip_label("custom", {from, to}) do
    "#{ThamaniDawaWeb.TimeFormat.date(from)} – #{ThamaniDawaWeb.TimeFormat.date(to)}"
  end

  defp range_chip_label(range, _dates) do
    Dashboards.ranges() |> Enum.into(%{}) |> Map.get(range, "Today")
  end

  def render(assigns) do
    assigns = assign(assigns, :range_label, range_chip_label(assigns.range, assigns.dates))

    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/sites"}
      back={@return_to}
      back_label={@back_label}
    >
      <div class="td-back">
        <.link navigate={@return_to} class="td-back-link">
          <.td_icon name="arrow-left" class="size-3.5" /> {@back_label}
        </.link>
      </div>
      <.td_page_header title={@site.name} subtitle={site_subtitle(@site)}>
        <:actions>
          <.td_badge
            :if={@site.is_active}
            tone="success"
            label="Active"
          />
          <.td_badge
            :if={!@site.is_active}
            tone="neutral"
            label="Inactive"
          />
          <.td_button
            id="btn-edit-site"
            variant="secondary"
            navigate={~p"/org/sites/#{@site.id}/edit"}
            label="Edit site"
          >
            <:icon><.td_icon name="note-pencil" /></:icon>
          </.td_button>
        </:actions>
      </.td_page_header>

      <div class="td-filter-row mb-4">
        <div class="td-org-dash-search">
          <input
            type="search"
            name="search"
            value={@search_query}
            placeholder={"Search patients, visits, revenue or reports at #{@site.name}..."}
            phx-keyup="search"
            phx-focus="activate_search"
            phx-click="activate_search"
            phx-debounce="250"
            autocomplete="off"
            class="td-input td-org-dash-search-input"
          />
            <div
              :if={
                @search_query != "" and String.trim(@search_query) != "" and
                  Map.get(assigns, :search_active, true)
              }
              class="td-popover td-org-dash-search-pop"
            >
              <% items = combined_search_items(@search_results) %>
              <div class="td-org-dash-search-hd">
                <p class="td-popover-label">Search hits at {@site.name} for "{@search_query}"</p>
                <button type="button" phx-click="clear_search" class="td-text-btn">
                  Clear search
                </button>
              </div>
              <p class="td-org-dash-search-hint">
                Site metrics below filtered for "{@search_query}"
                <span>
                  {@stats.total_patients} patients • {@stats.patient_visits} visits • {money(
                    @stats.revenue_collected
                  )}
                </span>
              </p>
              <div :if={items == []} class="td-empty-inline">
                No matching records found at {@site.name} for "{@search_query}"
              </div>
              <div :for={item <- items} class="td-org-dash-search-item">
                <div>
                  <p class="td-org-dash-search-title">{item.title}</p>
                  <p class="td-muted">{item.subtitle}</p>
                </div>
                <span class="td-chip is-quiet">{item.badge}</span>
              </div>
            </div>
        </div>

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
            class="td-popover td-view-menu-pop"
            role="menu"
            hidden
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
            <button
              type="button"
              role="menuitem"
              class={["td-menu-item", @range == "custom" && "is-selected"]}
              phx-click={
                JS.hide(to: "#site-dashboard-range-filter-menu")
                |> JS.push("toggle_filters")
              }
            >
              <span class="flex-1">Custom…</span>
              <.td_icon :if={@range == "custom"} name="check" class="size-3.5" />
            </button>
          </div>
        </div>

        <div class="relative">
          <button type="button" phx-click="toggle_filters" class="td-chip">
            <.td_icon name="funnel-simple" class="size-3.5" />
            Filters
            <span :if={@range == "custom"} class="td-chip-dot"></span>
          </button>
          <div :if={@show_filters} class="fixed inset-0 z-40" phx-click="toggle_filters" />
          <div :if={@show_filters} class="td-popover td-org-dash-filters absolute right-0 top-full z-50 mt-2">
            <form phx-submit="apply_custom_range">
              <div class="td-org-dash-filters-hd">
                <h3>Filters</h3>
                <button type="button" phx-click="toggle_filters" class="td-icon-btn" aria-label="Close filters">
                  <.td_icon name="x" class="size-3.5" />
                </button>
              </div>
              <p class="td-popover-label">Date range</p>
              <.date_range_picker
                id="site-filter-dates"
                from_name="from"
                from_value={elem(@dates, 0)}
                to_name="to"
                to_value={elem(@dates, 1)}
                max="today"
              />
              <div class="td-org-dash-filters-ft">
                <button type="submit" class="td-btn is-primary">Apply filters</button>
              </div>
            </form>
          </div>
        </div>
      </div>

      <div
        :if={
          @search_query != "" and String.trim(@search_query) != "" and
            Map.get(assigns, :search_active, true)
        }
        class="fixed inset-0 z-30"
        style="background: var(--color-td-scrim);"
        phx-click="dismiss_search"
      />

      <%!-- Site Stat Cards Grid --%>
      <div class="dashboard-stat-grid mt-6">
        <.stat_tile
          icon="hero-user-group"
          label="Total patients"
          value={@stats.total_patients}
          sublabel="Registered patients"
        />
        <.stat_tile
          icon="hero-building-office-2"
          label="Patient visits"
          value={@stats.patient_visits}
          sublabel="Visits in selected window"
        />
        <.stat_tile
          icon="hero-banknotes"
          label="Revenue collected"
          value={money(@stats.revenue_collected)}
          sublabel="Wallet credits at this site"
        />
        <.stat_tile
          icon="hero-users"
          label="Staff assigned"
          value={@stats.active_staff}
          sublabel="Assigned to this site"
        />
        <.stat_tile
          icon="hero-document-text"
          label="Prescriptions"
          value={@stats.prescriptions}
          sublabel="Prescriptions in selected window"
        />
        <.stat_tile
          icon="hero-beaker"
          label="Lab orders completed"
          value={@stats.lab_tests_done}
          sublabel="Completed lab orders at this site"
        />
        <.stat_tile
          icon="hero-clock"
          label="Pending prescriptions"
          value={@stats.pending_prescriptions}
          sublabel="Awaiting dispensing"
        />
        <.stat_tile
          icon="hero-clipboard-document-list"
          label="Pending lab orders"
          value={@stats.pending_lab_orders}
          sublabel="Awaiting results"
        />
      </div>

      <%!-- Revenue Charts Grid --%>
      <div class="dashboard-chart-grid mt-6">
        <.chart_card
          id="site-daily-revenue-chart"
          title="Daily revenue"
          subtitle={"Wallet credits collected per day at #{@site.name} in the selected window"}
          type="line"
          data={daily_revenue_chart_data(@daily_revenue)}
          options={chart_options()}
        />
        <.chart_card
          id="site-monthly-revenue-chart"
          title="Monthly revenue"
          subtitle={"Total wallet credits collected at #{@site.name} in the last 12 months"}
          type="bar"
          data={monthly_revenue_chart_data(@monthly_revenue)}
          options={chart_options()}
        />
        <.chart_card
          :if={@sales_by_method != []}
          id="site-payment-methods-chart"
          title="Payment methods"
          subtitle={"Completed payments at #{@site.name}"}
          type="doughnut"
          data={method_chart_data(@sales_by_method)}
          options={legend_chart_options()}
        />
        <div
          :if={@sales_by_method == []}
          id="site-payment-methods-empty"
          class="dashboard-chart-card"
        >
          <.blank_state icon="hero-credit-card" title="No completed sales yet">
            Once payments complete at this site, their mix will appear here.
          </.blank_state>
        </div>
        <.chart_card
          :if={Site.pharmacy?(@site) and @top_products != []}
          id="site-top-products-chart"
          title="Most dispensed medicines"
          subtitle={"Dispensed at #{@site.name}"}
          type="bar"
          data={top_products_chart_data(@top_products)}
          options={horizontal_bar_options()}
        />
        <div
          :if={Site.pharmacy?(@site) and @top_products == []}
          id="site-top-products-empty"
          class="dashboard-chart-card"
        >
          <.blank_state icon="hero-cube" title="No dispensing activity yet">
            Dispensed products will show up here once prescriptions start being filled.
          </.blank_state>
        </div>
        <.chart_card
          :if={Site.lab?(@site)}
          id="site-lab-volume-chart"
          title="Lab order volume"
          subtitle={"Orders created per day at #{@site.name}, last 30 days"}
          type="line"
          data={lab_volume_chart_data(@lab_orders_by_day)}
          options={chart_options()}
        />
      </div>

      <section id="site-team" class="mt-8">
        <.td_card_header title="Site team" subtitle="People currently assigned to this location" />
        <.table id="site-staff" rows={@staff}>
          <:col :let={user} label="Name">
            <span class="td-person">
              <.td_orb seed={to_string(user.id)} size={24} />
              {user.name}
            </span>
          </:col>
          <:col :let={user} label="Role">{Accounts.User.humanize_roles(user.roles)}</:col>
          <:empty_state>
            <.blank_state icon="hero-users" title="No staff assigned">
              Staff assigned to this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </section>

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
        <section id="pharmacy-stock-overview" class="mt-6">
          <.td_card_header title="Stock attention" subtitle="Inventory that may need action soon" />

          <div class="grid gap-6 xl:grid-cols-2">
            <div class="flex min-w-0 flex-col [&>.responsive-table]:flex-1">
              <div class="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h3 class="font-medium text-thamani-forest">Low stock</h3>
                  <p class="mt-0.5 text-sm text-thamani-pewter">At or below reorder level</p>
                </div>
                <span class="rounded-full bg-td-warning-tint px-2.5 py-1 text-xs font-medium text-td-warning">
                  {length(@low_stock)} items
                </span>
              </div>
              <.table id="site-low-stock" rows={@low_stock}>
                <:col :let={{product, _total}} label="Product">
                  {product_display_name(product)}
                </:col>
                <:col :let={{product, _total}} label="Reorder level">
                  {product && product.reorder_level}
                </:col>
                <:col :let={{_product, total}} label="Remaining">{total}</:col>
                <:empty_state>
                  <.blank_state icon="hero-check-circle" title="Stock levels look healthy">
                    No products are currently at their reorder level.
                  </.blank_state>
                </:empty_state>
              </.table>
            </div>

            <div class="flex min-w-0 flex-col [&>.responsive-table]:flex-1">
              <div class="mb-3 flex items-center justify-between gap-3">
                <div>
                  <h3 class="font-medium text-thamani-forest">Near-expiry batches</h3>
                  <p class="mt-0.5 text-sm text-thamani-pewter">
                    Expiring within {@near_expiry_days} days
                  </p>
                </div>
                <span class="rounded-full bg-td-warning-tint px-2.5 py-1 text-xs font-medium text-td-warning">
                  {length(@near_expiry)} batches
                </span>
              </div>
              <.table
                id="site-near-expiry"
                rows={@near_expiry}
                empty_class="!px-3 !py-3"
                row_click={fn batch -> JS.navigate(~p"/org/batches/#{batch.id}") end}
              >
                <:col :let={batch} label="Product">
                  {product_name(@products_by_id, batch.product_id)}
                </:col>
                <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
                <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
                <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
                <:empty_state>
                  <.blank_state
                    icon="hero-calendar-days"
                    title="No batches expiring soon"
                    class="!border-0 !bg-transparent !py-2 [&>span]:!size-8"
                  >
                    Nothing expires within the next {@near_expiry_days} days.
                  </.blank_state>
                </:empty_state>
              </.table>
            </div>
          </div>
        </section>

        <div class="mt-8">
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

      <div :if={is_nil(@tab)}>
        <.blank_state icon="hero-building-office-2" title="No operations configured" class="mt-6">
          This site has no pharmacy or lab operations to show.
        </.blank_state>
      </div>
    </Layouts.org_shell>
    """
  end
end
