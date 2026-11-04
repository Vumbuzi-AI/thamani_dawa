defmodule ThamaniDawaWeb.LabDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Dashboards
  alias ThamaniDawa.LabOrders
  alias ThamaniDawaWeb.SiteScoping

  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = scope.current_site_id

    lab_orders =
      organization_id
      |> LabOrders.list_lab_orders_with_patient()
      |> SiteScoping.for_current_site(scope)

    {from, to} = Dashboards.range_dates("this_month")

    completed_this_month =
      Enum.count(lab_orders, fn order ->
        order.status == :completed and
          Date.compare(DateTime.to_date(order.inserted_at), from) != :lt and
          Date.compare(DateTime.to_date(order.inserted_at), to) != :gt
      end)

    overdue_count =
      Enum.count(lab_orders, fn order ->
        order.status in [:pending, :in_progress] and
          DateTime.diff(DateTime.utc_now(), order.inserted_at, :hour) >= 24
      end)

    {:ok,
     socket
     |> assign(:auto_start_tour?, params["tour"] == "1")
     |> assign(:pending, Enum.filter(lab_orders, &(&1.status == :pending)))
     |> assign(:incomplete, Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress])))
     |> assign(:in_progress_count, Enum.count(lab_orders, &(&1.status == :in_progress)))
     |> assign(:cancelled_count, Enum.count(lab_orders, &(&1.status == :cancelled)))
     |> assign(
       :unpaid_count,
       Enum.count(lab_orders, &(&1.status != :cancelled and not &1.has_paid))
     )
     |> assign(:overdue_count, overdue_count)
     |> assign(:completed_this_month, completed_this_month)
     |> assign(:stats, Dashboards.lab_stats(organization_id, site_id))
     |> assign(:orders_by_day, Dashboards.lab_orders_by_day(organization_id, site_id))
     |> assign(:orders_by_status, Dashboards.lab_orders_by_status(organization_id, site_id))}
  end

  defp product_tour_steps do
    [
      %{
        selector: ~s([data-tour-target="/lab"]),
        title: "Start with your dashboard",
        description:
          "See pending work, completed reports, revenue, and lab activity at your current site."
      },
      %{
        selector: ~s([data-tour-target="/lab/orders"]),
        title: "Work through lab orders",
        description:
          "Collect specimens, enter results, and track every order from request to completion."
      },
      %{
        selector: ~s([data-tour-target="/lab/tests"]),
        title: "Maintain the test catalogue",
        description:
          "Find the tests your lab offers and the information needed to process them correctly."
      },
      %{
        selector: ~s([data-tour-target="/lab/stock"]),
        title: "Monitor lab stock",
        description: "Review consumables, batches, quantities, and expiry risk for your site."
      },
      %{
        selector: ~s([data-tour-target="/lab/scan"]),
        title: "Scan for faster workflows",
        description:
          "Use scanning to identify supported records without manually searching for them."
      }
    ]
  end

  defp patient_name(%{patient_visit: %{patient: patient}}) when not is_nil(patient),
    do: patient.full_name

  defp patient_name(_lab_order), do: "(unknown patient)"

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

  defp orders_by_day_chart_data(orders_by_day) do
    %{
      labels: Enum.map(orders_by_day, fn {date, _n} -> Calendar.strftime(date, "%d %b") end),
      datasets: [
        %{
          label: "Lab orders",
          data: Enum.map(orders_by_day, fn {_date, n} -> n end),
          borderColor: "#1c3a13",
          backgroundColor: "rgba(28, 58, 19, 0.14)",
          fill: true,
          tension: 0.3,
          pointRadius: 3
        }
      ]
    }
  end

  defp orders_by_status_chart_data(orders_by_status) do
    %{
      labels: Enum.map(orders_by_status, fn {status, _n} -> Phoenix.Naming.humanize(status) end),
      datasets: [
        %{
          label: "Lab orders",
          data: Enum.map(orders_by_status, fn {_status, n} -> n end),
          backgroundColor: ["#1c3a13", "#757c5d", "#698e79", "#c21f17"],
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
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab">
      <.header icon="hero-squares-2x2">
        Lab dashboard
        <:subtitle>Pending orders and incomplete reports at your site.</:subtitle>
        <:actions>
          <.button variant="primary" navigate={~p"/lab/orders/new"}>
            <.icon name="hero-plus" class="size-4" /> New lab order
          </.button>
        </:actions>
      </.header>

      <div class="dashboard-stat-grid mt-4">
        <.stat_tile
          icon="hero-clock"
          label="Pending orders"
          value={length(@pending)}
          sublabel="Awaiting collection or results"
        />
        <.stat_tile
          icon="hero-arrow-path"
          label="In progress"
          value={@in_progress_count}
          sublabel="Currently being processed"
        />
        <.stat_tile
          icon="hero-check-circle"
          label="Completed this month"
          value={@completed_this_month}
          sublabel="Reports finalized"
        />
        <.stat_tile
          icon="hero-x-circle"
          label="Cancelled"
          value={@cancelled_count}
          sublabel="Cancelled orders, network-wide"
        />
        <.stat_tile
          icon="hero-banknotes"
          label="Revenue this month"
          value={money(@stats.revenue_this_month)}
          sublabel="Wallet credits collected"
        />
        <.stat_tile
          icon="hero-credit-card"
          label="Unpaid orders"
          value={@unpaid_count}
          sublabel="Active orders awaiting payment"
        />
        <.stat_tile
          icon="hero-clipboard-document-check"
          label="Tests awaiting results"
          value={@stats.tests_awaiting_results}
          sublabel="Samples collected, results not finalized"
        />
        <.stat_tile
          icon="hero-exclamation-triangle"
          label="Overdue orders"
          value={@overdue_count}
          sublabel="Open for more than 24 hours"
        />
      </div>

      <div class="dashboard-chart-grid mt-6">
        <.chart_card
          id="lab-orders-by-day-chart"
          title="Lab orders"
          subtitle="Orders created per day, last 30 days"
          type="line"
          data={orders_by_day_chart_data(@orders_by_day)}
          options={chart_options()}
        />
        <.chart_card
          id="lab-orders-by-status-chart"
          title="Orders by status"
          subtitle="All lab orders at your site"
          type="bar"
          data={orders_by_status_chart_data(@orders_by_status)}
          options={chart_options()}
        />
      </div>

      <.header variant="plain" class="mt-4">Pending orders</.header>
      <.table
        id="pending-orders"
        rows={@pending}
        row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
      >
        <:col :let={lab_order} label="Patient">{patient_name(lab_order)}</:col>
        <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="No pending orders">
            New lab orders at your site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>

      <.header variant="plain" class="mt-6">Incomplete reports</.header>
      <.table
        id="incomplete-orders"
        rows={@incomplete}
        row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
      >
        <:col :let={lab_order} label="Patient">{patient_name(lab_order)}</:col>
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

      <Layouts.product_tour
        id="lab-product-tour"
        tour_key={"thamani-lab-tour-v1-#{@current_scope.user.id}"}
        auto_start={@auto_start_tour?}
        steps={product_tour_steps()}
      />
    </Layouts.lab_shell>
    """
  end
end
