defmodule ThamaniDawaWeb.ReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    suppliers_by_id =
      organization_id |> Suppliers.list_suppliers() |> Map.new(&{&1.id, &1})

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
     |> assign(:suppliers_by_id, suppliers_by_id)
     |> assign(:gs1_decode_error, nil)
     |> assign(:scan_form, to_form(%{"raw_gs1" => ""}))
     |> assign(:receive_batch, nil)
     |> assign(:receive_form, nil)
     |> stream(:pending_batches, pending_batches)}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    apply_action(socket, socket.assigns.live_action, id)
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_index(socket)}
  end

  defp apply_action(socket, :receive, batch_id) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, String.to_integer(batch_id))

    {:noreply,
     socket
     |> assign(:receive_batch, batch)
     |> assign(:receive_form, to_form(%{"quantity" => batch.quantity}, as: :receive))}
  end

  defp apply_index(socket) do
    socket
    |> assign(:receive_batch, nil)
    |> assign(:receive_form, nil)
  end

  def handle_event("receive_via_gs1", %{"raw_gs1" => raw_gs1}, socket) do
    socket = assign(socket, :scan_form, to_form(%{"raw_gs1" => raw_gs1}))

    case GS1Decoder.parse(raw_gs1) do
      {:ok, %{gtin: gtin, batch_no: batch_no}} when is_binary(gtin) and is_binary(batch_no) ->
        receive_matching_pending_batch(socket, gtin, batch_no)

      {:ok, _incomplete} ->
        {:noreply,
         assign(socket, :gs1_decode_error, "That code is missing a GTIN or batch/lot number")}

      {:error, _reason} ->
        {:noreply, assign(socket, :gs1_decode_error, decode_error_message(raw_gs1))}
    end
  end

  def handle_event("receive", %{"receive" => %{"quantity" => quantity}}, socket) do
    batch = socket.assigns.receive_batch

    cond do
      is_nil(batch) ->
        {:noreply, put_flash(socket, :error, "No batch selected.")}

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

  defp decode_error_message(raw_gs1) do
    if bare_gtin?(raw_gs1) do
      "That looks like a bare GTIN — scan the full barcode (it also encodes the batch/lot " <>
        "number), or use the Receive button in the table below."
    else
      "Couldn't decode that code"
    end
  end

  defp bare_gtin?(raw), do: String.match?(raw, ~r/^\d{8}$|^\d{12,14}$/)

  defp do_receive(socket, batch, quantity) do
    scope = socket.assigns.current_scope

    case Batches.receive_batch(batch, scope.user.id, %{"quantity" => quantity}) do
      {:ok, received} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock received.")
         |> assign(:gs1_decode_error, nil)
         |> assign(:receive_batch, nil)
         |> assign(:receive_form, nil)
         |> stream_delete(:pending_batches, received)
         |> push_patch(to: ~p"/pharmacy/receive-stock")}

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

  defp supplier_name(suppliers_by_id, supplier_id) do
    case Map.get(suppliers_by_id, supplier_id) do
      nil -> "—"
      supplier -> supplier.name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/receive-stock"
    >
      <.header icon="hero-arrow-down-tray">
        Receive stock
        <:subtitle>
          Confirm dispatched batches at your site by scanning or reviewing the delivery.
        </:subtitle>
      </.header>

      <.modal
        :if={@live_action == :receive and not is_nil(@receive_batch)}
        id="receive-batch-modal"
        show
        on_cancel={JS.patch(~p"/pharmacy/receive-stock")}
      >
        <h2 class="mb-1 font-semibold text-slate-900">Receive batch</h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          Confirm the quantity actually received for this batch.
        </p>
        <dl class="mb-4 grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Product</dt>
            <dd class="mt-0.5 font-medium text-slate-900">
              {product_name(@products_by_id, @receive_batch.product_id)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Batch / lot
            </dt>
            <dd class="mt-0.5 font-mono">{@receive_batch.batch_no}</dd>
          </div>
          <div :if={@receive_batch.serial}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Serial</dt>
            <dd class="mt-0.5 font-mono">{@receive_batch.serial}</dd>
          </div>
          <div :if={@receive_batch.manufacture_date}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufacture date
            </dt>
            <dd class="mt-0.5">{@receive_batch.manufacture_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Expiry</dt>
            <dd class="mt-0.5">{@receive_batch.expiry_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Site</dt>
            <dd class="mt-0.5">{site_name(@sites_by_id, @receive_batch.site_id)}</dd>
          </div>
        </dl>
        <.form
          for={@receive_form}
          id="receive-batch-form"
          phx-submit="receive"
          class="flex flex-col gap-4"
        >
          <.input
            field={@receive_form[:quantity]}
            type="number"
            label="Quantity received"
            min="0"
            required
          />
          <div class="flex gap-2">
            <.button variant="primary" phx-disable-with="Receiving…">Confirm receipt</.button>
            <.button patch={~p"/pharmacy/receive-stock"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <section
        id="receive-stock-scan-panel"
        class="mb-5 rounded-xl border border-thamani-stone bg-thamani-snow p-4 sm:p-5"
      >
        <div class="mb-4 flex items-start gap-3">
          <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-thamani-lime text-thamani-forest">
            <.icon name="hero-qr-code" class="size-5" />
          </div>
          <div>
            <h2 class="text-base font-semibold text-thamani-forest">Scan to receive</h2>
            <p class="mt-0.5 text-sm text-thamani-pewter">
              Scan the full GS1 barcode to match and receive a pending batch immediately.
            </p>
          </div>
        </div>
        <.form
          for={@scan_form}
          id="receive-stock-gs1-form"
          phx-submit="receive_via_gs1"
          class="flex flex-col gap-3 sm:flex-row sm:items-end"
        >
          <div class="flex-1 [&>div]:mb-0">
            <.input
              field={@scan_form[:raw_gs1]}
              label="GS1 barcode"
              placeholder="(01)0...(10)LOT1(17)261231"
              autocomplete="off"
            />
          </div>
          <.button variant="primary" phx-disable-with="Receiving…">
            Scan and receive
          </.button>
        </.form>
        <p
          :if={@gs1_decode_error}
          id="gs1-decode-error"
          role="alert"
          class="mt-2 flex items-center gap-2 text-sm text-thamani-error"
        >
          <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
          {@gs1_decode_error}
        </p>
      </section>

      <.table id="pending-batches" rows={@streams.pending_batches}>
        <:col :let={{_id, batch}} label="Product">
          <div class="font-medium text-thamani-forest">
            {product_name(@products_by_id, batch.product_id)}
          </div>
          <div class="mt-0.5 font-mono text-xs text-thamani-subtle">{batch.gtin}</div>
        </:col>
        <:col :let={{_id, batch}} label="Site">{site_name(@sites_by_id, batch.site_id)}</:col>
        <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
        <:col :let={{_id, batch}} label="Serial">{batch.serial || "—"}</:col>
        <:col :let={{_id, batch}} label="Manufacture date">{batch.manufacture_date || "—"}</:col>
        <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={{_id, batch}} label="Expected">
          <span class="tabular-nums">{batch.quantity}</span>
        </:col>
        <:col :let={{_id, batch}} label="Supplier">
          {supplier_name(@suppliers_by_id, batch.supplier_id)}
        </:col>
        <:action :let={{_id, batch}}>
          <.button
            variant="ghost"
            patch={~p"/pharmacy/receive-stock/#{batch.id}/receive"}
            class="gap-2"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" />
            Receive
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-check-circle" title="Nothing awaiting receipt">
            Batches dispatched to your site will appear here for confirmation.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
