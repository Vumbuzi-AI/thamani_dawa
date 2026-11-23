defmodule ThamaniDawaWeb.ManufacturerProductLive.Ssccs do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)
    rows = Manufacturing.list_sscc_groups(organization_id, product.id)

    {:ok,
     socket
     |> assign(:page_title, "Product SSCCs")
     |> assign(:product, product)
     |> assign(:groups, group_ssccs(rows))}
  end

  defp group_ssccs(rows) do
    rows
    |> Enum.group_by(fn %{sscc: sscc} -> if sscc.pallet, do: sscc.pallet.code, else: nil end)
    |> Enum.map(fn {pallet_code, shippers} ->
      %{
        pallet_code: pallet_code,
        shippers: shippers,
        primary_count: Enum.sum(Enum.map(shippers, & &1.serial_count))
      }
    end)
    |> Enum.sort_by(&{is_nil(&1.pallet_code), &1.pallet_code || ""})
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-cube-transparent">
        Shipping SSCCs
        <:subtitle>{@product.name} · <span class="font-mono">{@product.gtin}</span></:subtitle>
        <:actions>
          <.button navigate={~p"/manufacturer/products"}><.icon name="hero-arrow-left" class="size-4" />
          Products</.button>
        </:actions>
      </.header>

      <div :if={@groups == []} id="manufacturer-sscc-empty-state">
        <.blank_state
          icon="hero-cube-transparent"
          title="No SSCCs — these are created when stock is shipped"
        >
          Generate primary serials first, then pack them into shipping units from the shipment flow.
        </.blank_state>
      </div>

      <div id="manufacturer-product-ssccs" class="mt-6 space-y-5">
        <section
          :for={group <- @groups}
          id={"sscc-group-#{group.pallet_code || "unassigned"}"}
          class="overflow-hidden rounded-2xl border border-thamani-stone bg-white shadow-sm"
        >
          <div class="flex flex-wrap items-center justify-between gap-3 bg-thamani-snow px-5 py-4">
            <div>
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                Pallet SSCC
              </p><p class="mt-1 font-mono font-semibold text-thamani-forest">
                {group.pallet_code || "Not assigned to a pallet"}
              </p>
            </div>
            <div class="flex gap-2 text-xs">
              <span class="rounded-full bg-white px-3 py-1.5 font-semibold">{length(group.shippers)} shippers</span><span class="rounded-full bg-white px-3 py-1.5 font-semibold">{group.primary_count} primary serials</span>
            </div>
          </div>
          <div class="divide-y divide-thamani-stone">
            <article :for={row <- group.shippers} id={"shipper-sscc-#{row.sscc.id}"} class="p-5">
              <div class="grid gap-4 md:grid-cols-6">
                <div>
                  <p class="text-xs text-thamani-pewter">Shipper SSCC</p><p class="mt-1 font-mono text-sm font-semibold">
                    {row.sscc.code}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Batch</p><p class="mt-1 text-sm font-semibold">
                    {row.sscc.batch || Enum.map_join(row.sscc.batches, ", ", & &1.batch_no)}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">GTIN</p><p class="mt-1 font-mono text-sm">
                    {row.sscc.gtin}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Produced</p><p class="mt-1 text-sm">
                    {row.sscc.production_date || "—"}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Expires</p><p class="mt-1 text-sm">
                    {row.sscc.expiry_date || "—"}
                  </p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Primary serials</p><p class="mt-1 text-sm font-semibold">
                    {row.serial_count}
                  </p>
                </div>
              </div>
              <div class="mt-4 flex flex-wrap gap-2">
                <.button id={"sscc-#{row.sscc.id}-shippers"} type="button" variant="ghost">Shippers list</.button>
                <.button
                  id={"sscc-#{row.sscc.id}-serials"}
                  navigate={~p"/manufacturer/sscc/#{row.sscc.id}/serials"}
                  variant="ghost"
                >Serials list</.button>
                <.button
                  id={"sscc-#{row.sscc.id}-label"}
                  navigate={~p"/manufacturer/sscc/#{row.sscc.id}/label"}
                  variant="ghost"
                >Pallet Label</.button>
                <.button
                  id={"sscc-#{row.sscc.id}-export"}
                  href={~p"/manufacturer/sscc/#{row.sscc.id}/export"}
                  variant="ghost"
                >Export CSV</.button>
              </div>
            </article>
          </div>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
