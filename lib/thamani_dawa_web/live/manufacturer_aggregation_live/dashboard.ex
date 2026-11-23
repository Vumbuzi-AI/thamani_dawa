defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Dashboard do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    pallets = Manufacturing.list_pallets(socket.assigns.current_scope.organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Aggregation")
     |> assign(:pallets, pallets)
     |> assign(:query, "")}
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  defp visible(%{pallets: pallets, query: query}) do
    case String.downcase(String.trim(query)) do
      "" ->
        pallets

      term ->
        Enum.filter(pallets, fn pallet ->
          [pallet.code | Enum.flat_map(pallet.shipper_ssccs, &[&1.code, &1.gtin, &1.batch])]
          |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), term)))
        end)
    end
  end

  defp total_serials(pallet),
    do: Enum.sum(Enum.map(pallet.shipper_ssccs, &(&1.count_of_trade_items || 0)))

  defp distinct_count(pallet, field),
    do:
      pallet.shipper_ssccs
      |> Enum.map(&Map.get(&1, field))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> length()

  def render(assigns) do
    assigns = assign(assigns, :visible, visible(assigns))

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-squares-plus">
        Aggregation
        <:subtitle>Group shipper SSCCs from any product or batch into pallet SSCCs.</:subtitle>
        <:actions>
          <.button
            id="create-pallet"
            variant="primary"
            navigate={~p"/manufacturer/aggregations/pallets/new"}
          ><.icon name="hero-plus" class="size-4" /> Create pallet SSCC</.button>
        </:actions>
      </.header>

      <section id="aggregation-pallets" class="overflow-hidden rounded-2xl ff-surface-card">
        <div class="border-b border-thamani-stone p-4">
          <form id="pallet-search" phx-change="search" phx-submit="search">
            <label class="relative block">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-thamani-pewter"
              />
              <input
                type="search"
                name="q"
                value={@query}
                phx-debounce="200"
                placeholder="Search pallets by SSCC, shipper, GTIN or batch"
                autocomplete="off"
                class="w-full rounded-xl border border-thamani-stone bg-td-surface py-2.5 pl-9 pr-3 text-sm text-thamani-forest outline-none transition focus:border-thamani-forest"
              />
            </label>
          </form>
        </div>
        <div
          :if={@visible == []}
          id="aggregation-pallets-empty"
          class="p-10 text-center text-sm text-thamani-pewter"
        >
          {if @pallets == [], do: "No pallet SSCCs yet.", else: "No pallets match “#{@query}”."}
        </div>
        <div class="divide-y divide-thamani-stone">
          <.link
            :for={pallet <- @visible}
            id={"aggregation-pallet-#{pallet.id}"}
            navigate={~p"/manufacturer/aggregations/pallets/#{pallet.id}"}
            class="flex items-center justify-between gap-4 px-5 py-4 transition hover:bg-thamani-lime/20"
          >
            <div class="min-w-0">
              <p class="truncate font-mono text-sm font-semibold text-thamani-forest">
                {pallet.code}
              </p>
              <p class="mt-1 text-xs text-thamani-pewter">
                {distinct_count(pallet, :gtin)} products · {distinct_count(pallet, :batch)} batches · {total_serials(
                  pallet
                )} serials
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-3">
              <span class="rounded-full bg-thamani-canvas px-3 py-1 text-xs font-semibold text-thamani-forest">
                {length(pallet.shipper_ssccs)} shippers
              </span>
              <.icon name="hero-chevron-right" class="size-5 text-thamani-pewter" />
            </div>
          </.link>
        </div>
      </section>
    </Layouts.manufacturer_shell>
    """
  end
end
