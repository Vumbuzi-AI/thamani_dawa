defmodule ThamaniDawaWeb.LabStockLive do
  @moduledoc """
  Read-only stock for lab sites (Doop _VFeE7v1Z3 products, QxyvdDb1ea all
  batches). Admins see every lab site in the organization; lab staff
  (lab_technician, pharma_lab) see their assigned lab sites, and a picked
  current site narrows it to that site. Nothing here mutates a batch —
  receiving stays on `LabReceiveStockLive`.

  Filters, tab and page live in the URL so the stat strip can link to a
  filtered view. Rows are rolled up and filtered in memory by
  `ThamaniDawaWeb.SiteStock`, which also renders the page.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteStock

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    sites =
      if Scope.admin?(scope), do: Sites.list_sites(scope.organization_id), else: scope.user.sites

    lab_sites = Enum.filter(sites, &Site.lab?/1)

    allowed_site_ids =
      case scope.current_site_id do
        nil -> Enum.map(lab_sites, & &1.id)
        current_id -> [current_id]
      end

    batches = Batches.list_site_stock(scope.organization_id, allowed_site_ids)

    site_options =
      for site <- lab_sites, site.id in allowed_site_ids, do: {site.name, site.id}

    {:ok,
     socket
     |> assign(:page_title, "Lab stock")
     |> SiteStock.init(batches, allowed_site_ids,
       sites: site_options,
       base_path: "/lab/stock",
       export_prefix: "lab-stock"
     )}
  end

  def handle_params(params, _url, socket), do: {:noreply, SiteStock.apply_params(socket, params)}

  def handle_event(event, params, socket), do: SiteStock.handle_event(event, params, socket)

  defp subtitle([_one]), do: "Every batch across your site, read-only."
  defp subtitle(_site_ids), do: "Every batch across your lab sites, read-only."

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/lab/stock"
      crumb="Stock"
    >
      <:tools>
        <.td_button
          id="lab-stock-receive"
          variant="primary"
          label="Receive stock"
          glyph="tray-arrow-down"
          navigate={~p"/lab/receive-stock"}
        />
      </:tools>

      <SiteStock.stock_page
        id="lab-stock"
        title="Lab stock"
        subtitle={subtitle(@allowed_site_ids)}
        base_path="/lab/stock"
        view={@view}
        entries={@entries}
        total={@total}
        page={@page}
        last_page={@last_page}
        search={@search}
        filters={@filters}
        sites={@site_options}
        categories={@categories}
        stats={@stats}
        tick_max={@tick_max}
        today={@today}
        filtered?={@filtered?}
        exporting={@exporting}
        csv_ready={@csv_ready}
        stock_takes_path={~p"/lab/stock-takes"}
        disposals_path={~p"/lab/disposals"}
        scan_path={~p"/lab/scan"}
        requisition_path={~p"/lab/requisitions/new"}
        product_path={fn id -> ~p"/lab/stock/products/#{id}" end}
        batch_path={fn id -> ~p"/lab/stock/batches/#{id}" end}
        empty_hint="Batches received at your lab site appear here."
      />
    </Layouts.lab_shell>
    """
  end
end
