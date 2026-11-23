defmodule ThamaniDawaWeb.ManufacturerProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.Billing
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Products")
     |> assign(:search, "")
     |> assign(:view_mode, "list")
     |> assign(:page_number, 1)
     |> assign(:product, nil)}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> assign(:search, Map.get(params, "search", socket.assigns.search))
      |> assign(:view_mode, view_mode(params, socket.assigns.view_mode))
      |> load_products()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    product = %Product{}

    socket
    |> assign(:product, product)
    |> assign(:form, to_form(Manufacturing.change_product(product), as: :product))
  end

  defp apply_action(socket, :new_serial, %{"gtin" => gtin}) do
    scope = socket.assigns.current_scope
    product = Manufacturing.get_product_by_gtin!(scope.organization_id, gtin)
    site = Sites.get_site!(scope.organization_id, scope.current_site_id)
    facilities = Sites.list_sites(scope.organization_id)

    socket
    |> assign(:product, product)
    |> assign(:site, site)
    |> assign(:facilities, facilities)
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :product, nil)

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products?#{%{search: search, view: socket.assigns.view_mode}}"
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/manufacturer/products")}
  end

  def handle_event("set_view", %{"view" => mode}, socket) when mode in ["list", "grid"] do
    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products?#{%{search: socket.assigns.search, view: mode}}"
     )}
  end

  def handle_event("sync_products", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.sync_products(organization_id) do
      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Synced #{count} product#{if count == 1, do: "", else: "s"} from GS1."
         )
         |> load_products()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't sync products: #{inspect(reason)}")}
    end
  end

  def handle_event("validate", %{"product" => params}, socket) do
    changeset =
      socket.assigns.product
      |> Manufacturing.change_product(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Manufacturing.create_product(organization_id, params) do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{product.name} added.")
         |> push_patch(to: ~p"/manufacturer/products")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  def handle_info({:serial_generation_complete, count}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{count} primary serial#{if count == 1, do: "", else: "s"} generated.")
     |> push_patch(to: ~p"/manufacturer/products")}
  end

  def handle_info({:serial_generation_complete, serial_count, shipper_count}, socket) do
    {:noreply,
     socket
     |> put_flash(
       :info,
       "#{serial_count} primary serial#{if serial_count == 1, do: "", else: "s"} and " <>
         "#{shipper_count} shipper SSCC#{if shipper_count == 1, do: "", else: "s"} generated."
     )
     |> push_patch(to: ~p"/manufacturer/products")}
  end

  def handle_info({:serial_generation_failed, reason}, socket) do
    {:noreply, put_flash(socket, :error, generation_error(reason))}
  end

  defp load_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    page_info =
      Manufacturing.paginate_products_with_counts(organization_id,
        page: socket.assigns.page_number,
        search: socket.assigns.search
      )

    remote_counts = remote_counts(organization_id)
    usage = Billing.active_usage(organization_id)

    page_info = %{page_info | entries: merge_remote_counts(page_info.entries, remote_counts)}

    counts =
      organization_id
      |> Manufacturing.list_products_with_counts()
      |> merge_remote_counts(remote_counts)
      |> generation_counts()

    socket
    |> assign(:page_info, page_info)
    |> assign(:rows, page_info.entries)
    |> assign(:number_generated, counts.serials + counts.ssccs)
    |> assign(:maximum, maximum(usage))
  end

  defp remote_counts(organization_id) do
    case Manufacturing.remote_product_counts(organization_id) do
      {:ok, counts} -> counts
      {:error, _reason} -> %{}
    end
  end

  defp merge_remote_counts(entries, remote_counts) do
    Enum.map(entries, fn %{product: product} = entry ->
      case remote_counts[product.gtin] do
        nil -> entry
        counts -> Map.merge(entry, counts)
      end
    end)
  end

  defp generation_counts(entries) do
    Enum.reduce(entries, %{serials: 0, ssccs: 0}, fn entry, totals ->
      %{
        serials: totals.serials + entry.serial_count,
        ssccs: totals.ssccs + entry.sscc_count
      }
    end)
  end

  defp maximum(%{quantity_limit: nil}), do: "Unlimited"
  defp maximum(%{quantity_limit: limit}) when is_integer(limit), do: limit
  defp maximum(_usage), do: 0

  defp view_mode(params, fallback) do
    case Map.get(params, "view", fallback) do
      mode when mode in ["list", "grid"] -> mode
      _other -> "list"
    end
  end

  defp generation_error(%Ecto.Changeset{}),
    do: "The batch details conflict with an existing batch."

  defp generation_error(:unconfigured),
    do: "The GS1 member API is not configured. No serials were saved."

  defp generation_error(:unavailable),
    do: "The GS1 member API is unavailable. No serials were saved."

  defp generation_error(:invalid_quantity),
    do: "The shipper quantity must be a positive integer no greater than the primary quantity."

  defp generation_error(:not_found),
    do:
      "This GTIN isn't registered under your GS1 member account. Use \"Sync from GS1\" to import your products before generating serials."

  defp generation_error(:unauthorized),
    do: "GS1 rejected the API credentials. Check the organization's GS1 API key."

  defp generation_error(:forbidden),
    do:
      "This GS1 account isn't allowed to issue SSCCs, which make-to-order requires. Use make-to-stock, or contact GS1 Kenya to enable SSCC API access."

  defp generation_error(reason), do: "Serial generation failed: #{inspect(reason)}"

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-archive-box">
        Products
        <:subtitle>GTINs registered to this organization and their serialisation activity.</:subtitle>
        <:actions>
          <.button id="sync-manufacturer-products" phx-click="sync_products"><.icon
            name="hero-arrow-path"
            class="size-4"
          /> Sync from GS1</.button>
          <.button
            id="add-manufacturer-product"
            variant="primary"
            patch={~p"/manufacturer/products/new"}
          ><.icon name="hero-plus" class="size-4" /> Add product</.button>
        </:actions>
      </.header>

      <div class="dashboard-stat-grid mt-6 sm:grid-cols-2">
        <.stat_tile
          id="manufacturer-number-generated"
          icon="hero-qr-code"
          label="Number generated"
          value={@number_generated}
          sublabel="Primary serials and shipping SSCCs"
        />
        <.stat_tile
          id="manufacturer-maximum"
          icon="hero-chart-bar-square"
          label="Maximum"
          value={@maximum}
          sublabel="Current serialisation quota"
        />
      </div>

      <div class="mt-6 flex flex-col gap-3 rounded-2xl border border-thamani-stone bg-white p-3 shadow-sm sm:flex-row sm:items-center">
        <form id="manufacturer-product-search" phx-change="search" class="min-w-0 flex-1">
          <.input
            type="search"
            name="search"
            value={@search}
            placeholder="Search GTIN, brand or description"
            phx-debounce="300"
            class="w-full"
          />
        </form>
        <div class="flex items-center gap-2">
          <div class="flex rounded-xl border border-thamani-stone bg-thamani-snow p-1">
            <button
              id="manufacturer-list-view"
              type="button"
              phx-click="set_view"
              phx-value-view="list"
              class={[
                "rounded-lg px-3 py-2 transition",
                @view_mode == "list" && "bg-white text-thamani-forest shadow-sm"
              ]}
              aria-label="List view"
            ><.icon name="hero-list-bullet" class="size-4" /></button>
            <button
              id="manufacturer-grid-view"
              type="button"
              phx-click="set_view"
              phx-value-view="grid"
              class={[
                "rounded-lg px-3 py-2 transition",
                @view_mode == "grid" && "bg-white text-thamani-forest shadow-sm"
              ]}
              aria-label="Grid view"
            ><.icon name="hero-squares-2x2" class="size-4" /></button>
          </div>
          <.button id="reset-manufacturer-products" type="button" phx-click="reset">Reset</.button>
        </div>
      </div>

      <div :if={@view_mode == "list"} class="mt-5">
        <.table id="manufacturer-products" rows={@rows}>
          <:col :let={%{product: product}} label="GTIN">
            <span class="font-mono text-sm">{product.gtin}</span>
          </:col>
          <:col :let={%{product: product}} label="Product">{product.name}</:col>
          <:col :let={%{product: product}} label="Description">{product.description || "—"}</:col>
          <:col :let={%{product: product}} label="Created at">
            {Calendar.strftime(product.inserted_at, "%d %b %Y")}
          </:col>
          <:col :let={%{product: product, sscc_count: count}} label="SSCC">
            <div class="flex items-center gap-2">
              <.link
                id={"product-#{product.id}-ssccs"}
                navigate={~p"/manufacturer/products/#{product.gtin}/ssccs"}
                class="rounded-lg p-2 text-thamani-pewter transition hover:bg-thamani-mist hover:text-thamani-forest"
                aria-label={"View SSCCs for #{product.name}"}
              ><.icon name="hero-eye" class="size-4" /></.link><span id={"product-#{product.id}-sscc-count"}>{count}</span>
            </div>
          </:col>
          <:col :let={%{product: product, serial_count: count}} label="Serials">
            <div class="flex items-center gap-2">
              <.link
                id={"product-#{product.id}-serials"}
                navigate={~p"/manufacturer/products/#{product.gtin}/serials"}
                class="rounded-lg p-2 text-thamani-pewter transition hover:bg-thamani-mist hover:text-thamani-forest"
                aria-label={"View serials for #{product.name}"}
              ><.icon name="hero-eye" class="size-4" /></.link><span id={"product-#{product.id}-serial-count"}>{count}</span>
            </div>
          </:col>
          <:action :let={%{product: product}}>
            <.button
              id={"product-#{product.id}-add-serial"}
              variant="primary"
              patch={~p"/manufacturer/products/#{product.gtin}/serials/new"}
            ><.icon name="hero-plus" class="size-4" /> Serial</.button>
          </:action>
          <:empty_state>
            <.blank_state icon="hero-archive-box" title="No products found">
              Add or sync a GTIN to start generating primary serials.
            </.blank_state>
          </:empty_state>
        </.table>
      </div>

      <div
        :if={@view_mode == "grid"}
        id="manufacturer-products-grid"
        class="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3"
      >
        <article
          :for={row <- @rows}
          id={"manufacturer-product-card-#{row.product.id}"}
          class="rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
        >
          <p class="font-mono text-xs text-thamani-pewter">{row.product.gtin}</p><h3 class="mt-2 text-lg font-semibold text-thamani-forest">
            {row.product.name}
          </h3><p class="mt-1 min-h-10 text-sm text-thamani-pewter">
            {row.product.description || "No description"}
          </p>
          <div class="mt-5 grid grid-cols-2 gap-2">
            <.link
              navigate={~p"/manufacturer/products/#{row.product.gtin}/ssccs"}
              class="rounded-xl bg-thamani-snow p-3 text-sm transition hover:bg-thamani-mist"
            ><span class="block text-xs text-thamani-pewter">SSCC</span><span class="font-semibold">{row.sscc_count}</span></.link><.link
              navigate={~p"/manufacturer/products/#{row.product.gtin}/serials"}
              class="rounded-xl bg-thamani-snow p-3 text-sm transition hover:bg-thamani-mist"
            ><span class="block text-xs text-thamani-pewter">Serials</span><span class="font-semibold">{row.serial_count}</span></.link>
          </div>
          <.button
            class="mt-4 w-full"
            variant="primary"
            patch={~p"/manufacturer/products/#{row.product.gtin}/serials/new"}
          ><.icon name="hero-plus" class="size-4" /> Serial</.button>
        </article>
      </div>

      <.pagination
        :if={@page_info.total_entries > 0}
        page={@page_info}
        path={~p"/manufacturer/products?#{%{search: @search, view: @view_mode}}"}
      />

      <.modal
        :if={@live_action == :new}
        id="manufacturer-product-modal"
        show
        on_cancel={JS.patch(~p"/manufacturer/products")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">Add product</h2>
        <.form for={@form} id="manufacturer-product-form" phx-change="validate" phx-submit="save">
          <div class="space-y-4">
            <.input field={@form[:gtin]} label="GTIN" placeholder="8 to 14 digits" required /><.input
              field={@form[:name]}
              label="Product name"
              required
            /><.input field={@form[:description]} label="Description" /><.input
              field={@form[:brand_owner]}
              label="Brand owner"
            />
          </div><div class="mt-6 flex justify-end gap-3">
            <.button type="button" phx-click={JS.patch(~p"/manufacturer/products")}>Cancel</.button><.button variant="primary">Save product</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :new_serial}
        id="manufacturer-serial-modal"
        show
        on_cancel={JS.patch(~p"/manufacturer/products")}
      >
        <h2 class="mb-6 text-2xl font-medium tracking-tight text-thamani-forest">
          Generate primary serials
        </h2>
        <.live_component
          module={ThamaniDawaWeb.ManufacturerProductLive.SerialWizard}
          id={"serial-wizard-#{@product.id}"}
          product={@product}
          organization_id={@current_scope.organization_id}
          site={@site}
          facilities={@facilities}
        />
      </.modal>
    </Layouts.manufacturer_shell>
    """
  end
end
