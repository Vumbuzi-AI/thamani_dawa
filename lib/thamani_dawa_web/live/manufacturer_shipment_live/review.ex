defmodule ThamaniDawaWeb.ManufacturerShipmentLive.Review do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor

  def mount(%{"id" => id}, _session, socket), do: {:ok, load(socket, id)}

  def handle_event("approve", _params, socket) do
    scope = socket.assigns.current_scope

    case Distributor.approve_shipment(
           scope.organization_id,
           scope.user,
           socket.assigns.shipment.id
         ) do
      {:ok, shipment} ->
        shipment = Distributor.get_shipment!(scope.organization_id, shipment.id, "manufacturer")

        {:noreply,
         socket
         |> assign_shipment(shipment)
         |> put_flash(:info, "Shipment approved and manufacturer EPCIS shipping event queued.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This shipment is already approved.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Shipment could not be approved.")}
    end
  end

  def handle_event("toggle_shipper", %{"id" => id}, socket),
    do:
      {:noreply,
       update(socket, :expanded, fn expanded ->
         if MapSet.member?(expanded, id),
           do: MapSet.delete(expanded, id),
           else: MapSet.put(expanded, id)
       end)}

  defp load(socket, id) do
    shipment =
      Distributor.get_shipment!(
        socket.assigns.current_scope.organization_id,
        id,
        "manufacturer"
      )

    socket
    |> assign(:page_title, shipment.order_number)
    |> assign(:expanded, MapSet.new())
    |> assign_shipment(shipment)
  end

  defp assign_shipment(socket, shipment),
    do:
      socket
      |> assign(:shipment, shipment)
      |> assign(
        :unit_count,
        shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum()
      )

  defp count_phrase(1, noun), do: "1 #{noun}"
  defp count_phrase(count, noun), do: "#{count} #{noun}s"

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/shipments"}
    >
      <div class="no-print">
        <.header icon="hero-truck" back={~p"/manufacturer/shipments"}>
          <span class="flex flex-wrap items-center gap-3">{@shipment.order_number}<.shipment_status_badge status={
            @shipment.status
          } /></span>
          <:subtitle>
            <span class="tracking-tight tabular-nums">{@shipment.reference}</span>
            · {count_phrase(length(@shipment.shippers), "shipper")} · {count_phrase(
              @unit_count,
              "unit"
            )}
          </:subtitle>
          <:actions>
            <div class="flex w-full flex-col gap-2 sm:flex-row sm:flex-wrap md:w-auto md:justify-end md:[&>*]:w-auto">
              <.button :if={@shipment.status == "approved"} id="manufacturer-delivery-note"><.icon
                name="hero-document-text"
                class="size-4"
              /> View delivery note</.button>
              <.button :if={@shipment.status == "approved"} id="manufacturer-packing-list"><.icon
                name="hero-queue-list"
                class="size-4"
              /> View packing list</.button>
              <.button
                :if={@shipment.status == "submitted"}
                id="approve-manufacturer-shipment"
                variant="primary"
                phx-click="approve"
              ><.icon name="hero-check-badge" class="size-4" /> Approve shipment</.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 md:grid-cols-3">
          <.party_card
            title="Ship from"
            icon="hero-building-office-2"
            company={@shipment.origin_company}
            address={@shipment.origin_address}
            gln={@shipment.origin_gln}
          />
          <.party_card
            title="Ship to"
            icon="hero-building-storefront"
            company={@shipment.destination_company}
            address={@shipment.destination_address}
            gln={@shipment.destination_gln}
          />
          <div class="rounded-2xl ff-surface-card p-4">
            <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              <.icon name="hero-user-group" class="size-4" /> Manufacturing team
            </div>
            <dl class="mt-2 space-y-1.5 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Created by</dt><dd class="text-right font-medium text-thamani-forest">
                  {(@shipment.created_by && @shipment.created_by.name) || "—"}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Created</dt><dd class="text-right">
                  {date_time(@shipment.inserted_at)}
                </dd>
              </div>
              <div :if={@shipment.approved_at} class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Approved</dt><dd class="text-right">
                  {date_time(@shipment.approved_at)}<span
                    :if={@shipment.approved_by}
                    class="block text-xs text-thamani-pewter"
                  >by {@shipment.approved_by.name}</span>
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <section class="mt-6 space-y-4" id="manufacturer-shippers">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Shippers</h2>
          <div
            :if={@shipment.shippers == []}
            class="rounded-2xl border border-dashed border-thamani-stone bg-thamani-canvas p-8 text-center text-sm text-thamani-pewter"
          >
            <.icon name="hero-device-phone-mobile" class="mx-auto mb-2 size-8 text-thamani-subtle" />
            Nothing packed yet. A mobile user finds this shipment by order
            <span class="font-semibold text-thamani-forest">{@shipment.order_number}</span>
            and scans units into shippers.
          </div>
          <article
            :for={shipper <- @shipment.shippers}
            id={"shipper-#{shipper.id}"}
            class="overflow-hidden rounded-2xl ff-surface-card"
          >
            <header class="flex flex-wrap items-center justify-between gap-3 border-b border-thamani-stone px-4 py-3 sm:px-5">
              <div class="flex items-center gap-3">
                <span class="flex size-8 items-center justify-center rounded-lg bg-thamani-canvas text-sm font-semibold text-thamani-forest">{shipper.sequence}</span><div>
                  <p class="font-medium text-thamani-forest">{shipper.name}</p><p class="text-xs text-thamani-pewter">
                    {length(shipper.items)} unit(s)
                  </p>
                </div>
              </div>
              <span
                :if={shipper.sscc}
                class="rounded-lg bg-thamani-lime px-3 py-1 font-mono text-xs font-semibold text-thamani-forest"
              >SSCC {shipper.sscc}</span>
            </header>
            <button
              type="button"
              phx-click="toggle_shipper"
              phx-value-id={Integer.to_string(shipper.id)}
              class="grid w-full grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))_auto] items-center gap-3 px-5 py-3 text-left transition-colors hover:bg-thamani-canvas"
            >
              <span><span class="block text-sm font-medium">{shipper.product_name ||
                "Packed trade items"}</span><span class="font-mono text-xs text-thamani-pewter">{shipper.gtin ||
                "Mixed contents"}</span></span>
              <span class="text-sm"><span class="block text-xs text-thamani-pewter">Batch</span>{shipper.batch ||
                "Mixed"}</span>
              <span class="text-sm"><span class="block text-xs text-thamani-pewter">Expiry</span>{shipper.expiry_date ||
                "—"}</span>
              <span class="text-sm"><span class="block text-xs text-thamani-pewter">Units</span>{length(
                shipper.items
              )}</span>
              <span class="flex items-center gap-1 text-xs font-semibold text-thamani-forest">{if MapSet.member?(
                                                                                                    @expanded,
                                                                                                    Integer.to_string(
                                                                                                      shipper.id
                                                                                                    )
                                                                                                  ),
                                                                                                  do:
                                                                                                    "Hide details",
                                                                                                  else:
                                                                                                    "View details"}<.icon
                name="hero-chevron-down"
                class="size-4"
              /></span>
            </button>
            <ul
              :if={MapSet.member?(@expanded, Integer.to_string(shipper.id))}
              class="grid gap-3 bg-thamani-canvas/60 px-5 py-4 sm:grid-cols-2 xl:grid-cols-3"
            >
              <li
                :for={item <- shipper.items}
                id={"shipment-item-#{item.id}"}
                class="rounded-xl border border-thamani-stone bg-white p-3 text-sm"
              >
                <p class="font-medium">{item.product_name || "Verified product"}</p><p class="font-mono text-xs text-thamani-pewter">
                  {item.gtin} · {item.serial}
                </p><p class="mt-1 text-xs">Batch {item.batch || "—"}</p>
              </li>
            </ul>
          </article>
        </section>

        <section class="mt-6 rounded-2xl ff-surface-card p-5" id="manufacturer-shipment-activity">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Activity</h2>
          <ol class="mt-4 border-l border-thamani-stone pl-5">
            <li class="relative pb-5">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span><p class="font-medium">
                Created
              </p><p class="text-xs text-thamani-pewter">
                {(@shipment.created_by && @shipment.created_by.name) || "System"} · {date_time(
                  @shipment.inserted_at
                )}
              </p>
            </li>
            <li :if={@shipment.status in ["submitted", "approved"]} class="relative pb-5">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span><p class="font-medium">
                Submitted for approval
              </p><p class="text-xs text-thamani-pewter">Manufacturing team</p>
            </li>
            <li :if={@shipment.status == "approved"} class="relative">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span><p class="font-medium">
                Approved · EPCIS shipping event queued
              </p><p class="text-xs text-thamani-pewter">
                {(@shipment.approved_by && @shipment.approved_by.name) || "System"} · {date_time(
                  @shipment.approved_at
                )}
              </p>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :company, :string, required: true
  attr :address, :string, default: nil
  attr :gln, :string, required: true

  defp party_card(assigns) do
    ~H"""
    <div class="rounded-2xl ff-surface-card p-4">
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
        <.icon name={@icon} class="size-4" /> {@title}
      </div><p class="mt-2 font-medium text-thamani-forest">{@company}</p><p
        :if={@address}
        class="text-sm"
      >
        {@address}
      </p><p class="mt-1 font-mono text-xs text-thamani-pewter">GLN {@gln}</p>
    </div>
    """
  end
end
