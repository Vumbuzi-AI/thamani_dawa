defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

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
    assign(socket, form: to_form(Product.changeset(%Product{}, %{}), as: :product), product: nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)
    assign(socket, form: to_form(Product.changeset(product, %{}), as: :product), product: product)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, product: nil)
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
          <.input field={@form[:uom]} label="Unit of measure" required />
          <.input field={@form[:gtin]} label="GTIN" required />
          <.input field={@form[:is_otc]} type="checkbox" label="Over-the-counter" />
          <.input field={@form[:is_dangerous_drug]} type="checkbox" label="Dangerous drug" />
          <.input field={@form[:reorder_level]} type="number" label="Reorder level" />
          <.input field={@form[:is_active]} type="checkbox" label="Active" />
          <div class="flex gap-2 mt-2">
            <.button variant="primary">Save</.button>
            <.button patch={~p"/org/products"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.table
        id="products"
        rows={@streams.products}
        row_click={fn {_id, product} -> JS.navigate(~p"/org/products/#{product.id}") end}
      >
        <:col :let={{_id, product}} label="Name">{product_name(product)}</:col>
        <:col :let={{_id, product}} label="Category">{product.category}</:col>
        <:col :let={{_id, product}} label="GTIN">{product.gtin}</:col>
        <:col :let={{_id, product}} label="Status">
          <.status_badge status={if product.is_active, do: :active, else: :inactive} />
        </:col>
        <:action :let={{_id, product}}>
          <.link patch={~p"/org/products/#{product.id}/edit"} class="link">Edit</.link>
        </:action>
        <:action :let={{_id, product}}>
          <.button type="button" phx-click="toggle_active" phx-value-id={product.id}>
            {if product.is_active, do: "Deactivate", else: "Reactivate"}
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
    </Layouts.org_shell>
    """
  end
end
