defmodule ThamaniDawaWeb.LabScanLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       parsed: nil,
       batch: nil,
       product: nil,
       site: nil,
       scan_form: to_form(%{"raw_gs1" => ""})
     )}
  end

  def handle_event("decode", %{"raw_gs1" => raw_gs1}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    socket = assign(socket, :scan_form, to_form(%{"raw_gs1" => raw_gs1}))

    case GS1Decoder.parse(raw_gs1) do
      {:ok, parsed} ->
        batch =
          organization_id
          |> Batches.list_batches()
          |> Enum.find(&(&1.gtin == parsed.gtin and &1.batch_no == parsed.batch_no))

        product = batch && Products.get_product!(organization_id, batch.product_id)
        site = if is_nil(batch) and parsed.gln, do: gln_site(organization_id, parsed.gln)

        {:noreply, assign(socket, parsed: parsed, batch: batch, product: product, site: site)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't decode that code: #{inspect(reason)}")}
    end
  end

  defp gln_site(organization_id, gln) do
    case Sites.get_site_by_gln(organization_id, gln) do
      {:ok, site} -> site
      {:error, :not_found} -> nil
    end
  end

  defp product_name(nil), do: nil
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/scan"}>
      <.header icon="hero-qr-code">
        Scan consumable
        <:subtitle>Decode a GS1 barcode and match it to lab stock or a registered site.</:subtitle>
      </.header>

      <section
        id="lab-scan-panel"
        class="rounded-xl ff-surface-card p-4 sm:p-5"
      >
        <.form
          for={@scan_form}
          id="lab-scan-form"
          phx-submit="decode"
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
          <.button variant="primary" phx-disable-with="Decoding…">
            Decode barcode
          </.button>
        </.form>
      </section>

      <div :if={@parsed} id="lab-scan-result" class="mt-5 space-y-5">
        <div>
          <h2 class="mb-3 text-base font-semibold text-thamani-forest">Decoded identifiers</h2>
          <.list>
            <:item title="GTIN">{@parsed.gtin}</:item>
            <:item title="Batch/lot">{@parsed.batch_no}</:item>
            <:item title="Production date">{@parsed.production_date}</:item>
            <:item title="Expiry date">{@parsed.expiry_date}</:item>
            <:item title="Serial">{@parsed.serial}</:item>
            <:item title="GLN">{@parsed.gln}</:item>
          </.list>
        </div>

        <section :if={@batch} id="lab-scan-batch-match">
          <h2 class="mb-3 text-base font-semibold text-thamani-forest">Matching batch</h2>
          <.list>
            <:item title="Product">{product_name(@product)}</:item>
            <:item title="Remaining quantity">{@batch.remaining_quantity}</:item>
            <:item title="Expiry">{@batch.expiry_date}</:item>
          </.list>
        </section>

        <section :if={@site} id="lab-scan-site-match">
          <h2 class="mb-3 text-base font-semibold text-thamani-forest">Matching site</h2>
          <.list>
            <:item title="Name">{@site.name}</:item>
            <:item title="Type">{Phoenix.Naming.humanize(@site.site_type)}</:item>
          </.list>
        </section>

        <div
          :if={is_nil(@batch) and is_nil(@site)}
          id="lab-scan-no-match"
          class="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800"
        >
          <.icon name="hero-exclamation-triangle" class="mt-0.5 size-5 shrink-0" />
          <div>
            <p class="font-medium">Barcode decoded, but no match was found</p>
            <p class="mt-1">Check the batch or site registration before using this consumable.</p>
          </div>
        </div>
      </div>
    </Layouts.lab_shell>
    """
  end
end
