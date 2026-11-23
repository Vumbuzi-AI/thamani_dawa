defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletNew do
  @moduledoc "Pick shipper SSCCs (any product or batch) and group them into a new pallet SSCC."
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    shippers = Manufacturing.list_available_ssccs(socket.assigns.current_scope.organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Create pallet SSCC")
     |> assign(:shippers, shippers)
     |> assign(:query, "")
     |> assign(:selected, MapSet.new())}
  end

  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_visible", _params, socket) do
    ids = socket.assigns |> visible() |> Enum.map(& &1.id)
    {:noreply, assign(socket, :selected, MapSet.union(socket.assigns.selected, MapSet.new(ids)))}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("create", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.create_pallet_from_shippers(
           organization_id,
           MapSet.to_list(socket.assigns.selected)
         ) do
      {:ok, pallet} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pallet SSCC #{pallet.code} created.")
         |> push_navigate(to: ~p"/manufacturer/aggregations/pallets/#{pallet.id}")}

      {:error, :no_shippers} ->
        {:noreply, put_flash(socket, :error, "Select at least one shipper SSCC.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create the pallet SSCC. Try again.")}
    end
  end

  defp visible(%{shippers: shippers, query: query}) do
    case String.downcase(String.trim(query)) do
      "" ->
        shippers

      term ->
        Enum.filter(shippers, fn s ->
          [
            s.code,
            s.gtin,
            s.batch,
            s.pallet && s.pallet.code | Enum.map(s.batches, & &1.batch_no)
          ]
          |> Enum.any?(&(is_binary(&1) and String.contains?(String.downcase(&1), term)))
        end)
    end
  end

  defp batch_label(sscc),
    do: sscc.batch || Enum.map_join(sscc.batches, ", ", & &1.batch_no) |> blank_dash()

  defp blank_dash(""), do: "—"
  defp blank_dash(value), do: value

  def render(assigns) do
    assigns = assign(assigns, :visible, visible(assigns))

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.header icon="hero-archive-box" back={~p"/manufacturer/aggregations"}>
        Create pallet SSCC
        <:subtitle>
          Select the shipper SSCCs to put on this pallet. They can come from any product or batch.
        </:subtitle>
      </.header>

      <section class="overflow-hidden rounded-2xl ff-surface-card">
        <div class="flex flex-col gap-3 border-b border-thamani-stone p-4 sm:flex-row sm:items-center">
          <form id="pallet-shipper-search" phx-change="search" phx-submit="search" class="flex-1">
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
                placeholder="Search by SSCC, GTIN or batch"
                autocomplete="off"
                class="w-full rounded-xl border border-thamani-stone bg-td-surface py-2.5 pl-9 pr-3 text-sm text-thamani-forest outline-none transition focus:border-thamani-forest"
              />
            </label>
          </form>
          <div class="flex gap-2 text-sm">
            <button
              id="pallet-select-visible"
              type="button"
              phx-click="select_visible"
              class="rounded-lg px-3 py-2 font-semibold text-thamani-forest transition hover:bg-thamani-lime/20"
            >
              Select all shown
            </button>
            <button
              :if={MapSet.size(@selected) > 0}
              id="pallet-clear-selection"
              type="button"
              phx-click="clear"
              class="rounded-lg px-3 py-2 font-semibold text-thamani-pewter transition hover:bg-thamani-canvas"
            >
              Clear
            </button>
          </div>
        </div>

        <div
          :if={@visible == []}
          id="pallet-shippers-empty"
          class="p-10 text-center text-sm text-thamani-pewter"
        >
          {if @shippers == [],
            do: "No shipper SSCCs available. Shippers already on a shipment can't be palletised.",
            else: "No shipper SSCCs match “#{@query}”."}
        </div>

        <ul id="pallet-shipper-options" class="divide-y divide-thamani-stone">
          <li :for={sscc <- @visible}>
            <button
              id={"pallet-option-#{sscc.id}"}
              type="button"
              phx-click="toggle"
              phx-value-id={sscc.id}
              class={[
                "flex w-full items-center gap-4 px-4 py-3.5 text-left transition",
                if(MapSet.member?(@selected, sscc.id),
                  do: "bg-thamani-lime/25",
                  else: "hover:bg-thamani-canvas"
                )
              ]}
            >
              <span class={[
                "flex size-5 shrink-0 items-center justify-center rounded-md border transition",
                if(MapSet.member?(@selected, sscc.id),
                  do: "border-thamani-forest bg-thamani-forest text-white",
                  else: "border-thamani-stone bg-td-surface"
                )
              ]}>
                <.icon :if={MapSet.member?(@selected, sscc.id)} name="hero-check" class="size-3.5" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate font-mono text-sm font-semibold text-thamani-forest">
                  {sscc.code}
                </span>
                <span class="mt-0.5 block truncate text-xs text-thamani-pewter">
                  GTIN {sscc.gtin || "—"} · Batch {batch_label(sscc)} · Exp {sscc.expiry_date || "—"}
                </span>
              </span>
              <span class="hidden shrink-0 text-right text-xs text-thamani-pewter sm:block">
                <span class="block font-semibold text-thamani-forest">
                  {sscc.count_of_trade_items || 0} serials
                </span>
                <span :if={sscc.pallet}>On {sscc.pallet.code}</span>
              </span>
            </button>
          </li>
        </ul>
      </section>

      <div class="sticky bottom-4 mt-6 flex items-center justify-between gap-4 rounded-2xl border border-thamani-stone bg-td-surface p-4 shadow-lg">
        <p id="pallet-selected-count" class="text-sm text-thamani-forest">
          <span class="font-semibold">{MapSet.size(@selected)}</span> shipper SSCCs selected
        </p>
        <.button
          id="create-pallet-sscc"
          variant="primary"
          phx-click="create"
          phx-disable-with="Creating…"
          disabled={MapSet.size(@selected) == 0}
        ><.icon name="hero-archive-box" class="size-4" /> Create pallet SSCC</.button>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
