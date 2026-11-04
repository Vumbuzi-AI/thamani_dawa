defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GtinLookup
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites

  @default_filters %{category: "", is_otc: false, is_dangerous_drug: false}

  @units [
    {"KILOGRAM", "KGM"},
    {"GRAM", "GRM"},
    {"MILIGRAM", "MGM"},
    {"LITRE", "LTR"},
    {"MILLILITRE", "MLT"},
    {"CENTILITRE", "CTL"},
    {"METRE", "MTR"},
    {"CENTIMETER", "CMT"},
    {"MILLIMETRE", "MLT"},
    {"INCH", "INH"},
    {"TABLET", "U2"},
    {"PIECE", "H87"},
    {"AMPERE", "AMP"},
    {"PACK", "PK"},
    {"PACKET", "PA"},
    {"DOZEN", "DZN"},
    {"PAIR", "PR"},
    {"PAGE", "ZP"},
    {"KILOWATT", "KWT"},
    {"WATT", "WTT"},
    {"VOLT", "VLT"},
    {"KILOVOLT", "KVT"},
    {"TON", "LTN"},
    {"CAPSULE", "AV"},
    {"OUNCE", "ONZ"},
    {"ROLL", "RO"}
  ]

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:units, @units)
     |> assign(:lab_enabled, Sites.lab_enabled?(organization_id))
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> reload_products()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> reload_products()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    socket
    |> assign(form: to_form(Product.changeset(%Product{}, %{}), as: :product), product: nil)
    |> assign(:back_path, back_path(params, ~p"/org/products"))
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    back_path =
      if Map.get(params, "return_to") == "show" do
        ~p"/org/products/#{id}"
      else
        ~p"/org/products"
      end

    socket
    |> assign(form: to_form(Product.changeset(product, %{}), as: :product), product: product)
    |> assign(:back_path, back_path)
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :form)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(form: nil, product: nil)
    |> assign(:back_path, ~p"/org/products")
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      category: Map.get(filter_params, "category", ""),
      is_otc: Map.get(filter_params, "is_otc") == "true",
      is_dangerous_drug: Map.get(filter_params, "is_dangerous_drug") == "true"
    }

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket |> assign(:filters, @default_filters) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "category"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | category: ""})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_otc"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | is_otc: false})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_dangerous_drug"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | is_dangerous_drug: false})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("validate", %{"product" => attrs}, socket) do
    attrs = enforce_inventory_type(attrs, socket.assigns.lab_enabled)

    changeset =
      socket.assigns.product
      |> Kernel.||(%Product{})
      |> Product.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    save_product(
      socket,
      socket.assigns.live_action,
      enforce_inventory_type(attrs, socket.assigns.lab_enabled)
    )
  end

  def handle_event("gtin_search_change", %{"gtin_search" => gtin_search}, socket) do
    {:noreply, assign(socket, :gtin_search, gtin_search)}
  end

  def handle_event("skip_gtin", _params, socket) do
    {:noreply, assign(socket, :gtin_step, :form)}
  end

  def handle_event("scan_gtin", %{"gtin_search" => raw_gtin}, socket) do
    case String.trim(raw_gtin) do
      "" ->
        {:noreply, assign(socket, :gtin_step, :form)}

      trimmed ->
        case ThamaniDawa.Gtin.normalize(trimmed) do
          {:ok, normalized} ->
            {:noreply,
             socket
             |> assign(:gtin_step, :form)
             |> assign(:gtin_lookup, :searching)
             |> put_scanned_gtin(normalized)
             |> start_async(:gtin_lookup, fn ->
               GtinLookup.lookup(trimmed)
             end)}

          {:error, :invalid_gtin} ->
            {:noreply, assign(socket, :gtin_lookup, {:error, :invalid_gtin})}
        end
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    case Products.update_product(product, %{is_active: !product.is_active}) do
      {:ok, _updated} ->
        {:noreply, reload_products(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update product.")}
    end
  end

  def handle_async(:gtin_lookup, {:ok, {:ok, prefill}}, socket) do
    {:noreply,
     socket
     |> merge_gtin_prefill(prefill)
     |> assign(:gtin_lookup, {:found, prefill})}
  end

  def handle_async(:gtin_lookup, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, reason})}
  end

  def handle_async(:gtin_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, :provider_error})}
  end

  defp enforce_inventory_type(attrs, true), do: attrs

  defp enforce_inventory_type(attrs, false),
    do: Map.put(attrs, "inventory_type", "medicine")

  defp save_product(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Products.create_product(organization_id, attrs) do
      {:ok, product} ->
        socket =
          socket
          |> put_flash(:info, "Product created.")
          |> stream_insert(:products, build_row(organization_id, product))

        if socket.assigns.back_path == ~p"/org/dashboard" do
          {:noreply, push_navigate(socket, to: socket.assigns.back_path)}
        else
          {:noreply, push_patch(socket, to: socket.assigns.back_path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp save_product(socket, :edit, attrs) do
    case Products.update_product(socket.assigns.product, attrs) do
      {:ok, product} ->
        back_path = socket.assigns[:back_path] || ~p"/org/products"
        organization_id = socket.assigns.current_scope.organization_id

        socket =
          socket
          |> put_flash(:info, "Product updated.")
          |> stream_insert(:products, build_row(organization_id, product))

        if back_path == ~p"/org/products" do
          {:noreply, push_patch(socket, to: back_path)}
        else
          {:noreply, push_navigate(socket, to: back_path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp back_path(%{"return_to" => "dashboard"}, _default), do: ~p"/org/dashboard"
  defp back_path(_params, default), do: default

  defp reload_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page
    search = socket.assigns.search
    filters = socket.assigns.filters

    opts = [
      search: search,
      category: filters.category,
      is_otc: filters.is_otc,
      is_dangerous_drug: filters.is_dangerous_drug
    ]

    page_result = Products.list_products_paginated(organization_id, page, opts)

    all_products = Products.list_products(organization_id)

    categories =
      all_products
      |> distinct_categories()

    product_ids = Enum.map(page_result.entries, & &1.id)
    stock_summary = Batches.stock_summary_by_product(organization_id, product_ids)
    undispatched = Batches.undispatched_summary_by_product(organization_id, product_ids)
    batch_counts = Batches.batch_counts_by_product(organization_id, product_ids)

    rows =
      Enum.map(page_result.entries, fn product ->
        build_stock_row(product, stock_summary, undispatched, batch_counts)
      end)

    socket
    |> assign(:categories, categories)
    |> assign(:page_info, page_result)
    |> stream(:products, rows, reset: true)
  end

  defp uom_label(1, uom), do: uom
  defp uom_label(_count, nil), do: nil
  defp uom_label(_count, uom), do: pluralize(uom)

  defp pluralize(word) do
    cond do
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) -> word <> "es"
      String.match?(word, ~r/[^aeiou]y$/i) -> String.slice(word, 0..-2//1) <> "ies"
      true -> word <> "s"
    end
  end

  defp stock_level(_total, nil), do: nil
  defp stock_level(total, _reorder_level) when total <= 0, do: :out_of_stock
  defp stock_level(total, reorder_level) when total <= reorder_level, do: :low_stock
  defp stock_level(_total, _reorder_level), do: nil

  defp build_row(organization_id, product) do
    stock_summary = Batches.stock_summary_by_product(organization_id, [product.id])
    undispatched = Batches.undispatched_summary_by_product(organization_id, [product.id])
    batch_counts = Batches.batch_counts_by_product(organization_id, [product.id])
    build_stock_row(product, stock_summary, undispatched, batch_counts)
  end

  # "Org-wide stock" is every unit the org has on record for the product: in the
  # warehouse awaiting dispatch, received at a site, or dispatched but not yet
  # confirmed received. The breakdown is kept alongside so the single number
  # can be explained (tooltip) rather than mistaken for "ready to dispense."
  defp build_stock_row(product, stock_summary, undispatched, batch_counts) do
    site_summary = Map.get(stock_summary, product.id, %{})
    awaiting_dispatch = Map.get(undispatched, product.id, 0)
    received_at_sites = Map.get(site_summary, :received_remaining, 0)
    in_transit = Map.get(site_summary, :pending_remaining, 0)
    total_stock = awaiting_dispatch + received_at_sites + in_transit

    %{
      id: product.id,
      product: product,
      total_stock: total_stock,
      batch_count: Map.get(batch_counts, product.id, 0),
      stock_level: stock_level(total_stock, product.reorder_level)
    }
  end

  defp distinct_categories(products) do
    products
    |> Enum.map(& &1.category)
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp active_filter_count(filters) do
    Enum.count([filters.category != "", filters.is_otc, filters.is_dangerous_drug], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.category != "" && %{label: "Category: #{filters.category}", field: "category"},
      filters.is_otc && %{label: "OTC", field: "is_otc"},
      filters.is_dangerous_drug && %{label: "Dangerous drug", field: "is_dangerous_drug"}
    ]
    |> Enum.filter(& &1)
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp reset_gtin_lookup(socket) do
    socket
    |> assign(:gtin_search, "")
    |> assign(:gtin_lookup, :idle)
  end

  defp put_scanned_gtin(socket, normalized_gtin) do
    base = socket.assigns.product || %Product{}

    changeset =
      base
      |> Product.changeset(%{})
      |> Ecto.Changeset.change(gtin: normalized_gtin)

    assign(socket, :form, to_form(changeset, as: :product))
  end

  defp merge_gtin_prefill(socket, prefill) do
    base = socket.assigns.product || %Product{}
    attrs = Map.take(prefill, [:gtin, :brand_name, :generic_name, :manufacturer, :uom])

    changeset =
      base
      |> Product.changeset(%{})
      |> Ecto.Changeset.change(attrs)

    assign(socket, :form, to_form(changeset, as: :product))
  end

  defp gtin_lookup_message({:found, _prefill}),
    do: {:info, "Match found — review the fields below before saving."}

  defp gtin_lookup_message({:error, :not_found}),
    do: {:warning, "No match found for this GTIN — enter the product details manually."}

  defp gtin_lookup_message({:error, :timeout}),
    do: {:warning, "Lookup timed out — enter the product details manually."}

  defp gtin_lookup_message({:error, :provider_error}),
    do: {:warning, "Couldn't reach the lookup service — enter the product details manually."}

  # Nothing the person filling the form can do about our credentials, so the copy
  # matches the generic outage case; the cause is in the logs.
  defp gtin_lookup_message({:error, :unauthorized}),
    do: {:warning, "Couldn't reach the lookup service — enter the product details manually."}

  defp gtin_lookup_message(_), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header icon="hero-cube">
        Product catalog
        <:subtitle>Search, filter, and manage your product catalog.</:subtitle>
        <:actions>
          <.button id="product-new-button" variant="primary" patch={~p"/org/products/new"}>
            <.icon name="hero-plus" class="size-4" /> Add product
          </.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by name, GTIN, or category"
            />
          </form>

          <.filter_drawer
            id="products-filters"
            title="Filter products"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Category">
              <.input
                type="select"
                name="filters[category]"
                value={@filters.category}
                options={@categories}
                prompt="All categories"
              />
            </:group>
            <:group label="Flags">
              <.input
                type="checkbox"
                name="filters[is_otc]"
                value={@filters.is_otc}
                label="Over-the-counter"
              />
              <.input
                type="checkbox"
                name="filters[is_dangerous_drug]"
                value={@filters.is_dangerous_drug}
                label="Dangerous drug"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="product-modal"
        show
        on_cancel={
          if @back_path == ~p"/org/products",
            do: JS.patch(~p"/org/products"),
            else: JS.navigate(@back_path)
        }
      >
        <div class="space-y-6">
          <div>
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
              {if @live_action == :new, do: "Add a product", else: "Edit product"}
            </h2>
          </div>

          <div :if={@gtin_step == :scan} id="gtin-scan-step" class="space-y-4">
            <div class="bg-slate-50 rounded-lg p-4">
              <p class="text-sm text-slate-600 mb-4">
                <span class="font-medium">Scan or enter the product's GTIN</span>
                to automatically fill in product details, or skip to enter everything manually.
              </p>
            </div>

            <form
              id="gtin-scan-form"
              phx-submit="scan_gtin"
              phx-change="gtin_search_change"
              class="space-y-3"
            >
              <div class="relative">
                <input
                  type="text"
                  name="gtin_search"
                  value={@gtin_search}
                  placeholder="Scan or type a GTIN (e.g., 5901234123457)"
                  class="thamani-input w-full pl-4 pr-12"
                  autofocus
                  inputmode="numeric"
                />
                <div
                  :if={@gtin_search != "" and @gtin_lookup != :searching}
                  class="absolute right-3 top-1/2 -translate-y-1/2"
                >
                  <div
                    :if={@gtin_lookup == {:error, :invalid_gtin}}
                    class="text-red-500"
                  >
                    <.icon name="hero-x-circle" class="size-5" />
                  </div>
                </div>
              </div>

              <div
                :if={@gtin_lookup == {:error, :invalid_gtin}}
                class="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-lg"
              >
                <.icon
                  name="hero-exclamation-circle"
                  class="size-5 text-red-600 mt-0.5 flex-shrink-0"
                />
                <p class="text-sm text-red-700">
                  Please enter a valid GTIN. GTINs are numeric codes with 8, 12, 13, or 14 digits.
                </p>
              </div>

              <div class="flex gap-3">
                <.button
                  type="submit"
                  variant="primary"
                  class="flex-1"
                  disabled={@gtin_search == ""}
                  phx-disable-with="Looking up..."
                >
                  Look Up
                </.button>
                <.button
                  type="button"
                  phx-click="skip_gtin"
                  variant="ghost"
                >
                  Skip
                </.button>
              </div>
            </form>
          </div>

          <div :if={@gtin_step == :form} class="space-y-4">
            <div
              :if={@live_action == :new and @gtin_lookup != :idle}
              class="rounded-lg border p-3"
              style={
                case @gtin_lookup do
                  :searching -> "background-color: #F0F9FF; border-color: #E0F2FE;"
                  {:found, _} -> "background-color: #F0FDF4; border-color: #BBF7D0;"
                  {:error, _} -> "background-color: #FEF2F2; border-color: #FECACA;"
                  _ -> ""
                end
              }
            >
              <div :if={@gtin_lookup == :searching} class="flex items-center gap-2">
                <.icon name="hero-arrow-path" class="size-4 text-blue-600 motion-safe:animate-spin" />
                <p class="text-sm text-blue-700 font-medium">Looking up GTIN details...</p>
              </div>
              <% message = gtin_lookup_message(@gtin_lookup) %>
              <div
                :if={message}
                class="flex items-start gap-2"
              >
                <div>
                  <.icon
                    name={
                      case elem(message, 0) do
                        :info -> "hero-check-circle"
                        :warning -> "hero-exclamation-triangle"
                      end
                    }
                    class={
                      if elem(message, 0) == :info,
                        do: "size-5 text-green-600 mt-0.5",
                        else: "size-5 text-amber-600 mt-0.5"
                    }
                  />
                </div>
                <p
                  class="text-sm"
                  style={
                    if elem(message, 0) == :info,
                      do: "color: #16a34a; font-weight: 500;",
                      else: "color: #92400e;"
                  }
                >
                  {elem(message, 1)}
                </p>
              </div>
            </div>

            <.form
              for={@form}
              id="product-form"
              phx-submit="save"
              phx-change="validate"
              class="space-y-4"
            >
              <div class="grid grid-cols-2 gap-4">
                <.input field={@form[:price]} type="number" label="Price" min="0" required />
                <.input
                  field={@form[:uom]}
                  type="select"
                  label="Unit of measure"
                  options={@units}
                  prompt="Select a unit"
                  required
                />
              </div>

              <div class="space-y-2">
                <label class="block">
                  <span class="text-sm font-medium text-slate-700">
                    Product Name <span class="text-red-500">*</span>
                  </span>
                  <span class="text-xs text-slate-500 ml-1">(at least generic or brand name)</span>
                </label>
                <div class="grid grid-cols-2 gap-4">
                  <.input
                    field={@form[:generic_name]}
                    label="Generic name"
                    placeholder="e.g., Ibuprofen"
                  />
                  <.input field={@form[:brand_name]} label="Brand name" placeholder="e.g., Advil" />
                </div>
              </div>

              <div class="grid grid-cols-2 gap-4">
                <.input
                  field={@form[:category]}
                  type="combobox"
                  label="Category"
                  options={@categories}
                  placeholder="e.g., Analgesic"
                />
                <.input
                  field={@form[:manufacturer]}
                  label="Manufacturer"
                  placeholder="e.g., ABC Pharma"
                />
              </div>

              <.input
                :if={@lab_enabled}
                field={@form[:inventory_type]}
                type="select"
                label="Inventory type"
                options={[{"Medicine", :medicine}, {"Lab consumable", :lab_consumable}]}
                required
              />

              <.input field={@form[:gtin]} label="GTIN" required placeholder="e.g., 5901234123457" />

              <.input field={@form[:reorder_level]} type="number" label="Reorder level" min="0" />

              <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
                <div>
                  <p class="text-sm font-medium text-thamani-forest">Active</p>
                  <p class="text-xs text-thamani-pewter">Enable this product for orders</p>
                </div>
                <.input
                  field={@form[:is_active]}
                  type="checkbox"
                  label=""
                  class="size-5 rounded accent-thamani-forest cursor-pointer"
                />
              </div>

              <div class="rounded-xl border border-thamani-stone overflow-hidden divide-y divide-thamani-stone mb-3">
                <div class="flex items-center justify-between px-4 py-3">
                  <p class="text-sm font-medium text-thamani-forest">Over-the-counter</p>
                  <.input
                    field={@form[:is_otc]}
                    type="checkbox"
                    label=""
                    class="size-5 rounded accent-thamani-forest cursor-pointer"
                  />
                </div>
                <div class="flex items-center justify-between px-4 py-3">
                  <p class="text-sm font-medium text-thamani-forest">Dangerous drug</p>
                  <.input
                    field={@form[:is_dangerous_drug]}
                    type="checkbox"
                    label=""
                    class="size-5 rounded accent-thamani-forest cursor-pointer"
                  />
                </div>
              </div>

              <div class="pt-4">
                <.button variant="primary" class="w-full">Save Product</.button>
              </div>
            </.form>
          </div>
        </div>
      </.modal>

      <.table
        id="products"
        rows={@streams.products}
        mobile_columns={3}
        row_click={fn {_id, row} -> JS.navigate(~p"/org/products/#{row.product.id}") end}
      >
        <:col :let={{_id, row}} label="Name">
          <span class="hidden sm:inline">{product_name(row.product)}</span>
          <span class="flex min-w-0 items-center gap-3.5 sm:hidden">
            <span class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-thamani-lime/30 text-thamani-forest ring-1 ring-thamani-stone">
              <.icon name="hero-cube" class="size-6" />
            </span>
            <span class="min-w-0">
              <span class="block truncate text-base font-semibold text-thamani-forest">
                {product_name(row.product)}
              </span>
              <span class="mt-0.5 block truncate text-sm font-normal text-thamani-pewter">
                {row.product.category || "Uncategorized"}
              </span>
            </span>
          </span>
        </:col>
        <:col :let={{_id, row}} label="Category" mobile="hidden" tablet="hidden">
          {row.product.category || "Uncategorized"}
        </:col>
        <:col :let={{_id, row}} label="GTIN">
          <span class="tabular-nums">{row.product.gtin}</span>
        </:col>
        <:col :let={{_id, row}} label="Org-wide stock">
          <span
            id={"stock-total-#{row.product.id}"}
            aria-label={"#{row.total_stock} #{uom_label(row.total_stock, row.product.uom)} in stock"}
            class={[
              "inline-flex items-center tabular-nums",
              row.total_stock == 0 && "font-medium text-red-700"
            ]}
          >
            {row.total_stock} {uom_label(row.total_stock, row.product.uom)}
          </span>
        </:col>
        <:col :let={{_id, row}} label="Batches" tablet="hidden">
          <span class="tabular-nums">{row.batch_count}</span>
        </:col>
        <:col :let={{_id, row}} label="Status" mobile="aside">
          <span class="flex flex-col items-end gap-1.5 sm:items-start">
            <.status_badge status={if row.product.is_active, do: :active, else: :inactive} />
          </span>
        </:col>
        <:action :let={{_id, row}}>
          <.button
            variant="primary"
            navigate={~p"/org/products/#{row.product.id}/batches/new"}
            class="min-h-10 gap-2 px-4 py-2 text-sm"
            id={"btn-add-stock-#{row.product.id}"}
          >
            <.icon name="hero-plus" class="size-4" /> Add stock
          </.button>
        </:action>
        <:action :let={{_id, row}}>
          <.button
            variant="ghost-edit"
            patch={~p"/org/products/#{row.product.id}/edit"}
            class="min-h-10 gap-2 px-4 py-2 text-sm"
            id={"btn-edit-#{row.product.id}"}
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-cube"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No products match your search or filters",
                else: "No products yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Products you add will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={~p"/org/products"} />
    </Layouts.org_shell>
    """
  end
end
