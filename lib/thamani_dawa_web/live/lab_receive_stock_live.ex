defmodule ThamaniDawaWeb.LabReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    sites = Sites.list_sites(organization_id)
    lab_sites = Enum.filter(sites, &Site.lab?/1)
    lab_site_ids = MapSet.new(lab_sites, & &1.id)
    standalone_lab_site = if length(sites) == 1 and Site.lab?(hd(sites)), do: hd(sites)
    site_id = scope.current_site_id || (standalone_lab_site && standalone_lab_site.id)

    pending_batches =
      if site_id do
        Batches.list_pending_batches_for_site(organization_id, site_id)
      else
        organization_id
        |> Batches.list_pending_batches()
        |> Enum.filter(&MapSet.member?(lab_site_ids, &1.site_id))
      end

    usable_batches =
      if site_id do
        Batches.list_active_batches_for_site(organization_id, site_id)
      else
        []
      end

    products_by_id =
      organization_id
      |> Products.list_products()
      |> Map.new(&{&1.id, &1})

    lab_products =
      products_by_id
      |> Map.values()
      |> Enum.filter(&(&1.inventory_type == :lab_consumable and &1.is_active))
      |> Enum.sort_by(&String.downcase(&1.generic_name || &1.brand_name || ""))

    suppliers = Suppliers.list_active_suppliers(organization_id)
    suppliers_by_id = organization_id |> Suppliers.list_suppliers() |> Map.new(&{&1.id, &1})
    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:lab_products, lab_products)
     |> assign(:lab_products_by_id, Map.new(lab_products, &{&1.id, &1}))
     |> assign(:suppliers, suppliers)
     |> assign(:suppliers_by_id, suppliers_by_id)
     |> assign(:lab_site_ids, MapSet.new(lab_sites, & &1.id))
     |> assign(:lab_sites, lab_sites)
     |> assign(:site_id, site_id)
     |> assign(:direct_receipt_site, standalone_lab_site)
     |> assign(:direct_receipt?, not is_nil(standalone_lab_site))
     |> assign(:site_locked, not is_nil(site_id))
     |> assign(:form, to_form(Batch.changeset(%Batch{}, initial_attrs), as: :batch))
     |> assign(:selected_batch, nil)
     |> assign(:receive_batch, nil)
     |> assign(:receive_form, nil)
     |> assign(:usable_batches, usable_batches)
     |> stream(:pending_batches, pending_batches)}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    apply_action(socket, socket.assigns.live_action, id)
  end

  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, receive_batch: nil, receive_form: nil)}
  end

  defp apply_action(socket, :receive, batch_id) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, String.to_integer(batch_id))

    {:noreply,
     socket
     |> assign(:receive_batch, batch)
     |> assign(:receive_form, to_form(%{"quantity" => batch.quantity}, as: :receive))}
  end

  defp apply_action(socket, _action, _id) do
    {:noreply, assign(socket, receive_batch: nil, receive_form: nil)}
  end

  def handle_event("view_batch", %{"id" => id}, socket) do
    batch =
      Batches.get_batch_with_details!(
        socket.assigns.current_scope.organization_id,
        String.to_integer(id)
      )

    {:noreply, assign(socket, :selected_batch, batch)}
  end

  def handle_event("cancel_view", _params, socket) do
    {:noreply, assign(socket, :selected_batch, nil)}
  end

  def handle_event("validate_direct_receipt", %{"batch" => attrs}, socket) do
    changeset =
      direct_receipt_changeset(attrs, socket.assigns.lab_products_by_id, socket.assigns.site_id)
      |> Ecto.Changeset.validate_number(:quantity, greater_than: 0)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
  end

  def handle_event("save_direct_receipt", %{"batch" => attrs}, socket) do
    scope = socket.assigns.current_scope
    site = socket.assigns.direct_receipt_site

    if socket.assigns.direct_receipt? and direct_receipt_authorized?(scope, site) do
      changeset =
        direct_receipt_changeset(attrs, socket.assigns.lab_products_by_id, site.id)
        |> Ecto.Changeset.validate_number(:quantity, greater_than: 0)

      if changeset.valid? do
        batch_attrs = direct_receipt_batch_attrs(changeset)

        case Batches.receive_directly_at_site(
               scope.organization_id,
               site.id,
               scope.user.id,
               batch_attrs
             ) do
          {:ok, _batch} ->
            usable_batches =
              Batches.list_active_batches_for_site(scope.organization_id, site.id)

            {:noreply,
             socket
             |> put_flash(:info, "Lab stock received directly at #{site.name}.")
             |> assign(:form, to_form(Batch.changeset(%Batch{}, %{site_id: site.id}), as: :batch))
             |> assign(:usable_batches, usable_batches)}

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
        end
      else
        {:noreply, assign(socket, :form, to_form(%{changeset | action: :insert}, as: :batch))}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Direct receipt is only available at a standalone lab site.")}
    end
  end

  def handle_event("receive_batch", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, String.to_integer(id))

    if not Scope.admin?(scope) and scope.current_site_id != batch.site_id do
      {:noreply, put_flash(socket, :error, "Not authorized to receive this batch.")}
    else
      do_receive_batch(socket, scope, batch)
    end
  end

  def handle_event("receive", _params, socket)
      when is_nil(socket.assigns.receive_batch) do
    {:noreply, put_flash(socket, :error, "No batch selected.")}
  end

  def handle_event("receive", _params, socket) do
    scope = socket.assigns.current_scope
    batch = socket.assigns.receive_batch

    if not Scope.admin?(scope) and scope.current_site_id != batch.site_id do
      {:noreply, put_flash(socket, :error, "Not authorized to receive this batch.")}
    else
      do_receive_batch(socket, scope, batch)
    end
  end

  def handle_event(
        "record_usage",
        %{"batch_id" => batch_id, "quantity" => quantity} = attrs,
        socket
      ) do
    scope = socket.assigns.current_scope

    opts = [
      lab_order_id:
        blank_to_nil(attrs["lab_order_id"]) && String.to_integer(attrs["lab_order_id"]),
      purpose: blank_to_nil(attrs["purpose"])
    ]

    case LabOrders.record_consumable_usage(
           scope.organization_id,
           String.to_integer(batch_id),
           scope.user.id,
           String.to_integer(quantity),
           opts
         ) do
      {:ok, _usage} ->
        usable_batches =
          if socket.assigns.site_id do
            Batches.list_active_batches_for_site(scope.organization_id, socket.assigns.site_id)
          else
            []
          end

        {:noreply,
         socket
         |> put_flash(:info, "Usage recorded.")
         |> assign(:usable_batches, usable_batches)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record usage: #{inspect(reason)}")}
    end
  end

  defp do_receive_batch(socket, scope, batch) do
    case Batches.receive_batch(batch, scope.user.id) do
      {:ok, _received} ->
        usable_batches =
          if socket.assigns.site_id do
            Batches.list_active_batches_for_site(scope.organization_id, socket.assigns.site_id)
          else
            []
          end

        {:noreply,
         socket
         |> put_flash(:info, "Batch received and marked active.")
         |> assign(:selected_batch, nil)
         |> assign(:receive_batch, nil)
         |> assign(:receive_form, nil)
         |> reload_pending_batches(scope)
         |> assign(:usable_batches, usable_batches)
         |> push_patch(to: ~p"/lab/receive-stock")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not receive batch.")}
    end
  end

  defp reload_pending_batches(socket, scope) do
    org_id = scope.organization_id
    site_id = socket.assigns.site_id

    pending =
      if site_id do
        Batches.list_pending_batches_for_site(org_id, site_id)
      else
        lab_site_ids = MapSet.new(socket.assigns.lab_sites, & &1.id)

        org_id
        |> Batches.list_pending_batches()
        |> Enum.filter(&MapSet.member?(lab_site_ids, &1.site_id))
      end

    stream(socket, :pending_batches, pending, reset: true)
  end

  defp direct_receipt_authorized?(scope, site) do
    Scope.admin?(scope) or scope.current_site_id == site.id
  end

  defp direct_receipt_changeset(attrs, products_by_id, site_id) do
    attrs = Map.put(attrs, "site_id", site_id)

    case parse_optional_int(attrs["product_id"]) do
      product_id when is_integer(product_id) ->
        case Map.get(products_by_id, product_id) do
          %{inventory_type: :lab_consumable, is_active: true, gtin: gtin} ->
            attrs
            |> Map.put("gtin", gtin)
            |> then(&Batch.changeset(%Batch{}, &1))

          _ ->
            Batch.changeset(%Batch{}, attrs)
            |> Ecto.Changeset.add_error(:product_id, "must be an active lab consumable")
        end

      _ ->
        Batch.changeset(%Batch{}, attrs)
        |> Ecto.Changeset.add_error(:product_id, "choose a lab consumable")
    end
  end

  defp direct_receipt_batch_attrs(changeset) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take([
      :product_id,
      :gtin,
      :batch_no,
      :serial,
      :manufacturer,
      :manufacture_date,
      :expiry_date,
      :quantity,
      :cost_per_unit,
      :supplier_id
    ])
  end

  defp parse_optional_int(value) when is_integer(value), do: value

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_optional_int(_value), do: nil

  defp product_name(product) do
    case {product.generic_name, product.brand_name} do
      {generic_name, brand_name} when is_binary(generic_name) and is_binary(brand_name) ->
        "#{generic_name} — #{brand_name}"

      {generic_name, _brand_name} when is_binary(generic_name) ->
        generic_name

      {_generic_name, brand_name} when is_binary(brand_name) ->
        brand_name
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp product_display(batch, products_by_id) do
    case Map.get(products_by_id, batch.product_id) do
      nil -> "(unknown product)"
      p -> p.generic_name || p.brand_name || "(unnamed)"
    end
  end

  defp supplier_display(batch, suppliers_by_id) do
    case Map.get(suppliers_by_id, batch.supplier_id) do
      nil -> "—"
      supplier -> supplier.name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/lab/receive-stock"}
    >
      <.header icon="hero-arrow-down-tray">
        Receive stock / consumables
        <:subtitle>
          {if @direct_receipt?,
            do: "Record lab consumables directly at #{@direct_receipt_site.name}.",
            else: "Confirm dispatched batches at your site by reviewing the delivery."}
        </:subtitle>
      </.header>

      <section
        :if={@direct_receipt?}
        id="direct-lab-stock-receipt"
        class="rounded-2xl ff-surface-card p-5 sm:p-6"
      >
        <div class="mb-5">
          <h2 class="text-lg font-semibold text-thamani-forest">Receive stock directly</h2>
          <p class="mt-1 max-w-3xl text-sm leading-6 text-thamani-pewter">
            This organization has one lab-capable site. Record the delivery straight into {@direct_receipt_site.name}; no warehouse dispatch or second receipt step is needed.
          </p>
        </div>

        <p
          :if={@lab_products == []}
          class="rounded-xl bg-thamani-canvas px-4 py-3 text-sm text-thamani-pewter"
        >
          Create an active lab consumable product before receiving stock.
        </p>

        <.form
          :if={@lab_products != []}
          for={@form}
          id="direct-lab-stock-form"
          phx-change="validate_direct_receipt"
          phx-submit="save_direct_receipt"
          class="grid gap-4 sm:grid-cols-2 xl:grid-cols-3"
        >
          <.input
            field={@form[:product_id]}
            id="direct-lab-product-id"
            type="select"
            label="Lab consumable"
            options={Enum.map(@lab_products, &{product_name(&1), &1.id})}
            prompt="Choose product"
            required
          />
          <.input field={@form[:gtin]} type="hidden" />
          <.input
            field={@form[:batch_no]}
            id="direct-lab-batch-no"
            label="Batch / lot number"
            required
          />
          <.input
            field={@form[:expiry_date]}
            id="direct-lab-expiry-date"
            type="date"
            label="Expiry date"
            required
          />
          <.input
            field={@form[:quantity]}
            id="direct-lab-quantity"
            type="number"
            label="Quantity received"
            min="1"
            required
          />
          <.input
            field={@form[:supplier_id]}
            id="direct-lab-supplier-id"
            type="select"
            label="Supplier (optional)"
            options={Enum.map(@suppliers, &{&1.name, &1.id})}
            prompt="Choose supplier"
          />
          <.input field={@form[:serial]} id="direct-lab-serial" label="Serial number (optional)" />
          <.input
            field={@form[:manufacture_date]}
            id="direct-lab-manufacture-date"
            type="date"
            label="Manufacture date (optional)"
          />
          <.input
            field={@form[:manufacturer]}
            id="direct-lab-manufacturer"
            label="Manufacturer (optional)"
          />
          <.input
            field={@form[:cost_per_unit]}
            id="direct-lab-cost-per-unit"
            type="number"
            label="Cost per unit (optional)"
            min="0"
            step="0.01"
          />
          <div class="flex items-end sm:col-span-2 xl:col-span-3">
            <.button
              id="direct-lab-stock-submit"
              type="submit"
              variant="primary"
              phx-disable-with="Receiving stock…"
              class="w-full sm:w-auto"
            >
              Receive stock at site
            </.button>
          </div>
        </.form>
      </section>

      <.modal
        :if={@live_action == :receive and not is_nil(@receive_batch)}
        id="receive-batch-modal"
        show
        on_cancel={JS.patch(~p"/lab/receive-stock")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">Receive batch</h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          Confirm receipt of this pending delivery.
        </p>
        <dl class="mb-4 grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Product</dt>
            <dd class="mt-0.5 font-medium text-slate-900">
              {product_display(@receive_batch, @products_by_id)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Batch / lot
            </dt>
            <dd class="mt-0.5 font-mono">{@receive_batch.batch_no}</dd>
          </div>
          <div :if={@receive_batch.serial}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Serial</dt>
            <dd class="mt-0.5 font-mono">{@receive_batch.serial}</dd>
          </div>
          <div :if={@receive_batch.manufacture_date}>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Manufacture date
            </dt>
            <dd class="mt-0.5">{@receive_batch.manufacture_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Expiry</dt>
            <dd class="mt-0.5">{@receive_batch.expiry_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">Quantity</dt>
            <dd class="mt-0.5 tabular-nums">{@receive_batch.quantity}</dd>
          </div>
        </dl>
        <.form
          for={@receive_form}
          id="receive-batch-form"
          phx-submit="receive"
        >
          <.button variant="primary" phx-disable-with="Receiving…" class="w-full">Approve receipt</.button>
        </.form>
      </.modal>

      <div class="mb-8">
        <h2 class="text-base font-semibold mb-3">Pending deliveries</h2>
        <.table id="pending-batches" rows={@streams.pending_batches}>
          <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
          <:col :let={{_id, batch}} label="GTIN"><code>{batch.gtin}</code></:col>
          <:col :let={{_id, batch}} label="Serial">{batch.serial || "—"}</:col>
          <:col :let={{_id, batch}} label="Manufacture date">{batch.manufacture_date || "—"}</:col>
          <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={{_id, batch}} label="Qty">{batch.quantity}</:col>
          <:col :let={{_id, batch}} label="Supplier">
            {supplier_display(batch, @suppliers_by_id)}
          </:col>
          <:action :let={{_id, batch}}>
            <.button
              variant="ghost"
              patch={~p"/lab/receive-stock/#{batch.id}/receive"}
              class="gap-2"
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Receive
            </.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="Nothing pending delivery">
              {if @direct_receipt?,
                do: "New stock is received directly into your site's inventory above.",
                else: "Batches dispatched to this site will appear here for review."}
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div
        :if={@selected_batch}
        id="batch-review-panel"
        class="rounded-2xl bg-thamani-stone p-6 mb-8"
      >
        <div class="flex items-start justify-between mb-5">
          <h2 class="text-base font-semibold text-thamani-forest">
            Review batch before receiving
          </h2>
          <.button phx-click="cancel_view">Cancel</.button>
        </div>

        <dl class="grid grid-cols-2 gap-x-10 gap-y-3 mb-6 text-sm">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Product
            </dt>
            <dd class="font-medium text-thamani-forest">
              {product_display(@selected_batch, @products_by_id)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Batch / lot
            </dt>
            <dd><code>{@selected_batch.batch_no}</code></dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              GTIN
            </dt>
            <dd><code>{@selected_batch.gtin}</code></dd>
          </div>
          <div :if={@selected_batch.serial}>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Serial
            </dt>
            <dd>{@selected_batch.serial}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Expiry date
            </dt>
            <dd>{@selected_batch.expiry_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Quantity
            </dt>
            <dd>{@selected_batch.quantity}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Destination site
            </dt>
            <dd>{@selected_batch.site.name}</dd>
          </div>
          <div :if={@selected_batch.supplier_id}>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Supplier
            </dt>
            <dd>{@selected_batch.supplier.name}</dd>
          </div>
          <div :if={@selected_batch.manufacture_date}>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5 text-thamani-pewter">
              Manufacture date
            </dt>
            <dd>{@selected_batch.manufacture_date}</dd>
          </div>
        </dl>

        <.button phx-click="receive_batch" phx-value-id={@selected_batch.id} variant="primary">
          Approve receipt
        </.button>
      </div>
    </Layouts.lab_shell>
    """
  end
end
