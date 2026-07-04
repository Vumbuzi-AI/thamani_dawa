defmodule ThamaniDawaWeb.ReceiveStockLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Products
  alias ThamaniDawa.ScanEvents
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
      |> Enum.filter(&(&1.product_type == :drug))

    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    {:ok,
     socket
     |> assign(:products, products)
     |> assign(:suppliers, Suppliers.list_suppliers(organization_id))
     |> assign(:sites, Sites.list_sites(organization_id))
     |> assign(:site_locked, not is_nil(site_id))
     |> assign(:form, to_form(Batch.changeset(%Batch{}, initial_attrs), as: :batch))
     |> assign(:gs1_used, false)
     |> assign(:raw_gs1, nil)}
  end

  def handle_event("decode_gs1", %{"raw_gs1" => raw_gs1}, socket) do
    case GS1Decoder.parse(raw_gs1) do
      {:ok, parsed} ->
        changes =
          %{
            gtin: parsed.gtin,
            batch_no: parsed.batch_no,
            manufacture_date: parsed.production_date,
            expiry: parsed.expiry_date
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
      {:ok, batch} ->
        if socket.assigns.gs1_used do
          ScanEvents.log_scan_event(
            scope.organization_id,
            :receipt,
            batch.id,
            user.id,
            socket.assigns.raw_gs1
          )
        end

        {:noreply,
         socket
         |> put_flash(:info, "Stock received.")
         |> push_navigate(to: ~p"/pharmacy")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>Receive stock</.header>

      <.batch_form
        form={@form}
        products={@products}
        suppliers={@suppliers}
        sites={@sites}
        site_locked={@site_locked}
      />
    </Layouts.app_shell>
    """
  end
end
