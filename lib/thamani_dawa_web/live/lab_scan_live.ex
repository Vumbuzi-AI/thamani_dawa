defmodule ThamaniDawaWeb.LabScanLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    {:ok, assign(socket, parsed: nil, batch: nil, product: nil, site: nil)}
  end

  def handle_event("decode", %{"raw_gs1" => raw_gs1}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

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
      <.header>Scan</.header>

      <form phx-submit="decode">
        <.input
          name="raw_gs1"
          value={nil}
          label="Raw GS1 element string"
          placeholder="(01)0...(10)LOT1(17)261231"
        />
        <.button variant="primary" class="mt-2">Decode</.button>
      </form>

      <div :if={@parsed} class="mt-6">
        <.list>
          <:item title="GTIN">{@parsed.gtin}</:item>
          <:item title="Batch/lot">{@parsed.batch_no}</:item>
          <:item title="Production date">{@parsed.production_date}</:item>
          <:item title="Expiry date">{@parsed.expiry_date}</:item>
          <:item title="Serial">{@parsed.serial}</:item>
          <:item title="GLN">{@parsed.gln}</:item>
        </.list>

        <div :if={@batch} class="mt-4">
          <.header>Matching batch</.header>
          <.list>
            <:item title="Product">{product_name(@product)}</:item>
            <:item title="Remaining quantity">{@batch.remaining_quantity}</:item>
            <:item title="Expiry">{@batch.expiry_date}</:item>
          </.list>
        </div>

        <div :if={@site} class="mt-4">
          <.header>Matching site</.header>
          <.list>
            <:item title="Name">{@site.name}</:item>
            <:item title="Type">{Phoenix.Naming.humanize(@site.site_type)}</:item>
          </.list>
        </div>

        <p :if={is_nil(@batch) and is_nil(@site)} class="text-sm text-base-content/70 mt-4">
          No matching batch or site found for this code.
        </p>
      </div>
    </Layouts.lab_shell>
    """
  end
end
