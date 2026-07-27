defmodule ThamaniDawaWeb.OrgDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Dashboards

  def mount(_params, _session, socket) do
    {:ok, assign_range(socket, "this_month")}
  end

  def handle_event("set_range", %{"range" => range}, socket) do
    {:noreply, assign_range(socket, range)}
  end

  defp assign_range(socket, range) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id
    dates = Dashboards.range_dates(range)

    socket
    |> assign(:range, range)
    |> assign(:stats, Dashboards.admin_stats(organization_id, site_id, dates))
    |> assign(
      :daily_revenue,
      Dashboards.daily_revenue(organization_id, site_id, elem(dates, 0), elem(dates, 1))
    )
    |> assign(:monthly_revenue, Dashboards.monthly_revenue(organization_id, site_id))
  end

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
      <div class="flex flex-wrap items-start justify-between gap-4">
        <.header icon="hero-squares-2x2">
          Admin dashboard
          <:subtitle>Network-wide view across your organization.</:subtitle>
        </.header>
        <.range_filter event="set_range" current={@range} ranges={Dashboards.ranges()} />
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
