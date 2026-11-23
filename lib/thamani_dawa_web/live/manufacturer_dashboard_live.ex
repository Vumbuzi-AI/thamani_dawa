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
    >
      <.header icon="hero-squares-2x2">
        Manufacturer dashboard
        <:subtitle>
          Products, serialisation activity, and SSCC issuance across your organization.
        </:subtitle>
        <:actions>
          <.button
            id="manufacturer-new-product"
            variant="primary"
            navigate={~p"/manufacturer/products/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add product
          </.button>
        </:actions>
      </.header>

      <p class="dashboard-section-label mt-6">Overview</p>
      <div class="dashboard-stat-grid mt-2">
        <.stat_tile
          id="stat-manufacturer-products"
          icon="hero-archive-box"
          label="Products"
          value={@counts.products}
          sublabel="GTINs registered to this organization"
        />
        <.stat_tile
          id="stat-manufacturer-batches"
          icon="hero-cube"
          label="Batches"
          value={@counts.batches}
          sublabel="Production batches recorded"
        />
        <.stat_tile
          id="stat-manufacturer-serials"
          icon="hero-qr-code"
          label="Serials generated"
          value={@counts.serials}
          sublabel="Serialised DataMatrix codes issued"
        />
        <.stat_tile
          id="stat-manufacturer-ssccs"
          icon="hero-cube-transparent"
          label="SSCCs issued"
          value={@counts.ssccs}
          sublabel="Shipper cases packed and labeled"
        />
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
