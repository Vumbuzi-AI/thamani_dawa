defmodule ThamaniDawaWeb.OrgDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.{Dashboards, Organizations, Reports, Sites}

  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:auto_start_tour?, params["tour"] == "1")
     |> assign_onboarding()
     |> assign_range("this_month")}
  end

  defp assign_onboarding(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)
    sites = Sites.list_sites(organization_id)
    primary_site = List.first(sites)
    active_sites = Enum.filter(sites, & &1.is_active)

    setup_required? = not site_ready?(primary_site)

    socket
    |> assign(:organization, organization)
    |> assign(:primary_site, primary_site)
    |> assign(:setup_required?, setup_required?)
    |> assign(:pharmacy_metrics?, Enum.any?(active_sites, &Sites.Site.pharmacy?/1))
    |> assign(:lab_metrics?, Enum.any?(active_sites, &Sites.Site.lab?/1))
    |> assign(:site_profitability, Reports.site_profitability(organization_id))
  end

  defp site_ready?(nil), do: false

  defp site_ready?(site) do
    is_binary(site.address) and String.trim(site.address) != "" and not is_nil(site.site_type)
  end

  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign_range(socket, range)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
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
    site_id = scope.current_site_id
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
      site_id = scope.current_site_id
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
        {:noreply,
         put_flash(socket, :error, "Invalid date selection. Please choose valid dates.")}
    end
  end

  def handle_event("apply_custom_range", _params, socket) do
    {:noreply, put_flash(socket, :error, "Please select valid dates.")}
  end

  defp assign_range(socket, range) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
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

  defp format_range_dates({from, to}) do
    "System-wide view for #{Calendar.strftime(from, "%d %b %Y")} to #{Calendar.strftime(to, "%d %b %Y")}"
  end

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

  defp daily_revenue_chart_data(daily_revenue) do
    %{
      labels: Enum.map(daily_revenue, fn {date, _amount} -> Calendar.strftime(date, "%d %b") end),
      datasets: [
        %{
          label: "KSh Collected",
          data: Enum.map(daily_revenue, fn {_date, amount} -> amount end),
          borderColor: "#6667ab",
          backgroundColor: "rgba(102, 103, 171, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 3
        }
      ]
    }
  end

  defp monthly_revenue_chart_data(monthly_revenue) do
    %{
      labels:
        Enum.map(monthly_revenue, fn {date, _amount} -> Calendar.strftime(date, "%b %Y") end),
      datasets: [
        %{
          label: "Revenue",
          data: Enum.map(monthly_revenue, fn {_date, amount} -> amount end),
          backgroundColor: "#6667ab",
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

  defp site_chart_data(rows) do
    %{
      labels: Enum.map(rows, & &1.site.name),
      datasets: [
        %{
          label: "Revenue",
          data: Enum.map(rows, &Decimal.to_float(&1.revenue)),
          backgroundColor: "#84cc16",
          borderRadius: 6
        },
        %{
          label: "Cost of goods",
          data: Enum.map(rows, &Decimal.to_float(&1.cost_of_goods)),
          backgroundColor: "#94a3b8",
          borderRadius: 6
        }
      ]
    }
  end

  defp profit_chart_data(rows) do
    %{
      labels: Enum.map(rows, & &1.site.name),
      datasets: [
        %{
          label: "Profit",
          data: Enum.map(rows, &Decimal.to_float(&1.profit)),
          backgroundColor:
            Enum.map(rows, fn row ->
              if Decimal.negative?(row.profit), do: "#ef4444", else: "#84cc16"
            end),
          borderRadius: 6
        }
      ]
    }
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

    sites =
      Enum.map(Map.get(results, :sites, []), fn s ->
        %{
          type: :site,
          title: s.name,
          subtitle: "#{s.address || "No address"} • Type: #{s.site_type}",
          badge: "GLN: #{s.gln || "N/A"}",
          icon: "hero-building-office-2"
        }
      end)

    staff =
      Enum.map(Map.get(results, :staff, []), fn u ->
        %{
          type: :staff,
          title: u.name,
          subtitle: u.email,
          badge: String.capitalize(to_string(u.role)),
          icon: "hero-users"
        }
      end)

    visits =
      Enum.map(Map.get(results, :visits, []), fn v ->
        %{
          type: :visit,
          title: v.patient_name,
          subtitle:
            "Site: #{v.site_name} • Date: #{Calendar.strftime(to_date_val(v.inserted_at), "%d %b %Y")}",
          badge: String.capitalize(to_string(v.visit_type)),
          icon: "hero-document-text"
        }
      end)

    patients ++ sites ++ staff ++ visits
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/dashboard">
      <%!-- Fixed backdrop blur overlay when search popover is active --%>
      <div
        :if={
          not @setup_required? and @search_query != "" and String.trim(@search_query) != "" and
            Map.get(assigns, :search_active, true)
        }
        class="fixed inset-0 z-30 bg-black/15 backdrop-blur-sm transition-opacity"
        phx-click="dismiss_search"
      />

      <.header :if={not @setup_required?} icon="hero-squares-2x2">
        Admin Dashboard
        <:subtitle>
          {format_range_dates(@dates)}
        </:subtitle>
        <:actions>
          <div id="org-dashboard-range-filter" class="w-full">
            <.range_filter event="set_range" current={@range} ranges={Dashboards.ranges()} />
          </div>
        </:actions>
        <:toolbar>
          <div class="relative flex-1 w-full">
            <input
              type="text"
              name="search"
              value={@search_query}
              phx-keyup="search"
              phx-focus="activate_search"
              phx-click="activate_search"
              phx-debounce="250"
              placeholder="Search patients, visits, revenue or reports..."
              class="thamani-input relative z-40 w-full rounded-xl px-4 py-2.5 text-sm placeholder:text-thamani-pewter/60 focus:border-thamani-forest focus:outline-none focus:ring-0 transition-colors"
            />

            <%!-- Search Results Popover --%>
            <div
              :if={
                @search_query != "" and String.trim(@search_query) != "" and
                  Map.get(assigns, :search_active, true)
              }
              phx-window-keydown="dismiss_search"
              phx-key="escape"
              class="absolute left-0 right-0 top-full z-40 mt-2 rounded-2xl p-4 space-y-3 max-h-[460px] overflow-y-auto ff-surface-popover"
            >
              <div class="flex items-center justify-between border-b border-thamani-stone pb-2.5">
                <div class="flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-thamani-forest" />
                  <span class="text-xs font-medium text-thamani-forest uppercase tracking-wider">
                    Search hits for "{@search_query}"
                  </span>
                </div>
                <div class="flex items-center gap-3">
                  <button
                    type="button"
                    phx-click="clear_search"
                    class="text-xs font-medium text-thamani-forest hover:underline cursor-pointer"
                  >
                    Clear search
                  </button>
                  <button
                    type="button"
                    phx-click="dismiss_search"
                    class="text-xs font-medium text-thamani-pewter hover:text-thamani-forest cursor-pointer"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
              </div>

              <div class="text-xs text-thamani-pewter bg-thamani-stone/50 p-2.5 rounded-lg border border-thamani-stone flex items-center justify-between">
                <span>Metrics on dashboard below filtered for "{@search_query}"</span>
                <span class="font-medium text-thamani-forest">
                  {@stats.total_patients} patients • {@stats.patient_visits} visits • {money(
                    @stats.revenue_collected
                  )}
                </span>
              </div>

              <%!-- Unified Flat Search Items List --%>
              <% items = combined_search_items(@search_results) %>
              <div
                :if={items != []}
                class="divide-y divide-thamani-stone/60 rounded-xl ff-surface-card"
              >
                <div
                  :for={item <- items}
                  class="p-3 hover:bg-thamani-stone/40 transition-colors flex items-center justify-between gap-3"
                >
                  <div class="flex items-center gap-3 min-w-0">
                    <div class="flex size-8 shrink-0 items-center justify-center rounded-lg bg-thamani-stone text-thamani-forest">
                      <.icon name={item.icon} class="size-4" />
                    </div>
                    <div class="min-w-0">
                      <p class="text-sm font-medium text-thamani-forest truncate">{item.title}</p>
                      <p class="text-xs text-thamani-pewter truncate">{item.subtitle}</p>
                    </div>
                  </div>
                  <span class="px-2.5 py-1 text-xs font-medium bg-thamani-lime text-thamani-forest rounded-full shrink-0">
                    {item.badge}
                  </span>
                </div>
              </div>

              <%!-- Empty state --%>
              <div
                :if={items == []}
                class="py-8 text-center text-sm text-thamani-pewter"
              >
                No matching patients, sites, staff, or records found for "{@search_query}"
              </div>
            </div>
          </div>

          <div class="relative">
            <button
              type="button"
              phx-click="toggle_filters"
              class={[
                "inline-flex items-center justify-center gap-2 rounded-full px-5 py-2.5 text-sm font-normal transition-all shrink-0 cursor-pointer w-full sm:w-auto border",
                @show_filters &&
                  "bg-thamani-forest text-thamani-snow border-thamani-forest shadow-sm",
                !@show_filters &&
                  "bg-thamani-snow text-thamani-forest border-thamani-stone hover:bg-thamani-stone/60"
              ]}
            >
              <.icon name="hero-adjustments-horizontal" class="size-4" /> Filters
              <span :if={@range == "custom"} class="size-2 rounded-full bg-thamani-lime"></span>
            </button>

            <%!-- Backdrop to dismiss filter popover when clicking outside --%>
            <div
              :if={@show_filters}
              class="fixed inset-0 z-40 bg-black/5"
              phx-click="toggle_filters"
            />

            <%!-- Filters Date Range Picker Popover --%>
            <div
              :if={@show_filters}
              class="absolute right-0 top-full z-50 mt-2 w-[340px] sm:w-[420px] rounded-2xl p-5 ff-surface-popover transition-all"
            >
              <form phx-submit="apply_custom_range">
                <div class="flex items-center justify-between border-b border-thamani-stone pb-3 mb-4">
                  <div class="flex items-center gap-2">
                    <.icon name="hero-adjustments-horizontal" class="size-4 text-thamani-forest" />
                    <h3 class="font-semibold text-thamani-forest text-base">Filters</h3>
                  </div>
                  <div class="flex items-center gap-3">
                    <button
                      type="button"
                      phx-click="reset_filters"
                      class="text-xs font-semibold text-thamani-forest hover:underline cursor-pointer"
                    >
                      Reset all
                    </button>
                    <button
                      type="button"
                      phx-click="toggle_filters"
                      class="text-thamani-pewter hover:text-thamani-forest cursor-pointer p-1 rounded-lg hover:bg-thamani-stone/60 transition-colors"
                      aria-label="Close filters"
                    >
                      <.icon name="hero-x-mark" class="size-4" />
                    </button>
                  </div>
                </div>

                <p class="text-[11px] font-bold tracking-wider text-thamani-pewter uppercase mb-3">
                  Date Range
                </p>

                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-6">
                  <div>
                    <.date_picker
                      id="filter-date-from"
                      name="from"
                      value={elem(@dates, 0)}
                      label="Date From"
                      placeholder="MM/DD/YYYY"
                      max="today"
                      align="left"
                    />
                  </div>
                  <div>
                    <.date_picker
                      id="filter-date-to"
                      name="to"
                      value={elem(@dates, 1)}
                      label="Date To"
                      placeholder="MM/DD/YYYY"
                      max="today"
                      align="right"
                    />
                  </div>
                </div>

                <div class="flex items-center justify-end gap-3 border-t border-thamani-stone pt-4">
                  <button
                    type="button"
                    phx-click="clear_filters"
                    class="px-4 py-2 text-xs sm:text-sm font-normal text-thamani-forest border border-thamani-forest rounded-full hover:bg-thamani-stone transition-colors cursor-pointer"
                  >
                    Clear filters
                  </button>
                  <button
                    type="submit"
                    class="px-5 py-2 text-xs sm:text-sm font-normal text-thamani-snow bg-thamani-forest hover:opacity-90 rounded-full transition-colors cursor-pointer shadow-sm"
                  >
                    Apply filters
                  </button>
                </div>
              </form>
            </div>
          </div>
        </:toolbar>
      </.header>

      <section
        :if={@setup_required?}
        id="organization-onboarding-welcome"
        class="rounded-2xl border border-thamani-stone bg-white px-6 py-7 shadow-sm sm:px-8"
      >
        <h1 class="text-3xl font-medium tracking-tight text-thamani-forest sm:text-4xl">
          Welcome to {@organization.name}
        </h1>
        <p class="mt-3 max-w-2xl text-base leading-7 text-thamani-pewter">
          Add the location and services for your primary site. This is the only required setup
          before you can start using your dashboard.
        </p>
      </section>

      <section
        :if={@setup_required?}
        id="organization-onboarding"
        class="rounded-2xl border border-thamani-lime/70 bg-thamani-lime/15 p-5 shadow-sm"
      >
        <div class="flex items-start gap-3">
          <div class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-thamani-forest text-thamani-snow">
            <.icon name="hero-rocket-launch" class="size-5" />
          </div>
          <div class="min-w-0 flex-1">
            <h2 class="text-lg font-semibold text-thamani-forest">Complete your primary site</h2>
            <p class="mt-1 text-sm text-thamani-pewter">
              Confirm its address and whether it provides pharmacy, lab, combined, or warehouse
              services.
            </p>
          </div>
        </div>
        <.link
          id="complete-primary-site"
          navigate={
            if @primary_site,
              do: ~p"/org/sites/#{@primary_site.id}/edit?return_to=dashboard",
              else: ~p"/org/sites/new?return_to=dashboard"
          }
          class="mt-5 inline-flex items-center gap-2 rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-all hover:opacity-90 active:scale-[0.98]"
        >
          Complete site details <.icon name="hero-arrow-right" class="size-4" />
        </.link>
      </section>

      <div :if={not @setup_required?} id="admin-dashboard-stats" class="dashboard-stat-grid mt-6">
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
          sublabel="Wallet credits in selected window"
        />
        <.stat_tile
          icon="hero-users"
          label="Active staff"
          value={@stats.active_staff}
          sublabel="Enabled system accounts"
        />
        <.stat_tile
          :if={@pharmacy_metrics?}
          id="prescriptions-stat"
          icon="hero-document-text"
          label="Prescriptions"
          value={@stats.prescriptions}
          sublabel="Prescriptions in selected window"
        />
        <.stat_tile
          :if={@lab_metrics?}
          id="lab-tests-done-stat"
          icon="hero-beaker"
          label="Lab tests done"
          value={@stats.lab_tests_done}
          sublabel="Completed lab orders in selected window"
        />
        <.stat_tile
          :if={@pharmacy_metrics?}
          id="pending-prescriptions-stat"
          icon="hero-clock"
          label="Pending prescriptions"
          value={@stats.pending_prescriptions}
          sublabel="Awaiting dispensing, network-wide"
        />
        <.stat_tile
          :if={@lab_metrics?}
          id="pending-lab-orders-stat"
          icon="hero-clipboard-document-list"
          label="Pending lab orders"
          value={@stats.pending_lab_orders}
          sublabel="Awaiting results, network-wide"
        />
      </div>

      <div :if={not @setup_required?} id="admin-dashboard-charts" class="dashboard-chart-grid mt-6">
        <.chart_card
          id="daily-revenue-chart"
          title="Daily revenue"
          subtitle="Wallet credits collected per day in the selected window"
          type="line"
          data={daily_revenue_chart_data(@daily_revenue)}
          options={chart_options()}
        />
        <.chart_card
          id="monthly-revenue-chart"
          title="Monthly revenue"
          subtitle="Total wallet credits collected in the last 12 months"
          type="bar"
          data={monthly_revenue_chart_data(@monthly_revenue)}
          options={chart_options()}
        />
      </div>

      <div :if={not @setup_required?} id="org-analytics-charts" class="dashboard-chart-grid mt-6">
        <.chart_card
          id="org-site-performance-chart"
          title="Revenue and cost by site"
          subtitle="All-time site comparison"
          type="bar"
          data={site_chart_data(@site_profitability)}
          options={legend_chart_options()}
        />
        <.chart_card
          id="org-site-profit-chart"
          title="Profit by site"
          subtitle="All-time, revenue less stock cost"
          type="bar"
          data={profit_chart_data(@site_profitability)}
          options={chart_options()}
        />
      </div>

      <div
        :if={not @setup_required?}
        id="organization-product-tour"
        phx-hook=".ProductTour"
        phx-update="ignore"
        data-tour-key={"thamani-org-tour-v1-#{@current_scope.user.id}"}
        data-auto-start={to_string(@auto_start_tour?)}
        class="hidden"
      >
        <button
          type="button"
          data-tour-dismiss
          aria-label="Close product tour"
          class="fixed inset-0 z-40 cursor-default bg-slate-950/45 backdrop-blur-[1px]"
        ></button>
        <section
          data-tour-card
          role="dialog"
          aria-modal="true"
          aria-labelledby="product-tour-title"
          class="fixed z-[100] w-[min(390px,calc(100vw-2rem))] rounded-2xl border border-white/20 bg-thamani-forest p-5 text-white shadow-2xl transition-[top,left] duration-200"
        >
          <span
            data-tour-arrow
            class="absolute left-[-7px] top-1/2 hidden size-3.5 -translate-y-1/2 rotate-45 border-b border-l border-white/20 bg-thamani-forest"
          ></span>
          <div class="flex items-start justify-between gap-4">
            <div>
              <p
                data-tour-progress
                class="text-xs font-semibold uppercase tracking-[0.16em] text-thamani-lime"
              >
              </p>
              <h2 id="product-tour-title" data-tour-title class="mt-2 text-xl font-semibold"></h2>
            </div>
            <button
              type="button"
              data-tour-dismiss
              aria-label="Close product tour"
              class="rounded-lg p-1 text-white/70 transition-colors hover:bg-white/10 hover:text-white"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <p
            data-tour-description
            class="mt-3 text-[15px] leading-6"
            style="color: rgba(255, 255, 255, 0.84);"
          >
          </p>
          <div class="mt-5 flex items-center justify-between gap-3">
            <button
              type="button"
              data-tour-back
              class="rounded-full px-4 py-2 text-sm font-medium text-white/80 transition-colors hover:bg-white/10 disabled:invisible"
            >
              Back
            </button>
            <button
              type="button"
              data-tour-dismiss
              class="rounded-full px-3 py-2 text-sm font-medium text-white/70 transition-colors hover:bg-white/10 hover:text-white"
            >
              Skip tour
            </button>
            <button
              type="button"
              data-tour-next
              class="rounded-full bg-thamani-lime px-5 py-2 text-sm font-semibold text-thamani-forest transition-all hover:brightness-95 active:scale-[0.98]"
            >
              Next
            </button>
          </div>
        </section>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ProductTour">
        export default {
          mounted() {
            this.steps = [
              {
                selector: '[data-tour-target="/org/dashboard"]',
                title: "Start with your dashboard",
                description: "See patient activity, revenue, and operational work across every site."
              },
              {
                selector: '[data-tour-target="/org/sites"]',
                title: "Keep your locations up to date",
                description: "Add branches and update each site’s address and services: pharmacy, lab, combined, or warehouse."
              },
              {
                selector: '[data-tour-target="/org/products"]',
                title: "Add the medicines and supplies you use",
                description: "Create your shared catalog, then receive stock and distribute it to the sites that need it."
              },
              {
                selector: '[data-tour-target="/org/team"]',
                title: "Give your staff the right access",
                description: "Invite staff and assign site access so each person sees only the work relevant to them."
              },
              {
                selector: '[data-tour-target="/org/suppliers"]',
                title: "Record who supplies your stock",
                description: "Store contacts and GLNs for businesses that supply your medicines and medical products."
              },
              {
                selector: '[data-tour-target="/org/requisitions"]',
                title: "Coordinate stock requests between sites",
                description: "Review and track site stock requests from submission through approval and fulfilment."
              },
              {
                selector: '[data-tour-target="/org/earnings"]',
                title: "Follow the money",
                description: "Trace payments and site earnings here; view performance charts and site comparisons on the dashboard."
              }
            ]
            this.index = 0
            this.activeTarget = null
            this.dismiss = () => this.finish()
            this.next = () => this.index === this.steps.length - 1 ? this.finish() : this.show(this.index + 1)
            this.back = () => this.show(this.index - 1)
            this.start = () => this.show(0)
            this.reposition = () => this.positionCard()
            this.keydown = event => {
              if (event.key === "Escape") this.finish()
              if (event.key === "ArrowRight") this.next()
              if (event.key === "ArrowLeft" && this.index > 0) this.back()
            }

            this.el.querySelectorAll("[data-tour-dismiss]").forEach(button => button.addEventListener("click", this.dismiss))
            this.el.querySelector("[data-tour-next]").addEventListener("click", this.next)
            this.el.querySelector("[data-tour-back]").addEventListener("click", this.back)
            window.addEventListener("keydown", this.keydown)
            window.addEventListener("resize", this.reposition)

            if (this.el.dataset.autoStart === "true") {
              this.start()
              const url = new URL(window.location.href)
              url.searchParams.delete("tour")
              window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`)
            }
          },

          show(index) {
            this.clearTarget()
            this.index = Math.max(0, Math.min(index, this.steps.length - 1))
            const step = this.steps[this.index]
            const sidebar = document.getElementById("sidebar-shell")
            const aside = document.getElementById("sidebar-aside")
            sidebar?.classList.add("sidebar-mobile-open")
            aside?.classList.remove("sidebar-collapsed")

            this.activeTarget = document.querySelector(step.selector)
            if (this.activeTarget) {
              this.activeTarget.dataset.tourPreviousStyle = this.activeTarget.getAttribute("style") || ""
              this.activeTarget.style.position = "relative"
              this.activeTarget.style.zIndex = "55"
              this.activeTarget.style.boxShadow = "0 0 0 4px rgba(211, 239, 74, 0.9), 0 12px 30px rgba(0, 0, 0, 0.25)"
              this.activeTarget.scrollIntoView({block: "nearest"})
            }

            this.el.querySelector("[data-tour-progress]").textContent = `Quick tour · ${this.index + 1} of ${this.steps.length}`
            this.el.querySelector("[data-tour-title]").textContent = step.title
            this.el.querySelector("[data-tour-description]").textContent = step.description
            this.el.querySelector("[data-tour-back]").disabled = this.index === 0
            this.el.querySelector("[data-tour-next]").textContent = this.index === this.steps.length - 1 ? "Finish" : "Next"
            this.el.classList.remove("hidden")
            this.positionCard()
            window.clearTimeout(this.positionTimer)
            this.positionTimer = window.setTimeout(() => this.positionCard(), 220)
            this.el.querySelector("[data-tour-next]").focus()
          },

          positionCard() {
            const card = this.el.querySelector("[data-tour-card]")
            const arrow = this.el.querySelector("[data-tour-arrow]")
            if (!card || !this.activeTarget) return

            const target = this.activeTarget.getBoundingClientRect()
            const cardWidth = card.offsetWidth
            const cardHeight = card.offsetHeight
            const gap = 20
            const edge = 16
            const roomOnRight = window.innerWidth - target.right - gap

            if (window.innerWidth >= 640 && roomOnRight >= cardWidth + edge) {
              const top = Math.min(
                Math.max(target.top + target.height / 2 - cardHeight / 2, edge),
                window.innerHeight - cardHeight - edge
              )
              card.style.left = `${target.right + gap}px`
              card.style.top = `${top}px`
              arrow.classList.remove("hidden")
              arrow.style.top = `${Math.min(Math.max(target.top + target.height / 2 - top, 24), cardHeight - 24)}px`
            } else {
              card.style.left = `${Math.max((window.innerWidth - cardWidth) / 2, edge)}px`
              card.style.top = `${Math.max(window.innerHeight - cardHeight - edge, edge)}px`
              arrow.classList.add("hidden")
            }
          },

          clearTarget() {
            if (!this.activeTarget) return
            this.activeTarget.setAttribute("style", this.activeTarget.dataset.tourPreviousStyle || "")
            delete this.activeTarget.dataset.tourPreviousStyle
            this.activeTarget = null
          },

          finish() {
            this.clearTarget()
            this.el.classList.add("hidden")
            localStorage.setItem(this.el.dataset.tourKey, "complete")
            document.getElementById("sidebar-shell")?.classList.remove("sidebar-mobile-open")
          },

          destroyed() {
            this.clearTarget()
            window.clearTimeout(this.positionTimer)
            window.removeEventListener("keydown", this.keydown)
            window.removeEventListener("resize", this.reposition)
          }
        }
      </script>
    </Layouts.org_shell>
    """
  end
end
