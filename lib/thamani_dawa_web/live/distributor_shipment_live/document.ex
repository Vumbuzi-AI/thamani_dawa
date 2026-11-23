defmodule ThamaniDawaWeb.DistributorShipmentLive.Document do
  @moduledoc """
  Printable dispatch papers for an approved shipment.

  The delivery note is the handover the receiver signs: parties, and one
  line per product, batch, and expiry. The packing list is the carton
  contents: each shipper's SSCC, then the units and serials inside it.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    shipment = Distributor.get_shipment!(organization_id, id)

    if shipment.status == "approved" do
      title =
        if(socket.assigns.live_action == :packing_list, do: "Packing list", else: "Delivery note")

      {:ok,
       socket
       |> assign(:page_title, "#{title} · #{shipment.order_number}")
       |> assign(:shipment, shipment)
       |> assign(:lines, delivery_lines(shipment))
       |> assign(:sections, packing_sections(shipment))
       |> assign(:unit_count, unit_count(shipment))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Delivery documents are available once the shipment is approved.")
       |> redirect(to: ~p"/distributor/shipments/#{shipment.id}")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <div class="no-print mb-4 flex flex-wrap items-center justify-between gap-3">
        <.link
          navigate={~p"/distributor/shipments/#{@shipment.id}"}
          class="inline-flex items-center gap-1.5 text-sm font-medium text-thamani-forest hover:underline"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to shipment
        </.link>
        <div class="flex flex-wrap items-center gap-2">
          <nav
            aria-label="Shipment document"
            class="inline-flex rounded-lg border border-thamani-stone bg-thamani-surface p-1"
          >
            <.link
              id="switch-delivery-note"
              navigate={~p"/distributor/shipments/#{@shipment.id}/delivery-note"}
              aria-current={@live_action == :delivery_note && "page"}
              class={[
                "inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors",
                @live_action == :delivery_note && "bg-td-accent-tint text-thamani-forest",
                @live_action != :delivery_note &&
                  "text-thamani-pewter hover:bg-td-surface/60 hover:text-thamani-forest"
              ]}
            >
              Delivery note
            </.link>
            <.link
              id="switch-packing-list"
              navigate={~p"/distributor/shipments/#{@shipment.id}/packing-list"}
              aria-current={@live_action == :packing_list && "page"}
              class={[
                "inline-flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors",
                @live_action == :packing_list && "bg-td-accent-tint text-thamani-forest",
                @live_action != :packing_list &&
                  "text-thamani-pewter hover:bg-td-surface/60 hover:text-thamani-forest"
              ]}
            >
              Packing list
            </.link>
          </nav>
          <.button
            id="print-shipment-document"
            variant="primary"
            type="button"
            onclick="window.print()"
            class="gap-1.5"
          >
            <.icon name="hero-printer" class="size-4" /> Print
          </.button>
        </div>
      </div>

      <article
        id={document_id(@live_action)}
        class="printable-shipment-doc relative mx-auto max-w-4xl rounded-xl bg-td-surface p-6 shadow-sm ring-1 ring-thamani-stone sm:p-10"
      >
        <header class="grid gap-6 border-b border-thamani-stone pb-6 sm:grid-cols-[minmax(0,1fr)_auto]">
          <div>
            <p class="text-xl font-medium tracking-tight text-thamani-forest">
              {@shipment.origin_company || "Warehouse"}
            </p>
            <p class="mt-1 text-sm text-thamani-pewter">{party_lines(@shipment, :origin)}</p>
          </div>
          <div class="sm:text-right">
            <p class="text-xs font-medium text-thamani-pewter">{document_title(@live_action)}</p>
            <p class="text-lg font-medium tracking-tight text-thamani-forest tabular-nums">
              {@shipment.order_number}
            </p>
            <p class="text-sm tracking-tight text-thamani-pewter tabular-nums">
              {@shipment.reference}
            </p>
            <p class="text-sm text-thamani-pewter">Issued {short_date(@shipment.approved_at)}</p>
          </div>
        </header>

        <section class="grid gap-6 border-b border-thamani-stone py-6 sm:grid-cols-2">
          <div>
            <p class="text-xs font-medium text-thamani-pewter">Ship from</p>
            <p class="mt-1 font-medium text-thamani-forest">{@shipment.origin_company}</p>
            <p class="text-sm text-thamani-pewter">{party_lines(@shipment, :origin)}</p>
            <p class="text-sm tracking-tight text-thamani-pewter tabular-nums">
              GLN {@shipment.origin_gln}
            </p>
          </div>
          <div id="shipment-document-destination">
            <p class="text-xs font-medium text-thamani-pewter">Ship to</p>
            <p class="mt-1 font-medium text-thamani-forest">{@shipment.destination_company}</p>
            <p class="text-sm text-thamani-pewter">{party_lines(@shipment, :destination)}</p>
            <p class="text-sm tracking-tight text-thamani-pewter tabular-nums">
              GLN {@shipment.destination_gln}
            </p>
          </div>
        </section>

        <%= if @live_action == :delivery_note do %>
          <div id="delivery-note-lines" class="mt-6">
            <.document_lines lines={@lines} empty="No units on this shipment." />
          </div>
          <p class="mt-4 text-sm text-thamani-pewter">
            {tally(@shipment, @unit_count)}
          </p>
          <div id="delivery-note-signatures" class="mt-10 grid gap-8 sm:grid-cols-2">
            <div>
              <p class="text-xs font-medium text-thamani-pewter">Dispatched by</p>
              <p class="mt-2 text-sm font-medium text-thamani-forest">
                {(@shipment.approved_by && @shipment.approved_by.name) || "—"}
              </p>
              <div class="mt-8 border-b border-thamani-stone"></div>
              <p class="mt-1 text-xs text-thamani-pewter">
                Signature · {short_date(@shipment.approved_at)}
              </p>
            </div>
            <div id="delivery-note-received-by">
              <p class="text-xs font-medium text-thamani-pewter">Received by</p>
              <div class="mt-12 border-b border-thamani-stone"></div>
              <p class="mt-1 text-xs text-thamani-pewter">Name, signature, date, and stamp</p>
            </div>
          </div>
        <% else %>
          <div id="packing-list-shippers" class="mt-6 space-y-8">
            <section
              :for={section <- @sections}
              id={"packing-shipper-#{section.shipper.id}"}
              class="packing-shipper"
            >
              <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                <h2 class="text-base font-medium text-thamani-forest">
                  {section.shipper.name || "Shipper #{section.shipper.sequence}"}
                </h2>
                <p class="text-sm tracking-tight text-thamani-pewter tabular-nums">
                  SSCC {section.shipper.sscc || "—"}
                </p>
              </div>
              <.document_lines
                lines={section.lines}
                serials?={true}
                empty="This shipper has no units."
              />
            </section>
          </div>
          <div id="packing-list-checked-by" class="mt-10 max-w-xs">
            <p class="text-xs font-medium text-thamani-pewter">Checked by</p>
            <div class="mt-12 border-b border-thamani-stone"></div>
            <p class="mt-1 text-xs text-thamani-pewter">Name and signature</p>
          </div>
        <% end %>
      </article>
    </Layouts.distributor_shell>
    """
  end

  attr :lines, :list, required: true
  attr :serials?, :boolean, default: false
  attr :empty, :string, required: true

  defp document_lines(assigns) do
    ~H"""
    <div class="mt-3">
      <div class="hidden border-b border-thamani-stone pb-2 text-xs font-medium text-thamani-pewter sm:grid sm:grid-cols-[minmax(0,1.5fr)_minmax(12rem,1fr)_8.5rem_3.5rem] sm:gap-4">
        <span>Product</span>
        <span>Batch</span>
        <span>Expiry</span>
        <span class="text-right">Units</span>
      </div>
      <p :if={@lines == []} class="border-b border-thamani-stone py-6 text-sm text-thamani-pewter">
        {@empty}
      </p>
      <div :for={line <- @lines} class="border-b border-thamani-stone py-3">
        <div class="grid gap-y-1 sm:grid-cols-[minmax(0,1.5fr)_minmax(12rem,1fr)_8.5rem_3.5rem] sm:items-baseline sm:gap-4">
          <div class="min-w-0">
            <p class="font-medium text-thamani-forest">{line.product_name || "—"}</p>
            <p :if={line.gtin} class="text-xs tracking-tight text-thamani-pewter tabular-nums">
              {line.gtin}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-thamani-pewter sm:hidden">Batch</p>
            <p class="tracking-tight whitespace-nowrap text-thamani-evergreen tabular-nums">
              {line.batch || "—"}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-thamani-pewter sm:hidden">Expiry</p>
            <p class="whitespace-nowrap text-thamani-evergreen tabular-nums">
              {short_date(line.expiry)}
            </p>
          </div>
          <div>
            <p class="text-xs font-medium text-thamani-pewter sm:hidden">Units</p>
            <p class="tabular-nums sm:text-right">{line.quantity}</p>
          </div>
        </div>
        <div :if={@serials? && line.serials != []} class="mt-3">
          <p class="text-xs font-medium text-thamani-pewter">Serials</p>
          <ul class="mt-1 flex flex-wrap gap-x-4 gap-y-1">
            <li
              :for={serial <- line.serials}
              class="text-sm tracking-tight text-thamani-evergreen tabular-nums"
            >
              {serial}
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp document_id(:packing_list), do: "shipment-packing-list"
  defp document_id(_action), do: "shipment-delivery-note"

  defp document_title(:packing_list), do: "Packing list"
  defp document_title(_action), do: "Delivery note"

  defp unit_count(shipment) do
    Enum.reduce(shipment.shippers, 0, fn shipper, count -> count + length(shipper.items) end)
  end

  defp tally(shipment, unit_count) do
    "#{count_phrase(length(shipment.shippers), "shipper")} · #{count_phrase(unit_count, "unit")}. Serials are on the packing list."
  end

  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(count, word), do: "#{count} #{word}s"

  defp delivery_lines(shipment) do
    shipment.shippers
    |> Enum.flat_map(& &1.items)
    |> Enum.group_by(&line_key/1)
    |> Enum.map(fn {key, items} -> line(key, items) end)
    |> Enum.sort_by(&{&1.product_name || "", &1.batch || ""})
  end

  defp packing_sections(shipment) do
    Enum.map(shipment.shippers, fn shipper ->
      lines =
        shipper.items
        |> Enum.group_by(&line_key/1)
        |> Enum.map(fn {key, items} -> line(key, items) end)
        |> Enum.sort_by(&{&1.product_name || "", &1.batch || ""})

      %{shipper: shipper, lines: lines}
    end)
  end

  defp line_key(item), do: {item.product_name, item.gtin, item.batch, item.expiry_date}

  defp line({name, gtin, batch, expiry}, items) do
    %{
      product_name: name,
      gtin: gtin,
      batch: batch,
      expiry: expiry,
      quantity: length(items),
      serials: items |> Enum.map(& &1.serial) |> Enum.reject(&is_nil/1) |> Enum.sort()
    }
  end

  defp party_lines(shipment, :origin) do
    [shipment.origin_address, po_box(shipment.origin_po_box)] |> present()
  end

  defp party_lines(shipment, :destination) do
    [shipment.destination_address, po_box(shipment.destination_po_box)] |> present()
  end

  defp po_box(nil), do: nil
  defp po_box(""), do: nil
  defp po_box(box), do: "P.O. Box #{box}"

  defp present(parts) do
    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> "—"
      lines -> Enum.join(lines, ", ")
    end
  end
end
