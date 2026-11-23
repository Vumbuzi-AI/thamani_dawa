defmodule ThamaniDawaWeb.ManufacturerDashboardLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    counts = Manufacturing.dashboard_counts(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Manufacturer dashboard")
     |> assign(:counts, counts)}
  end

  def render(assigns) do
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
          navigate={~p"/manufacturer/products"}
        />
      </:tools>

      <.td_list_page
        title="Manufacturer dashboard"
        subtitle="Products, serialisation activity, and SSCC issuance across your organization."
      >
        <:actions>
          <.td_button variant="secondary" label="View products" navigate={~p"/manufacturer/products"} />
        </:actions>
        <div class="td-stats">
          <.td_stat id="stat-manufacturer-products" caption="Products" value={@counts.products} />
          <.td_stat id="stat-manufacturer-batches" caption="Batches" value={@counts.batches} />
          <.td_stat
            id="stat-manufacturer-serials"
            caption="Serials generated"
            value={@counts.serials}
          />
          <.td_stat id="stat-manufacturer-ssccs" caption="SSCCs issued" value={@counts.ssccs} />
        </div>
      </.td_list_page>
    </Layouts.manufacturer_shell>
    """
  end
end
