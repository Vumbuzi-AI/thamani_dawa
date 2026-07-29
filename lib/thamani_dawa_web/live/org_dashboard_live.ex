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
          @search_query != "" and String.trim(@search_query) != "" and
            Map.get(assigns, :search_active, true)
        }
        class="fixed inset-0 z-30 bg-black/15 backdrop-blur-sm transition-opacity"
        phx-click="dismiss_search"
      />

      <.header icon="hero-squares-2x2">
        Admin Dashboard
        <:subtitle>
          {format_range_dates(@dates)}
        </:subtitle>
        <:actions>
          <.range_filter event="set_range" current={@range} ranges={Dashboards.ranges()} />
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
