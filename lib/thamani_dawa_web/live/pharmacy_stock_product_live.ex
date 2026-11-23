defmodule ThamaniDawaWeb.PharmacyStockProductLive do
  @moduledoc """
  One product's batches at the viewer's sites (Doop k6in9fJ2Ub; pharma-lab
  MS7rEsXApn), reached from `PharmacyStockLive`. Admins without a picked
  site see every site; everyone else sees their current site. Read-only;
  rendered by `ThamaniDawaWeb.SiteStock`.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawaWeb.SiteStock

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    product = Products.get_product!(org_id, id)
    allowed_site_ids = if Scope.admin?(scope), do: nil, else: [scope.current_site_id]

    {:ok,
     socket
     |> assign(:page_title, SiteStock.product_name(product))
     |> assign(:product, product)
     |> assign(:batches, Batches.list_batches_for_product(org_id, id, allowed_site_ids))
     |> assign(:today, ThamaniDawa.BusinessDate.today())}
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
      crumb_parent="Stock"
      crumb={SiteStock.product_name(@product)}
    >
      <SiteStock.product_detail
        product={@product}
        batches={@batches}
        today={@today}
        back_path={~p"/pharmacy/stock"}
        scan_path={~p"/pharmacy/scan"}
        requisition_path={~p"/pharmacy/requisitions/new"}
        batch_path={fn id -> ~p"/pharmacy/stock/batches/#{id}" end}
      />
    </Layouts.pharmacy_shell>
    """
  end
end
