defmodule ThamaniDawaWeb.PharmacyStockBatchLive do
  @moduledoc """
  One batch and who has drawn from it (Doop UlUYBX60A_; pharma-lab
  hXPInx920g), with the Print Data Matrix dialog (87EK_g6B4h, NoAAUBFYIM).
  Reached from `PharmacyStockProductLive` or the All batches tab on
  `PharmacyStockLive`. Read-only.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawaWeb.SiteStock

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    _ =
      if Scope.admin?(scope),
        do: :ok,
        else: Batches.get_batch_for_site!(org_id, id, scope.current_site_id)

    batch = Batches.get_batch_with_details!(org_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Batch #{batch.batch_no}")
     |> assign(:batch, batch)
     |> assign(:history, SiteStock.usage_history(batch))
     |> assign(:today, ThamaniDawa.BusinessDate.today())
     |> assign(:printing, false)}
  end

  def handle_event("open_print", _params, socket), do: {:noreply, assign(socket, :printing, true)}

  def handle_event("close_print", _params, socket),
    do: {:noreply, assign(socket, :printing, false)}

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
      crumb_parent="Stock"
      crumb={@batch.batch_no}
    >
      <SiteStock.batch_detail
        batch={@batch}
        history={@history}
        today={@today}
        printing={@printing}
        back_path={~p"/pharmacy/stock/products/#{@batch.product_id}"}
      />
    </Layouts.pharmacy_shell>
    """
  end
end
