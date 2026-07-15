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
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       scan_state: :idle,
       decode_error: nil,
       parsed: nil,
       batch: nil,
       product: nil,
       site: nil
     )}
  end

  def handle_event("decode", %{"raw_gs1" => raw_gs1}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)

    case GS1Decoder.parse(raw_gs1) do
      {:ok, %{gtin: gtin, batch_no: batch_no} = parsed}
      when is_binary(gtin) and gtin != "" and is_binary(batch_no) and batch_no != "" ->
        socket =
          socket
          |> assign(:decode_error, nil)
          |> lookup_approved_batch(organization_id, site_id, parsed)

        {:noreply, socket}

      {:ok, _incomplete} ->
        {:noreply,
         assign(socket,
           scan_state: :idle,
           decode_error: "That code is missing a GTIN or batch/lot number.",
           parsed: nil,
           batch: nil,
           product: nil,
           site: nil
         )}

      {:error, _reason} ->
        {:noreply,
         assign(socket,
           scan_state: :idle,
           decode_error: "Couldn't decode that GS1 code. Check the format and try again.",
           parsed: nil,
           batch: nil,
           product: nil,
           site: nil
         )}
    end
  end

  defp lookup_approved_batch(socket, organization_id, site_id, parsed) do
    opts = if site_id, do: [site_id: site_id], else: []

    case Batches.find_approved_batch_for_scan(
           organization_id,
           parsed.gtin,
           parsed.batch_no,
           opts
         ) do
      {:ok, batch} ->
        product = Products.get_product!(organization_id, batch.product_id)
        site = Sites.get_site!(organization_id, batch.site_id)

        assign(socket,
          scan_state: :found,
          parsed: parsed,
          batch: batch,
          product: product,
          site: site
        )

      {:error, :not_at_site} ->
        assign(socket,
          scan_state: :not_at_site,
          parsed: parsed,
          batch: nil,
          product: nil,
          site: nil
        )

      {:error, :not_found} ->
        assign(socket,
          scan_state: :unavailable,
          parsed: parsed,
          batch: nil,
          product: nil,
          site: nil
        )
    end
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
                name="raw_gs1"
                label="GS1 element string"
                placeholder="(01)00614141000012(10)LOT123(17)261231"
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
        <div
          class="rounded-2xl border p-6 space-y-5"
          style="background: #f0fce8; border-color: #a8e26a;"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest mb-1" style="color: #4a7a1e;">
                Approved stock found
              </p>
              <h2 id="result-product-name" class="text-xl font-bold" style="color: #1c3a13;">
                {product_display_name(@product)}
              </h2>
              <p class="text-sm mt-0.5" style="color: #4a7a1e;">
                {if @product.category, do: @product.category}
                {if @product.uom, do: "· #{@product.uom}"}
              </p>
            </div>
            <span
              class="shrink-0 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold"
              style="background: #d3fa99; color: #1c3a13;"
            >
              <.icon name="hero-check-circle" class="size-3.5" />Approved
            </span>
          </div>

          <div class="grid grid-cols-2 gap-x-8 gap-y-3 sm:grid-cols-3">
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">GTIN</p>
              <p id="result-gtin" class="font-mono text-sm font-semibold">{@batch.gtin}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Batch / lot</p>
              <p id="result-batch-no" class="font-mono text-sm font-semibold">{@batch.batch_no}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Expiry date</p>
              <p
                id="result-expiry"
                class={[
                  "text-sm font-semibold",
                  Date.compare(@batch.expiry_date, Date.utc_today()) == :lt && "text-error"
                ]}
              >
                {Calendar.strftime(@batch.expiry_date, "%d %b %Y")}
              </p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Site</p>
              <p id="result-site" class="text-sm font-semibold">{@site.name}</p>
            </div>
            <div>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Remaining qty</p>
              <p id="result-quantity" class="text-sm font-semibold">{@batch.remaining_quantity}</p>
            </div>
            <div :if={@batch.manufacture_date}>
              <p class="text-xs text-base-content/50 uppercase tracking-wide">Manufacture date</p>
              <p class="text-sm">{Calendar.strftime(@batch.manufacture_date, "%d %b %Y")}</p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Batch exists in org but not at this pharmacist's site --%>
      <div :if={@scan_state == :not_at_site} id="scan-result-not-at-site">
        <div
          class="rounded-2xl border p-6"
          style="background: #fffbeb; border-color: #fcd34d;"
        >
          <div class="flex items-start gap-4">
            <div class="shrink-0 rounded-full p-2" style="background: #fef3c7;">
              <.icon name="hero-building-office-2" class="size-5 text-amber-800" />
            </div>
            <div>
              <p
                id="scan-not-at-site-heading"
                class="font-semibold text-base"
                style="color: #78350f;"
              >
                Not at your site
              </p>
              <p class="text-sm mt-1" style="color: #92400e;">
                This batch
                (<span class="font-mono font-semibold">{@parsed.batch_no}</span>)
                is approved stock in your organisation but is held at a different site.
                Contact your admin if a transfer is needed.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Code decoded but no approved stock found anywhere in org --%>
      <div :if={@scan_state == :unavailable} id="scan-result-unavailable">
        <div
          class="rounded-2xl border p-6"
          style="background: #fff8f0; border-color: #f5c08a;"
        >
          <div class="flex items-start gap-4">
            <div class="shrink-0 rounded-full p-2" style="background: #fde8c8;">
              <.icon name="hero-no-symbol" class="size-5 text-amber-700" />
            </div>
            <div>
              <p
                id="scan-unavailable-heading"
                class="font-semibold text-base"
                style="color: #92400e;"
              >
                No approved stock found
              </p>
              <p class="text-sm mt-1" style="color: #b45309;">
                Batch <span class="font-mono font-semibold">{@parsed.batch_no}</span>
                (GTIN <span class="font-mono font-semibold">{@parsed.gtin}</span>)
                was not found in approved stock.
              </p>
            </div>
          </div>
        </div>
      </div>

      <%!-- Idle — nothing scanned yet --%>
      <div :if={@scan_state == :idle} id="scan-idle-hint">
        <p class="text-sm text-base-content/50 text-center py-8">
          Scan or paste a GS1 element string above to look up stock.
        </p>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
