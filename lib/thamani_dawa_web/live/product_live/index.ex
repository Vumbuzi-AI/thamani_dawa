defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:sites, Sites.list_sites(organization_id))
     |> stream(:products, Products.list_products(organization_id))}
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
    organization_id = socket.assigns.current_scope.organization_id

    products = Products.list_products(organization_id)
    filtered = filtered_products(products, search)

    {:noreply,
     socket
     |> assign(:search, search)
     |> stream(:products, filtered, reset: true)}
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

  defp filtered_products(products, search) do
    search = String.downcase(String.trim(search))

    if search == "" do
      products
    else
      Enum.filter(products, fn product ->
        [product.generic_name, product.brand_name, product.gtin, product.category]
        |> Enum.filter(& &1)
        |> Enum.any?(&String.contains?(String.downcase(&1), search))
      end)
    end
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header>
        Product catalog
        <:actions>
          <.button variant="primary" patch={~p"/org/products/new"}>+ Add product</.button>
        </:actions>
      </.header>

      <%= if @live_action in [:new, :edit] do %>
        <div class="card bg-base-200 mb-4">
          <div class="card-body">
            <h2 class="font-semibold mb-2">
              {if @live_action == :new, do: "Add a product", else: "Edit product"}
            </h2>
            <.form for={@form} id="product-form" phx-submit="save" phx-change="validate">
              <.input
                field={@form[:site_id]}
                type="select"
                label="Site"
                options={Enum.map(@sites, &{&1.name, &1.id})}
                prompt="Choose a site"
                required
              />
              <.input field={@form[:price]} type="number" label="Price" required />
              <.input field={@form[:generic_name]} label="Generic name" />
              <.input field={@form[:brand_name]} label="Brand name" />
              <.input field={@form[:category]} label="Category" />
              <.input field={@form[:uom]} label="Unit of measure" />
              <.input field={@form[:gtin]} label="GTIN" />
              <.input field={@form[:is_otc]} type="checkbox" label="Over-the-counter" />
              <.input field={@form[:is_dangerous_drug]} type="checkbox" label="Dangerous drug" />
              <.input field={@form[:reorder_level]} type="number" label="Reorder level" />
              <div class="flex gap-2 mt-2">
                <.button variant="primary">Save</.button>
                <.button patch={~p"/org/products"}>Cancel</.button>
              </div>
            </.form>
          </div>
        </div>
      <% end %>

      <form phx-change="search" class="mb-4" id="search-form">
        <.input name="search" value={@search} placeholder="Search by name, GTIN, or category" />
      </form>

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
      </.table>
    </Layouts.org_shell>
    """
  end
end
