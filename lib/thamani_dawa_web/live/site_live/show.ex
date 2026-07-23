defmodule ThamaniDawaWeb.SiteLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  @near_expiry_days 30

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    site = Sites.get_site!(organization_id, id)

    socket =
      socket
      |> assign(:site, site)
      |> assign(:near_expiry_days, @near_expiry_days)
      |> load_pharmacy(organization_id, site)
      |> load_lab(organization_id, site)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    {:noreply, assign(socket, :tab, tab_from_params(params, socket.assigns.site))}
  end

  defp tab_from_params(%{"tab" => "lab"}, site),
    do: if(Site.lab?(site), do: :lab, else: default_tab(site))

  defp tab_from_params(%{"tab" => "pharmacy"}, site),
    do: if(Site.pharmacy?(site), do: :pharmacy, else: default_tab(site))

  defp tab_from_params(_params, site), do: default_tab(site)

  defp default_tab(site) do
    cond do
      Site.pharmacy?(site) -> :pharmacy
      Site.lab?(site) -> :lab
      true -> nil
    end
  end

  defp load_pharmacy(socket, organization_id, site) do
    if Site.pharmacy?(site) do
      products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})
      batches = Batches.list_active_batches_for_site(organization_id, site.id)

      pending_prescriptions =
        organization_id
        |> Prescriptions.list_prescriptions()
        |> SiteScoping.for_site(site.id)
        |> Enum.filter(&(&1.status in [:pending, :partially_dispensed]))

      socket
      |> assign(:products_by_id, products_by_id)
      |> assign(:low_stock, low_stock(batches, products_by_id))
      |> assign(:near_expiry, near_expiry(batches))
      |> assign(:pending_prescriptions, pending_prescriptions)
    else
      socket
    end
  end

  defp load_lab(socket, organization_id, site) do
    if Site.lab?(site) do
      lab_orders =
        organization_id
        |> LabOrders.list_lab_orders_with_patient()
        |> SiteScoping.for_site(site.id)

      socket
      |> assign(:pending_orders, Enum.filter(lab_orders, &(&1.status == :pending)))
      |> assign(
        :incomplete_orders,
        Enum.filter(lab_orders, &(&1.status in [:pending, :in_progress]))
      )
    else
      socket
    end
  end

  defp low_stock(batches, products_by_id) do
    batches
    |> Enum.group_by(& &1.product_id)
    |> Enum.map(fn {product_id, product_batches} ->
      {products_by_id[product_id], Enum.sum(Enum.map(product_batches, & &1.remaining_quantity))}
    end)
    |> Enum.filter(fn {product, total} ->
      product && product.reorder_level && total <= product.reorder_level
    end)
  end

  defp near_expiry(batches) do
    today = Date.utc_today()

    batches
    |> Enum.filter(&(Date.diff(&1.expiry_date, today) in 0..@near_expiry_days))
    |> Enum.sort_by(& &1.expiry_date, Date)
  end

  defp product_name(products_by_id, product_id) do
    product_display_name(products_by_id[product_id])
  end

  defp product_display_name(nil), do: "(unknown product)"

  defp product_display_name(product),
    do: product.generic_name || product.brand_name || "(unnamed)"

  defp patient_name(%{patient_visit: %{patient: patient}}) when not is_nil(patient),
    do: patient.full_name

  defp patient_name(_lab_order), do: "(unknown patient)"

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/sites"}>
      <.header>
        {@site.name}
        <:subtitle>
          {Phoenix.Naming.humanize(@site.site_type)} · {@site.address}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/org/sites/#{@site.id}/edit"}>Edit</.button>
          <.button navigate={~p"/org/sites"}>Back</.button>
        </:actions>
      </.header>

      <div
        :if={Site.pharmacy?(@site) and Site.lab?(@site)}
        class="tabs tabs-boxed w-fit mt-6 mb-2 p-1 bg-base-200"
      >
        <.link
          patch={~p"/org/sites/#{@site.id}?tab=pharmacy"}
          class={["tab px-6 font-medium", @tab == :pharmacy && "tab-active"]}
        >
          Pharmacy
        </.link>
        <.link
          patch={~p"/org/sites/#{@site.id}?tab=lab"}
          class={["tab px-6 font-medium", @tab == :lab && "tab-active"]}
        >
          Lab
        </.link>
      </div>

      <div :if={@tab == :pharmacy}>
        <.header class="mt-6">
          Low stock
          <:subtitle>Products at or below their reorder level</:subtitle>
        </.header>
        <.table id="site-low-stock" rows={@low_stock}>
          <:col :let={{product, _total}} label="Product">{product_display_name(product)}</:col>
          <:col :let={{product, _total}} label="Reorder level">
            {product && product.reorder_level}
          </:col>
          <:col :let={{_product, total}} label="Remaining">{total}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No products are low on stock">
              Products will show up here once they drop to their reorder level.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header class="mt-6">
          Near-expiry batches
          <:subtitle>Expiring within {@near_expiry_days} days</:subtitle>
        </.header>
        <.table id="site-near-expiry" rows={@near_expiry}>
          <:col :let={batch} label="Product">{product_name(@products_by_id, batch.product_id)}</:col>
          <:col :let={batch} label="Batch no.">{batch.batch_no}</:col>
          <:col :let={batch} label="Expiry">{batch.expiry_date}</:col>
          <:col :let={batch} label="Remaining">{batch.remaining_quantity}</:col>
          <:empty_state>
            <.blank_state icon="hero-calendar-days" title="No batches expiring soon">
              Batches will appear here within {@near_expiry_days} days of their expiry date.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header class="mt-6">Pending prescriptions</.header>
        <.table
          id="site-pending-prescriptions"
          rows={@pending_prescriptions}
          row_click={
            fn prescription -> JS.navigate(~p"/pharmacy/prescriptions/#{prescription.id}") end
          }
        >
          <:col :let={prescription} label="Status">
            <.status_badge status={prescription.status} />
          </:col>
          <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
          <:col :let={prescription} label="Paid">
            {if prescription.has_paid, do: "Yes", else: "No"}
          </:col>
          <:empty_state>
            <.blank_state icon="hero-clipboard-document-check" title="No pending prescriptions">
              Prescriptions awaiting dispensing at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={@tab == :lab}>
        <.header class="mt-6">Pending orders</.header>
        <.table
          id="site-pending-orders"
          rows={@pending_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No pending orders">
              New lab orders at this site will appear here.
            </.blank_state>
          </:empty_state>
        </.table>

        <.header class="mt-6">Incomplete reports</.header>
        <.table
          id="site-incomplete-orders"
          rows={@incomplete_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(lab_order)}
          </:col>
          <:col :let={lab_order} label="Status">
            <.status_badge status={lab_order.status} />
          </:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
          <:empty_state>
            <.blank_state icon="hero-check-circle" title="No incomplete reports">
              Orders still awaiting collection or results will appear here.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div :if={is_nil(@tab)}>
        <.blank_state icon="hero-building-office-2" title="No operations configured" class="mt-6">
          This site has no pharmacy or lab operations to show.
        </.blank_state>
      </div>
    </Layouts.org_shell>
    """
  end
end
