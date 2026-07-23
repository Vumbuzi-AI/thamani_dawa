defmodule ThamaniDawaWeb.PharmacyStockLive do
  @moduledoc """
  Read-only, organization-wide view of every batch across every site —
  deliberately does *not* call `SiteScoping.for_current_site/2`, unlike every
  other pharmacy screen. Pharmacists are otherwise locked to their home site
  (`[[design_patterns]]`); this is the one screen that shows them the whole
  organization's stock, with an explicit site filter to narrow back down.
  Nothing here mutates a batch — receiving/dispensing stay on
  `ReceiveStockLive`/`PrescriptionLive`, both still site-locked as before.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  @default_filters %{site: "", status: ""}

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id
    sites = Sites.list_sites(org_id)

    {:ok,
     socket
     |> assign(:products_by_id, org_id |> Products.list_products() |> Map.new(&{&1.id, &1}))
     |> assign(:sites_by_id, Map.new(sites, &{&1.id, &1}))
     |> assign(:site_options, Enum.map(sites, &{&1.name, &1.id}))
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> reload_batches()}
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_batches()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      site: Map.get(filter_params, "site", ""),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> reload_batches()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_batches()}
  end

  def handle_event("clear_chip", %{"field" => "site"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | site: ""}) |> reload_batches()}
  end

  def handle_event("clear_chip", %{"field" => "status"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | status: ""}) |> reload_batches()}
  end

  defp reload_batches(socket) do
    org_id = socket.assigns.current_scope.organization_id

    filtered =
      org_id
      |> Batches.list_batches()
      |> filter_by_search(socket.assigns.search, socket.assigns.products_by_id)
      |> filter_by_site(socket.assigns.filters.site)
      |> filter_by_status(socket.assigns.filters.status)
      |> Enum.sort_by(& &1.expiry_date, Date)

    stream(socket, :batches, filtered, reset: true)
  end

  defp filter_by_search(batches, "", _products_by_id), do: batches

  defp filter_by_search(batches, search, products_by_id) do
    search = String.downcase(String.trim(search))

    Enum.filter(batches, fn batch ->
      product = products_by_id[batch.product_id]

      [product && product.generic_name, product && product.brand_name, batch.gtin, batch.batch_no]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_site(batches, ""), do: batches

  defp filter_by_site(batches, site_id_str),
    do: Enum.filter(batches, &(to_string(&1.site_id) == site_id_str))

  defp filter_by_status(batches, ""), do: batches
  defp filter_by_status(batches, "active"), do: Enum.filter(batches, &(!is_nil(&1.approver_id)))
  defp filter_by_status(batches, "pending"), do: Enum.filter(batches, &is_nil(&1.approver_id))

  defp active_filter_count(filters) do
    Enum.count([filters.site != "", filters.status != ""], & &1)
  end

  defp filter_chips(filters, sites_by_id) do
    [
      filters.site != "" &&
        %{label: "Site: #{site_label(filters.site, sites_by_id)}", field: "site"},
      filters.status != "" &&
        %{label: "Status: #{Phoenix.Naming.humanize(filters.status)}", field: "status"}
    ]
    |> Enum.filter(& &1)
  end

  defp site_label(site_id_str, sites_by_id) do
    case sites_by_id[String.to_integer(site_id_str)] do
      nil -> site_id_str
      site -> site.name
    end
  end

  defp product_name(nil), do: "(unknown product)"
  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp site_name(nil), do: "(unknown site)"
  defp site_name(site), do: site.name

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock"
    >
      <.header icon="hero-cube">
        Organization stock
        <:subtitle>Every batch across every site in your organization — read-only.</:subtitle>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by product, GTIN, or batch no."
            />
          </form>

          <.filter_drawer
            id="stock-filters"
            title="Filter stock"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Site">
              <.input
                type="select"
                name="filters[site]"
                value={@filters.site}
                options={@site_options}
                prompt="All sites"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Pending receipt", "pending"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters, @sites_by_id)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.table id="stock" rows={@streams.batches}>
        <:col :let={{_id, batch}} label="Product">
          {product_name(@products_by_id[batch.product_id])}
        </:col>
        <:col :let={{_id, batch}} label="Site">{site_name(@sites_by_id[batch.site_id])}</:col>
        <:col :let={{_id, batch}} label="Batch no.">{batch.batch_no}</:col>
        <:col :let={{_id, batch}} label="Expiry">{batch.expiry_date}</:col>
        <:col :let={{_id, batch}} label="Remaining">{batch.remaining_quantity}</:col>
        <:col :let={{_id, batch}} label="Status">
          <.status_badge status={if batch.approver_id, do: :active, else: :pending_receipt} />
        </:col>
        <:empty_state>
          <.blank_state
            icon="hero-cube"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No batches match your search or filters",
                else: "No stock yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Batches dispatched to any site will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
