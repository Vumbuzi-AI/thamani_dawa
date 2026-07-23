defmodule ThamaniDawaWeb.PharmacyScanLive do
  @moduledoc """
  GS1 scan-lookup for pharmacy staff to decode barcodes, find matching approved stock, and display product/batch details for traceability.

  UI states:
  - `:idle`         — No scan submitted yet.
  - `:found`        — Matched approved stock at the user's site (or org-wide for admins).
  - `:not_at_site`  — Stock is approved but held at a different site (for site-locked users).
  - `:unavailable`  — No approved stock found (missing, pending, or belongs to another org).
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  def mount(params, _session, socket) do
    socket =
      assign(socket,
        scan_state: :idle,
        decode_error: nil,
        gtin: nil,
        batches: [],
        product: nil,
        site: nil,
        total_qty: nil,
        earliest_expiry: nil,
        batch_count: 0
      )

    case params["gtin"] do
      gtin when is_binary(gtin) and gtin != "" ->
        organization_id = socket.assigns.current_scope.organization_id
        site_id = SiteScoping.default_site_id(socket.assigns.current_scope)

        {:ok, lookup_approved_batches(socket, organization_id, site_id, String.trim(gtin))}

      _ ->
        {:ok, socket}
    end
  end

  def handle_event("decode", %{"gtin" => gtin}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)
    gtin = String.trim(gtin)

    if gtin != "" do
      socket =
        socket
        |> assign(:decode_error, nil)
        |> lookup_approved_batches(organization_id, site_id, gtin)

      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         scan_state: :idle,
         decode_error: "Please enter a valid GTIN.",
         gtin: nil,
         batches: [],
         product: nil,
         site: nil
       )}
    end
  end

  defp lookup_approved_batches(socket, organization_id, site_id, gtin) do
    opts = if site_id, do: [site_id: site_id], else: []

    case Batches.find_approved_batches_by_gtin(
           organization_id,
           gtin,
           opts
         ) do
      {:ok, batches} ->
        product = Products.get_product!(organization_id, hd(batches).product_id)
        site = Sites.get_site!(organization_id, hd(batches).site_id)

        total_qty = calculate_total_quantity(batches)

        earliest_expiry =
          batches
          |> Enum.map(& &1.expiry_date)
          |> Enum.min(Date)

        assign(socket,
          scan_state: :found,
          gtin: gtin,
          batches: batches,
          product: product,
          site: site,
          total_qty: total_qty,
          earliest_expiry: earliest_expiry,
          batch_count: length(batches)
        )

      {:error, :not_at_site} ->
        assign(socket,
          scan_state: :not_at_site,
          gtin: gtin,
          batches: [],
          product: nil,
          site: nil
        )

      {:error, :not_found} ->
        assign(socket,
          scan_state: :unavailable,
          gtin: gtin,
          batches: [],
          product: nil,
          site: nil
        )
    end
  end

  defp calculate_total_quantity(batches) do
    Enum.reduce(batches, 0, fn b, acc -> b.remaining_quantity + acc end)
  end

  defp product_display_name(product) do
    [product.generic_name, product.brand_name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> case do
      [] -> "(unnamed product)"
      names -> Enum.join(names, " / ")
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/scan"
    >
      <.header>
        Scan lookup
        <:subtitle>Decode a GS1 barcode to check approved stock and traceability details</:subtitle>
      </.header>

      <div class="card bg-base-200 mb-6">
        <div class="card-body">
          <form
            id="scan-form"
            phx-submit="decode"
            class="flex flex-col gap-3 sm:flex-row sm:items-end"
          >
            <div class="flex-1">
              <.input
                name="gtin"
                label="GTIN / Barcode"
                placeholder="00614141000012"
                autocomplete="off"
              />
            </div>
            <.button id="scan-submit" variant="primary" class="sm:mb-0.5">
              <.icon name="hero-qr-code" class="size-4 mr-1" />Lookup
            </.button>
          </form>
          <p :if={@decode_error} id="scan-decode-error" class="mt-2 text-error text-sm">
            {@decode_error}
          </p>
        </div>
      </div>

      <%!-- Approved batch found at this site --%>
      <div :if={@scan_state == :found} id="scan-result-found">
        <div class="rounded-2xl border border-emerald-200 bg-emerald-50 p-6 space-y-5">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest mb-1 text-emerald-700">
                Approved stock found
              </p>
              <h2 id="result-product-name" class="text-xl font-bold text-thamani-forest">
                {product_display_name(@product)}
              </h2>
              <p class="text-sm mt-0.5 text-emerald-700">
                {if @product.category, do: @product.category}
                {if @product.uom, do: "· #{@product.uom}"}
              </p>
            </div>
            <span class="shrink-0 inline-flex items-center gap-1.5 rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-700">
              <.icon name="hero-check-circle" class="size-3.5" />Approved
            </span>
          </div>

          <div class="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3">
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">GTIN</p>
              <p id="result-gtin" class="font-mono text-sm font-semibold">{@gtin}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Batch / lot</p>
              <p id="result-batch-no" class="text-sm font-semibold">
                {if @batch_count > 1, do: "#{@batch_count} batches", else: hd(@batches).batch_no}
              </p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Expiry date</p>
              <p
                id="result-expiry"
                class={[
                  "text-sm font-semibold",
                  Date.compare(@earliest_expiry, Date.utc_today()) == :lt && "text-error"
                ]}
              >
                {Calendar.strftime(@earliest_expiry, "%d %b %Y")} {if @batch_count > 1,
                  do: "(Earliest)"}
              </p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Site</p>
              <p id="result-site" class="text-sm font-semibold">{@site.name}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Remaining qty</p>
              <p id="result-quantity" class="text-sm font-semibold">{@total_qty}</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Batch exists in org but not at this pharmacist's site --%>
      <div :if={@scan_state == :not_at_site} id="scan-result-not-at-site">
        <div class="rounded-2xl border border-amber-200 bg-amber-50 p-6">
          <div class="flex items-start gap-4">
            <div class="shrink-0 rounded-full bg-amber-100 p-2">
              <.icon name="hero-building-office-2" class="size-5 text-amber-800" />
            </div>
            <div>
              <p id="scan-not-at-site-heading" class="font-semibold text-base text-amber-800">
                Not at your site
              </p>
              <p class="text-sm mt-1 text-amber-700">
                This product GTIN
                (<span class="font-mono font-semibold">{@gtin}</span>)
                is approved stock in your organisation but is held at a different site.
                Contact your admin if a transfer is needed.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Code decoded but no approved stock found anywhere in org --%>
      <div :if={@scan_state == :unavailable} id="scan-result-unavailable">
        <div class="rounded-2xl border border-rose-200 bg-rose-50 p-6">
          <div class="flex items-start gap-4">
            <div class="shrink-0 rounded-full bg-rose-100 p-2">
              <.icon name="hero-no-symbol" class="size-5 text-rose-700" />
            </div>
            <div>
              <p id="scan-unavailable-heading" class="font-semibold text-base text-rose-800">
                No approved stock found
              </p>
              <p class="text-sm mt-1 text-rose-700">
                Product GTIN <span class="font-mono font-semibold">{@gtin}</span>
                was not found in approved stock.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Idle — nothing scanned yet --%>
      <div :if={@scan_state == :idle} id="scan-idle-hint">
        <p class="text-sm text-base-content/50 text-center py-8">
          Scan or paste a GTIN or barcode above to look up stock.
        </p>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
