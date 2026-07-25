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
        scan_form: to_form(%{"gtin" => params["gtin"] || ""}),
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
        |> assign(:scan_form, to_form(%{"gtin" => gtin}))
        |> assign(:decode_error, nil)
        |> lookup_approved_batches(organization_id, site_id, gtin)

      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         scan_state: :idle,
         decode_error: "Please enter a valid GTIN.",
         scan_form: to_form(%{"gtin" => gtin}),
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
      <.header icon="hero-qr-code">
        Scan lookup
        <:subtitle>Check approved stock, location, expiry, and traceability details.</:subtitle>
      </.header>

      <section
        id="scan-lookup-panel"
        class="mb-5 rounded-xl border border-thamani-stone bg-thamani-snow p-4 sm:p-5"
      >
        <.form
          for={@scan_form}
          id="scan-form"
          phx-submit="decode"
          class="flex flex-col gap-3 sm:flex-row sm:items-end"
        >
          <div class="flex-1 [&>div]:mb-0">
            <.input
              field={@scan_form[:gtin]}
              label="GTIN or barcode"
              placeholder="00614141000012"
              autocomplete="off"
            />
          </div>
          <.button id="scan-submit" variant="primary">
            <.icon name="hero-magnifying-glass" class="mr-1 size-4" /> Look up stock
          </.button>
        </.form>
        <p
          :if={@decode_error}
          id="scan-decode-error"
          role="alert"
          class="mt-2 flex items-center gap-2 text-sm text-thamani-error"
        >
          <.icon name="hero-exclamation-circle" class="size-4 shrink-0" />
          {@decode_error}
        </p>
      </section>

      <%!-- Approved batch found at this site --%>
      <div :if={@scan_state == :found} id="scan-result-found">
        <div class="space-y-5 rounded-2xl border border-emerald-200 bg-emerald-50 p-5 sm:p-6">
          <div class="flex items-start justify-between gap-4">
            <div>
              <p class="text-xs font-semibold uppercase tracking-widest mb-1 text-emerald-700">
                Approved stock found
              </p>
              <h2 id="result-product-name" class="text-xl font-semibold text-thamani-forest">
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

          <dl class="grid grid-cols-1 gap-x-8 gap-y-4 border-t border-emerald-200 pt-4 sm:grid-cols-3">
            <div>
              <dt class="text-xs font-medium text-emerald-800/70">GTIN</dt>
              <dd id="result-gtin" class="mt-1 break-all font-mono text-sm font-medium">{@gtin}</dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-emerald-800/70">Batch / lot</dt>
              <dd id="result-batch-no" class="mt-1 text-sm font-medium">
                {if @batch_count > 1, do: "#{@batch_count} batches", else: hd(@batches).batch_no}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-emerald-800/70">Earliest expiry</dt>
              <dd
                id="result-expiry"
                class={[
                  "mt-1 text-sm font-medium tabular-nums",
                  Date.compare(@earliest_expiry, Date.utc_today()) == :lt && "text-thamani-error"
                ]}
              >
                {Calendar.strftime(@earliest_expiry, "%d %b %Y")} {if @batch_count > 1,
                  do: "(Earliest)"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-emerald-800/70">Site</dt>
              <dd id="result-site" class="mt-1 text-sm font-medium">{@site.name}</dd>
            </div>
            <div>
              <dt class="text-xs font-medium text-emerald-800/70">Remaining quantity</dt>
              <dd id="result-quantity" class="mt-1 text-lg font-semibold tabular-nums">
                {@total_qty}
              </dd>
            </div>
          </dl>
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
        <.blank_state icon="hero-qr-code" title="Ready to scan">
          Scan or paste a GTIN or barcode above to look up approved stock.
        </.blank_state>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
