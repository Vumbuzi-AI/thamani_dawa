defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    pallet = Manufacturing.get_pallet!(socket.assigns.current_scope.organization_id, id)
    {:ok, socket |> assign(:page_title, "Pallet #{pallet.code}") |> assign(:pallet, pallet)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-archive-box" back={~p"/manufacturer/aggregations"}>
        Pallet: {@pallet.code}
        <:subtitle>Where this pallet ships from and to, and the shipper SSCCs on it.</:subtitle>
        <:actions>
          <.button
            id="add-pallet-shipper"
            variant="primary"
            navigate={~p"/manufacturer/aggregations/pallets/#{@pallet.id}/ssccs/new"}
          ><.icon name="hero-plus" class="size-4" /> Add shipper SSCC</.button>
        </:actions>
      </.header>
      <div class="grid gap-4 md:grid-cols-2">
        <.party_card
          title="From"
          gln={@pallet.from_gln}
          company={@pallet.from_company_name}
          address={@pallet.from_address}
          icon="hero-building-office-2"
        />
        <.party_card
          title="To"
          gln={@pallet.to_gln}
          company={@pallet.to_company_name}
          address={@pallet.to_address}
          icon="hero-map-pin"
        />
      </div>
      <section id="pallet-shippers" class="mt-6 overflow-hidden rounded-2xl ff-surface-card">
        <div class="border-b border-thamani-stone p-5 font-semibold text-thamani-forest">
          {length(@pallet.shipper_ssccs)} shipper SSCCs
        </div>
        <div :if={@pallet.shipper_ssccs == []} class="p-8 text-center text-sm text-thamani-pewter">
          No shipper SSCCs on this pallet yet.
        </div>
        <div class="divide-y divide-thamani-stone">
          <.link
            :for={sscc <- @pallet.shipper_ssccs}
            id={"pallet-shipper-#{sscc.id}"}
            navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
            class="flex items-center justify-between p-5 hover:bg-thamani-lime/20"
          >
            <div>
              <p class="font-mono text-sm font-semibold text-thamani-forest">{sscc.code}</p><p class="text-sm text-thamani-pewter">
                GTIN {sscc.gtin || "Not added"} · {length(sscc.batches)} batches
              </p>
            </div>
            <.icon name="hero-chevron-right" class="size-5 text-thamani-pewter" />
          </.link>
        </div>
      </section>
    </Layouts.manufacturer_shell>
    """
  end

  attr :title, :string, required: true
  attr :gln, :string, default: nil
  attr :company, :string, default: nil
  attr :address, :string, default: nil
  attr :icon, :string, required: true

  defp party_card(assigns) do
    ~H"""
    <article class="rounded-2xl ff-surface-card p-5">
      <div class="flex items-center gap-2 text-sm font-semibold text-thamani-forest">
        <.icon name={@icon} class="size-5" /> {@title}
      </div><p class="mt-3 font-medium">{@company}</p><p class="text-sm text-thamani-pewter">
        GLN {@gln}
      </p><p class="mt-1 text-sm text-thamani-pewter">{@address}</p>
    </article>
    """
  end
end
