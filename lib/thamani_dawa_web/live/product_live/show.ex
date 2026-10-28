defmodule ThamaniDawaWeb.ProductLive.Show do
  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.BatchLabelComponent

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    batches = Batches.list_batches_for_product(organization_id, product.id)

    undispatched_batches =
      Batches.list_undispatched_batches_for_product(organization_id, product.id)

    sites_by_id =
      organization_id
      |> Sites.list_sites()
      |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:product, product)
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:suppliers, Suppliers.list_active_suppliers(organization_id))
     |> assign(:selected_batch, nil)
     |> assign(:dispatch_batch, nil)
     |> assign(:dispatch_form, nil)
     |> assign(:stock_tab, "warehouse")
     |> stream(:batches, batches)
     |> stream(:undispatched_batches, undispatched_batches)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket |> assign(:form, nil) |> assign(:dispatch_batch, nil) |> assign(:dispatch_form, nil)
  end

  defp apply_action(socket, :new_batch, _params) do
    changeset = Batch.org_intake_changeset(%Batch{}, %{gtin: socket.assigns.product.gtin})
    assign(socket, :form, to_form(changeset, as: :batch))
  end

  defp apply_action(socket, :dispatch_batch, %{"batch_id" => batch_id}) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, String.to_integer(batch_id))

    socket
    |> assign(:dispatch_batch, batch)
    |> assign(
      :dispatch_form,
      to_form(%{"site_id" => nil, "quantity" => batch.remaining_quantity}, as: :dispatch)
    )
  end

  def handle_event("switch_stock_tab", %{"tab" => tab}, socket)
      when tab in ~w(warehouse sites) do
    {:noreply, assign(socket, :stock_tab, tab)}
  end

  def handle_event("switch_stock_tab", _params, socket), do: {:noreply, socket}

  def handle_event("validate", %{"batch" => attrs}, socket) do
    changeset =
      %Batch{}
      |> Batch.org_intake_changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
  end

  def handle_event("save", %{"batch" => attrs}, socket) do
    scope = socket.assigns.current_scope
    product = socket.assigns.product

    attrs = Map.put(attrs, "product_id", product.id)

    case Batches.receive_into_org_stock(scope.organization_id, attrs) do
      {:ok, batch} ->
        # A freshly-inserted batch has :product/:supplier as
        # %Ecto.Association.NotLoaded{} — fill them in from what's already
        # in memory rather than an extra query.
        supplier = Enum.find(socket.assigns.suppliers, &(&1.id == batch.supplier_id))
        batch = %{batch | product: product, supplier: supplier}

        {:noreply,
         socket
         |> put_flash(:info, "Batch recorded as stock — dispatch it to a site when ready.")
         |> stream_insert(:undispatched_batches, batch)
         |> push_patch(to: ~p"/org/products/#{product.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
    end
  end

  def handle_event("dispatch", %{"dispatch" => dispatch_params}, socket) do
    org_batch = socket.assigns.dispatch_batch
    product = socket.assigns.product

    with {site_id, ""} <- Integer.parse(dispatch_params["site_id"] || ""),
         {quantity, ""} <- Integer.parse(dispatch_params["quantity"] || "") do
      do_dispatch(socket, org_batch, product, site_id, quantity)
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Choose a destination site and quantity.")}
    end
  end

  def handle_event("show_datamatrix", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = Batches.get_batch_with_details!(organization_id, String.to_integer(id))
    {:noreply, assign(socket, :selected_batch, batch)}
  end

  def handle_event("close_datamatrix", _params, socket) do
    {:noreply, assign(socket, :selected_batch, nil)}
  end

  def handle_event("toggle_active", _params, socket) do
    product = socket.assigns.product

    case Products.update_product(product, %{is_active: !product.is_active}) do
      {:ok, updated_product} ->
        status_msg =
          if updated_product.is_active, do: "Product reactivated.", else: "Product deactivated."

        {:noreply,
         socket
         |> assign(:product, updated_product)
         |> put_flash(:info, status_msg)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update product.")}
    end
  end

  defp do_dispatch(socket, org_batch, product, site_id, quantity) do
    case Batches.dispatch_to_site(org_batch, site_id, quantity) do
      {:ok, dispatched} ->
        dispatch_succeeded(socket, org_batch, product, dispatched)

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, dispatch_error_message(reason))}
    end
  end

  defp dispatch_succeeded(socket, org_batch, product, dispatched) do
    # A freshly-inserted batch has :site/:approver/:supplier as
    # %Ecto.Association.NotLoaded{} — fill them in from what's already
    # in memory rather than an extra query.
    supplier = Enum.find(socket.assigns.suppliers, &(&1.id == dispatched.supplier_id))

    dispatched = %{
      dispatched
      | product: product,
        site: socket.assigns.sites_by_id[dispatched.site_id],
        approver: nil,
        supplier: supplier
    }

    socket =
      socket
      |> put_flash(:info, "Batch dispatched — awaiting receipt at site.")
      |> stream_insert(:batches, dispatched)
      |> assign(:selected_batch, dispatched)
      |> refresh_undispatched_batch(org_batch, product)

    {:noreply, push_patch(socket, to: ~p"/org/products/#{product.id}")}
  end

  defp refresh_undispatched_batch(socket, org_batch, product) do
    remaining_batch =
      socket.assigns.current_scope.organization_id
      |> Batches.list_undispatched_batches_for_product(product.id)
      |> Enum.find(&(&1.id == org_batch.id))

    if remaining_batch do
      stream_insert(socket, :undispatched_batches, remaining_batch)
    else
      stream_delete(socket, :undispatched_batches, org_batch)
    end
  end

  defp dispatch_error_message(:already_dispatched),
    do: "That batch has already been dispatched."

  defp dispatch_error_message(:nothing_to_dispatch),
    do: "That batch has no remaining quantity to dispatch."

  defp dispatch_error_message(:invalid_dispatch_quantity),
    do: "Enter a dispatch quantity greater than zero."

  defp dispatch_error_message(:insufficient_quantity),
    do: "The dispatch quantity exceeds the warehouse stock."

  defp dispatch_error_message(%Ecto.Changeset{} = changeset),
    do: "Couldn't dispatch that batch: #{changeset_error_summary(changeset)}"

  defp dispatch_error_message(_reason), do: "Couldn't dispatch that batch."

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp user_display(nil), do: "—"
  defp user_display(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_display(%{email: email}), do: email

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/products"}
      back={~p"/org/products"}
    >
      <.header icon="hero-cube">
        {product_name(@product)}
        <:actions>
          <div class="grid w-full grid-cols-3 gap-2 xl:w-auto">
            <.button
              :if={@live_action == :show}
              variant="primary"
              patch={~p"/org/products/#{@product.id}/batches/new"}
              id="btn-add-product-stock"
              class="min-w-0 gap-1.5 px-3"
            >
              <.icon name="hero-plus" class="size-4" /> Add stock
            </.button>
            <.button
              variant="ghost-edit"
              navigate={~p"/org/products/#{@product.id}/edit?return_to=show"}
              id="btn-edit-product"
              class="min-w-0 gap-1.5 px-3"
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
            <.button
              type="button"
              phx-click="toggle_active"
              variant={if @product.is_active, do: "destructive", else: "ghost"}
              id="btn-toggle-active-product"
              class="min-w-0 px-3"
            >
              {if @product.is_active, do: "Deactivate", else: "Reactivate"}
            </.button>
          </div>
        </:actions>
      </.header>

      <dl
        id="product-details"
        class="mb-6 grid grid-cols-2 gap-x-6 gap-y-5 rounded-2xl border border-thamani-stone bg-thamani-snow p-4 text-sm shadow-[0_1px_3px_rgba(28,58,19,0.06)] sm:grid-cols-4 sm:p-5"
      >
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Status</dt>
          <dd><.status_badge status={if @product.is_active, do: :active, else: :inactive} /></dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Brand</dt>
          <dd class="font-medium text-thamani-forest">{@product.brand_name || "—"}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Category</dt>
          <dd class="font-medium text-thamani-forest">{@product.category || "—"}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Manufacturer</dt>
          <dd class="font-medium text-thamani-forest">{@product.manufacturer || "—"}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Unit</dt>
          <dd class="font-medium text-thamani-forest">{@product.uom || "—"}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">GTIN</dt>
          <dd class="truncate font-mono font-medium text-thamani-forest">
            {@product.gtin || "—"}
          </dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Price</dt>
          <dd class="font-medium text-thamani-forest">{@product.price}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Reorder level</dt>
          <dd class="font-medium text-thamani-forest">{@product.reorder_level || "—"}</dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">OTC</dt>
          <dd class="font-medium text-thamani-forest">
            {if @product.is_otc, do: "Yes", else: "No"}
          </dd>
        </div>
        <div>
          <dt class="mb-1 text-sm text-thamani-pewter">Dangerous drug</dt>
          <dd class="font-medium text-thamani-forest">
            {if @product.is_dangerous_drug, do: "Yes", else: "No"}
          </dd>
        </div>
      </dl>

      <.modal
        :if={@live_action == :new_batch}
        id="batch-modal"
        show
        on_cancel={JS.patch(~p"/org/products/#{@product.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Add stock
        </h2>
        <.form for={@form} id="batch-form" phx-submit="save" phx-change="validate">
          <div class="grid grid-cols-2 gap-x-4">
            <.input field={@form[:gtin]} label="GTIN" required />
            <.input field={@form[:batch_no]} label="Batch / lot number" required />
            <.input field={@form[:serial]} label="Serial" />
            <.date_picker
              field={@form[:manufacture_date]}
              label="Manufacture date"
              placeholder="Choose date"
            />
            <.date_picker
              field={@form[:expiry_date]}
              label="Expiry date"
              placeholder="Choose expiry date"
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
          <div class="pt-4">
            <.button variant="primary" class="w-full">Add to stock</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :dispatch_batch and not is_nil(@dispatch_batch)}
        id="dispatch-batch-modal"
        show
        on_cancel={JS.patch(~p"/org/products/#{@product.id}")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Dispatch batch to site
        </h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          Batch / lot <span class="font-mono">{@dispatch_batch.batch_no}</span>
          · {@dispatch_batch.remaining_quantity} units available.
        </p>
        <.form for={@dispatch_form} id="dispatch-batch-form" phx-submit="dispatch">
          <.input
            field={@dispatch_form[:quantity]}
            type="number"
            label="Quantity to dispatch"
            min="1"
            max={@dispatch_batch.remaining_quantity}
            required
          />
          <.input
            field={@dispatch_form[:site_id]}
            type="select"
            label="Destination site"
            options={Enum.map(@sites_by_id, fn {_id, s} -> {s.name, s.id} end)}
            prompt="Choose a site"
            required
          />
          <div class="pt-4">
            <.button variant="primary" class="w-full">Dispatch batch</.button>
          </div>
        </.form>
      </.modal>

      <.batch_label_modal
        :if={@selected_batch}
        batch={@selected_batch}
        on_close={JS.push("close_datamatrix")}
      />

      <.tab_group variant="compact" class="mb-5 w-full max-w-none sm:max-w-md [&>button]:flex-1">
        <:tab
          id="warehouse-stock-tab"
          active={@stock_tab == "warehouse"}
          phx_click="switch_stock_tab"
          phx_value_tab="warehouse"
          controls="warehouse-stock-panel"
        >
          Warehouse stock
        </:tab>
        <:tab
          id="sites-stock-tab"
          active={@stock_tab == "sites"}
          phx_click="switch_stock_tab"
          phx_value_tab="sites"
          controls="sites-stock-panel"
        >
          Stock at sites
        </:tab>
      </.tab_group>

      <div
        id="warehouse-stock-panel"
        role="tabpanel"
        aria-labelledby="warehouse-stock-tab"
        class={@stock_tab != "warehouse" && "hidden"}
      >
        <p class="mb-4 text-sm text-thamani-pewter">
          Stock held in the organization warehouse. Dispatch a batch when it is ready to move to a site.
        </p>
        <section
          id="undispatched-batches"
          phx-update="stream"
          aria-label="Warehouse batches"
          class="grid gap-3 lg:hidden"
        >
          <div id="undispatched-batches-empty" class="hidden only:block lg:col-span-2">
            <.blank_state icon="hero-archive-box" title="No organization warehouse stock">
              Stock added here remains in the warehouse until you dispatch it to a site.
            </.blank_state>
          </div>

          <article
            :for={{id, batch} <- @streams.undispatched_batches}
            id={id}
            class="group overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow shadow-[0_1px_3px_rgba(28,58,19,0.08)] transition-all duration-200 hover:-translate-y-0.5 hover:border-thamani-forest/20 hover:shadow-[0_10px_30px_rgba(28,58,19,0.08)]"
          >
            <div class="p-4 sm:p-5">
              <div class="flex items-start gap-3.5">
                <div class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-thamani-canvas text-thamani-forest ring-1 ring-thamani-stone transition-colors duration-200 group-hover:bg-thamani-lime/40">
                  <.icon name="hero-archive-box" class="size-5" />
                </div>
                <div class="min-w-0 flex-1 pt-0.5">
                  <p class="text-sm text-thamani-pewter">Batch / lot</p>
                  <h3 class="mt-0.5 truncate text-base font-semibold text-thamani-forest">
                    {batch.batch_no}
                  </h3>
                </div>
                <span class="shrink-0 rounded-full bg-thamani-lime px-3 py-1 text-sm font-semibold tabular-nums text-thamani-forest">
                  {batch.remaining_quantity} units
                </span>
              </div>

              <dl class="mt-4 grid grid-cols-2 border-t border-thamani-stone/80 pt-4">
                <div class="min-w-0 pr-4">
                  <dt class="text-sm text-thamani-pewter">Expiry</dt>
                  <dd class="mt-1 text-sm font-medium tabular-nums text-slate-900">
                    {batch.expiry_date}
                  </dd>
                </div>
                <div class="min-w-0 border-l border-thamani-stone/80 pl-4">
                  <dt class="text-sm text-thamani-pewter">Supplier</dt>
                  <dd class="mt-1 truncate text-sm font-medium text-slate-900">
                    {(batch.supplier && batch.supplier.name) || "—"}
                  </dd>
                </div>
              </dl>
            </div>

            <div class="border-t border-thamani-stone bg-thamani-canvas/60 p-3 sm:px-5">
              <.button
                variant="ghost-edit"
                patch={~p"/org/products/#{@product.id}/batches/#{batch.id}/dispatch"}
                id={"btn-dispatch-batch-#{batch.id}"}
                class="w-full gap-2 px-4 py-2 text-sm"
              >
                <.icon name="hero-paper-airplane" class="size-4" /> Dispatch to site
              </.button>
            </div>
          </article>
        </section>

        <div class="hidden lg:block">
          <.table
            id="warehouse-batches-table"
            rows={@streams.undispatched_batches}
            row_id={fn {id, _batch} -> "warehouse-table-#{id}" end}
          >
            <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
            <:col :let={{_id, batch}} label="Available stock">
              {batch.remaining_quantity} units
            </:col>
            <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
            <:col :let={{_id, batch}} label="Supplier">
              {(batch.supplier && batch.supplier.name) || "—"}
            </:col>
            <:action :let={{_id, batch}}>
              <.button
                variant="ghost-edit"
                patch={~p"/org/products/#{@product.id}/batches/#{batch.id}/dispatch"}
                id={"btn-dispatch-batch-table-#{batch.id}"}
              >
                <.icon name="hero-paper-airplane" class="size-4" /> Dispatch to site
              </.button>
            </:action>
            <:empty_state>
              <.blank_state icon="hero-archive-box" title="No organization warehouse stock">
                Stock added here remains in the warehouse until you dispatch it to a site.
              </.blank_state>
            </:empty_state>
          </.table>
        </div>
      </div>

      <div
        id="sites-stock-panel"
        role="tabpanel"
        aria-labelledby="sites-stock-tab"
        class={@stock_tab != "sites" && "hidden"}
      >
        <p class="mb-4 text-sm text-thamani-pewter">
          These batches are already assigned to a site, including stock received before centralized
          stock tracking was introduced.
        </p>
        <.table
          id="batches"
          rows={@streams.batches}
          row_click={fn {_id, batch} -> JS.navigate(~p"/org/batches/#{batch.id}") end}
        >
          <:col :let={{_id, batch}} label="Site">{batch.site.name}</:col>
          <:col :let={{_id, batch}} label="Batch details">
            <div class="font-medium text-slate-900">{batch.batch_no}</div>
            <div
              :if={batch.serial || batch.manufacture_date}
              class="mt-1 text-xs font-normal text-thamani-pewter"
            >
              <span :if={batch.serial}>Serial {batch.serial}</span>
              <span :if={batch.serial && batch.manufacture_date}> · </span>
              <span :if={batch.manufacture_date}>Mfd {batch.manufacture_date}</span>
            </div>
          </:col>
          <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={{_id, batch}} label="Stock">{batch.remaining_quantity} / {batch.quantity}</:col>
          <:col :let={{_id, batch}} label="Received by" mobile="hidden">
            {user_display(batch.approver)}
          </:col>
          <:col :let={{_id, batch}} label="Status" mobile="aside">
            <.status_badge status={if batch.approver_id, do: :active, else: :pending_receipt} />
          </:col>
          <:action :let={{_id, batch}}>
            <.button
              type="button"
              variant="ghost-edit"
              phx-click="show_datamatrix"
              phx-value-id={batch.id}
              phx-stop-propagation
              id={"btn-datamatrix-#{batch.id}"}
            >
              <.icon name="hero-qr-code" class="w-4 h-4 mr-1" /> Print Label
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-archive-box" title="No batches yet">
              Batches dispatched to a site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>
    </Layouts.org_shell>
    """
  end
end
