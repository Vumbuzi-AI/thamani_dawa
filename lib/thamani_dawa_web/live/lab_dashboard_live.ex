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
        title: "See today’s workload",
        description:
          "See pending work, completed reports, revenue, and lab activity at your current site."
      },
      %{
        selector: ~s([data-tour-target="/lab/orders"]),
        title: "Process lab orders",
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
        title: "Check lab stock",
        description: "Review consumables, batches, quantities, and expiry risk for your site."
      },
      %{
        selector: ~s([data-tour-target="/lab/scan"]),
        title: "Scan to find records faster",
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

  defp phrase(1, singular, _plural), do: "1 #{singular}"
  defp phrase(n, _singular, plural), do: "#{n} #{plural}"

  defp bar_marks(orders_by_day) do
    points = Enum.take(orders_by_day, -30)
    max = points |> Enum.map(fn {_date, n} -> n end) |> Enum.max(fn -> 0 end)
    total = length(points)

    points
    |> Enum.with_index()
    |> Enum.map(fn {{date, count}, index} ->
      height = if max == 0, do: 8, else: max(8, round(count / max * 100))

      %{
        height: height,
        recent: index >= total - 7,
        label: date |> Calendar.strftime("%d %b") |> String.trim_leading("0")
      }
    end)
  end

  defp axis_labels(marks) do
    case marks do
      [] ->
        []

      marks ->
        last = length(marks) - 1
        mid = div(last, 2)
        [Enum.at(marks, 0).label, Enum.at(marks, mid).label, Enum.at(marks, last).label]
    end
  end

  defp status_rows(orders_by_status) do
    counts = Map.new(orders_by_status)

    [
      {:pending, "Pending", "Awaiting collection or results", "warning"},
      {:in_progress, "In progress", "Currently being processed", "info"},
      {:completed, "Completed", "Reports finalized", "success"},
      {:cancelled, "Cancelled", "Cancelled orders", "neutral"}
    ]
    |> Enum.map(fn {key, label, caption, tone} ->
      %{label: label, caption: caption, tone: tone, count: Map.get(counts, key, 0)}
    end)
  end

  defp tick_on?(index, count, max) do
    filled = if max == 0, do: 0, else: round(count / max * 12)
    index < filled
  end

  defp status_tone(:pending), do: "warning"
  defp status_tone(:in_progress), do: "info"
  defp status_tone(:completed), do: "success"
  defp status_tone(:cancelled), do: "neutral"
  defp status_tone(_), do: "neutral"

  defp status_label(status),
    do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp short_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%d %b, %H:%M")
  defp short_dt(_), do: ""

  defp newest(orders) do
    Enum.sort_by(orders, fn order -> DateTime.to_unix(order.inserted_at) end, :desc)
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:bars, bar_marks(assigns.orders_by_day))
      |> assign(:statuses, status_rows(assigns.orders_by_status))
      |> assign(:pending_rows, assigns.pending |> newest() |> Enum.take(4))
      |> assign(:incomplete_rows, assigns.incomplete |> newest() |> Enum.take(4))

    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/lab"
      crumb="Dashboard"
    >
      <:tools>
        <.td_button variant="primary" navigate={~p"/lab/orders/new"} label="New lab order">
          <:icon><.td_icon name="plus" /></:icon>
        </.td_button>
      </:tools>

      <div class="td-dash">
        <.td_page_header
          title="Lab dashboard"
          subtitle="Pending orders and incomplete reports at your site."
        >
          <:actions>
            <.td_button variant="secondary" navigate={~p"/lab/scan"} label="Scan">
              <:icon><.td_icon name="scan" /></:icon>
            </.td_button>
          </:actions>
        </.td_page_header>

        <div class="td-glances">
          <.td_glance_strip>
            <.td_glance_cell
              navigate={~p"/lab/orders"}
              tone="warning"
              value={phrase(length(@pending), "pending order", "pending orders")}
              caption="Awaiting collection or results"
            >
              <:icon><.td_icon name="hourglass" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              navigate={~p"/lab/orders"}
              tone="info"
              value={phrase(@in_progress_count, "in progress", "in progress")}
              caption="Currently being processed"
            >
              <:icon><.td_icon name="flask" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              tone="success"
              value={phrase(@completed_this_month, "completed this month", "completed this month")}
              caption="Reports finalized"
            >
              <:icon><.td_icon name="check-circle" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              navigate={~p"/lab/transactions"}
              tone="neutral"
              value={"#{money(@stats.revenue_this_month)} this month"}
              caption="Wallet credits collected"
            >
              <:icon><.td_icon name="wallet" class="size-[18px]" /></:icon>
            </.td_glance_cell>
          </.td_glance_strip>

          <.td_glance_strip>
            <.td_glance_cell
              navigate={~p"/lab/orders"}
              tone="danger"
              value={phrase(@unpaid_count, "unpaid order", "unpaid orders")}
              caption="Active orders awaiting payment"
            >
              <:icon><.td_icon name="coins" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              navigate={~p"/lab/orders"}
              tone="info"
              value={
                phrase(
                  @stats.tests_awaiting_results,
                  "test awaiting results",
                  "tests awaiting results"
                )
              }
              caption="Samples collected, results not finalized"
            >
              <:icon><.td_icon name="eyedropper" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              navigate={~p"/lab/orders"}
              tone="expiry"
              value={phrase(@overdue_count, "overdue order", "overdue orders")}
              caption="Open for more than 24 hours"
            >
              <:icon><.td_icon name="clock" class="size-[18px]" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              tone="neutral"
              value={phrase(@cancelled_count, "cancelled", "cancelled")}
              caption="Cancelled at this site"
            >
              <:icon><.td_icon name="x-circle" class="size-[18px]" /></:icon>
            </.td_glance_cell>
          </.td_glance_strip>
        </div>

        <div class="td-dash-row">
          <section class="td-dash-card">
            <.td_card_header title="Lab orders" subtitle="Orders created per day, last 30 days" />
            <div class="td-bars" aria-label="Lab orders over the last 30 days">
              <i :for={bar <- @bars} class={bar.recent && "is-now"} style={"height: #{bar.height}%"}></i>
            </div>
            <div :if={@bars != []} class="td-axis">
              <span :for={label <- axis_labels(@bars)}>{label}</span>
            </div>
          </section>
          <section class="td-dash-card">
            <.td_card_header title="Orders by status" subtitle="All lab orders at your site" />
            <div :for={row <- @statuses} class="td-status-row">
              <div class="td-status-copy">
                <b>{row.label}</b>
                <span>{row.caption}</span>
              </div>
              <span class="td-ticks" aria-hidden="true">
                <i
                  :for={index <- 0..11}
                  class={[
                    tick_on?(index, row.count, status_max(@statuses)) && "is-on",
                    "is-#{row.tone}"
                  ]}
                ></i>
              </span>
              <span class="td-status-n">{row.count}</span>
            </div>
          </section>
        </div>

        <div class="td-dash-row">
          <section class="td-dash-card">
            <.td_card_header title="Pending orders" subtitle="Newest first">
              <:actions>
                <.td_button variant="secondary" navigate={~p"/lab/orders"} label="View all" />
              </:actions>
            </.td_card_header>
            <table class="td-rows">
              <thead>
                <tr>
                  <th>Patient</th>
                  <th>Urgency</th>
                  <th>Created</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={lab_order <- @pending_rows}>
                  <td>
                    <.link class="td-person" navigate={~p"/lab/orders/#{lab_order.id}"}>
                      <.td_orb seed={patient_name(lab_order)} size={20} />
                      <span>{patient_name(lab_order)}</span>
                    </.link>
                  </td>
                  <td>
                    <.td_badge :if={lab_order.urgency == "urgent"} tone="danger" label="Urgent" />
                    <span :if={lab_order.urgency != "urgent"} class="td-note">
                      {lab_order.urgency || "Routine"}
                    </span>
                  </td>
                  <td>{short_dt(lab_order.inserted_at)}</td>
                  <td>
                    <.td_badge
                      tone={status_tone(lab_order.status)}
                      label={status_label(lab_order.status)}
                    />
                  </td>
                </tr>
                <tr :if={@pending_rows == []}>
                  <td colspan="4" class="td-note">No pending orders at this site.</td>
                </tr>
              </tbody>
            </table>
          </section>
          <section class="td-dash-card">
            <.td_card_header title="Incomplete reports" subtitle="Results still to finalize" />
            <table class="td-rows">
              <thead>
                <tr>
                  <th>Order</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={lab_order <- @incomplete_rows}>
                  <td>
                    <.link navigate={~p"/lab/orders/#{lab_order.id}"}>
                      {patient_name(lab_order)}
                    </.link>
                  </td>
                  <td>
                    <.td_badge
                      tone={status_tone(lab_order.status)}
                      label={status_label(lab_order.status)}
                    />
                  </td>
                </tr>
                <tr :if={@incomplete_rows == []}>
                  <td colspan="2" class="td-note">No incomplete reports.</td>
                </tr>
              </tbody>
            </table>
          </section>
        </div>
      </div>

      <Layouts.product_tour
        id="lab-product-tour"
        tour_key={"thamani-lab-tour-v1-#{@current_scope.user.id}"}
        auto_start={@auto_start_tour?}
        steps={product_tour_steps()}
      />
    </Layouts.lab_shell>
    """
  end

  defp status_max(rows) do
    rows |> Enum.map(& &1.count) |> Enum.max(fn -> 0 end)
  end
end
