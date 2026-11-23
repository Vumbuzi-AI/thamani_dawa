defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Dashboard do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    pallets = Manufacturing.list_pallets(organization_id)
    all_ssccs = Manufacturing.available_ssccs_for_aggregation(organization_id)
    standalone = Enum.filter(all_ssccs, &is_nil(&1.manufacturer_pallet_id))

    {:ok,
     socket
     |> assign(:page_title, "Aggregation")
     |> assign(:pallets, pallets)
     |> assign(:standalone, standalone)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-squares-plus">
        Aggregation
        <:subtitle>
          Build pallet and shipper SSCC hierarchies, then add their GTINs, batches, and serials.
        </:subtitle>
        <:actions>
          <.button
            id="add-aggregation-sscc"
            variant="primary"
            navigate={~p"/manufacturer/aggregations/new"}
          ><.icon name="hero-plus" class="size-4" /> Add SSCC</.button>
        </:actions>
      </.header>

      <div class="grid gap-6 xl:grid-cols-2">
        <section id="aggregation-pallets" class="overflow-hidden rounded-2xl ff-surface-card">
          <div class="border-b border-thamani-stone p-5">
            <h2 class="font-semibold text-thamani-forest">Pallet SSCCs</h2><p class="mt-1 text-sm text-thamani-pewter">
              Parties are entered once and inherited by every shipper.
            </p>
          </div>
          <div :if={@pallets == []} class="p-8 text-center text-sm text-thamani-pewter">
            No pallets yet.
          </div>
          <div class="divide-y divide-thamani-stone">
            <.link
              :for={pallet <- @pallets}
              id={"aggregation-pallet-#{pallet.id}"}
              navigate={~p"/manufacturer/aggregations/pallets/#{pallet.id}"}
              class="flex items-center justify-between gap-4 p-5 transition hover:bg-thamani-lime/20"
            >
              <div>
                <p class="font-mono text-sm font-semibold text-thamani-forest">{pallet.code}</p><p class="mt-1 text-sm text-thamani-pewter">
                  {pallet.from_company_name} → {pallet.to_company_name}
                </p>
              </div>
              <span class="rounded-full bg-thamani-canvas px-3 py-1 text-xs font-semibold text-thamani-forest">{length(
                pallet.shipper_ssccs
              )} shippers</span>
            </.link>
          </div>
        </section>

        <section
          id="aggregation-standalone-shippers"
          class="overflow-hidden rounded-2xl ff-surface-card"
        >
          <div class="border-b border-thamani-stone p-5">
            <h2 class="font-semibold text-thamani-forest">Standalone shipper SSCCs</h2><p class="mt-1 text-sm text-thamani-pewter">
              Cases that are not grouped under a pallet.
            </p>
          </div>
          <div :if={@standalone == []} class="p-8 text-center text-sm text-thamani-pewter">
            No standalone shippers yet.
          </div>
          <div class="divide-y divide-thamani-stone">
            <.link
              :for={sscc <- @standalone}
              id={"aggregation-sscc-#{sscc.id}"}
              navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
              class="flex items-center justify-between gap-4 p-5 transition hover:bg-thamani-lime/20"
            >
              <div>
                <p class="font-mono text-sm font-semibold text-thamani-forest">{sscc.code}</p><p class="mt-1 text-sm text-thamani-pewter">
                  {sscc.from_company_name} → {sscc.to_company_name}
                </p>
              </div>
              <span class="rounded-full bg-thamani-canvas px-3 py-1 text-xs font-semibold text-thamani-forest">{sscc.count_of_trade_items ||
                0} serials</span>
            </.link>
          </div>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
