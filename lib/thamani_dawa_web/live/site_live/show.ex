defmodule ThamaniDawaWeb.SiteLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.Patients
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
        organization_id |> LabOrders.list_lab_orders() |> SiteScoping.for_site(site.id)

      patient_by_visit_id =
        organization_id
        |> ThamaniDawa.PatientVisits.list_patient_visits()
        |> Map.new(&{&1.id, Patients.get_patient!(organization_id, &1.patient_id)})

      socket
      |> assign(:patient_by_visit_id, patient_by_visit_id)
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

  defp patient_name(patient_by_visit_id, visit_id) do
    case patient_by_visit_id[visit_id] do
      nil -> "(unknown patient)"
      patient -> patient.full_name
    end
  end

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
            {Phoenix.Naming.humanize(prescription.status)}
          </:col>
          <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
          <:col :let={prescription} label="Paid">
            {if prescription.has_paid, do: "Yes", else: "No"}
          </:col>
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
            {patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
          </:col>
          <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        </.table>

        <.header class="mt-6">Incomplete reports</.header>
        <.table
          id="site-incomplete-orders"
          rows={@incomplete_orders}
          row_click={fn o -> JS.navigate(~p"/lab/orders/#{o.id}") end}
        >
          <:col :let={lab_order} label="Patient">
            {patient_name(@patient_by_visit_id, lab_order.patient_visit_id)}
          </:col>
          <:col :let={lab_order} label="Status">{Phoenix.Naming.humanize(lab_order.status)}</:col>
          <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
        </.table>
      </div>

      <div :if={is_nil(@tab)} class="text-center text-base-content/50 py-8">
        This site has no pharmacy or lab operations to show.
      </div>
    </Layouts.org_shell>
    """
  end
end
