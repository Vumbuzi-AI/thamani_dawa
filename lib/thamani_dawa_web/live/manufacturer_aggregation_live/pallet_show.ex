defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    pallet = Manufacturing.get_pallet!(socket.assigns.current_scope.organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Pallet #{pallet.code}")
     |> assign(:pallet, pallet)
     |> assign(
       :total_serials,
       Enum.sum(Enum.map(pallet.shipper_ssccs, &(&1.count_of_trade_items || 0)))
     )}
  end

  defp batch_label(sscc),
    do: sscc.batch || Enum.map_join(sscc.batches, ", ", & &1.batch_no)

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-archive-box" back={~p"/manufacturer/aggregations"}>
        <span class="font-mono">{@pallet.code}</span>
        <:subtitle>
          Pallet SSCC · {length(@pallet.shipper_ssccs)} shippers · {@total_serials} primary serials
        </:subtitle>
      </.header>

      <div :if={@pallet.shipper_ssccs == []} id="pallet-shippers-empty">
        <.blank_state icon="hero-cube-transparent" title="No shipper SSCCs on this pallet">
          Shippers on this pallet were moved or shipped.
        </.blank_state>
      </div>

      <div id="pallet-shippers" class="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        <article
          :for={sscc <- @pallet.shipper_ssccs}
          id={"pallet-shipper-#{sscc.id}"}
          class="flex flex-col rounded-2xl border border-thamani-stone bg-td-surface p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-td-hairline hover:shadow-md"
        >
          <div class="flex items-start gap-3">
            <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-td-accent-tint text-thamani-forest">
              <.icon name="hero-qr-code" class="size-5" />
            </span>
            <div class="min-w-0">
              <p class="text-xs font-bold uppercase tracking-[0.16em] text-thamani-pewter">
                Shipper SSCC
              </p>
              <p class="mt-1 truncate font-mono font-semibold text-thamani-forest">{sscc.code}</p>
            </div>
          </div>

          <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Batch</dt>
              <dd class="mt-1 font-semibold text-thamani-forest">{batch_label(sscc)}</dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">GTIN</dt>
              <dd class="mt-1 truncate font-mono text-thamani-forest">{sscc.gtin || "—"}</dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Produced</dt>
              <dd class="mt-1 text-thamani-forest">{sscc.production_date || "—"}</dd>
            </div>
            <div>
              <dt class="text-xs font-bold uppercase tracking-wide text-thamani-pewter">Expires</dt>
              <dd class="mt-1 text-thamani-forest">{sscc.expiry_date || "—"}</dd>
            </div>
          </dl>

          <div class="mt-5">
            <span class="rounded-full bg-thamani-lime/30 px-3 py-1.5 text-xs font-bold text-thamani-forest">
              {sscc.count_of_trade_items || 0} Primary serials
            </span>
          </div>
          <hr class="my-5 border-thamani-stone" />
          <div class="mt-auto flex flex-wrap gap-2">
            <.button
              id={"pallet-shipper-#{sscc.id}-serials"}
              navigate={~p"/manufacturer/sscc/#{sscc.id}/serials"}
            ><.icon name="hero-list-bullet" class="size-4" /> Serials</.button>
            <.button
              id={"pallet-shipper-#{sscc.id}-label"}
              navigate={~p"/manufacturer/sscc/#{sscc.id}/label"}
              variant="ghost"
            ><.icon name="hero-qr-code" class="size-4" /> Label</.button>
            <.button
              id={"pallet-shipper-#{sscc.id}-export"}
              href={~p"/manufacturer/sscc/#{sscc.id}/export"}
              variant="ghost"
            ><.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV</.button>
          </div>
        </article>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
