defmodule ThamaniDawaWeb.ManufacturerDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:page_title, "Manufacturer dashboard")
     |> assign(:counts, Manufacturing.dashboard_counts(organization_id))
     |> assign(:summary, Manufacturing.dashboard_summary(organization_id))}
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :pipeline_max,
        Enum.max([
          assigns.summary.open_aggregations,
          assigns.summary.ready_to_ship,
          assigns.summary.shipped_this_week
        ])
      )

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer"}
      crumb="Dashboard"
    >
      <:tools>
        <.td_button
          id="manufacturer-view-products"
          variant="primary"
          label="View products"
          glyph="package"
          navigate={~p"/manufacturer/products"}
        />
      </:tools>

      <.td_dashboard
        id="manufacturer-dashboard"
        title="Manufacturer dashboard"
        subtitle="Products, serialisation activity, and SSCC issuance across your organization."
      >
        <:strip id="manufacturer-glances">
          <.td_glance_cell
            id="stat-manufacturer-products"
            navigate={~p"/manufacturer/products"}
            tone="neutral"
            value={phrase(@counts.products, "GTIN registered", "GTINs registered")}
            caption="Products in this organization"
          >
            <:icon><.td_icon name="package" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-manufacturer-batches"
            navigate={~p"/manufacturer/inventory"}
            tone="info"
            value={phrase(@counts.batches, "production batch", "production batches")}
            caption="Batches recorded"
          >
            <:icon><.td_icon name="stack" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-manufacturer-serials"
            navigate={~p"/manufacturer/products"}
            tone="success"
            value={phrase(@counts.serials, "serial generated", "serials generated")}
            caption="Serialised DataMatrix codes issued"
          >
            <:icon><.td_icon name="grid-four" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id="stat-manufacturer-ssccs"
            navigate={~p"/manufacturer/aggregations"}
            tone="warning"
            value={phrase(@counts.ssccs, "SSCC issued", "SSCCs issued")}
            caption="Shipper cases packed and labeled"
          >
            <:icon><.td_icon name="archive" class="size-[18px]" /></:icon>
          </.td_glance_cell>
        </:strip>

        <.td_dash_row>
          <.td_dash_card
            id="manufacturer-recent-serial-jobs"
            title="Recent serial jobs"
            subtitle="Latest DataMatrix issuance by batch"
          >
            <:actions>
              <.td_button label="View products" glyph="plus" navigate={~p"/manufacturer/products"} />
            </:actions>
            <table :if={@summary.recent_jobs != []} class="td-rows is-tight">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Batch</th>
                  <th class="is-num">Serials</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={job <- @summary.recent_jobs}
                  id={"serial-job-#{job.batch_id}"}
                  class="is-link"
                  phx-click={JS.navigate(~p"/manufacturer/products/#{job.product_id}")}
                >
                  <td>
                    {job.product_name}
                    <span class="td-mono td-sub">{job.gtin}</span>
                  </td>
                  <td class="td-mono">{job.batch_no}</td>
                  <td class="is-num">{number(job.serials)}</td>
                  <td>
                    <.td_badge
                      tone={if job.serials > 0, do: "success", else: "neutral"}
                      label={if job.serials > 0, do: "Issued", else: "No serials yet"}
                    />
                  </td>
                </tr>
              </tbody>
            </table>
            <p :if={@summary.recent_jobs == []} id="manufacturer-no-serial-jobs" class="td-dash-empty">
              No serial jobs yet. Add a product and record a batch to issue serials.
            </p>
          </.td_dash_card>

          <.td_dash_card
            id="manufacturer-aggregation-pipeline"
            title="Aggregation pipeline"
            subtitle="Cases waiting to be packed"
            width={340}
          >
            <.td_tick_row
              label="Open aggregations"
              caption="Serials grouped into SSCCs"
              count={@summary.open_aggregations}
              max={@pipeline_max}
              tone="warning"
              navigate={~p"/manufacturer/aggregations"}
            />
            <.td_tick_row
              label="Ready to ship"
              caption="SSCCs not yet on a shipment"
              count={@summary.ready_to_ship}
              max={@pipeline_max}
              tone="success"
              navigate={~p"/manufacturer/shipments"}
            />
            <.td_tick_row
              label="Shipped this week"
              caption="Shipments sent in the last 7 days"
              count={@summary.shipped_this_week}
              max={@pipeline_max}
              tone="success"
              navigate={~p"/manufacturer/shipments"}
            />
          </.td_dash_card>
        </.td_dash_row>
      </.td_dashboard>
    </Layouts.manufacturer_shell>
    """
  end

  defp phrase(count, singular, plural),
    do: "#{number(count)} #{if count == 1, do: singular, else: plural}"
end
