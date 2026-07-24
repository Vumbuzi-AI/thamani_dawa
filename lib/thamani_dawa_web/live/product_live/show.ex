defmodule ThamaniDawaWeb.ProductLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    batches = Batches.list_batches_for_product(organization_id, product.id)

    sites_by_id =
      organization_id
      |> Sites.list_sites()
      |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:product, product)
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:suppliers, Suppliers.list_suppliers(organization_id))
     |> stream(:batches, batches)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :show) do
    assign(socket, :form, nil)
  end

  defp apply_action(socket, :new_batch) do
    changeset = Batch.changeset(%Batch{}, %{gtin: socket.assigns.product.gtin})
    assign(socket, :form, to_form(changeset, as: :batch))
  end

  def handle_event("validate", %{"batch" => attrs}, socket) do
    changeset =
      %Batch{}
      |> Batch.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
  end

  def handle_event("save", %{"batch" => attrs}, socket) do
    scope = socket.assigns.current_scope
    product = socket.assigns.product

    attrs = Map.put(attrs, "product_id", product.id)

    case Batches.create_batch(scope.organization_id, attrs) do
      {:ok, batch} ->
        # A freshly-inserted batch has :site/:approver/:supplier as
        # %Ecto.Association.NotLoaded{} — fill them in from what's already
        # in memory rather than an extra query.
        supplier = Enum.find(socket.assigns.suppliers, &(&1.id == batch.supplier_id))

        batch = %{
          batch
          | site: socket.assigns.sites_by_id[batch.site_id],
            approver: nil,
            supplier: supplier
        }

        {:noreply,
         socket
         |> put_flash(:info, "Batch dispatched — awaiting receipt at site.")
         |> stream_insert(:batches, batch)
         |> push_patch(to: ~p"/org/products/#{product.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
    end
  end

  defp user_display(nil), do: "—"
  defp user_display(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_display(%{email: email}), do: email

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/products"}>
      <.header>
        {product_name(@product)}
        <:actions>
          <.button
            :if={@live_action == :show}
            variant="primary"
            patch={~p"/org/products/#{@product.id}/batches/new"}
          >
            + Dispatch batch to site
          </.button>
          <.button variant="ghost-edit" navigate={~p"/org/products/#{@product.id}/edit"}>Edit</.button>
          <.button navigate={~p"/org/products"}>Back</.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 py-4 border-b border-base-200 text-sm mb-6">
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Brand</div>
          <div class="font-medium">{@product.brand_name || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Category</div>
          <div class="font-medium">{@product.category || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Unit</div>
          <div class="font-medium">{@product.uom || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">GTIN</div>
          <div class="font-medium font-mono">{@product.gtin || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Price</div>
          <div class="font-medium">{@product.price}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Reorder level</div>
          <div class="font-medium">{@product.reorder_level || "—"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">OTC</div>
          <div class="font-medium">{if @product.is_otc, do: "Yes", else: "No"}</div>
        </div>
        <div>
          <div class="text-xs uppercase tracking-wide opacity-50 mb-1">Dangerous drug</div>
          <div class="font-medium">{if @product.is_dangerous_drug, do: "Yes", else: "No"}</div>
        </div>
      </div>

      <.modal
        :if={@live_action == :new_batch}
        id="batch-modal"
        show
        on_cancel={JS.patch(~p"/org/products/#{@product.id}")}
      >
        <h2 class="font-semibold mb-2">Dispatch batch to site</h2>
        <.form for={@form} id="batch-form" phx-submit="save" phx-change="validate">
          <div class="grid grid-cols-2 gap-x-4">
            <.input
              field={@form[:site_id]}
              type="select"
              label="Destination site"
              options={Enum.map(@sites_by_id, fn {_id, s} -> {s.name, s.id} end)}
              prompt="Choose a site"
              required
            />
            <.input field={@form[:gtin]} label="GTIN" required />
            <.input field={@form[:batch_no]} label="Batch / lot number" required />
            <.input field={@form[:serial]} label="Serial" />
            <.input field={@form[:manufacture_date]} type="date" label="Manufacture date" />
            <.input
              field={@form[:expiry_date]}
              type="date"
              label="Expiry date"
              min={Date.to_iso8601(Date.utc_today())}
              required
            />
            <.input field={@form[:quantity]} type="number" label="Quantity" required />
            <.input field={@form[:cost_per_unit]} type="number" label="Cost per unit" step="0.01" />
            <.input
              field={@form[:supplier_id]}
              type="select"
              label="Supplier"
              options={Enum.map(@suppliers, &{&1.name, &1.id})}
              prompt="No supplier"
            />
          </div>
          <div class="flex gap-2 mt-2">
            <.button variant="primary">Dispatch</.button>
            <.button patch={~p"/org/products/#{@product.id}"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.header class="mt-6">Batches</.header>
      <.table id="batches" rows={@streams.batches}>
        <:col :let={{_id, batch}} label="Site">{batch.site.name}</:col>
        <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
        <:col :let={{_id, batch}} label="Serial">{batch.serial || "—"}</:col>
        <:col :let={{_id, batch}} label="Manufacture date">{batch.manufacture_date || "—"}</:col>
        <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={{_id, batch}} label="Supplier">
          {(batch.supplier && batch.supplier.name) || "—"}
        </:col>
        <:col :let={{_id, batch}} label="Stock">{batch.remaining_quantity} / {batch.quantity}</:col>
        <:col :let={{_id, batch}} label="Received by">{user_display(batch.approver)}</:col>
        <:col :let={{_id, batch}} label="Status">
          <.status_badge status={if batch.approver_id, do: :active, else: :pending_receipt} />
        </:col>
        <:empty_state>
          <.blank_state icon="hero-archive-box" title="No batches yet">
            Batches dispatched to a site will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.org_shell>
    """
  end
end
