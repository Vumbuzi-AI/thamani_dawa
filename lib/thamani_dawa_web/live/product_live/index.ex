defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.GtinLookup
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product

  @default_filters %{category: "", is_otc: false, is_dangerous_drug: false}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> reload_products()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(form: to_form(Product.changeset(%Product{}, %{}), as: :product), product: nil)
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    socket
    |> assign(form: to_form(Product.changeset(product, %{}), as: :product), product: product)
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :form)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(form: nil, product: nil)
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_products()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      category: Map.get(filter_params, "category", ""),
      is_otc: Map.get(filter_params, "is_otc") == "true",
      is_dangerous_drug: Map.get(filter_params, "is_dangerous_drug") == "true"
    }

    {:noreply, socket |> assign(:filters, filters) |> reload_products()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "category"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | category: ""}) |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_otc"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | is_otc: false}) |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_dangerous_drug"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | is_dangerous_drug: false})
     |> reload_products()}
  end

  def handle_event("validate", %{"product" => attrs}, socket) do
    changeset =
      socket.assigns.product
      |> Kernel.||(%Product{})
      |> Product.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    save_product(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("gtin_search_change", %{"gtin_search" => gtin_search}, socket) do
    {:noreply, assign(socket, :gtin_search, gtin_search)}
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
             |> start_async(:gtin_lookup, fn -> GtinLookup.lookup(trimmed) end)}

          {:error, :invalid_gtin} ->
            {:noreply, assign(socket, :gtin_lookup, {:error, :invalid_gtin})}
        end
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

  defp save_product(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Products.create_product(organization_id, attrs) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created.")
         |> stream_insert(:products, product)
         |> push_patch(to: ~p"/org/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp save_product(socket, :edit, attrs) do
    case Products.update_product(socket.assigns.product, attrs) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product updated.")
         |> stream_insert(:products, product)
         |> push_patch(to: ~p"/org/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp reload_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    products = Products.list_products(organization_id)

    filtered =
      products
      |> filter_by_search(socket.assigns.search)
      |> filter_by_category(socket.assigns.filters.category)
      |> filter_by_flag(:is_otc, socket.assigns.filters.is_otc)
      |> filter_by_flag(:is_dangerous_drug, socket.assigns.filters.is_dangerous_drug)

    socket
    |> assign(:categories, distinct_categories(products))
    |> stream(:products, filtered, reset: true)
  end

  defp filter_by_search(products, ""), do: products

  defp filter_by_search(products, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(products, fn product ->
      [product.generic_name, product.brand_name, product.gtin, product.category]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_category(products, ""), do: products

  defp filter_by_category(products, category),
    do: Enum.filter(products, &(&1.category == category))

  defp filter_by_flag(products, _field, false), do: products
  defp filter_by_flag(products, field, true), do: Enum.filter(products, &Map.get(&1, field))

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

  defp gtin_lookup_message(_), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header icon="hero-cube">
        Product catalog
        <:subtitle>Search, filter, and manage your product catalog.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/org/products/new"}>+ Add product</.button>
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
        on_cancel={JS.patch(~p"/org/products")}
      >
        <h2 class="font-semibold mb-2">
          {if @live_action == :new, do: "Add a product", else: "Edit product"}
        </h2>

        <div :if={@gtin_step == :scan} id="gtin-scan-step">
          <p class="text-sm mb-2" style="color: var(--thamani-pewter);">
            Scan or enter the product's GTIN to prefill what it can find, or continue without
            one to enter everything manually.
          </p>
          <form
            id="gtin-scan-form"
            phx-submit="scan_gtin"
            phx-change="gtin_search_change"
            class="flex gap-2"
          >
            <input
              type="text"
              name="gtin_search"
              value={@gtin_search}
              placeholder="Scan or type a GTIN"
              class="thamani-input flex-1"
              autofocus
            />
            <.button type="submit" variant="primary" phx-disable-with="Looking up...">
              Continue
            </.button>
          </form>
          <p
            :if={@gtin_lookup == {:error, :invalid_gtin}}
            class="mt-2 text-sm"
            style="color: #C21F17;"
          >
            is not a valid GTIN
          </p>
          <div class="flex justify-end mt-4">
            <.button type="button" patch={~p"/org/products"}>Cancel</.button>
          </div>
        </div>

        <div :if={@gtin_step == :form}>
          <div
            :if={@live_action == :new and @gtin_lookup != :idle}
            class="mb-4 rounded-box border border-thamani-stone p-3"
          >
            <p :if={@gtin_lookup == :searching} class="text-sm flex items-center gap-1">
              <.icon name="hero-arrow-path" class="size-3 motion-safe:animate-spin" /> Looking up...
            </p>
            <% message = gtin_lookup_message(@gtin_lookup) %>
            <p
              :if={message}
              class="text-sm"
              style={
                if elem(message, 0) == :info,
                  do: "color: var(--thamani-forest);",
                  else: "color: var(--thamani-pewter);"
              }
            >
              {elem(message, 1)}
            </p>
          </div>

          <.form for={@form} id="product-form" phx-submit="save" phx-change="validate">
            <.input field={@form[:price]} type="number" label="Price" min="0" required />

            <p class="text-xs mb-1" style="color: var(--thamani-pewter);">
              Name <span style="color: #C21F17;">*</span>
              — at least one of generic or brand name is required
            </p>
            <div class="grid grid-cols-2 gap-x-4">
              <.input field={@form[:generic_name]} label="Generic name" />
              <.input field={@form[:brand_name]} label="Brand name" />
            </div>
            <.input field={@form[:category]} label="Category" />
            <.input field={@form[:manufacturer]} label="Manufacturer" />
            <.input field={@form[:uom]} label="Unit of measure" required />
            <.input field={@form[:gtin]} label="GTIN" required />
            <.input field={@form[:is_otc]} type="checkbox" label="Over-the-counter" />
            <.input field={@form[:is_dangerous_drug]} type="checkbox" label="Dangerous drug" />
            <.input field={@form[:reorder_level]} type="number" label="Reorder level" />
            <div class="flex gap-2 mt-2">
              <.button variant="primary">Save</.button>
              <.button patch={~p"/org/products"}>Cancel</.button>
            </div>
          </.form>
        </div>
      </.modal>

      <.table
        id="products"
        rows={@streams.products}
        row_click={fn {_id, product} -> JS.navigate(~p"/org/products/#{product.id}") end}
      >
        <:col :let={{_id, product}} label="Name">{product_name(product)}</:col>
        <:col :let={{_id, product}} label="Category">{product.category}</:col>
        <:col :let={{_id, product}} label="GTIN">{product.gtin}</:col>
        <:action :let={{_id, product}}>
          <.link patch={~p"/org/products/#{product.id}/edit"} class="link">Edit</.link>
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
    </Layouts.org_shell>
    """
  end
end
