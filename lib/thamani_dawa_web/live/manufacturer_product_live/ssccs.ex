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

      <div id="manufacturer-product-ssccs" class="mt-6 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        <article
          :for={group <- @groups}
          id={"sscc-group-#{group.pallet_code || "unassigned"}"}
          class="flex flex-col rounded-2xl border border-thamani-stone bg-td-surface p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-td-hairline hover:shadow-md"
        >
          <div class="flex items-start gap-3">
            <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-td-accent-tint text-thamani-forest">
              <.icon name="hero-qr-code" class="size-5" />
            </span>
            <div class="min-w-0">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                Pallet SSCC
              </p><p class="mt-1 font-mono font-semibold text-thamani-forest">
                {group.pallet_code || "Not assigned to a pallet"}
              </p>
            </div>
          </div>

          <% row = hd(group.shippers) %>
          <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Batch</dt><dd class="mt-1 font-semibold text-thamani-forest">
                {row.sscc.batch || Enum.map_join(row.sscc.batches, ", ", & &1.batch_no)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">GTIN</dt><dd class="mt-1 truncate font-mono text-thamani-forest">
                {row.sscc.gtin}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Produced</dt><dd class="mt-1 text-thamani-forest">
                {row.sscc.production_date || "—"}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Expires</dt><dd class="mt-1 text-thamani-forest">
                {row.sscc.expiry_date || "—"}
              </dd>
            </div>
          </dl>

          <div class="mt-5 flex flex-wrap gap-2">
            <span class="rounded-full bg-thamani-mist px-3 py-1.5 text-xs font-bold text-thamani-forest">{length(
              group.shippers
            )} Shippers</span>
            <span class="rounded-full bg-thamani-lime/30 px-3 py-1.5 text-xs font-bold text-thamani-forest">{group.primary_count} Primary serials</span>
          </div>
          <hr class="my-5 border-thamani-stone" />
          <div class="mt-auto flex flex-wrap gap-2">
            <.button id={"sscc-#{row.sscc.id}-shippers"} type="button" variant="primary"><.icon
              name="hero-truck"
              class="size-4"
            /> Shippers</.button>
            <.button
              id={"sscc-#{row.sscc.id}-serials"}
              navigate={~p"/manufacturer/sscc/#{row.sscc.id}/serials"}
            ><.icon name="hero-list-bullet" class="size-4" /> Serials</.button>
            <.button
              id={"sscc-#{row.sscc.id}-label"}
              navigate={~p"/manufacturer/sscc/#{row.sscc.id}/label"}
              variant="ghost"
            ><.icon name="hero-qr-code" class="size-4" /> Pallet Label</.button>
            <.button
              id={"sscc-#{row.sscc.id}-export"}
              href={~p"/manufacturer/sscc/#{row.sscc.id}/export"}
              variant="ghost"
            ><.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV</.button>
          </div>
        </article>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
