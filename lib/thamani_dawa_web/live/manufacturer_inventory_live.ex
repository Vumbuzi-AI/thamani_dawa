defmodule ThamaniDawaWeb.ManufacturerInventoryLive do
  @moduledoc """
  Manufacturer inventory overview: batches, shippers, and pallets with
  operational counts and status.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  @batch_sorts ~w(newest oldest expiry_soonest expiry_latest)
  @pallet_sorts ~w(newest oldest)
  @batch_statuses ~w(all ready_to_pack packing_in_progress packed)

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    batch_rows = Manufacturing.list_inventory_batches(organization_id)
    shipper_rows = Manufacturing.list_inventory_shippers(organization_id)
    pallet_rows = Manufacturing.list_inventory_pallets(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Inventory")
     |> assign(:batch_rows, batch_rows)
     |> assign(:shipper_rows, shipper_rows)
     |> assign(:pallet_rows, pallet_rows)
     |> assign(:summary, summary(batch_rows, shipper_rows, pallet_rows))
     |> assign(:tab, "batches")
     |> assign(:search, "")
     |> assign(:status_filter, "all")
     |> assign(:sort, "newest")
     |> assign(:visible_rows, [])}
  end

  def handle_params(params, _url, socket) do
    tab = normalize_tab(params["tab"])
    search = params["q"] || ""
    status_filter = normalize_batch_status(params["status"])
    sort = normalize_sort(tab, params["sort"])

    socket =
      socket
      |> assign(:tab, tab)
      |> assign(:search, search)
      |> assign(:status_filter, if(tab == "batches", do: status_filter, else: "all"))
      |> assign(:sort, sort)

    {:noreply, assign(socket, :visible_rows, visible_rows(socket.assigns))}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: inventory_path(socket.assigns, %{q: search}))}
  end

  def handle_event("set_filter", %{"field" => "status", "value" => value}, socket) do
    {:noreply, push_patch(socket, to: inventory_path(socket.assigns, %{status: value}))}
  end

  def handle_event("set_filter", %{"field" => "sort", "value" => value}, socket) do
    {:noreply, push_patch(socket, to: inventory_path(socket.assigns, %{sort: value}))}
  end

  def handle_event("set_filter", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/inventory"}
      crumb="Inventory"
    >
      <.td_list_page
        title="Inventory"
        subtitle="Track batches, shippers, and pallets across your manufacturing inventory."
      >
        <:tabs>
          <.td_tab
            id="inventory-batches-tab"
            label="Batches"
            count={length(@batch_rows)}
            active={@tab == "batches"}
            patch={inventory_path(assigns, %{tab: "batches"})}
          />
          <.td_tab
            id="inventory-shippers-tab"
            label="Shippers"
            count={length(@shipper_rows)}
            active={@tab == "shippers"}
            patch={inventory_path(assigns, %{tab: "shippers"})}
          />
          <.td_tab
            id="inventory-pallets-tab"
            label="Pallets"
            count={length(@pallet_rows)}
            active={@tab == "pallets"}
            patch={inventory_path(assigns, %{tab: "pallets"})}
          />
        </:tabs>

        <:filters>
          <div class="flex-1 min-w-[240px]">
            <form id="inventory-search-form" phx-change="search" phx-submit="search">
              <.td_search
                id="inventory-search"
                name="search"
                value={@search}
                placeholder={search_placeholder(@tab)}
                phx-debounce="300"
              />
            </form>
          </div>
          <.td_filter_menu
            :if={@tab == "batches"}
            id="inventory-status"
            field="status"
            label="Status"
            value={@status_filter}
            options={batch_status_options()}
          />
          <.td_filter_menu
            id="inventory-sort"
            field="sort"
            label="Sort"
            value={@sort}
            options={sort_options(@tab)}
          />
        </:filters>

        <div class="flex flex-col gap-4">
          <.td_glance_strip id="inventory-summary">
            <.td_glance_cell value={to_string(@summary.batches)} caption="Batches" tone="neutral">
              <:icon><.td_icon name="stack" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              value={to_string(@summary.generated_serials)}
              caption="Generated serials"
              tone="info"
            >
              <:icon><.td_icon name="barcode" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell
              value={to_string(@summary.unpacked_serials)}
              caption="Unpacked serials"
              tone="warning"
            >
              <:icon><.td_icon name="package" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell value={to_string(@summary.shippers)} caption="Shippers" tone="success">
              <:icon><.td_icon name="package" /></:icon>
            </.td_glance_cell>
            <.td_glance_cell value={to_string(@summary.pallets)} caption="Pallets" tone="neutral">
              <:icon><.td_icon name="squares-four" /></:icon>
            </.td_glance_cell>
          </.td_glance_strip>

          <.batches_table
            :if={@tab == "batches"}
            rows={@visible_rows}
            search={@search}
            status_filter={@status_filter}
          />
          <.shippers_table :if={@tab == "shippers"} rows={@visible_rows} search={@search} />
          <.pallets_table :if={@tab == "pallets"} rows={@visible_rows} search={@search} />
        </div>
      </.td_list_page>
    </Layouts.manufacturer_shell>
    """
  end

  defp batches_table(assigns) do
    ~H"""
    <section id="inventory-batches" class="td-card">
      <.td_data_table
        id="inventory-batches-table"
        rows={@rows}
        row_id={fn row -> "inventory-batch-#{row.batch.id}" end}
      >
        <:col :let={row} label="Product">
          <div class="td-stack-sm">
            <div class="font-medium text-td-ink">{row.product.name}</div>
            <div class="td-mono">{row.product.gtin}</div>
          </div>
        </:col>
        <:col :let={row} label="Batch">{row.batch.batch_no}</:col>
        <:col :let={row} label="Production">
          {ThamaniDawaWeb.TimeFormat.date(row.batch.production_date)}
        </:col>
        <:col :let={row} label="Expiry">
          {ThamaniDawaWeb.TimeFormat.date(row.batch.expiry_date)}
        </:col>
        <:col :let={row} label="Generated">{row.generated_count}</:col>
        <:col :let={row} label="Packed">{row.packed_count}</:col>
        <:col :let={row} label="Unpacked">{max(row.generated_count - row.packed_count, 0)}</:col>
        <:col :let={row} label="Status">
          <.td_badge tone={batch_status_tone(row)} label={batch_status_label(row)} />
        </:col>
        <:action :let={row}>
          <.td_button
            id={"inventory-batch-action-#{row.batch.id}"}
            variant="secondary"
            label={batch_action_label(row)}
            navigate={~p"/manufacturer/aggregations/batches/#{row.batch.id}/prepare"}
          />
        </:action>
      </.td_data_table>
      <.td_empty
        :if={@rows == []}
        icon="stack"
        title={
          if(@search != "" or @status_filter != "all", do: "No batches found", else: "No batches yet")
        }
        hint={
          if(@search != "" or @status_filter != "all",
            do: "Try adjusting your search or filters.",
            else: "Generate serials for a product and the batch will appear here."
          )
        }
      >
        <:action>
          <.td_button
            :if={@search == "" and @status_filter == "all"}
            id="inventory-go-products"
            variant="secondary"
            glyph="arrow-right"
            label="Go to products"
            navigate={~p"/manufacturer/products"}
          />
        </:action>
      </.td_empty>
    </section>
    """
  end

  defp shippers_table(assigns) do
    ~H"""
    <section id="inventory-shippers" class="td-card">
      <.td_data_table
        id="inventory-shippers-table"
        rows={@rows}
        row_id={fn row -> "inventory-shipper-#{row.shipper.id}" end}
      >
        <:col :let={row} label="SSCC">
          <.link
            id={"inventory-shipper-detail-#{row.shipper.id}"}
            navigate={~p"/manufacturer/aggregations/ssccs/#{row.shipper.id}"}
            class="td-mono"
          >
            {row.shipper.code}
          </.link>
        </:col>
        <:col :let={row} label="Product">
          <div class="td-stack-sm">
            <div class="font-medium text-td-ink">{row.product_name || "Unknown product"}</div>
            <div :if={row.product_gtin} class="td-mono">{row.product_gtin}</div>
          </div>
        </:col>
        <:col :let={row} label="Batch">{row.shipper.batch || "—"}</:col>
        <:col :let={row} label="Packs">{row.shipper.count_of_trade_items || 0}</:col>
        <:col :let={row} label="Pallet">{row.pallet_code || "Not on a pallet"}</:col>
        <:col :let={row} label="Status">
          <.td_badge
            tone={shipper_status_tone(row.shipper.status)}
            label={humanize_status(row.shipper.status)}
          />
        </:col>
      </.td_data_table>
      <.td_empty
        :if={@rows == []}
        icon="package"
        title={if(@search != "", do: "No shippers found", else: "No shippers yet")}
        hint={
          if(@search != "",
            do: "Try adjusting your search.",
            else: "Create shippers from packed batch serials and they will appear here."
          )
        }
      />
    </section>
    """
  end

  defp pallets_table(assigns) do
    ~H"""
    <section id="inventory-pallets" class="td-card">
      <.td_data_table
        id="inventory-pallets-table"
        rows={@rows}
        row_id={fn row -> "inventory-pallet-#{row.pallet.id}" end}
      >
        <:col :let={row} label="SSCC"><span class="td-mono">{row.pallet.code}</span></:col>
        <:col :let={row} label="Shippers">{row.shipper_count}</:col>
        <:col :let={row} label="Composition">{pallet_composition(row)}</:col>
        <:col :let={row} label="Status">
          <.td_badge
            tone={pallet_status_tone(row.pallet.status)}
            label={humanize_status(row.pallet.status)}
          />
        </:col>
      </.td_data_table>
      <.td_empty
        :if={@rows == []}
        icon="squares-four"
        title={if(@search != "", do: "No pallets found", else: "No pallets yet")}
        hint={
          if(@search != "",
            do: "Try adjusting your search.",
            else: "Create pallets from shippers and they will appear here."
          )
        }
      />
    </section>
    """
  end

  defp visible_rows(%{tab: "batches"} = assigns) do
    assigns.batch_rows
    |> Enum.filter(&matches_batch?(&1, assigns.search, assigns.status_filter))
    |> sort_batches(assigns.sort)
  end

  defp visible_rows(%{tab: "shippers"} = assigns) do
    assigns.shipper_rows
    |> Enum.filter(&matches_shipper?(&1, assigns.search))
    |> sort_rows(assigns.sort)
  end

  defp visible_rows(%{tab: "pallets"} = assigns) do
    assigns.pallet_rows
    |> Enum.filter(&matches_pallet?(&1, assigns.search))
    |> sort_rows(assigns.sort)
  end

  defp matches_batch?(row, search, status_filter) do
    matches_search?(search, [
      row.product.name,
      row.product.gtin,
      row.batch.batch_no
    ]) and matches_batch_status?(row, status_filter)
  end

  defp matches_shipper?(row, search) do
    matches_search?(search, [
      row.shipper.code,
      row.product_name,
      row.product_gtin,
      row.shipper.batch,
      row.pallet_code
    ])
  end

  defp matches_pallet?(row, search) do
    matches_search?(search, [row.pallet.code | row.batch_nos])
  end

  defp matches_search?("", _values), do: true

  defp matches_search?(search, values) do
    query = String.downcase(String.trim(search))

    Enum.any?(values, fn
      nil -> false
      value -> String.contains?(String.downcase(to_string(value)), query)
    end)
  end

  defp matches_batch_status?(_row, "all"), do: true
  defp matches_batch_status?(row, "ready_to_pack"), do: batch_status(row) == :ready_to_pack

  defp matches_batch_status?(row, "packing_in_progress"),
    do: batch_status(row) == :packing_in_progress

  defp matches_batch_status?(row, "packed"), do: batch_status(row) == :packed
  defp matches_batch_status?(_row, _), do: true

  defp sort_batches(rows, "oldest"),
    do: Enum.sort_by(rows, &{&1.batch.inserted_at, &1.batch.id})

  defp sort_batches(rows, "expiry_soonest"),
    do: Enum.sort_by(rows, &{&1.batch.expiry_date, &1.batch.id})

  defp sort_batches(rows, "expiry_latest"),
    do: Enum.sort_by(rows, &{&1.batch.expiry_date, &1.batch.id}, :desc)

  defp sort_batches(rows, _),
    do: Enum.sort_by(rows, &{&1.batch.inserted_at, &1.batch.id}, :desc)

  defp sort_rows(rows, "oldest"), do: Enum.sort_by(rows, &{inserted_at(&1), row_id(&1)})
  defp sort_rows(rows, _), do: Enum.sort_by(rows, &{inserted_at(&1), row_id(&1)}, :desc)

  defp inserted_at(%{shipper: shipper}), do: shipper.inserted_at
  defp inserted_at(%{pallet: pallet}), do: pallet.inserted_at

  defp row_id(%{shipper: shipper}), do: shipper.id
  defp row_id(%{pallet: pallet}), do: pallet.id

  defp summary(batch_rows, shipper_rows, pallet_rows) do
    generated = Enum.reduce(batch_rows, 0, fn row, acc -> acc + row.generated_count end)
    packed = Enum.reduce(batch_rows, 0, fn row, acc -> acc + row.packed_count end)

    %{
      batches: length(batch_rows),
      generated_serials: generated,
      unpacked_serials: max(generated - packed, 0),
      shippers: length(shipper_rows),
      pallets: length(pallet_rows)
    }
  end

  defp batch_status(row) do
    generated = row.generated_count
    packed = row.packed_count

    cond do
      generated > 0 and packed >= generated -> :packed
      packed > 0 -> :packing_in_progress
      true -> :ready_to_pack
    end
  end

  defp batch_status_label(row) do
    case batch_status(row) do
      :packed -> "Packed"
      :packing_in_progress -> "Packing in progress"
      :ready_to_pack -> "Ready to pack"
    end
  end

  defp batch_status_tone(row) do
    case batch_status(row) do
      :packed -> "success"
      :packing_in_progress -> "warning"
      :ready_to_pack -> "info"
    end
  end

  defp batch_action_label(row) do
    case batch_status(row) do
      :packed -> "View shippers"
      :packing_in_progress -> "Continue packing"
      :ready_to_pack -> "Create shippers"
    end
  end

  defp shipper_status_tone("available"), do: "info"
  defp shipper_status_tone("assigned"), do: "neutral"
  defp shipper_status_tone("awaiting_verification"), do: "warning"
  defp shipper_status_tone("completed"), do: "success"
  defp shipper_status_tone("in_transit"), do: "success"
  defp shipper_status_tone(_), do: "neutral"

  defp pallet_status_tone("draft"), do: "neutral"
  defp pallet_status_tone("loading"), do: "info"
  defp pallet_status_tone("awaiting_verification"), do: "warning"
  defp pallet_status_tone("completed"), do: "success"
  defp pallet_status_tone("in_transit"), do: "success"
  defp pallet_status_tone(_), do: "neutral"

  defp humanize_status(nil), do: "Unknown"
  defp humanize_status(status), do: status |> String.replace("_", " ") |> String.capitalize()

  defp pallet_composition(row) do
    parts = ["#{row.shipper_count} shipper#{if row.shipper_count == 1, do: "", else: "s"}"]

    parts =
      if row.product_count > 0 do
        parts ++ ["#{row.product_count} product#{if row.product_count == 1, do: "", else: "s"}"]
      else
        parts
      end

    parts =
      case row.batch_nos do
        [] ->
          parts

        [batch_no] ->
          parts ++ ["Batch #{batch_no}"]

        batch_nos ->
          parts ++
            [
              "Batches #{Enum.join(Enum.take(batch_nos, 3), ", ")}#{if length(batch_nos) > 3, do: "…"}"
            ]
      end

    Enum.join(parts, " · ")
  end

  defp search_placeholder("batches"), do: "Search product, GTIN, or batch"
  defp search_placeholder("shippers"), do: "Search SSCC, product, batch, or pallet"
  defp search_placeholder("pallets"), do: "Search SSCC or batch"
  defp search_placeholder(_), do: "Search"

  defp batch_status_options do
    [
      {"all", "All statuses"},
      {"ready_to_pack", "Ready to pack"},
      {"packing_in_progress", "Packing in progress"},
      {"packed", "Packed"}
    ]
  end

  defp sort_options("batches") do
    [
      {"newest", "Newest first"},
      {"oldest", "Oldest first"},
      {"expiry_soonest", "Expiry soonest"},
      {"expiry_latest", "Expiry latest"}
    ]
  end

  defp sort_options(_tab) do
    [
      {"newest", "Newest first"},
      {"oldest", "Oldest first"}
    ]
  end

  defp normalize_tab(tab) when tab in ~w(batches shippers pallets), do: tab
  defp normalize_tab(_), do: "batches"

  defp normalize_batch_status(status) when status in @batch_statuses, do: status
  defp normalize_batch_status(_), do: "all"

  defp normalize_sort("batches", sort) when sort in @batch_sorts, do: sort

  defp normalize_sort(tab, sort) when tab in ~w(shippers pallets) and sort in @pallet_sorts,
    do: sort

  defp normalize_sort(_tab, _), do: "newest"

  defp inventory_path(assigns, overrides) do
    params =
      %{
        tab: assigns.tab,
        q: blank_to_nil(assigns.search),
        status:
          if(assigns.tab == "batches", do: blank_to_nil(assigns.status_filter, "all"), else: nil),
        sort: blank_to_nil(assigns.sort, "newest")
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    ~p"/manufacturer/inventory?#{params}"
  end

  defp blank_to_nil(value, default \\ nil)
  defp blank_to_nil(nil, default), do: default
  defp blank_to_nil("", default), do: default
  defp blank_to_nil(value, default), do: if(value == default, do: nil, else: value)
end
