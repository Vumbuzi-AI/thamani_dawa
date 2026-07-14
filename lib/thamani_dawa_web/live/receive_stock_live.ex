defmodule ThamaniDawaWeb.ReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    pending_batches =
      organization_id
      |> Batches.list_pending_batches()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(&pharmacy_capable_site?(sites_by_id, &1))
      |> Enum.sort_by(& &1.expiry_date, Date)

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:gs1_decode_error, nil)
     |> stream(:pending_batches, pending_batches)}
  end

  def handle_event("receive_via_gs1", %{"raw_gs1" => raw_gs1}, socket) do
    case GS1Decoder.parse(raw_gs1) do
      {:ok, %{gtin: gtin, batch_no: batch_no}} when is_binary(gtin) and is_binary(batch_no) ->
        receive_matching_pending_batch(socket, gtin, batch_no)

      {:ok, _incomplete} ->
        {:noreply,
         assign(socket, :gs1_decode_error, "That code is missing a GTIN or batch/lot number")}

      {:error, _reason} ->
        {:noreply, assign(socket, :gs1_decode_error, "Couldn't decode that code")}
    end
  end

  def handle_event("receive", %{"batch_id" => id, "quantity" => quantity}, socket) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, id)

    cond do
      not pharmacy_capable_site?(socket.assigns.sites_by_id, batch) ->
        {:noreply, put_flash(socket, :error, "That site isn't set up for pharmacy stock.")}

      match?({_int, ""}, Integer.parse(quantity)) ->
        {quantity, ""} = Integer.parse(quantity)
        do_receive(socket, batch, quantity)

      true ->
        {:noreply, put_flash(socket, :error, "Enter a valid quantity.")}
    end
  end

  defp receive_matching_pending_batch(socket, gtin, batch_no) do
    scope = socket.assigns.current_scope
    site_id = SiteScoping.default_site_id(scope)

    case Batches.find_pending_batch(scope.organization_id, gtin, batch_no, site_id: site_id) do
      {:ok, batch} ->
        if pharmacy_capable_site?(socket.assigns.sites_by_id, batch) do
          do_receive(socket, batch, batch.quantity)
        else
          {:noreply, assign(socket, :gs1_decode_error, "No matching pending batch at your site")}
        end

      {:error, :not_found} ->
        {:noreply, assign(socket, :gs1_decode_error, "No matching pending batch at your site")}
    end
  end

  defp do_receive(socket, batch, quantity) do
    scope = socket.assigns.current_scope

    case Batches.receive_batch(batch, scope.user.id, %{"quantity" => quantity}) do
      {:ok, received} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock received.")
         |> assign(:gs1_decode_error, nil)
         |> stream_delete(:pending_batches, received)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't receive that batch.")}
    end
  end

  defp pharmacy_capable_site?(sites_by_id, batch) do
    case Map.get(sites_by_id, batch.site_id) do
      nil -> false
      site -> Site.pharmacy?(site)
    end
  end

  defp product_name(products_by_id, product_id) do
    case Map.get(products_by_id, product_id) do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  defp site_name(sites_by_id, site_id) do
    case Map.get(sites_by_id, site_id) do
      nil -> "—"
      site -> site.name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/receive-stock"
    >
      <.header>
        Receive stock
        <:subtitle>Batches dispatched to your site, awaiting confirmation</:subtitle>
      </.header>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Scan to receive</h2>
          <form
            id="receive-stock-gs1-form"
            phx-submit="receive_via_gs1"
            class="flex gap-2 items-end"
          >
            <div class="flex-1">
              <.input
                name="raw_gs1"
                label="Raw GS1 element string"
                placeholder="(01)0...(10)LOT1(17)261231"
              />
            </div>
            <.button class="mb-2">Scan &amp; receive</.button>
          </form>
          <p :if={@gs1_decode_error} id="gs1-decode-error" class="mt-2 text-error">
            {@gs1_decode_error}
          </p>
        </div>
      </div>

      <.table id="pending-batches" rows={@streams.pending_batches}>
        <:col :let={{_id, batch}} label="Product">
          {product_name(@products_by_id, batch.product_id)}
        </:col>
        <:col :let={{_id, batch}} label="Site">{site_name(@sites_by_id, batch.site_id)}</:col>
        <:col :let={{_id, batch}} label="GTIN">{batch.gtin}</:col>
        <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
        <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
        <:action :let={{_id, batch}}>
          <form id={"receive-batch-#{batch.id}"} phx-submit="receive" class="flex gap-2 items-center">
            <input type="hidden" name="batch_id" value={batch.id} />
            <input
              type="number"
              name="quantity"
              value={batch.quantity}
              min="0"
              class="input input-sm w-24"
            />
            <.button variant="primary" class="btn-sm">Receive</.button>
          </form>
        </:action>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
