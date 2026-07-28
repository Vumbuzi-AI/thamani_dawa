defmodule ThamaniDawaWeb.OrgDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Dashboards

  def mount(_params, _session, socket) do
    {:ok, assign_range(socket, "this_month")}
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
     |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates, query))
     |> assign(
       :search_results,
       Dashboards.search_admin_dashboard(organization_id, query, dates, site_id)
     )}
  end

  def handle_event("clear_search", _params, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
    dates = socket.assigns.dates

    {:noreply,
     socket
     |> assign(:search_query, "")
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
         {:ok, to_date} <- parse_date(to_str) do
      dates = Dashboards.custom_range_dates(from_date, to_date)
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

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/dashboard">
      <div class="relative bg-white rounded-3xl p-6 sm:p-8 shadow-xs border border-slate-100/80 mb-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 class="text-2xl sm:text-3xl font-bold text-slate-900 tracking-tight">
              Admin Dashboard
            </h1>
            <p class="text-xs sm:text-sm text-slate-500 font-normal mt-1">
              {format_range_dates(@dates)}
            </p>
          </div>

          <.range_filter event="set_range" current={@range} ranges={Dashboards.ranges()} />
        </div>

        <div class="mt-6 flex flex-col sm:flex-row items-center gap-3 w-full">
          <div class="relative flex-1 w-full">
            <input
              type="text"
              name="search"
              value={@search_query}
              phx-keyup="search"
              phx-debounce="250"
              placeholder="Search patients, visits, revenue or reports..."
              class="w-full rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm text-slate-700 placeholder:text-slate-400 focus:border-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-600/15 shadow-2xs transition-all"
            />

            <%!-- Search Results Popover attached to input card --%>
            <div
              :if={@search_query != "" and String.trim(@search_query) != ""}
              class="absolute left-0 right-0 top-full z-40 mt-2 bg-white rounded-2xl border border-slate-200/90 shadow-2xl p-5 space-y-4 max-h-[460px] overflow-y-auto"
            >
              <div class="flex items-center justify-between border-b border-slate-100 pb-3">
                <div class="flex items-center gap-2">
                  <.icon name="hero-magnifying-glass" class="size-4 text-indigo-600" />
                  <span class="text-xs font-semibold text-slate-700 uppercase tracking-wider">
                    Search hits for "{@search_query}"
                  </span>
                </div>
                <button
                  type="button"
                  phx-click="clear_search"
                  class="text-xs font-medium text-indigo-600 hover:text-indigo-800 hover:underline cursor-pointer"
                >
                  Clear search
                </button>
              </div>

              <div class="text-xs text-slate-600 bg-slate-50 p-2.5 rounded-lg border border-slate-100 flex items-center justify-between">
                <span>Metrics on dashboard below are now filtered for "{@search_query}"</span>
                <span class="font-bold text-indigo-700">
                  {@stats.total_patients} patients • {@stats.patient_visits} visits • {money(
                    @stats.revenue_collected
                  )}
                </span>
              </div>

              <%!-- Patients Section --%>
              <div :if={@search_results.patients != []} class="space-y-2">
                <div class="flex items-center gap-2 text-xs font-bold text-indigo-700 uppercase tracking-wider">
                  <.icon name="hero-user" class="size-4" />
                  Patients ({length(@search_results.patients)})
                </div>
                <div class="divide-y divide-slate-100 rounded-xl border border-slate-100 bg-white">
                  <div
                    :for={patient <- @search_results.patients}
                    class="p-3 hover:bg-slate-50 transition-colors flex items-center justify-between"
                  >
                    <div>
                      <p class="text-sm font-semibold text-slate-900">{patient.full_name}</p>
                      <p class="text-xs text-slate-500">
                        Phone: {patient.phone} • DOB: {patient.date_of_birth}
                      </p>
                    </div>
                    <span class="px-2.5 py-1 text-xs font-medium bg-indigo-50 text-indigo-700 rounded-full">
                      GSRN: {patient.gsrn}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Facilities / Sites Section --%>
              <div :if={@search_results.sites != []} class="space-y-2">
                <div class="flex items-center gap-2 text-xs font-bold text-emerald-700 uppercase tracking-wider">
                  <.icon name="hero-building-office-2" class="size-4" />
                  Facilities & Sites ({length(@search_results.sites)})
                </div>
                <div class="divide-y divide-slate-100 rounded-xl border border-slate-100 bg-white">
                  <div
                    :for={site <- @search_results.sites}
                    class="p-3 hover:bg-slate-50 transition-colors flex items-center justify-between"
                  >
                    <div>
                      <p class="text-sm font-semibold text-slate-900">{site.name}</p>
                      <p class="text-xs text-slate-500">
                        {site.address || "No address"} • Type: {site.site_type}
                      </p>
                    </div>
                    <span class="px-2.5 py-1 text-xs font-medium bg-emerald-50 text-emerald-700 rounded-full">
                      GLN: {site.gln || "N/A"}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Staff Section --%>
              <div :if={@search_results.staff != []} class="space-y-2">
                <div class="flex items-center gap-2 text-xs font-bold text-violet-700 uppercase tracking-wider">
                  <.icon name="hero-users" class="size-4" />
                  Staff & Team ({length(@search_results.staff)})
                </div>
                <div class="divide-y divide-slate-100 rounded-xl border border-slate-100 bg-white">
                  <div
                    :for={user <- @search_results.staff}
                    class="p-3 hover:bg-slate-50 transition-colors flex items-center justify-between"
                  >
                    <div>
                      <p class="text-sm font-semibold text-slate-900">{user.name}</p>
                      <p class="text-xs text-slate-500">{user.email}</p>
                    </div>
                    <span class="px-2.5 py-1 text-xs font-medium bg-violet-50 text-violet-700 rounded-full capitalize">
                      {user.role}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Visits Section --%>
              <div :if={@search_results.visits != []} class="space-y-2">
                <div class="flex items-center gap-2 text-xs font-bold text-amber-700 uppercase tracking-wider">
                  <.icon name="hero-document-text" class="size-4" />
                  Recent Visits ({length(@search_results.visits)})
                </div>
                <div class="divide-y divide-slate-100 rounded-xl border border-slate-100 bg-white">
                  <div
                    :for={visit <- @search_results.visits}
                    class="p-3 hover:bg-slate-50 transition-colors flex items-center justify-between"
                  >
                    <div>
                      <p class="text-sm font-semibold text-slate-900">{visit.patient_name}</p>
                      <p class="text-xs text-slate-500">
                        Site: {visit.site_name} • Date: {Calendar.strftime(
                          to_date_val(visit.inserted_at),
                          "%d %b %Y"
                        )}
                      </p>
                    </div>
                    <span class="px-2.5 py-1 text-xs font-medium bg-amber-50 text-amber-700 rounded-full capitalize">
                      {visit.visit_type}
                    </span>
                  </div>
                </div>
              </div>

              <%!-- Empty state --%>
              <div
                :if={
                  @search_results.patients == [] and @search_results.sites == [] and
                    @search_results.staff == [] and @search_results.visits == []
                }
                class="py-8 text-center text-sm text-slate-500"
              >
                No matching patients, sites, staff, or records found for "{@search_query}"
              </div>
            </div>
          </div>

          <button
            type="button"
            phx-click="toggle_filters"
            class="inline-flex items-center justify-center gap-2 rounded-xl bg-[#3b3a98] hover:bg-[#312e84] text-white px-5 py-2.5 text-sm font-medium shadow-xs transition-colors shrink-0 cursor-pointer w-full sm:w-auto"
          >
            <.icon name="hero-adjustments-horizontal" class="size-4" /> Filters
          </button>
        </div>

        <%!-- Filters Date Range Picker Popover --%>
        <div
          :if={@show_filters}
          class="absolute right-6 top-[80px] z-50 mt-2 w-full max-w-md rounded-2xl border border-slate-200/90 bg-white p-6 shadow-2xl transition-all"
        >
          <form phx-submit="apply_custom_range">
            <div class="flex items-center justify-between border-b border-slate-100 pb-3 mb-4">
              <h3 class="font-semibold text-slate-900 text-base">Filters</h3>
              <div class="flex items-center gap-3">
                <button
                  type="button"
                  phx-click="reset_filters"
                  class="text-xs font-semibold text-indigo-600 hover:text-indigo-800 cursor-pointer"
                >
                  Reset all
                </button>
                <button
                  type="button"
                  phx-click="toggle_filters"
                  class="text-slate-400 hover:text-slate-600 cursor-pointer"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
            </div>

            <p class="text-[11px] font-bold tracking-wider text-slate-400 uppercase mb-3">
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
                />
              </div>
              <div>
                <.date_picker
                  id="filter-date-to"
                  name="to"
                  value={elem(@dates, 1)}
                  label="Date To"
                  placeholder="MM/DD/YYYY"
                />
              </div>
            </div>

            <div class="flex items-center justify-end gap-3 border-t border-slate-100 pt-4">
              <button
                type="button"
                phx-click="clear_filters"
                class="px-4 py-2 text-xs sm:text-sm font-medium text-slate-600 hover:text-slate-900 border border-slate-200 rounded-xl hover:bg-slate-50 transition-colors cursor-pointer"
              >
                Clear filters
              </button>
              <button
                type="submit"
                class="px-5 py-2 text-xs sm:text-sm font-medium text-white bg-[#3b3a98] hover:bg-[#312e84] rounded-xl shadow-xs transition-colors cursor-pointer"
              >
                Apply filters
              </button>
            </div>
          </form>
        </div>
      </div>

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
          sublabel="Wallet credits in selected window"
        />
        <.stat_tile
          icon="hero-users"
          label="Active staff"
          value={@stats.active_staff}
          sublabel="Enabled system accounts"
        />
        <.stat_tile
          icon="hero-document-text"
          label="Prescriptions"
          value={@stats.prescriptions}
          sublabel="Prescriptions in selected window"
        />
        <.stat_tile
          icon="hero-beaker"
          label="Lab tests done"
          value={@stats.lab_tests_done}
          sublabel="Completed lab orders in selected window"
        />
        <.stat_tile
          icon="hero-clock"
          label="Pending prescriptions"
          value={@stats.pending_prescriptions}
          sublabel="Awaiting dispensing, network-wide"
        />
        <.stat_tile
          icon="hero-clipboard-document-list"
          label="Pending lab orders"
          value={@stats.pending_lab_orders}
          sublabel="Awaiting results, network-wide"
        />
      </div>

      <div class="dashboard-chart-grid mt-6">
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
    </Layouts.org_shell>
    """
  end
end
