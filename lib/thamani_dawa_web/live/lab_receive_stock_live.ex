defmodule ThamaniDawaWeb.LabReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.SiteScoping

  import ThamaniDawaWeb.BatchFormComponents

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)

    lab_sites = organization_id |> Sites.list_sites() |> Enum.filter(&Site.lab?/1)
    lab_site_ids = MapSet.new(lab_sites, & &1.id)

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

    suppliers = Suppliers.list_suppliers(organization_id)
    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:suppliers, suppliers)
     |> assign(:suppliers_by_id, Map.new(suppliers, &{&1.id, &1}))
     |> assign(:sites_by_id, Map.new(lab_sites, &{&1.id, &1}))
     |> assign(:lab_sites, lab_sites)
     |> assign(:site_id, site_id)
     |> assign(:site_locked, not is_nil(site_id))
     |> assign(:form, to_form(Batch.changeset(%Batch{}, initial_attrs), as: :batch))
     |> assign(:gs1_used, false)
     |> assign(:raw_gs1, nil)
     |> assign(:gs1_decode_error, nil)
     |> assign(:selected_batch, nil)
     |> assign(:usable_batches, usable_batches)
     |> stream(:pending_batches, pending_batches)}
  end

  def handle_event("view_batch", %{"id" => id}, socket) do
    batch =
      Batches.get_batch!(socket.assigns.current_scope.organization_id, String.to_integer(id))

    {:noreply, assign(socket, :selected_batch, batch)}
  end

  def handle_event("cancel_view", _params, socket) do
    {:noreply, assign(socket, :selected_batch, nil)}
  end

  def handle_event("receive_batch", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    batch = Batches.get_batch!(scope.organization_id, String.to_integer(id))

    if not Scope.admin?(scope) and scope.user.site_id != batch.site_id do
      {:noreply, put_flash(socket, :error, "Not authorized to receive this batch.")}
    else
      do_receive_batch(socket, scope, batch)
    end
  end

  def handle_event("decode_gs1", %{"raw_gs1" => raw_gs1}, socket) do
    case GS1Decoder.parse(raw_gs1) do
      {:ok, parsed} ->
        changes =
          %{
            gtin: parsed.gtin,
            batch_no: parsed.batch_no,
            manufacture_date: parsed.production_date,
            expiry_date: parsed.expiry_date
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        changeset = Ecto.Changeset.change(socket.assigns.form.source, changes)

        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :batch))
         |> assign(:gs1_used, true)
         |> assign(:raw_gs1, raw_gs1)
         |> assign(:gs1_decode_error, nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket, :gs1_decode_error, "Couldn't decode that code: #{inspect(reason)}")}
    end
  end

  def handle_event("save", %{"batch" => attrs}, socket) do
    scope = socket.assigns.current_scope
    site_id_str = Map.get(attrs, "site_id", "")

    case parse_id(site_id_str) do
      {:ok, site_id} when not is_map_key(socket.assigns.sites_by_id, site_id) ->
        {:noreply, put_flash(socket, :error, "Selected site cannot receive lab consumables.")}

      _ ->
        walk_in_receive(socket, scope, attrs)
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
         |> reload_pending_batches(scope)
         |> assign(:usable_batches, usable_batches)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not receive batch.")}
    end
  end

  defp walk_in_receive(socket, scope, attrs) do
    with {:create, {:ok, batch}} <-
           {:create, Batches.create_batch(scope.organization_id, attrs)},
         {:receive, {:ok, _}} <-
           {:receive, Batches.receive_batch(batch, scope.user.id)} do
      {:noreply, socket |> put_flash(:info, "Stock received.") |> push_navigate(to: ~p"/lab")}
    else
      {:create, {:error, changeset}} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}

      {:receive, {:error, _}} ->
        {:noreply, put_flash(socket, :error, "Batch saved but could not be marked received.")}
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

  defp parse_id(""), do: :empty

  defp parse_id(str) do
    case Integer.parse(str) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp batch_label(batch, products_by_id) do
    product = products_by_id[batch.product_id]
    name = (product && (product.generic_name || product.brand_name)) || "(unknown product)"
    "#{name} — #{batch.batch_no} (#{batch.remaining_quantity} left, exp. #{batch.expiry_date})"
  end

  defp lookup_name(id, map, field \\ :name) do
    case Map.get(map, id) do
      nil -> "—"
      record -> Map.get(record, field) || "—"
    end
  end

  defp product_display(batch, products_by_id) do
    case Map.get(products_by_id, batch.product_id) do
      nil -> "(unknown product)"
      p -> p.generic_name || p.brand_name || "(unnamed)"
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/lab/receive-stock"}
    >
      <.header>Receive stock / consumables</.header>

      <div class="mb-8">
        <h2 class="text-base font-semibold mb-3">Pending deliveries</h2>
        <.table id="pending-batches" rows={@streams.pending_batches}>
          <:col :let={{_id, batch}} label="Batch / lot">{batch.batch_no}</:col>
          <:col :let={{_id, batch}} label="GTIN"><code>{batch.gtin}</code></:col>
          <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={{_id, batch}} label="Qty">{batch.quantity}</:col>
          <:action :let={{_id, batch}}>
            <.button phx-click="view_batch" phx-value-id={batch.id}>View</.button>
          </:action>
        </.table>
      </div>

      <div
        :if={@selected_batch}
        id="batch-review-panel"
        class="rounded-2xl p-6 mb-8"
        style="background: #eeeee9;"
      >
        <div class="flex items-start justify-between mb-5">
          <h2 class="text-base font-semibold" style="color: #1c3a13;">
            Review batch before receiving
          </h2>
          <.button phx-click="cancel_view">Cancel</.button>
        </div>

        <dl class="grid grid-cols-2 gap-x-10 gap-y-3 mb-6 text-sm">
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Product
            </dt>
            <dd class="font-medium" style="color: #1c3a13;">
              {product_display(@selected_batch, @products_by_id)}
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Batch / lot
            </dt>
            <dd><code>{@selected_batch.batch_no}</code></dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              GTIN
            </dt>
            <dd><code>{@selected_batch.gtin}</code></dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Expiry date
            </dt>
            <dd>{@selected_batch.expiry_date}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Quantity
            </dt>
            <dd>{@selected_batch.quantity}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Destination site
            </dt>
            <dd>{lookup_name(@selected_batch.site_id, @sites_by_id)}</dd>
          </div>
          <div :if={@selected_batch.supplier_id}>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Supplier
            </dt>
            <dd>{lookup_name(@selected_batch.supplier_id, @suppliers_by_id)}</dd>
          </div>
          <div :if={@selected_batch.manufacture_date}>
            <dt class="text-xs font-medium uppercase tracking-wide mb-0.5" style="color: #6b7280;">
              Manufacture date
            </dt>
            <dd>{@selected_batch.manufacture_date}</dd>
          </div>
        </dl>

        <.button phx-click="receive_batch" phx-value-id={@selected_batch.id} variant="primary">
          Approve receipt
        </.button>
      </div>

      <div class="mb-8">
        <h2 class="text-base font-semibold mb-3">Receive unscheduled delivery</h2>
        <.batch_form
          form={@form}
          products={Map.values(@products_by_id)}
          suppliers={@suppliers}
          sites={@lab_sites}
          site_locked={@site_locked}
          gs1_decode_error={@gs1_decode_error}
        />
      </div>

      <div class="rounded-2xl p-6 mt-6" style="background: #eeeee9;">
        <h2 class="text-base font-medium mb-4" style="color: #1c3a13;">Log consumable usage</h2>
        <.form
          for={%{}}
          id="consumable-usage-form"
          phx-submit="record_usage"
          class="flex flex-wrap gap-3 items-end"
        >
          <.input
            type="select"
            name="batch_id"
            label="Batch"
            value={nil}
            options={Enum.map(@usable_batches, &{batch_label(&1, @products_by_id), &1.id})}
            prompt="Choose a batch"
          />
          <.input type="number" name="quantity" label="Quantity" required />
          <.input type="number" name="lab_order_id" label="Lab order ID (optional)" />
          <.input type="text" name="purpose" label="Purpose" />
          <.button variant="primary">Record usage</.button>
        </.form>
      </div>
    </Layouts.lab_shell>
    """
  end
end
