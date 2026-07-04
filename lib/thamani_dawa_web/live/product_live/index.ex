defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product

  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:search, "") |> assign_products()}
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
    {:noreply, assign(socket, :search, search)}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    save_product(socket, socket.assigns.live_action, attrs)
  end

  defp save_product(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Products.create_product(organization_id, attrs) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product created.")
         |> assign_products()
         |> push_patch(to: ~p"/pharmacy/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp save_product(socket, :edit, attrs) do
    case Products.update_product(socket.assigns.product, attrs) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, "Product updated.")
         |> assign_products()
         |> push_patch(to: ~p"/pharmacy/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp assign_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    assign(socket, :products, Products.list_products(organization_id))
  end

  defp filtered_products(products, search) do
    search = String.downcase(String.trim(search))

    if search == "" do
      products
    else
      Enum.filter(products, fn product ->
        [product.generic_name, product.brand_name, product.name, product.gtin, product.category]
        |> Enum.filter(& &1)
        |> Enum.any?(&String.contains?(String.downcase(&1), search))
      end)
    end
  end

  defp product_name(product), do: product.generic_name || product.name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Product catalog
        <:actions>
          <.button variant="primary" navigate={~p"/pharmacy/products/new"}>+ Add product</.button>
        </:actions>
      </.header>

      <div :if={@live_action in [:new, :edit]} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">
            {if @live_action == :new, do: "Add a product", else: "Edit product"}
          </h2>
          <form phx-submit="save">
            <.input
              field={@form[:product_type]}
              type="select"
              label="Type"
              options={Enum.map(Product.product_types(), &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose a type"
              required
            />
            <.input field={@form[:generic_name]} label="Generic name (drugs)" />
            <.input field={@form[:brand_name]} label="Brand name" />
            <.input field={@form[:name]} label="Name (non-drug items)" />
            <.input field={@form[:category]} label="Category" />
            <.input field={@form[:uom]} label="Unit of measure" />
            <.input field={@form[:gtin]} label="GTIN" />
            <.input field={@form[:is_otc]} type="checkbox" label="Over-the-counter" />
            <.input field={@form[:is_dangerous_drug]} type="checkbox" label="Dangerous drug" />
            <.input field={@form[:reorder_level]} type="number" label="Reorder level" />
            <div class="flex gap-2 mt-2">
              <.button variant="primary">Save</.button>
              <.button navigate={~p"/pharmacy/products"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <form phx-change="search" class="mb-4">
        <.input name="search" value={@search} placeholder="Search by name, GTIN, or category" />
      </form>

      <.table
        id="products"
        rows={filtered_products(@products, @search)}
        row_click={&~p"/pharmacy/products/#{&1.id}"}
      >
        <:col :let={product} label="Name">{product_name(product)}</:col>
        <:col :let={product} label="Type">{Phoenix.Naming.humanize(product.product_type)}</:col>
        <:col :let={product} label="Category">{product.category}</:col>
        <:col :let={product} label="GTIN">{product.gtin}</:col>
        <:action :let={product}>
          <.link navigate={~p"/pharmacy/products/#{product.id}/edit"} class="link">Edit</.link>
        </:action>
      </.table>
    </Layouts.app_shell>
    """
  end
end
