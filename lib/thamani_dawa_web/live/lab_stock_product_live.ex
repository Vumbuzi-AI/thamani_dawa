defmodule ThamaniDawaWeb.LabStockProductLive do
  @moduledoc """
  One product's batches at the viewer's lab sites (Doop eKD_3r3UqQ), reached
  from `LabStockLive`. Read-only; rendered by `ThamaniDawaWeb.SiteStock`.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteStock

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    sites = if Scope.admin?(scope), do: Sites.list_sites(org_id), else: scope.user.sites
    lab_site_ids = sites |> Enum.filter(&Site.lab?/1) |> Enum.map(& &1.id)

    allowed_site_ids =
      case scope.current_site_id do
        nil -> lab_site_ids
        current_id -> [current_id]
      end

    product = Products.get_product!(org_id, id)
    batches = Batches.list_batches_for_product(org_id, id, allowed_site_ids)

    {:ok,
     socket
     |> assign(:page_title, SiteStock.product_name(product))
     |> assign(:product, product)
     |> assign(:batches, batches)
     |> assign(:today, ThamaniDawa.BusinessDate.today())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/lab/stock"
      crumb_parent="Stock"
      crumb={SiteStock.product_name(@product)}
    >
      <SiteStock.product_detail
        product={@product}
        batches={@batches}
        today={@today}
        back_path={~p"/lab/stock"}
        scan_path={~p"/lab/scan"}
        requisition_path={~p"/lab/requisitions/new"}
        batch_path={fn id -> ~p"/lab/stock/batches/#{id}" end}
      />
    </Layouts.lab_shell>
    """
  end
end
