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
     |> assign(:selected_group, nil)
     |> assign(:modal_tab, :shipper)
     |> assign(:groups, group_ssccs(rows))}
  end

  def handle_event("show_shippers", %{"group-id" => group_id}, socket) do
    selected_group =
      Enum.find(socket.assigns.groups, fn group ->
        Enum.any?(group.shippers, &(to_string(&1.sscc.id) == group_id))
      end)

    {:noreply,
     socket
     |> assign(:selected_group, selected_group)
     |> assign(:modal_tab, :shipper)}
  end

  def handle_event("switch_modal_tab", %{"type" => type}, socket)
      when type in ["shipper", "primary"] do
    {:noreply, assign(socket, :modal_tab, String.to_existing_atom(type))}
  end

  def handle_event("close_shippers", _params, socket) do
    {:noreply, assign(socket, :selected_group, nil)}
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

  defp ai_elements(sscc) do
    [
      {"00", sscc.code},
      {"02", sscc.gtin && String.pad_leading(sscc.gtin, 14, "0")},
      {"10", sscc.batch},
      {"17", date_ai(sscc.expiry_date)},
      {"11", date_ai(sscc.production_date)},
      {"37", sscc.count_of_trade_items && to_string(sscc.count_of_trade_items)},
      {"400", sscc.order_number}
    ]
    |> Enum.reject(fn {_ai, value} -> value in [nil, ""] end)
  end

  defp gs1_text(sscc), do: Enum.map_join(ai_elements(sscc), fn {ai, v} -> "(#{ai})#{v}" end)

  defp date_ai(nil), do: nil
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  defp party(sscc, field) do
    (sscc.pallet && Map.get(sscc.pallet, field)) || Map.get(sscc, field)
  end

  attr :row, :map, required: true
  attr :product_name, :string, required: true
  attr :position, :integer, required: true
  attr :total, :integer, required: true

  defp shipper_label(assigns) do
    ~H"""
    <article
      id={"pallet-shipper-#{@row.sscc.id}"}
      class="rounded-xl border border-cyan-200 bg-cyan-50 p-4"
    >
      <div
        id={"sscc-label-content-#{@row.sscc.id}"}
        class="printable-sscc-label mx-auto w-[400px] max-w-full border-2 border-black bg-white text-black"
        style="font-family: Arial, Helvetica, sans-serif"
      >
        <div class="flex min-h-28">
          <div class="flex-1 border-r-2 border-black p-2">
            <div class="mb-1 font-bold">From Address</div>
            <div class="text-[13px] font-semibold">{party(@row.sscc, :from_company_name)}</div>
            <div class="whitespace-pre-line text-[13px]">{party(@row.sscc, :from_address)}</div>
          </div>
          <div class="flex-1 p-2">
            <div class="mb-1 font-bold">To Address</div>
            <div class="text-[13px] font-semibold">{party(@row.sscc, :to_company_name)}</div>
            <div class="whitespace-pre-line text-[13px]">{party(@row.sscc, :to_address)}</div>
          </div>
        </div>
        <div class="px-2.5">
          <div class="grid grid-cols-2 gap-x-5 gap-y-4 border-t-2 border-black py-3">
            <div>
              <span class="block text-[11px]">SSCC</span><b class="text-[16px]">{@row.sscc.code}</b>
            </div>
            <div class="text-right">
              <span class="block text-[11px]">QUANTITY</span><b class="text-[18px]">{@row.serial_count}</b>
            </div>
            <div>
              <span class="block text-[11px]">CONTENT</span><b class="text-[17px]">{String.pad_leading(
                @row.sscc.gtin || "",
                14,
                "0"
              )}</b>
            </div>
            <div class="text-right">
              <span class="block text-[11px]">EXPIRY</span><b class="text-[17px]">{date_ai(
                @row.sscc.expiry_date
              ) || "—"}</b>
            </div>
            <div>
              <span class="block text-[11px]">BATCH/LOT</span><b class="text-[17px]">{@row.sscc.batch ||
                "—"}</b>
            </div>
            <div class="text-right">
              <span class="block text-[11px]">PROD DATE</span><b class="text-[17px]">{date_ai(
                @row.sscc.production_date
              ) || "—"}</b>
            </div>
            <div>
              <span class="block text-[11px]">MATERIAL DESCRIPTION</span><b class="text-[14px]">{@product_name}</b>
            </div>
            <div class="text-right">
              <span class="block text-[11px]">ORDER NUMBER</span><b class="text-[17px]">{@row.sscc.order_number ||
                "—"}</b>
            </div>
          </div>
          <div class="flex items-start gap-4 border-t-2 border-black py-3 pl-6">
            <canvas
              id={"sscc-modal-barcode-#{@row.sscc.id}"}
              phx-hook="DataMatrix"
              phx-update="ignore"
              data-gs1-text={gs1_text(@row.sscc)}
              class="size-[120px] shrink-0"
            ></canvas>
            <div class="mt-2 flex-1 text-[12px] leading-[1.35]">
              <div :for={{ai, value} <- ai_elements(@row.sscc)}>({ai}) {value}</div>
            </div>
          </div>
        </div>
        <div
          id={"shipper-label-position-#{@row.sscc.id}"}
          class="border-t-2 border-black px-2.5 py-1 text-right text-[11px] font-bold tabular-nums"
        >
          {@position}/{@total}
        </div>
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-2">
        <.button
          id={"print-shipper-#{@row.sscc.id}"}
          type="button"
          variant="primary"
          phx-hook="LabelPrint"
          data-print-target={"#sscc-label-content-#{@row.sscc.id}"}
        ><.icon name="hero-printer" class="size-4" /> Print</.button>
        <.button
          id={"download-shipper-#{@row.sscc.id}"}
          type="button"
          phx-hook="LabelSvgDownload"
          data-role="download-label-svg"
          data-sscc={@row.sscc.code}
          data-gs1-text={gs1_text(@row.sscc)}
          data-quantity={@row.serial_count}
          data-gtin={@row.sscc.gtin}
          data-expiry={date_ai(@row.sscc.expiry_date)}
          data-batch={@row.sscc.batch}
          data-production={date_ai(@row.sscc.production_date)}
          data-material-description={@product_name}
          data-order-number={@row.sscc.order_number}
          data-from-company={party(@row.sscc, :from_company_name)}
          data-from-address={party(@row.sscc, :from_address)}
          data-to-company={party(@row.sscc, :to_company_name)}
          data-to-address={party(@row.sscc, :to_address)}
        ><.icon name="hero-code-bracket" class="size-4" /> Download as SVG</.button>
        <.button
          id={"shipper-#{@row.sscc.id}-serials"}
          type="button"
          class="ml-auto"
          phx-click={JS.toggle(to: "#shipper-primaries-#{@row.sscc.id}")}
        ><.icon name="hero-list-bullet" class="size-4" /> Show serials ({@row.serial_count})</.button>
      </div>
      <div
        id={"shipper-primaries-#{@row.sscc.id}"}
        class="mt-3 hidden rounded-lg border border-cyan-200 bg-white p-4"
      >
        <p :if={@row.serials == []} class="text-sm text-thamani-pewter">
          No local serials are recorded for this shipper.
        </p>
        <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          <span
            :for={serial <- @row.serials}
            class="truncate rounded-md bg-thamani-canvas px-3 py-2 font-mono text-xs text-thamani-forest"
          >{serial}</span>
        </div>
      </div>
    </article>
    """
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
            <.button
              id={"sscc-#{row.sscc.id}-shippers"}
              type="button"
              variant="primary"
              phx-click="show_shippers"
              phx-value-group-id={row.sscc.id}
            ><.icon name="hero-truck" class="size-4" /> Shippers</.button>
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

      <.modal
        :if={@selected_group}
        id="pallet-shippers-modal"
        show
        size="wide"
        class="shipper-labels-modal"
        title="Shipper Serials"
        subtitle={"SSCC #{@selected_group.pallet_code || "Not assigned to a pallet"}"}
        on_cancel={JS.push("close_shippers")}
      >
        <div class="flex flex-wrap items-center gap-2 border-b border-thamani-stone pb-4">
          <.button type="button" variant="primary">Shipper ({length(@selected_group.shippers)})</.button>
          <.button
            type="button"
            navigate={~p"/manufacturer/sscc/#{hd(@selected_group.shippers).sscc.id}/serials"}
          >Primary ({@selected_group.primary_count})</.button>
          <.button id="print-all-shippers" type="button" phx-hook="PrintAllLabels"><.icon
            name="hero-printer"
            class="size-4"
          /> Print All Shipper</.button>
          <span class="ml-auto rounded-md bg-thamani-mist px-3 py-1 text-xs font-bold text-thamani-forest">{length(
            @selected_group.shippers
          )} items</span>
        </div>

        <div id="pallet-shippers-list" class="mt-4 max-h-[68vh] space-y-5 overflow-y-auto pr-1">
          <.shipper_label
            :for={{shipper, index} <- Enum.with_index(@selected_group.shippers, 1)}
            row={shipper}
            product_name={@product.name}
            position={index}
            total={length(@selected_group.shippers)}
          />
        </div>

        <div class="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-thamani-stone pt-4">
          <span class="text-sm text-thamani-pewter">Showing {length(@selected_group.shippers)} of {length(
            @selected_group.shippers
          )} items</span>
          <div class="flex flex-wrap gap-2">
            <.button type="button" phx-click="close_shippers">Close</.button>
            <.button id="print-all-shippers-footer" type="button" phx-hook="PrintAllLabels"><.icon
              name="hero-printer"
              class="size-4"
            /> Print All Shipper</.button>
            <.button
              id="download-all-shippers-svg"
              type="button"
              variant="primary"
              phx-hook="DownloadAllLabelsSvg"
            ><.icon name="hero-arrow-down-tray" class="size-4" /> Download All Shipper as SVG</.button>
          </div>
        </div>
      </.modal>
    </Layouts.manufacturer_shell>
    """
  end
end
