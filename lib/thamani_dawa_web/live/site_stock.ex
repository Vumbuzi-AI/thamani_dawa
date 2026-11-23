defmodule ThamaniDawaWeb.SiteStock do
  @moduledoc """
  The read-only site stock page shared by `/lab/stock` and `/pharmacy/stock`
  (Doop frames _VFeE7v1Z3 "Lab stock · products" and QxyvdDb1ea "Lab stock ·
  all batches"; the pharmacy and pharma-lab copies use the same layout).

  The LiveView loads every batch held at the viewer's sites once
  (`Batches.list_site_stock/2`); this module rolls them up by product, works
  out the stat strip, filters and pages in memory, renders the page and
  builds the CSV export.
  """

  use ThamaniDawaWeb, :html

  alias ThamaniDawaWeb.Money
  alias ThamaniDawaWeb.TimeFormat

  @page_size 25
  @near_days 90
  @default_filters %{site: "", category: "", status: "", expiry: ""}

  def page_size, do: @page_size
  def near_days, do: @near_days
  def default_filters, do: @default_filters

  ## Data

  @doc "One row per product, with its batches and stock level, by name."
  def product_rows(batches) do
    batches
    |> Enum.reject(&is_nil(&1.product))
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, [first | _] = product_batches} ->
      product = first.product
      remaining = product_batches |> Enum.map(&(&1.remaining_quantity || 0)) |> Enum.sum()

      %{
        id: product_id,
        product: product,
        batches: product_batches,
        batch_count: length(product_batches),
        remaining: remaining,
        level: level(remaining, product.reorder_level)
      }
    end)
    |> Enum.sort_by(&String.downcase(product_name(&1.product)))
  end

  defp level(remaining, _reorder) when remaining <= 0, do: :out

  defp level(remaining, reorder) when is_integer(reorder) and remaining <= reorder,
    do: :low

  defp level(_remaining, _reorder), do: :in

  @doc """
  What the stat strip shows. Only received batches count: stock still
  awaiting receipt is not on the shelf yet.
  """
  def stats(batches, today) do
    received = Enum.reject(batches, &is_nil(&1.approver_id))
    rows = product_rows(received)

    %{
      out: Enum.count(rows, &(&1.level == :out)),
      low: Enum.count(rows, &(&1.level == :low)),
      near_expiry:
        Enum.count(
          received,
          &(batch_state(&1, today) == :near_expiry and (&1.remaining_quantity || 0) > 0)
        ),
      reorder_cost:
        rows
        |> Enum.filter(&(&1.level in [:low, :out] and is_integer(&1.product.reorder_level)))
        |> Enum.map(fn row ->
          max(row.product.reorder_level - row.remaining, 0) * (row.product.price || 0)
        end)
        |> Enum.sum()
    }
  end

  @doc """
  Everything the page needs for one view of `batches` (all stock at the
  viewer's sites): the site filter narrows rows and stats alike, the other
  filters and the search narrow the table only.
  """
  def compute(batches, view, search, filters, page, today) do
    scoped = scope_site(batches, filters.site)
    rows = product_rows(scoped)

    filtered =
      if view == "products",
        do: filter_products(rows, filters, search, today),
        else: filter_batches(scoped, filters, search, today)

    {entries, total, last_page} = paginate(filtered, page)

    %{
      rows: rows,
      categories: categories(product_rows(batches)),
      stats: stats(scoped, today),
      tick_max: tick_max(rows),
      filtered: filtered,
      entries: entries,
      total: total,
      last_page: last_page,
      page: page |> max(1) |> min(last_page),
      filtered?:
        String.trim(search) != "" or
          Enum.any?(Map.take(filters, [:category, :status, :expiry]), fn {_k, v} -> v != "" end)
    }
  end

  ## LiveView plumbing shared by `LabStockLive` and `PharmacyStockLive`

  @doc """
  Mount-time assigns for a stock page. `batches` is every batch at
  `site_ids`; `sites` is the Site filter's `{name, id}` options; `base_path`
  is where filters patch to and `export_prefix` names exported files.
  """
  def init(socket, batches, site_ids, opts) do
    Phoenix.Component.assign(socket,
      today: ThamaniDawa.BusinessDate.today(),
      allowed_site_ids: site_ids,
      all_batches: batches,
      site_options: Keyword.get(opts, :sites, []),
      base_path: Keyword.fetch!(opts, :base_path),
      export_prefix: Keyword.fetch!(opts, :export_prefix),
      exporting: false
    )
  end

  @doc "Reads tab, search, filters and page from the URL and recomputes the page."
  def apply_params(socket, params) do
    filters = %{
      site: sanitize_site(Map.get(params, "site", ""), socket.assigns.allowed_site_ids),
      category: Map.get(params, "category", ""),
      status: Map.get(params, "status", ""),
      expiry: Map.get(params, "expiry", "")
    }

    view = if params["view"] == "batches", do: "batches", else: "products"

    page =
      case Integer.parse(Map.get(params, "page", "1")) do
        {page, ""} -> page
        _ -> 1
      end

    search = Map.get(params, "search", "")

    computed =
      compute(socket.assigns.all_batches, view, search, filters, page, socket.assigns.today)

    Phoenix.Component.assign(socket,
      view: view,
      search: search,
      filters: filters,
      all_rows: computed.rows,
      categories: computed.categories,
      stats: computed.stats,
      tick_max: computed.tick_max,
      filtered: computed.filtered,
      entries: computed.entries,
      total: computed.total,
      last_page: computed.last_page,
      page: computed.page,
      filtered?: computed.filtered?
    )
  end

  @doc "Handles every stock page event; returns `{:noreply, socket}`."
  def handle_event("set_view", %{"view" => view}, socket),
    do: {:noreply, patch(socket, %{view: view})}

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, patch(socket, %{search: search})}

  def handle_event("set_filter", %{"field" => field, "value" => value}, socket)
      when field in ["site", "category", "status", "expiry"] do
    filters = Map.put(socket.assigns.filters, String.to_existing_atom(field), value)
    {:noreply, patch(socket, %{filters: filters})}
  end

  def handle_event("page", %{"to" => to}, socket) do
    %{view: view, search: search, filters: filters, base_path: base} = socket.assigns

    {:noreply,
     Phoenix.LiveView.push_patch(socket,
       to: stock_path(base, query(view, search, filters, %{"page" => to}))
     )}
  end

  def handle_event("open_export", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :exporting, true)}

  def handle_event("close_export", _params, socket),
    do: {:noreply, Phoenix.Component.assign(socket, :exporting, false)}

  def handle_event("export_csv", params, socket) do
    columns = Map.get(params, "columns", "visible")
    %{view: view, today: today, filtered: filtered, export_prefix: prefix} = socket.assigns

    content =
      if view == "products",
        do: products_csv(filtered, columns),
        else: batches_csv(filtered, columns, today)

    {:noreply,
     socket
     |> Phoenix.Component.assign(:exporting, false)
     |> Phoenix.LiveView.push_event("td:csv", %{
       filename: "#{prefix}-#{view}-#{Date.to_iso8601(today)}.csv",
       content: content
     })}
  end

  def handle_event("export_product", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.all_rows, &(to_string(&1.id) == to_string(id))) do
      nil ->
        {:noreply, socket}

      row ->
        slug = row.product.gtin || to_string(row.id)

        {:noreply,
         Phoenix.LiveView.push_event(socket, "td:csv", %{
           filename: "#{socket.assigns.export_prefix}-#{slug}-batches.csv",
           content: batches_csv(row.batches, "all", socket.assigns.today)
         })}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp patch(socket, changes) do
    %{view: view, search: search, filters: filters, base_path: base} = socket.assigns
    view = Map.get(changes, :view, view)
    search = Map.get(changes, :search, search)
    filters = Map.get(changes, :filters, filters)

    Phoenix.LiveView.push_patch(socket,
      to: stock_path(base, query(view, search, filters)),
      replace: true
    )
  end

  @doc "Keeps a site filter value only when it names one of `site_ids`."
  def sanitize_site(value, site_ids) do
    case Integer.parse(value || "") do
      {site_id, ""} -> if site_id in site_ids, do: value, else: ""
      _ -> ""
    end
  end

  defp scope_site(batches, ""), do: batches

  defp scope_site(batches, site) do
    case Integer.parse(site) do
      {site_id, ""} -> Enum.filter(batches, &(&1.site_id == site_id))
      _ -> batches
    end
  end

  @doc "Display state of a batch: pending receipt, written off, expired, near-expiry or active."
  def batch_state(batch, today) do
    cond do
      is_nil(batch.approver_id) -> :pending
      batch.status not in [:active, nil] -> :inactive
      batch.expiry_date && Date.compare(batch.expiry_date, today) == :lt -> :expired
      batch.expiry_date && Date.diff(batch.expiry_date, today) <= @near_days -> :near_expiry
      true -> :active
    end
  end

  def categories(rows) do
    rows
    |> Enum.map(& &1.product.category)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  def filter_products(rows, filters, search, today) do
    Enum.filter(rows, fn row ->
      category_match?(row.product, filters.category) and
        (filters.status == "" or Atom.to_string(row.level) == filters.status) and
        (filters.expiry == "" or Enum.any?(row.batches, &expiry_match?(&1, filters.expiry, today))) and
        product_search_match?(row, search)
    end)
  end

  def filter_batches(batches, filters, search, today) do
    batches
    |> Enum.reject(&is_nil(&1.product))
    |> Enum.filter(fn batch ->
      category_match?(batch.product, filters.category) and
        batch_status_match?(batch_state(batch, today), filters.status) and
        (filters.expiry == "" or expiry_match?(batch, filters.expiry, today)) and
        batch_search_match?(batch, search)
    end)
  end

  defp batch_status_match?(_state, ""), do: true
  defp batch_status_match?(state, "active"), do: state in [:active, :near_expiry]
  defp batch_status_match?(state, status), do: Atom.to_string(state) == status

  defp category_match?(_product, ""), do: true
  defp category_match?(product, category), do: product.category == category

  defp expiry_match?(%{expiry_date: nil}, _filter, _today), do: false

  defp expiry_match?(%{expiry_date: expiry}, filter, today) do
    days = Date.diff(expiry, today)

    case filter do
      "expired" -> days < 0
      "30" -> days >= 0 and days <= 30
      "90" -> days >= 0 and days <= 90
      "later" -> days > 90
      _ -> true
    end
  end

  defp product_search_match?(row, search) do
    case normalize(search) do
      "" ->
        true

      term ->
        contains?(product_name(row.product), term) or contains?(row.product.gtin, term) or
          contains?(row.product.category, term) or
          Enum.any?(row.batches, &contains?(&1.batch_no, term))
    end
  end

  defp batch_search_match?(batch, search) do
    case normalize(search) do
      "" ->
        true

      term ->
        contains?(product_name(batch.product), term) or contains?(batch.product.gtin, term) or
          contains?(batch.batch_no, term) or contains?(batch.serial, term)
    end
  end

  defp normalize(nil), do: ""
  defp normalize(search), do: search |> String.trim() |> String.downcase()

  defp contains?(nil, _term), do: false

  defp contains?(value, term),
    do: value |> to_string() |> String.downcase() |> String.contains?(term)

  @doc "Slices one page; returns `{entries, total, last_page}`."
  def paginate(list, page) do
    total = length(list)
    last_page = max(div(total + @page_size - 1, @page_size), 1)
    page = page |> max(1) |> min(last_page)
    {Enum.slice(list, (page - 1) * @page_size, @page_size), total, last_page}
  end

  @doc "Tick scale for the Remaining column: four times the largest reorder level, or the largest stock."
  def tick_max(rows) do
    reorder = rows |> Enum.map(&(&1.product.reorder_level || 0)) |> Enum.max(fn -> 0 end)
    stock = rows |> Enum.map(& &1.remaining) |> Enum.max(fn -> 0 end)
    if reorder > 0, do: max(reorder * 4, 1), else: max(stock, 1)
  end

  def product_name(nil), do: "(unknown product)"
  def product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  ## CSV

  def products_csv(rows, columns) do
    headers =
      ["Product", "GTIN", "Category", "Price (KSh)", "Batches", "Remaining", "Status"] ++
        if(columns == "all", do: ["Reorder level"], else: [])

    lines =
      Enum.map(rows, fn row ->
        [
          product_name(row.product),
          row.product.gtin,
          row.product.category,
          row.product.price,
          row.batch_count,
          row.remaining,
          row.level |> level_badge() |> elem(0)
        ] ++ if(columns == "all", do: [row.product.reorder_level], else: [])
      end)

    encode([headers | lines])
  end

  def batches_csv(batches, columns, today) do
    headers =
      [
        "Product",
        "GTIN",
        "Batch no.",
        "Serial",
        "Manufactured",
        "Expiry",
        "Supplier",
        "Remaining",
        "Status"
      ] ++ if(columns == "all", do: ["Site", "Received"], else: [])

    lines =
      Enum.map(batches, fn batch ->
        [
          product_name(batch.product),
          batch.product && batch.product.gtin,
          batch.batch_no,
          batch.serial,
          batch.manufacture_date,
          batch.expiry_date,
          batch.supplier && batch.supplier.name,
          batch.remaining_quantity,
          batch |> batch_state(today) |> state_badge() |> elem(0)
        ] ++
          if(columns == "all",
            do: [
              batch.site && batch.site.name,
              batch.received_at && TimeFormat.datetime(batch.received_at)
            ],
            else: []
          )
      end)

    encode([headers | lines])
  end

  defp encode(lines) do
    lines
    |> Enum.map_join("\r\n", fn line -> Enum.map_join(line, ",", &cell/1) end)
    |> Kernel.<>("\r\n")
  end

  defp cell(nil), do: ""

  defp cell(value) do
    value = to_string(value)

    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: "\"" <> String.replace(value, "\"", "\"\"") <> "\"",
      else: value
  end

  ## Labels

  def level_badge(:in), do: {"In stock", "success"}
  def level_badge(:low), do: {"Low stock", "warning"}
  def level_badge(:out), do: {"Out of stock", "danger"}

  def state_badge(:active), do: {"Active", "success"}
  def state_badge(:near_expiry), do: {"Near-expiry", "expiry"}
  def state_badge(:expired), do: {"Expired", "danger"}
  def state_badge(:pending), do: {"Pending receipt", "info"}
  def state_badge(:inactive), do: {"Inactive", "danger"}

  defp batch_badge(batch, today) do
    case batch_state(batch, today) do
      :inactive -> {Phoenix.Naming.humanize(batch.status), "danger"}
      state -> state_badge(state)
    end
  end

  defp level_tone(:in), do: "neutral"
  defp level_tone(:low), do: "warning"
  defp level_tone(:out), do: "danger"

  def status_options("products"),
    do: [{"", "Any"}, {"in", "In stock"}, {"low", "Low stock"}, {"out", "Out of stock"}]

  def status_options(_batches),
    do: [
      {"", "Any"},
      {"active", "Active"},
      {"near_expiry", "Near-expiry"},
      {"expired", "Expired"},
      {"pending", "Pending receipt"},
      {"inactive", "Inactive"}
    ]

  def expiry_options,
    do: [
      {"", "Any"},
      {"expired", "Expired"},
      {"30", "Within 30 days"},
      {"90", "Within 90 days"},
      {"later", "Later"}
    ]

  @doc "Query params for a stock URL; blank values are dropped."
  def query(view, search, filters, extra \\ %{}) do
    %{
      "view" => if(view == "products", do: nil, else: view),
      "search" => blank_to_nil(search),
      "site" => blank_to_nil(Map.get(filters, :site, "")),
      "category" => blank_to_nil(filters.category),
      "status" => blank_to_nil(filters.status),
      "expiry" => blank_to_nil(filters.expiry)
    }
    |> Map.merge(extra)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  def stock_path(base, params) when map_size(params) == 0, do: base
  def stock_path(base, params), do: base <> "?" <> URI.encode_query(params)

  ## Page

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :base_path, :string, required: true
  attr :view, :string, required: true
  attr :entries, :list, required: true
  attr :total, :integer, required: true
  attr :page, :integer, required: true
  attr :last_page, :integer, required: true
  attr :search, :string, required: true
  attr :filters, :map, required: true
  attr :categories, :list, required: true
  attr :stats, :map, required: true
  attr :tick_max, :integer, required: true
  attr :today, Date, required: true
  attr :filtered?, :boolean, required: true
  attr :exporting, :boolean, default: false
  attr :stock_takes_path, :string, required: true
  attr :disposals_path, :string, required: true
  attr :scan_path, :string, required: true
  attr :requisition_path, :string, required: true
  attr :product_path, :any, required: true, doc: "fn product_id -> path"
  attr :batch_path, :any, required: true, doc: "fn batch_id -> path"
  attr :empty_hint, :string, required: true

  attr :sites, :list,
    default: [],
    doc: "{name, id} options; the Site filter shows when there are two or more"

  def stock_page(assigns) do
    ~H"""
    <section class="td-recipe td-list-page td-stock-page">
      <.td_page_header title={@title} subtitle={@subtitle}>
        <:actions>
          <.td_button
            id={"#{@id}-stock-takes"}
            label="Stock takes"
            glyph="list-checks"
            navigate={@stock_takes_path}
          />
          <.td_button
            id={"#{@id}-disposals"}
            label="Disposals"
            glyph="trash"
            navigate={@disposals_path}
          />
          <.td_button
            id={"#{@id}-export"}
            label="Export CSV"
            glyph="download-simple"
            phx-click="open_export"
          />
        </:actions>
      </.td_page_header>

      <div class="td-stock-strip">
        <div class="td-glance">
          <.td_glance_cell
            id={"#{@id}-stat-out"}
            patch={
              stock_path(@base_path, query("products", "", %{default_filters() | status: "out"}))
            }
            tone="danger"
            value={"#{@stats.out} out of stock"}
            caption="Products with no remaining stock"
          >
            <:icon><.td_icon name="x-circle" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id={"#{@id}-stat-low"}
            patch={
              stock_path(@base_path, query("products", "", %{default_filters() | status: "low"}))
            }
            tone="warning"
            value={"#{@stats.low} low on stock"}
            caption="At or below reorder level"
          >
            <:icon><.td_icon name="warning" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id={"#{@id}-stat-near-expiry"}
            patch={
              stock_path(
                @base_path,
                query("batches", "", %{default_filters() | site: @filters.site, expiry: "90"})
              )
            }
            tone="expiry"
            value={"#{@stats.near_expiry} near-expiry #{if @stats.near_expiry == 1, do: "batch", else: "batches"}"}
            caption={"Expiring within #{near_days()} days"}
          >
            <:icon><.td_icon name="calendar-x" class="size-[18px]" /></:icon>
          </.td_glance_cell>
          <.td_glance_cell
            id={"#{@id}-stat-reorder"}
            patch={
              stock_path(@base_path, query("products", "", %{default_filters() | status: "low"}))
            }
            tone="info"
            value={"#{Money.ksh(@stats.reorder_cost)} to reorder"}
            caption="Estimated cost to reach reorder levels"
          >
            <:icon><.td_icon name="money" class="size-[18px]" /></:icon>
          </.td_glance_cell>
        </div>
      </div>

      <nav class="td-tabs" aria-label="Stock view">
        <.link
          id="products-tab"
          patch={stock_path(@base_path, query("products", @search, @filters))}
          class={["td-tab", @view == "products" && "is-active"]}
          aria-current={@view == "products" && "page"}
        >
          Products
        </.link>
        <.link
          id="batches-tab"
          patch={stock_path(@base_path, query("batches", @search, @filters))}
          class={["td-tab", @view == "batches" && "is-active"]}
          aria-current={@view == "batches" && "page"}
        >
          All batches
        </.link>
      </nav>

      <div id={"#{@id}-toolbar"} class="td-toolbar">
        <form phx-change="search" id="search-form" onsubmit="return false">
          <label class="td-search">
            <.td_icon name="magnifying-glass" />
            <input
              type="search"
              name="search"
              value={@search}
              placeholder="Search product, GTIN or batch"
              phx-debounce="200"
              autocomplete="off"
            />
            <kbd>/</kbd>
          </label>
        </form>
        <.filter_chip
          :if={length(@sites) > 1}
          id={@id}
          field="site"
          label="Site"
          value={@filters.site}
          options={[{"", "All"} | Enum.map(@sites, fn {name, id} -> {to_string(id), name} end)]}
        />
        <.filter_chip
          id={@id}
          field="category"
          label="Category"
          value={@filters.category}
          options={[{"", "All"} | Enum.map(@categories, &{&1, &1})]}
        />
        <.filter_chip
          id={@id}
          field="status"
          label="Status"
          value={@filters.status}
          options={status_options(@view)}
        />
        <.filter_chip
          id={@id}
          field="expiry"
          label="Expiry"
          value={@filters.expiry}
          options={expiry_options()}
        />
      </div>

      <div :if={@entries == []} class="td-pad td-empty-wrap">
        <div id={"#{@id}-empty"} class="td-card td-empty-card">
          <%= if @filtered? do %>
            <p class="td-empty-title">
              {if @view == "products", do: "No products match", else: "No batches match"}
            </p>
            <p class="td-note">
              Try another filter or clear the search to see all stock at your site.
            </p>
            <.td_button
              id={"#{@id}-clear-filters"}
              label="Clear filters"
              patch={stock_path(@base_path, query(@view, "", default_filters()))}
            />
          <% else %>
            <p class="td-empty-title">No stock yet</p>
            <p class="td-note">{@empty_hint}</p>
          <% end %>
        </div>
      </div>

      <div
        :if={@entries != [] and @view == "products"}
        id={"#{@id}-products"}
        class="td-data td-list-table"
      >
        <table>
          <thead>
            <tr>
              <th>Product</th>
              <th>Category</th>
              <th class="is-num">Price</th>
              <th class="is-num">Batches</th>
              <th class="is-num">Remaining</th>
              <th>Status</th>
              <th class="td-act"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="products">
            <tr
              :for={row <- @entries}
              id={"products-#{row.id}"}
              class="is-link"
              phx-click={JS.navigate(@product_path.(row.id))}
            >
              <td>
                <span class="td-cell-2">
                  <span>{product_name(row.product)}</span>
                  <span class="td-mono">{row.product.gtin}</span>
                </span>
              </td>
              <td>{row.product.category || "—"}</td>
              <td class="is-num">
                {if row.product.price, do: Money.ksh(row.product.price), else: "—"}
              </td>
              <td class="is-num">{row.batch_count}</td>
              <td class="is-num">
                <span class="td-remaining">
                  <.td_ticks count={row.remaining} max={@tick_max} tone={level_tone(row.level)} />
                  <span>{row.remaining}</span>
                </span>
              </td>
              <td>
                <% {label, tone} = level_badge(row.level) %>
                <.td_badge tone={tone} label={label} />
              </td>
              <td class="td-act">
                <.row_menu id={"products-#{row.id}-actions"}>
                  <.td_menu_item
                    icon="stack"
                    label="View batches"
                    phx-click={JS.navigate(@product_path.(row.id))}
                  />
                  <.td_menu_item icon="scan" label="Scan lookup" phx-click={JS.navigate(@scan_path)} />
                  <.td_menu_item
                    icon="clipboard-text"
                    label="Add to requisition"
                    phx-click={JS.navigate(@requisition_path)}
                  />
                  <.td_menu_item
                    icon="download-simple"
                    label="Export batch list"
                    phx-click={JS.push("export_product", value: %{id: row.id})}
                  />
                </.row_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@entries != [] and @view == "batches"}
        id={"#{@id}-batches"}
        class="td-data td-list-table"
      >
        <table>
          <thead>
            <tr>
              <th>Product</th>
              <th>Batch no.</th>
              <th>Serial</th>
              <th>Manufactured</th>
              <th>Expiry</th>
              <th>Supplier</th>
              <th class="is-num">Remaining</th>
              <th>Status</th>
              <th class="td-act"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="stock">
            <tr
              :for={batch <- @entries}
              id={"stock-#{batch.id}"}
              class="is-link"
              phx-click={JS.navigate(@batch_path.(batch.id))}
            >
              <td>
                <span class="td-cell-2">
                  <span>{product_name(batch.product)}</span>
                  <span class="td-mono">{batch.product.gtin}</span>
                </span>
              </td>
              <td><span class="td-mono">{batch.batch_no}</span></td>
              <td>
                <span :if={batch.serial} class="td-mono">{batch.serial}</span><span
                  :if={!batch.serial}
                  class="td-muted"
                >—</span>
              </td>
              <td>{TimeFormat.date(batch.manufacture_date)}</td>
              <td>{TimeFormat.date(batch.expiry_date)}</td>
              <td>{(batch.supplier && batch.supplier.name) || "—"}</td>
              <td class="is-num">{batch.remaining_quantity}</td>
              <td>
                <% {label, tone} = batch_badge(batch, @today) %>
                <.td_badge tone={tone} label={label} />
              </td>
              <td class="td-act">
                <.row_menu id={"stock-#{batch.id}-actions"}>
                  <.td_menu_item
                    icon="package"
                    label="View batch"
                    phx-click={JS.navigate(@batch_path.(batch.id))}
                  />
                  <.td_menu_item
                    icon="stack"
                    label="View product"
                    phx-click={JS.navigate(@product_path.(batch.product_id))}
                  />
                  <.td_menu_item icon="scan" label="Scan lookup" phx-click={JS.navigate(@scan_path)} />
                  <.td_menu_item
                    icon="clipboard-text"
                    label="Add to requisition"
                    phx-click={JS.navigate(@requisition_path)}
                  />
                </.row_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@entries != []} class="td-tfoot">
        <span>
          <b>{(@page - 1) * page_size() + 1} to {(@page - 1) * page_size() + length(@entries)}</b>
          of {@total} {if @view == "products", do: "products", else: "batches"}
        </span>
        <span class="td-tfoot-pager">
          <button
            type="button"
            class="td-icon-btn"
            aria-label="Previous page"
            disabled={@page == 1}
            phx-click="page"
            phx-value-to={@page - 1}
          >
            <.td_icon name="caret-left" />
          </button>
          <button
            type="button"
            class="td-icon-btn"
            aria-label="Next page"
            disabled={@page >= @last_page}
            phx-click="page"
            phx-value-to={@page + 1}
          >
            <.td_icon name="caret-right" />
          </button>
        </span>
      </div>

      <.td_csv_download id={"#{@id}-csv"} />

      <.td_export_modal
        :if={@exporting}
        id={"#{@id}-export-modal"}
        on_cancel={JS.push("close_export")}
        columns={[{"All visible columns", "visible"}, {"Every column", "all"}]}
        count={@total}
        noun={if @view == "products", do: "products", else: "batches"}
      />
    </section>
    """
  end

  attr :id, :string, required: true
  attr :field, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true

  defp filter_chip(assigns) do
    ~H"""
    <div class="td-chip-wrap">
      <button
        type="button"
        id={"#{@id}-chip-#{@field}"}
        class="td-chip"
        phx-click={JS.toggle(to: "##{@id}-menu-#{@field}")}
        phx-click-away={JS.hide(to: "##{@id}-menu-#{@field}")}
        aria-haspopup="menu"
      >
        <span class="td-chip-label">{@label}</span>
        <span class="td-chip-value">{option_label(@options, @value)}</span>
        <.td_icon name="caret-down" />
      </button>
      <div id={"#{@id}-menu-#{@field}"} class="td-popover td-filter-menu hidden" role="menu">
        <p class="td-popover-label">{@label}</p>
        <button
          :for={{value, label} <- @options}
          type="button"
          id={"#{@id}-#{@field}-#{if value == "", do: "any", else: value}"}
          class={["td-menu-item", value == @value && "is-selected"]}
          phx-click={
            JS.push("set_filter", value: %{field: @field, value: value})
            |> JS.hide(to: "##{@id}-menu-#{@field}")
          }
          role="menuitemradio"
          aria-checked={to_string(value == @value)}
        >
          <span>{label}</span>
          <.td_icon :if={value == @value} name="check" class="size-4 td-menu-check" />
        </button>
      </div>
    </div>
    """
  end

  defp option_label(options, value) do
    Enum.find_value(options, value, fn {v, label} -> if v == value, do: label end)
  end

  attr :id, :string, required: true
  slot :inner_block, required: true

  defp row_menu(assigns) do
    ~H"""
    <div id={"#{@id}-wrap"} class="td-chip-wrap td-row-menu" phx-hook=".RowMenu" data-menu={@id}>
      <button
        type="button"
        id={"#{@id}-button"}
        class="td-icon-btn"
        aria-label="Row actions"
        aria-haspopup="menu"
        phx-click={JS.toggle(to: "##{@id}")}
        phx-click-away={JS.hide(to: "##{@id}")}
      >
        <.td_icon name="dots-three" />
      </button>
      <div id={@id} class="td-popover td-row-popover hidden" role="menu">
        {render_slot(@inner_block)}
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".RowMenu">
      // The table scrolls, so an absolutely positioned menu is cut off on the
      // last rows. Pin it to the viewport next to its button instead, and open
      // it upward when there is no room below.
      export default {
        mounted() {
          this.button = this.el.querySelector("button")
          this.menu = document.getElementById(this.el.dataset.menu)
          this.place = () => {
            const rect = this.button.getBoundingClientRect()
            const height = this.menu.offsetHeight || 180
            const below = window.innerHeight - rect.bottom
            const up = below < height + 12 && rect.top > below
            this.menu.style.position = "fixed"
            this.menu.style.right = `${Math.max(window.innerWidth - rect.right, 8)}px`
            this.menu.style.left = "auto"
            this.menu.style.top = up ? "auto" : `${rect.bottom + 4}px`
            this.menu.style.bottom = up ? `${window.innerHeight - rect.top + 4}px` : "auto"
          }
          this.hide = () => this.menu.classList.add("hidden")
          this.button.addEventListener("click", () => requestAnimationFrame(this.place))
          this.scroller = this.el.closest(".td-data")
          this.scroller && this.scroller.addEventListener("scroll", this.hide, {passive: true})
          window.addEventListener("resize", this.hide)
        },
        destroyed() {
          this.scroller && this.scroller.removeEventListener("scroll", this.hide)
          window.removeEventListener("resize", this.hide)
        }
      }
    </script>
    """
  end

  ## Product and batch detail (Doop eKD_3r3UqQ / 5MdRlvaDiH, print 6gWHYiELXI)

  @doc "Usage history rows for a batch loaded with `Batches.get_batch_with_details!/2`, newest first."
  def usage_history(batch) do
    dispenses =
      Enum.map(batch.prescription_batch_dispenses, fn dispense ->
        prescription = dispense.prescription_item.prescription

        %{
          at: dispense.dispensed_at,
          who: user_display(dispense.dispensed_by),
          detail: "Dispensed #{dispense.quantity} to #{patient_name(prescription)}"
        }
      end)

    lab_usages =
      Enum.map(batch.lab_consumable_usages, fn usage ->
        %{
          at: usage.used_at,
          who: user_display(usage.used_by),
          detail:
            "Used #{usage.quantity} for #{patient_name(usage.lab_order)} · #{ThamaniDawa.LabOrders.reference(usage.lab_order)}"
        }
      end)

    received =
      if batch.received_at,
        do: [
          %{
            at: batch.received_at,
            who: user_display(batch.approver),
            detail:
              "Received #{batch.quantity}" <>
                if(batch.supplier, do: " from #{batch.supplier.name}", else: "")
          }
        ],
        else: []

    (dispenses ++ lab_usages ++ received)
    |> Enum.filter(& &1.at)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  def user_display(nil), do: "—"
  def user_display(%{name: name}) when is_binary(name) and name != "", do: name
  def user_display(%{email: email}), do: email

  defp patient_name(%{patient_visit: %{patient: %{full_name: full_name}}}), do: full_name
  defp patient_name(_), do: "(unknown patient)"

  attr :product, :map, required: true
  attr :batches, :list, required: true
  attr :today, Date, required: true
  attr :back_path, :string, required: true
  attr :scan_path, :string, required: true
  attr :requisition_path, :string, required: true
  attr :batch_path, :any, required: true
  attr :batches_subtitle, :string, default: "Batches available at your permitted site."

  def product_detail(assigns) do
    remaining = assigns.batches |> Enum.map(&(&1.remaining_quantity || 0)) |> Enum.sum()

    earliest =
      assigns.batches
      |> Enum.filter(&((&1.remaining_quantity || 0) > 0 and &1.expiry_date))
      |> Enum.map(& &1.expiry_date)
      |> Enum.min(Date, fn -> nil end)

    assigns =
      assigns
      |> assign(:remaining, remaining)
      |> assign(:earliest, earliest)
      |> assign(:level, level(remaining, assigns.product.reorder_level))

    ~H"""
    <section id="stock-product-detail" class="td-recipe td-list-page td-detail-page">
      <div class="td-back">
        <.link navigate={@back_path} class="td-back-link">
          <.td_icon name="arrow-left" class="size-3.5" /> Back to Stock
        </.link>
      </div>

      <header class="td-idh">
        <div class="td-idh-text">
          <h1 class="td-idh-title">
            <span>{product_name(@product)}</span>
            <% {label, tone} = level_badge(@level) %>
            <.td_badge tone={tone} label={label} />
          </h1>
          <p class="td-idh-sub td-mono">
            GTIN {@product.gtin || "—"} · {length(@batches)} {if length(@batches) == 1,
              do: "batch",
              else: "batches"}<span :if={@earliest}> · earliest expiry {Date.to_iso8601(@earliest)}</span>
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button id="stock-product-scan" label="Scan lookup" glyph="scan" navigate={@scan_path} />
          <.td_button
            id="stock-product-requisition"
            label="Add to requisition"
            glyph="clipboard-text"
            navigate={@requisition_path}
          />
        </div>
      </header>

      <div class="td-detail-scroll">
        <div class="td-stack-pad">
          <div class="td-card">
            <dl class="td-kv-grid is-pad is-6">
              <div class="td-kv">
                <dt class="td-kv-label">GTIN</dt>
                <dd class="td-kv-value is-mono">{@product.gtin || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Category</dt>
                <dd class="td-kv-value">{@product.category || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Price</dt>
                <dd class="td-kv-value">
                  {if @product.price, do: Money.ksh(@product.price), else: "—"}
                </dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Reorder level</dt>
                <dd class="td-kv-value">{@product.reorder_level || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Remaining</dt>
                <dd class="td-kv-value">
                  {@remaining} {if @remaining == 1, do: "unit", else: "units"}
                </dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Earliest expiry</dt>
                <dd class="td-kv-value">{TimeFormat.date(@earliest)}</dd>
              </div>
            </dl>
          </div>

          <section class="td-card">
            <.td_card_header title="Batches" subtitle={@batches_subtitle} />
            <div :if={@batches == []} class="td-empty-card">
              <p class="td-empty-title">No batches for this product yet</p>
              <p class="td-note">Batches received at your site appear here.</p>
            </div>
            <div :if={@batches != []} class="td-data">
              <table>
                <thead>
                  <tr>
                    <th>Site</th>
                    <th>Batch no.</th>
                    <th>Expiry</th>
                    <th class="is-num">Remaining</th>
                    <th>Supplier</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody id="batches">
                  <tr
                    :for={batch <- @batches}
                    id={"batches-#{batch.id}"}
                    class="is-link"
                    phx-click={JS.navigate(@batch_path.(batch.id))}
                  >
                    <td>{(batch.site && batch.site.name) || "—"}</td>
                    <td><span class="td-mono">{batch.batch_no}</span></td>
                    <td>{TimeFormat.date(batch.expiry_date)}</td>
                    <td class="is-num">{batch.remaining_quantity}</td>
                    <td>{(batch.supplier && batch.supplier.name) || "—"}</td>
                    <td>
                      <% {label, tone} = batch_badge(batch, @today) %>
                      <.td_badge tone={tone} label={label} />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </section>
    """
  end

  attr :batch, :map, required: true
  attr :history, :list, required: true
  attr :today, Date, required: true
  attr :back_path, :string, required: true
  attr :printing, :boolean, default: false

  def batch_detail(assigns) do
    ~H"""
    <section id="stock-batch-detail" class="td-recipe td-list-page td-detail-page">
      <div class="td-back">
        <.link navigate={@back_path} class="td-back-link">
          <.td_icon name="arrow-left" class="size-3.5" /> Back to product
        </.link>
      </div>

      <header class="td-idh">
        <div class="td-idh-text">
          <h1 class="td-idh-title">
            <span>{product_name(@batch.product)}</span>
            <% {label, tone} = batch_badge(@batch, @today) %>
            <.td_badge tone={tone} label={label} />
          </h1>
          <p class="td-idh-sub td-mono">
            Batch {@batch.batch_no} · GTIN {@batch.gtin || (@batch.product && @batch.product.gtin) ||
              "—"}
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button
            id="print-data-matrix"
            label="Print Data Matrix"
            glyph="printer"
            phx-click="open_print"
          />
        </div>
      </header>

      <div class="td-detail-scroll">
        <div class="td-stack-pad">
          <div class="td-card">
            <dl class="td-kv-grid is-pad is-6">
              <div class="td-kv">
                <dt class="td-kv-label">GTIN</dt>
                <dd class="td-kv-value is-mono">
                  {@batch.gtin || (@batch.product && @batch.product.gtin) || "—"}
                </dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Batch / lot</dt>
                <dd class="td-kv-value is-mono">{@batch.batch_no}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Expiry</dt>
                <dd class="td-kv-value">{TimeFormat.date(@batch.expiry_date)}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Stock</dt>
                <dd class="td-kv-value">{@batch.remaining_quantity} of {@batch.quantity} left</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Received by</dt>
                <dd class="td-kv-value td-truncate" title={received_text(@batch)}>
                  {received_text(@batch)}
                </dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Supplier</dt>
                <dd class="td-kv-value">{(@batch.supplier && @batch.supplier.name) || "—"}</dd>
              </div>
            </dl>
          </div>

          <section class="td-card">
            <.td_card_header
              title="Usage history"
              subtitle="Everyone who has drawn stock from this batch, newest first"
            />
            <div :if={@history == []} class="td-empty-card">
              <p class="td-empty-title">No one has drawn from this batch yet</p>
              <p class="td-note">Dispenses, sales and lab use appear here.</p>
            </div>
            <div :if={@history != []} class="td-data">
              <table>
                <thead>
                  <tr>
                    <th>When</th>
                    <th>By</th>
                    <th>Detail</th>
                  </tr>
                </thead>
                <tbody id="batch-usage">
                  <tr :for={{event, index} <- Enum.with_index(@history)} id={"batch-usage-#{index}"}>
                    <td>{TimeFormat.datetime(event.at)}</td>
                    <td>
                      <span class="td-person">
                        <.td_orb seed={event.who} size={16} />
                        <span>{event.who}</span>
                      </span>
                    </td>
                    <td>{event.detail}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>

      <.data_matrix_modal :if={@printing} batch={@batch} />
    </section>
    """
  end

  defp received_text(%{received_at: nil}), do: "Not received yet"

  defp received_text(batch),
    do: "#{user_display(batch.approver)} · #{TimeFormat.date(batch.received_at)}"

  attr :batch, :map, required: true

  defp data_matrix_modal(assigns) do
    assigns =
      assigns
      |> assign(:gs1_text, ThamaniDawa.GS1Encoder.bwipjs_text(assigns.batch))
      |> assign(:human_text, ThamaniDawa.GS1Encoder.human_readable(assigns.batch))

    ~H"""
    <.modal
      id="data-matrix-modal"
      show
      title="Print Data Matrix"
      subtitle="A GS1 label for this batch, ready for your label printer."
      on_cancel={JS.push("close_print")}
    >
      <div class="td-modal-form">
        <div id={"batch-label-#{@batch.id}"} class="td-label-preview printable-batch-label">
          <canvas
            id={"datamatrix-canvas-#{@batch.id}"}
            phx-hook="DataMatrix"
            data-gs1-text={@gs1_text}
          ></canvas>
          <div class="td-label-preview-body">
            <span class="td-label-preview-title">{product_name(@batch.product)}</span>
            <span class="td-mono">{@human_text}</span>
            <span>Expiry {TimeFormat.date(@batch.expiry_date)} · Batch {@batch.batch_no}</span>
          </div>
        </div>
        <div class="td-fgrid is-2 no-print">
          <.input
            type="select"
            id="data-matrix-label-size"
            name="label_size"
            label="Label size"
            value="50x25"
            options={[{"50 × 25 mm", "50x25"}]}
          />
          <.input
            type="number"
            id="data-matrix-copies"
            name="copies"
            label="Copies"
            value="1"
            min="1"
          />
        </div>
      </div>
      <:footer>
        <.td_button type="button" label="Cancel" phx-click={JS.push("close_print")} />
        <.td_button
          id="print-data-matrix-labels"
          type="button"
          variant="primary"
          glyph="printer"
          label="Print labels"
          onclick="window.print()"
        />
      </:footer>
    </.modal>
    """
  end
end
