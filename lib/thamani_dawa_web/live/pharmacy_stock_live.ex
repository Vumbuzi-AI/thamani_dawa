defmodule ThamaniDawaWeb.PharmacyStockLive do
  @moduledoc """
  Read-only stock for pharmacy and combined pharmacy-lab sites (Doop
  puMtQXqNOq products, fO2XgZ8Xir all batches; pharma-lab c3EiqRelu0,
  fiY29WINlP). Admins see every site in the organization, with a Site
  filter to narrow down. Other staff see only their assigned sites (or the
  picked current site): both the data and the Site filter's options are
  limited to that set, and a hand-crafted site value outside it is dropped.
  Nothing here mutates a batch — receiving and dispensing stay on
  `ReceiveStockLive` and `PrescriptionLive`.

  Same page as `LabStockLive`, rendered and filtered by
  `ThamaniDawaWeb.SiteStock`.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteStock

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    sites = if Scope.admin?(scope), do: Sites.list_sites(org_id), else: scope.user.sites

    allowed_site_ids =
      case scope.current_site_id do
        nil -> Enum.map(sites, & &1.id)
        current_id -> [current_id]
      end

    site_options = for site <- sites, site.id in allowed_site_ids, do: {site.name, site.id}

    {:ok,
     socket
     |> assign(:page_title, "Stock")
     |> assign(:admin_wide?, Scope.admin?(scope) and is_nil(scope.current_site_id))
     |> SiteStock.init(Batches.list_site_stock(org_id, allowed_site_ids), allowed_site_ids,
       sites: site_options,
       base_path: "/pharmacy/stock",
       export_prefix: "pharmacy-stock"
     )}
  end

  def handle_params(params, _url, socket), do: {:noreply, SiteStock.apply_params(socket, params)}

  def handle_event(event, params, socket), do: SiteStock.handle_event(event, params, socket)

  defp subtitle(true, _ids), do: "Every batch across every site in your organization, read-only."
  defp subtitle(false, [_one]), do: "Every batch across your site, read-only."
  defp subtitle(false, _ids), do: "Every batch across your assigned sites, read-only."

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
      crumb="Stock"
    >
      <:search>
        <form phx-change="search" id="search-form" onsubmit="return false">
          <.td_search
            name="search"
            value={@search}
            placeholder="Search product, GTIN or batch"
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <:tools>
        <.td_button
          id="pharmacy-stock-receive"
          variant="primary"
          label="Receive stock"
          glyph="tray-arrow-down"
          navigate={~p"/pharmacy/receive-stock"}
        />
      </:tools>

      <SiteStock.stock_page
        id="pharmacy-stock"
        title="Stock"
        subtitle={subtitle(@admin_wide?, @allowed_site_ids)}
        base_path="/pharmacy/stock"
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
        stock_takes_path={~p"/pharmacy/stock-takes"}
        disposals_path={~p"/pharmacy/disposals"}
        scan_path={~p"/pharmacy/scan"}
        requisition_path={~p"/pharmacy/requisitions/new"}
        product_path={fn id -> ~p"/pharmacy/stock/products/#{id}" end}
        batch_path={fn id -> ~p"/pharmacy/stock/batches/#{id}" end}
        empty_hint="Batches received at your site appear here."
        receive_path={~p"/pharmacy/receive-stock"}
      />
    </Layouts.pharmacy_shell>
    """
  end
end
