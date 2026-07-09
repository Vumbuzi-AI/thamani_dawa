defmodule ThamaniDawaWeb.LabReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.SiteScoping

  import ThamaniDawaWeb.BatchFormComponents

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)

    products =
      organization_id
      |> Products.list_products()
      |> SiteScoping.for_current_site(scope)

    usable_batches =
      organization_id
      |> Batches.list_batches()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(&(&1.remaining_quantity > 0))

    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    {:ok,
     socket
     |> assign(:products, products)
     |> assign(:suppliers, Suppliers.list_suppliers(organization_id))
     |> assign(:sites, Sites.list_sites(organization_id))
     |> assign(:site_locked, not is_nil(site_id))
     |> assign(:form, to_form(Batch.changeset(%Batch{}, initial_attrs), as: :batch))
     |> assign(:gs1_used, false)
     |> assign(:raw_gs1, nil)
     |> assign(:usable_batches, usable_batches)}
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
         |> assign(:raw_gs1, raw_gs1)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't decode that code: #{inspect(reason)}")}
    end
  end

  def handle_event("save", %{"batch" => attrs}, socket) do
    scope = socket.assigns.current_scope
    user = scope.user

    attrs =
      Map.merge(attrs, %{
        "received_by_id" => user.id,
        "received_at" => DateTime.utc_now()
      })

    case Batches.create_batch(scope.organization_id, attrs) do
      {:ok, _batch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock received.")
         |> push_navigate(to: ~p"/lab")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
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
          scope.organization_id
          |> Batches.list_batches()
          |> SiteScoping.for_current_site(scope)
          |> Enum.filter(&(&1.remaining_quantity > 0))

        {:noreply,
         socket
         |> put_flash(:info, "Usage recorded.")
         |> assign(:usable_batches, usable_batches)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't record usage: #{inspect(reason)}")}
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp batch_label(batch, products_by_id) do
    product = products_by_id[batch.product_id]

    name =
      (product && (product.generic_name || product.brand_name)) || "(unknown product)"

    "#{name} — #{batch.batch_no} (#{batch.remaining_quantity} left, exp. #{batch.expiry_date})"
  end

  def render(assigns) do
    products_by_id = Map.new(assigns.products, &{&1.id, &1})
    assigns = assign(assigns, :products_by_id, products_by_id)

    ~H"""
    <Layouts.lab_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/lab/receive-stock"}
    >
      <.header>Receive stock / consumables</.header>

      <.batch_form
        form={@form}
        products={@products}
        suppliers={@suppliers}
        sites={@sites}
        site_locked={@site_locked}
      />

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
