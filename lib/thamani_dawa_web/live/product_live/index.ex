defmodule ThamaniDawaWeb.ProductLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.GtinLookup
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Importer
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites

  @default_filters %{category: "", is_otc: false, is_dangerous_drug: false}
  @max_import_file_size 5_000_000
  @import_preview_limit 10
  @onboarding_catalog_page_size 7

  @units [
    {"KILOGRAM", "KGM"},
    {"GRAM", "GRM"},
    {"MILIGRAM", "MGM"},
    {"LITRE", "LTR"},
    {"MILLILITRE", "MLT"},
    {"CENTILITRE", "CTL"},
    {"METRE", "MTR"},
    {"CENTIMETER", "CMT"},
    {"MILLIMETRE", "MLT"},
    {"INCH", "INH"},
    {"TABLET", "U2"},
    {"PIECE", "H87"},
    {"AMPERE", "AMP"},
    {"PACK", "PK"},
    {"PACKET", "PA"},
    {"DOZEN", "DZN"},
    {"PAIR", "PR"},
    {"PAGE", "ZP"},
    {"KILOWATT", "KWT"},
    {"WATT", "WTT"},
    {"VOLT", "VLT"},
    {"KILOVOLT", "KVT"},
    {"TON", "LTN"},
    {"CAPSULE", "AV"},
    {"OUNCE", "ONZ"},
    {"ROLL", "RO"}
  ]

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:units, @units)
     |> assign(:lab_enabled, Sites.lab_enabled?(organization_id))
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign(:show_onboarding_product_form?, false)
     |> assign(:onboarding_inventory_mode, nil)
     |> assign(:onboarding_product_page, 1)
     |> assign_onboarding_import_defaults()
     |> allow_upload(:onboarding_csv_file,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: @max_import_file_size
     )}
  end

  defp assign_onboarding_import_defaults(socket) do
    socket
    |> assign(:import_step, :upload)
    |> assign(:import_filename, nil)
    |> assign(:import_headers, nil)
    |> assign(:import_rows, nil)
    |> assign(:import_mapping, nil)
    |> assign(:import_preview, nil)
    |> assign(:import_summary, nil)
    |> assign(:import_upload_error, nil)
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    search = Map.get(params, "search", "")

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> reload_products()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    socket
    |> assign(form: to_form(Product.changeset(%Product{}, %{}), as: :product), product: nil)
    |> assign(:back_path, back_path(params, ~p"/org/products"))
    |> assign(:finish_onboarding_replay?, params["finish"] == "tour")
    |> assign(:onboarding_products, Products.list_products(organization_id))
    |> assign(:onboarding_progress, Organizations.onboarding_progress(organization))
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    back_path =
      if Map.get(params, "return_to") == "show" do
        ~p"/org/products/#{id}"
      else
        ~p"/org/products"
      end

    socket
    |> assign(form: to_form(Product.changeset(product, %{}), as: :product), product: product)
    |> assign(:back_path, back_path)
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :form)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(form: nil, product: nil)
    |> assign(:back_path, ~p"/org/products")
    |> reset_gtin_lookup()
    |> assign(:gtin_step, :scan)
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("set_filter", %{"field" => "category", "value" => value}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | category: value || ""})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      category: Map.get(filter_params, "category", ""),
      is_otc: Map.get(filter_params, "is_otc") == "true",
      is_dangerous_drug: Map.get(filter_params, "is_dangerous_drug") == "true"
    }

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket |> assign(:filters, @default_filters) |> assign(:page, 1) |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "category"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | category: ""})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_otc"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | is_otc: false})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("clear_chip", %{"field" => "is_dangerous_drug"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | is_dangerous_drug: false})
     |> assign(:page, 1)
     |> reload_products()}
  end

  def handle_event("validate", %{"product" => attrs}, socket) do
    attrs = enforce_inventory_type(attrs, socket.assigns.lab_enabled)

    changeset =
      socket.assigns.product
      |> Kernel.||(%Product{})
      |> Product.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :product))}
  end

  def handle_event("save", %{"product" => attrs}, socket) do
    save_product(
      socket,
      socket.assigns.live_action,
      enforce_inventory_type(attrs, socket.assigns.lab_enabled)
    )
  end

  def handle_event("gtin_search_change", %{"gtin_search" => gtin_search}, socket) do
    {:noreply, assign(socket, :gtin_search, gtin_search)}
  end

  def handle_event("skip_gtin", _params, socket) do
    {:noreply, assign(socket, :gtin_step, :form)}
  end

  def handle_event("scan_gtin", %{"gtin_search" => raw_gtin}, socket) do
    case String.trim(raw_gtin) do
      "" ->
        {:noreply, assign(socket, :gtin_step, :form)}

      trimmed ->
        case ThamaniDawa.Gtin.normalize(trimmed) do
          {:ok, normalized} ->
            {:noreply,
             socket
             |> assign(:gtin_step, :form)
             |> assign(:gtin_lookup, :searching)
             |> put_scanned_gtin(normalized)
             |> start_async(:gtin_lookup, fn ->
               GtinLookup.lookup(trimmed)
             end)}

          {:error, :invalid_gtin} ->
            {:noreply, assign(socket, :gtin_lookup, {:error, :invalid_gtin})}
        end
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Products.get_product!(organization_id, id)

    case Products.update_product(product, %{is_active: !product.is_active}) do
      {:ok, _updated} ->
        {:noreply, reload_products(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update product.")}
    end
  end

  def handle_event("open_onboarding_product", _params, socket) do
    {:noreply, assign(socket, :show_onboarding_product_form?, true)}
  end

  def handle_event("onboarding_product_page", %{"page" => page}, socket) do
    requested_page =
      case Integer.parse(page) do
        {number, ""} -> number
        _ -> 1
      end

    {:noreply,
     assign(
       socket,
       :onboarding_product_page,
       clamp_onboarding_product_page(requested_page, socket.assigns.onboarding_products)
     )}
  end

  def handle_event("close_onboarding_product", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_onboarding_product_form?, false)
     |> assign(form: to_form(Product.changeset(%Product{}, %{}), as: :product), product: nil)
     |> reset_gtin_lookup()
     |> assign(:gtin_step, :scan)}
  end

  def handle_event("continue_onboarding", _params, socket) do
    destination =
      if socket.assigns.finish_onboarding_replay?,
        do: ~p"/onboarding?complete=1&force=1",
        else: ~p"/onboarding?complete=1"

    {:noreply, push_navigate(socket, to: destination)}
  end

  def handle_event("choose_inventory_mode", %{"mode" => mode}, socket) do
    socket = assign(socket, :onboarding_inventory_mode, String.to_existing_atom(mode))

    {:noreply, if(mode == "import", do: socket, else: clear_import_draft(socket))}
  end

  def handle_event("back_to_inventory_choice", _params, socket) do
    {:noreply,
     socket
     |> assign(:onboarding_inventory_mode, nil)
     |> assign_onboarding_import_defaults()
     |> clear_import_draft()}
  end

  def handle_event("onboarding_import_validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("onboarding_import_upload", _params, socket) do
    cond do
      socket.assigns.uploads.onboarding_csv_file.entries == [] ->
        {:noreply, assign(socket, :import_upload_error, "Choose a CSV file first.")}

      not import_upload_ready?(socket.assigns.uploads.onboarding_csv_file) ->
        {:noreply, assign(socket, :import_upload_error, "Choose a valid CSV file first.")}

      true ->
        [entry | _] = socket.assigns.uploads.onboarding_csv_file.entries
        filename = entry.client_name

        [content] =
          consume_uploaded_entries(socket, :onboarding_csv_file, fn %{path: path}, _entry ->
            {:ok, File.read!(path)}
          end)

        handle_onboarding_import_upload(socket, filename, content)
    end
  end

  def handle_event(
        "restore_onboarding_import",
        %{"version" => 1, "filename" => filename, "content" => content},
        socket
      )
      when is_binary(filename) and is_binary(content) do
    if byte_size(content) <= @max_import_file_size and byte_size(filename) <= 255 do
      case Importer.parse(content) do
        {:ok, {headers, rows}} ->
          {:reply, %{restored: true},
           socket
           |> assign(:onboarding_inventory_mode, :import)
           |> assign_parsed_import(filename, headers, rows)}

        {:error, _reason} ->
          {:reply, %{restored: false}, clear_import_draft(socket)}
      end
    else
      {:reply, %{restored: false}, clear_import_draft(socket)}
    end
  end

  def handle_event("restore_onboarding_import", _params, socket) do
    {:reply, %{restored: false}, clear_import_draft(socket)}
  end

  def handle_event("onboarding_cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :onboarding_csv_file, ref)}
  end

  def handle_event("onboarding_confirm_mapping", %{"mapping" => mapping_params}, socket) do
    mapping =
      Map.new(mapping_params, fn {key, header} ->
        {String.to_existing_atom(key), if(header == "", do: nil, else: header)}
      end)

    missing_required =
      Importer.fields()
      |> Enum.filter(&(&1.required and is_nil(Map.get(mapping, &1.key))))

    socket = assign(socket, :import_mapping, mapping)

    if missing_required == [] do
      organization_id = socket.assigns.current_scope.organization_id

      preview =
        Importer.build_preview_rows(
          organization_id,
          socket.assigns.import_headers,
          socket.assigns.import_rows,
          mapping
        )

      {:noreply, socket |> assign(:import_preview, preview) |> assign(:import_step, :preview)}
    else
      labels = Enum.map_join(missing_required, ", ", & &1.label)

      {:noreply,
       put_flash(socket, :error, "Map these required fields before continuing: #{labels}.")}
    end
  end

  def handle_event("onboarding_back_to_map", _params, socket) do
    {:noreply, socket |> assign(:import_preview, nil) |> assign(:import_step, :map)}
  end

  def handle_event("onboarding_start_over", _params, socket) do
    {:noreply, socket |> assign_onboarding_import_defaults() |> clear_import_draft()}
  end

  def handle_event("onboarding_confirm_import", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Importer.import_rows(organization_id, socket.assigns.import_preview) do
      {:ok, count} ->
        {:noreply,
         socket
         |> assign(:import_step, :done)
         |> assign(:import_summary, %{
           created: count,
           total: length(socket.assigns.import_preview)
         })
         |> assign(:onboarding_products, Products.list_products(organization_id))
         |> clear_import_draft()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Import failed partway through. Please retry.")}
    end
  end

  defp handle_onboarding_import_upload(socket, filename, content) do
    case Importer.parse(content) do
      {:ok, {headers, rows}} ->
        {:noreply,
         socket
         |> assign_parsed_import(filename, headers, rows)
         |> push_event("save_onboarding_import", %{
           version: 1,
           filename: filename,
           content: content
         })}

      error ->
        handle_onboarding_import_parsed(socket, error)
    end
  end

  defp assign_parsed_import(socket, filename, headers, rows) do
    socket
    |> assign(:import_filename, filename)
    |> assign(:import_headers, headers)
    |> assign(:import_rows, rows)
    |> assign(:import_mapping, Importer.auto_map_columns(headers))
    |> assign(:import_step, :map)
    |> assign(:import_upload_error, nil)
  end

  defp clear_import_draft(socket), do: push_event(socket, "clear_onboarding_import", %{})

  defp handle_onboarding_import_parsed(socket, {:error, :empty_file}) do
    {:noreply,
     assign(socket, :import_upload_error, "That file doesn't have any product rows in it.")}
  end

  defp handle_onboarding_import_parsed(socket, {:error, :malformed_csv}) do
    {:noreply, assign(socket, :import_upload_error, "Couldn't read that file as CSV.")}
  end

  def handle_async(:gtin_lookup, {:ok, {:ok, prefill}}, socket) do
    {:noreply,
     socket
     |> merge_gtin_prefill(prefill)
     |> assign(:gtin_lookup, {:found, prefill})}
  end

  def handle_async(:gtin_lookup, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, reason})}
  end

  def handle_async(:gtin_lookup, {:exit, :timeout}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, :timeout})}
  end

  def handle_async(:gtin_lookup, {:exit, {:timeout, _detail}}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, :timeout})}
  end

  def handle_async(:gtin_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :gtin_lookup, {:error, :provider_error})}
  end

  defp enforce_inventory_type(attrs, true), do: attrs

  defp enforce_inventory_type(attrs, false),
    do: Map.put(attrs, "inventory_type", "medicine")

  defp save_product(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Products.create_product(organization_id, attrs) do
      {:ok, product} ->
        socket =
          socket
          |> put_flash(:info, "Product created.")
          |> stream_insert(:products, build_row(organization_id, product))

        cond do
          socket.assigns.back_path == ~p"/onboarding" ->
            onboarding_products = socket.assigns.onboarding_products ++ [product]

            {:noreply,
             socket
             |> assign(:onboarding_products, onboarding_products)
             |> assign(
               :onboarding_product_page,
               onboarding_product_total_pages(onboarding_products)
             )
             |> assign(:show_onboarding_product_form?, false)
             |> assign(
               form: to_form(Product.changeset(%Product{}, %{}), as: :product),
               product: nil
             )
             |> reset_gtin_lookup()
             |> assign(:gtin_step, :scan)}

          socket.assigns.back_path == ~p"/org/dashboard" ->
            {:noreply, push_navigate(socket, to: socket.assigns.back_path)}

          true ->
            {:noreply, push_patch(socket, to: socket.assigns.back_path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp save_product(socket, :edit, attrs) do
    case Products.update_product(socket.assigns.product, attrs) do
      {:ok, product} ->
        back_path = socket.assigns[:back_path] || ~p"/org/products"
        organization_id = socket.assigns.current_scope.organization_id

        socket =
          socket
          |> put_flash(:info, "Product updated.")
          |> stream_insert(:products, build_row(organization_id, product))

        if back_path == ~p"/org/products" do
          {:noreply, push_patch(socket, to: back_path)}
        else
          {:noreply, push_navigate(socket, to: back_path)}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :product))}
    end
  end

  defp back_path(%{"return_to" => "onboarding"}, _default), do: ~p"/onboarding"
  defp back_path(%{"return_to" => "dashboard"}, _default), do: ~p"/org/dashboard"
  defp back_path(_params, default), do: default

  defp reload_products(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page
    search = socket.assigns.search
    filters = socket.assigns.filters

    opts = [
      search: search,
      category: filters.category,
      is_otc: filters.is_otc,
      is_dangerous_drug: filters.is_dangerous_drug
    ]

    page_result = Products.list_products_paginated(organization_id, page, opts)

    all_products = Products.list_products(organization_id)

    categories =
      all_products
      |> distinct_categories()

    product_ids = Enum.map(page_result.entries, & &1.id)
    stock_summary = Batches.stock_summary_by_product(organization_id, product_ids)
    undispatched = Batches.undispatched_summary_by_product(organization_id, product_ids)
    batch_counts = Batches.batch_counts_by_product(organization_id, product_ids)

    rows =
      Enum.map(page_result.entries, fn product ->
        build_stock_row(product, stock_summary, undispatched, batch_counts)
      end)

    socket
    |> assign(:categories, categories)
    |> assign(:page_info, page_result)
    |> stream(:products, rows, reset: true)
  end

  defp uom_label(1, uom), do: uom
  defp uom_label(_count, nil), do: nil
  defp uom_label(_count, uom), do: pluralize(uom)

  defp pluralize(word) do
    cond do
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) -> word <> "es"
      String.match?(word, ~r/[^aeiou]y$/i) -> String.slice(word, 0..-2//1) <> "ies"
      true -> word <> "s"
    end
  end

  defp stock_level(_total, nil), do: nil
  defp stock_level(total, _reorder_level) when total <= 0, do: :out_of_stock
  defp stock_level(total, reorder_level) when total <= reorder_level, do: :low_stock
  defp stock_level(_total, _reorder_level), do: nil

  defp build_row(organization_id, product) do
    stock_summary = Batches.stock_summary_by_product(organization_id, [product.id])
    undispatched = Batches.undispatched_summary_by_product(organization_id, [product.id])
    batch_counts = Batches.batch_counts_by_product(organization_id, [product.id])
    build_stock_row(product, stock_summary, undispatched, batch_counts)
  end

  # "Org-wide stock" is every unit the org has on record for the product: in the
  # warehouse awaiting dispatch, received at a site, or dispatched but not yet
  # confirmed received. The breakdown is kept alongside so the single number
  # can be explained (tooltip) rather than mistaken for "ready to dispense."
  defp build_stock_row(product, stock_summary, undispatched, batch_counts) do
    site_summary = Map.get(stock_summary, product.id, %{})
    awaiting_dispatch = Map.get(undispatched, product.id, 0)
    received_at_sites = Map.get(site_summary, :received_remaining, 0)
    in_transit = Map.get(site_summary, :pending_remaining, 0)
    total_stock = awaiting_dispatch + received_at_sites + in_transit

    %{
      id: product.id,
      product: product,
      total_stock: total_stock,
      batch_count: Map.get(batch_counts, product.id, 0),
      stock_level: stock_level(total_stock, product.reorder_level)
    }
  end

  defp distinct_categories(products) do
    products
    |> Enum.map(& &1.category)
    |> Enum.filter(& &1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp active_filter_count(filters) do
    Enum.count([filters.category != "", filters.is_otc, filters.is_dangerous_drug], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.category != "" && %{label: "Category: #{filters.category}", field: "category"},
      filters.is_otc && %{label: "OTC", field: "is_otc"},
      filters.is_dangerous_drug && %{label: "Dangerous drug", field: "is_dangerous_drug"}
    ]
    |> Enum.filter(& &1)
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "(unnamed)"

  defp onboarding_inventory_mode(%{onboarding_inventory_mode: mode})
       when mode in [:manual, :import],
       do: mode

  defp onboarding_inventory_mode(%{onboarding_products: []}), do: :choice
  defp onboarding_inventory_mode(_assigns), do: :manual

  defp onboarding_product_page(products, page) do
    page = clamp_onboarding_product_page(page, products)

    Enum.slice(
      products,
      (page - 1) * @onboarding_catalog_page_size,
      @onboarding_catalog_page_size
    )
  end

  defp onboarding_product_total_pages(products) do
    max(ceil(length(products) / @onboarding_catalog_page_size), 1)
  end

  defp clamp_onboarding_product_page(page, products) do
    page |> max(1) |> min(onboarding_product_total_pages(products))
  end

  defp reset_gtin_lookup(socket) do
    socket
    |> assign(:gtin_search, "")
    |> assign(:gtin_lookup, :idle)
  end

  defp put_scanned_gtin(socket, normalized_gtin) do
    base = socket.assigns.product || %Product{}

    changeset =
      base
      |> Product.changeset(%{})
      |> Ecto.Changeset.change(gtin: normalized_gtin)

    assign(socket, :form, to_form(changeset, as: :product))
  end

  defp merge_gtin_prefill(socket, prefill) do
    base = socket.assigns.product || %Product{}
    attrs = Map.take(prefill, [:gtin, :brand_name, :generic_name, :manufacturer, :uom])

    changeset =
      base
      |> Product.changeset(%{})
      |> Ecto.Changeset.change(attrs)

    assign(socket, :form, to_form(changeset, as: :product))
  end

  defp gtin_lookup_message({:found, _prefill}),
    do: {:info, "Match found. Review the fields below before saving."}

  defp gtin_lookup_message({:error, :not_found}),
    do: {:warning, "No match found for this GTIN. Enter the product details manually."}

  defp gtin_lookup_message({:error, :timeout}),
    do: {:warning, "Lookup timed out. Enter the product details manually."}

  defp gtin_lookup_message({:error, :provider_error}),
    do: {:warning, "Couldn't reach the lookup service. Enter the product details manually."}

  # Nothing the person filling the form can do about our credentials, so the copy
  # matches the generic outage case; the cause is in the logs.
  defp gtin_lookup_message({:error, :unauthorized}),
    do: {:warning, "Couldn't reach the lookup service. Enter the product details manually."}

  defp gtin_lookup_message(_), do: nil

  def render(assigns) do
    if assigns.live_action == :new and assigns.back_path == ~p"/onboarding" do
      render_onboarding(assigns)
    else
      render_index(assigns)
    end
  end

  defp render_onboarding(assigns) do
    ~H"""
    <.onboarding_task_shell
      flash={@flash}
      current_scope={@current_scope}
      icon="hero-cube"
      title="Add your inventory"
      description="Build your catalogue so stock can be received and dispensed."
      progress_current={elem(@onboarding_progress, 0)}
      progress_total={elem(@onboarding_progress, 1)}
    >
      <:right>
        <div
          id="onboarding-inventory-workflow"
          phx-hook=".OnboardingImportDraft"
          data-storage-key={
            "thamani-dawa:onboarding-import:#{@current_scope.organization_id}:#{@current_scope.user.id}"
          }
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".OnboardingImportDraft">
            const draftLifetime = 2 * 60 * 60 * 1000

            export default {
              mounted() {
                this.storageKey = this.el.dataset.storageKey

                this.handleEvent("save_onboarding_import", payload => {
                  const draft = {...payload, expiresAt: Date.now() + draftLifetime}
                  try { sessionStorage.setItem(this.storageKey, JSON.stringify(draft)) } catch (_error) {}
                })

                this.handleEvent("clear_onboarding_import", () => this.clearDraft())

                const draft = this.readDraft()
                if (draft) {
                  this.pushEvent("restore_onboarding_import", draft, reply => {
                    if (!reply.restored) this.clearDraft()
                  })
                }
              },

              readDraft() {
                try {
                  const draft = JSON.parse(sessionStorage.getItem(this.storageKey))
                  if (!draft || draft.version !== 1 || draft.expiresAt <= Date.now()) {
                    this.clearDraft()
                    return null
                  }
                  return draft
                } catch (_error) {
                  this.clearDraft()
                  return null
                }
              },

              clearDraft() {
                try { sessionStorage.removeItem(this.storageKey) } catch (_error) {}
              }
            }
          </script>

          <%= case onboarding_inventory_mode(assigns) do %>
            <% :choice -> %>
              <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
                How would you like to add products?
              </h2>
              <p class="mt-2 text-sm leading-6 text-thamani-pewter">
                You can always switch methods or add more later.
              </p>

              <div class="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-2">
                <button
                  id="onboarding-choose-manual"
                  type="button"
                  phx-click="choose_inventory_mode"
                  phx-value-mode="manual"
                  class="group flex flex-col items-start gap-3 rounded-2xl border-2 border-[var(--thamani-stone)] bg-td-surface p-5 text-left transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)]"
                >
                  <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_20%,white)] text-[var(--thamani-forest)]">
                    <.icon name="hero-pencil-square" class="size-5" />
                  </span>
                  <span class="text-sm font-semibold text-thamani-forest">Add manually</span>
                  <span class="text-xs leading-5 text-thamani-pewter">
                    Scan a GTIN or fill in details for one product at a time.
                  </span>
                </button>

                <button
                  id="onboarding-choose-import"
                  type="button"
                  phx-click="choose_inventory_mode"
                  phx-value-mode="import"
                  class="group flex flex-col items-start gap-3 rounded-2xl border-2 border-[var(--thamani-stone)] bg-td-surface p-5 text-left transition-all hover:-translate-y-0.5 hover:border-[var(--thamani-forest)]"
                >
                  <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_20%,white)] text-[var(--thamani-forest)]">
                    <.icon name="hero-arrow-up-tray" class="size-5" />
                  </span>
                  <span class="text-sm font-semibold text-thamani-forest">Import from Excel</span>
                  <span class="text-xs leading-5 text-thamani-pewter">
                    Bring in your whole catalogue at once from a spreadsheet.
                  </span>
                </button>
              </div>
            <% :manual -> %>
              <div class="flex items-start justify-between gap-5">
                <div>
                  <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
                    Product catalog
                  </h2>
                  <p class="mt-2 text-sm leading-6 text-thamani-pewter">
                    Products added to this organization so far.
                  </p>
                  <button
                    id="onboarding-switch-to-import"
                    type="button"
                    phx-click="choose_inventory_mode"
                    phx-value-mode="import"
                    class="mt-2 text-xs font-medium text-thamani-forest underline decoration-[color-mix(in_srgb,var(--thamani-forest)_35%,transparent)] underline-offset-4"
                  >
                    Import from Excel instead
                  </button>
                </div>
                <button
                  id="onboarding-open-product"
                  type="button"
                  phx-click="open_onboarding_product"
                  class="inline-flex min-h-11 shrink-0 items-center justify-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md"
                >
                  <.icon name="hero-plus" class="mr-2 size-4" /> Add a product
                </button>
              </div>

              <div
                :if={@onboarding_products == []}
                id="onboarding-products-empty"
                class="mt-8 flex min-h-52 flex-col items-center justify-center rounded-2xl border border-dashed border-[var(--thamani-stone)] bg-transparent px-6 text-center"
              >
                <span class="flex size-12 items-center justify-center rounded-2xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
                  <.icon name="hero-cube" class="size-6" />
                </span>
                <h3 class="mt-4 text-base font-semibold text-thamani-forest">No products yet</h3>
                <p class="mt-1 max-w-xs text-sm leading-6 text-thamani-pewter">
                  Add the first product to your catalogue.
                </p>
              </div>

              <div :if={@onboarding_products != []} id="onboarding-products-list" class="mt-6">
                <h3 class="mb-2 text-sm font-semibold text-thamani-forest">
                  Products ({length(@onboarding_products)})
                </h3>

                <div class="overflow-hidden rounded-2xl border border-[var(--thamani-stone)]">
                  <div class="grid grid-cols-[1fr_auto_auto] gap-3 bg-[color-mix(in_srgb,var(--thamani-stone)_35%,white)] px-3 py-2 text-[11px] font-medium uppercase tracking-wide text-thamani-pewter">
                    <span>Name</span>
                    <span class="w-32">GTIN</span>
                    <span class="w-20 text-right">Status</span>
                  </div>

                  <div class="divide-y divide-[var(--thamani-stone)]">
                    <div
                      :for={
                        product <-
                          onboarding_product_page(
                            @onboarding_products,
                            @onboarding_product_page
                          )
                      }
                      id={"onboarding-product-#{product.id}"}
                      class="grid grid-cols-[1fr_auto_auto] items-center gap-3 px-3 py-2"
                    >
                      <span class="min-w-0 truncate text-[13px] leading-5 text-thamani-forest">
                        {product_name(product)}
                      </span>
                      <span class="w-32 truncate text-[13px] leading-5 tabular-nums text-thamani-pewter">
                        {product.gtin}
                      </span>
                      <span class="flex w-20 justify-end">
                        <.status_badge status={if product.is_active, do: :active, else: :inactive} />
                      </span>
                    </div>
                  </div>

                  <div
                    :if={onboarding_product_total_pages(@onboarding_products) > 1}
                    id="onboarding-products-pagination"
                    class="flex items-center justify-between border-t border-[var(--thamani-stone)] bg-[color-mix(in_srgb,var(--thamani-stone)_20%,white)] px-3 py-2"
                  >
                    <button
                      id="onboarding-products-previous"
                      type="button"
                      phx-click="onboarding_product_page"
                      phx-value-page={@onboarding_product_page - 1}
                      disabled={@onboarding_product_page == 1}
                      class="inline-flex min-h-8 items-center gap-1.5 rounded-full border border-thamani-stone bg-td-surface px-3 text-xs font-medium text-thamani-forest transition-colors hover:border-thamani-forest disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      <.icon name="hero-chevron-left" class="size-3.5" /> Previous
                    </button>

                    <span class="text-xs font-medium tabular-nums text-thamani-pewter">
                      Page {@onboarding_product_page} of {onboarding_product_total_pages(
                        @onboarding_products
                      )}
                    </span>

                    <button
                      id="onboarding-products-next"
                      type="button"
                      phx-click="onboarding_product_page"
                      phx-value-page={@onboarding_product_page + 1}
                      disabled={
                        @onboarding_product_page ==
                          onboarding_product_total_pages(@onboarding_products)
                      }
                      class="inline-flex min-h-8 items-center gap-1.5 rounded-full border border-thamani-stone bg-td-surface px-3 text-xs font-medium text-thamani-forest transition-colors hover:border-thamani-forest disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Next <.icon name="hero-chevron-right" class="size-3.5" />
                    </button>
                  </div>
                </div>
              </div>
            <% :import -> %>
              <.onboarding_import_wizard
                step={@import_step}
                uploads={@uploads}
                filename={@import_filename}
                headers={@import_headers}
                rows={@import_rows}
                mapping={@import_mapping}
                preview={@import_preview}
                summary={@import_summary}
                upload_error={@import_upload_error}
              />
          <% end %>
        </div>
      </:right>

      <:footer>
        <div class="flex items-center gap-4">
          <.link
            id="onboarding-product-back"
            navigate={~p"/onboarding"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
          >
            <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
          </.link>
          <.link
            id="onboarding-product-skip"
            navigate={~p"/onboarding?skip=first_product&complete=1"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 transition-colors hover:text-[var(--thamani-forest)]"
          >
            Skip this step
          </.link>
        </div>
        <button
          :if={onboarding_inventory_mode(assigns) != :import or @import_step == :done}
          id="onboarding-product-continue"
          type="button"
          phx-click="continue_onboarding"
          class="inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg"
        >
          Continue <.icon name="hero-arrow-right" class="ml-3 size-4" />
        </button>
      </:footer>
    </.onboarding_task_shell>

    <.modal
      :if={@show_onboarding_product_form?}
      id="onboarding-product-modal"
      show
      on_cancel={JS.push("close_onboarding_product")}
    >
      <div class="space-y-6">
        <div>
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
            Add a product
          </h2>
        </div>

        <.product_form_steps
          gtin_step={@gtin_step}
          gtin_search={@gtin_search}
          gtin_lookup={@gtin_lookup}
          live_action={@live_action}
          lab_enabled={@lab_enabled}
          categories={@categories}
          units={@units}
          form={@form}
        />
      </div>
    </.modal>
    """
  end

  defp render_index(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/products"}
      crumb="Products"
    >
      <:tools>
        <.td_button
          id="product-import-button"
          variant="secondary"
          label="Import products"
          glyph="upload-simple"
          navigate={~p"/org/products/import"}
        />
        <.td_button
          id="product-new-button"
          variant="primary"
          label="Add product"
          patch={~p"/org/products/new"}
        >
          <:icon><.td_icon name="plus" /></:icon>
        </.td_button>
      </:tools>

      <section class="td-recipe td-list-page">
        <.td_page_header title="Products" />

        <div class="td-toolbar">
          <form phx-change="search" id="search-form" onsubmit="return false">
            <label class="td-search">
              <.td_icon name="magnifying-glass" />
              <input
                type="search"
                name="search"
                value={@search}
                placeholder="Search by name, GTIN, or category"
                phx-debounce="200"
                autocomplete="off"
              />
              <kbd>/</kbd>
            </label>
          </form>
          <.td_filter_menu
            id="products"
            field="category"
            label="Category"
            value={@filters.category}
            options={[{"", "Any"} | Enum.map(@categories, &{&1, &1})]}
          />
          <%!-- Kept for product_live_test, which submits #products-filters-form. --%>
          <form id="products-filters-form" phx-change="apply_filters" phx-submit="apply_filters" class="sr-only">
            <select name="filters[category]">
              <option value="" selected={@filters.category == ""}>Any</option>
              <option
                :for={category <- @categories}
                value={category}
                selected={@filters.category == category}
              >
                {category}
              </option>
            </select>
            <.input type="checkbox" name="filters[is_otc]" value={@filters.is_otc} label="Over-the-counter" />
            <.input
              type="checkbox"
              name="filters[is_dangerous_drug]"
              value={@filters.is_dangerous_drug}
              label="Dangerous drug"
            />
          </form>
          <div :if={filter_chips(@filters) != []} class="td-filter-chips">
            <span :for={chip <- filter_chips(@filters)} class="td-chip">
              {chip.label}
            </span>
            <button type="button" class="td-btn is-secondary" phx-click="clear_filters">
              Clear filters
            </button>
          </div>
        </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="product-modal"
        show
        on_cancel={
          if @back_path == ~p"/org/products",
            do: JS.patch(~p"/org/products"),
            else: JS.navigate(@back_path)
        }
      >
        <div class="space-y-6">
          <div>
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
              {if @live_action == :new, do: "Add a product", else: "Edit product"}
            </h2>
          </div>

          <.product_form_steps
            gtin_step={@gtin_step}
            gtin_search={@gtin_search}
            gtin_lookup={@gtin_lookup}
            live_action={@live_action}
            lab_enabled={@lab_enabled}
            categories={@categories}
            units={@units}
            form={@form}
          />
        </div>
      </.modal>

      <div
        :if={@page_info.total_entries == 0}
        id="products-empty"
        class="td-pad td-empty-wrap"
      >
        <div class="td-card td-empty-card">
          <%= if @search != "" or active_filter_count(@filters) > 0 do %>
            <p class="td-empty-title">No products match</p>
            <p class="td-note">Try a different search, or clear the applied filters.</p>
            <button type="button" id="products-clear-filters" class="td-btn is-secondary" phx-click="clear_filters">
              Clear filters
            </button>
          <% else %>
            <p class="td-empty-title">No products yet</p>
            <p class="td-note">Products you add will appear here.</p>
          <% end %>
        </div>
      </div>

      <table class="td-rows">
        <thead>
          <tr>
            <th>Name</th>
            <th>Category</th>
            <th>GTIN</th>
            <th class="is-num">Org-wide stock</th>
            <th class="is-num">Batches</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody id="products" phx-update="stream">
          <tr
            :for={{id, row} <- @streams.products}
            id={id}
            phx-click={JS.navigate(~p"/org/products/#{row.product.id}")}
            class="td-row-link"
          >
            <td data-label="Name">{product_name(row.product)}</td>
            <td data-label="Category">{row.product.category || "Uncategorized"}</td>
            <td data-label="GTIN" class="is-num">{row.product.gtin}</td>
            <td data-label="Org-wide stock" class="is-num">
              <span
                id={"stock-total-#{row.product.id}"}
                aria-label={"#{row.total_stock} #{uom_label(row.total_stock, row.product.uom)} in stock"}
                class={row.total_stock == 0 && "td-danger"}
              >
                {row.total_stock} {uom_label(row.total_stock, row.product.uom)}
              </span>
            </td>
            <td data-label="Batches" class="is-num">{row.batch_count}</td>
            <td data-label="Status">
              <.status_badge status={if row.product.is_active, do: :active, else: :inactive} />
            </td>
            <td>
              <div class="td-row-actions" onclick="event.stopPropagation()">
                <.td_button
                  id={"btn-add-stock-#{row.product.id}"}
                  variant="primary"
                  size="md"
                  label="Add stock"
                  navigate={~p"/org/products/#{row.product.id}/batches/new"}
                />
                <.td_button
                  id={"btn-edit-#{row.product.id}"}
                  variant="secondary"
                  label="Edit"
                  patch={~p"/org/products/#{row.product.id}/edit"}
                />
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <.pagination page={@page_info} path={~p"/org/products"} />
      </section>
    </Layouts.org_shell>
    """
  end

  attr :gtin_step, :atom, required: true
  attr :gtin_search, :string, required: true
  attr :gtin_lookup, :any, required: true
  attr :live_action, :atom, required: true
  attr :lab_enabled, :boolean, required: true
  attr :categories, :list, required: true
  attr :units, :list, required: true
  attr :form, :map, required: true

  defp product_form_steps(assigns) do
    ~H"""
    <div :if={@gtin_step == :scan} id="gtin-scan-step" class="space-y-4">
      <div class="bg-td-wash rounded-lg p-4">
        <p class="text-sm text-td-ink-2 mb-4">
          <span class="font-medium">Scan or enter the product's GTIN</span>
          to automatically fill in product details, or skip to enter everything manually.
        </p>
      </div>

      <form
        id="gtin-scan-form"
        phx-submit="scan_gtin"
        phx-change="gtin_search_change"
        class="space-y-3"
      >
        <div class="relative">
          <input
            type="text"
            name="gtin_search"
            value={@gtin_search}
            placeholder="Scan or type a GTIN (e.g., 5901234123457)"
            class="thamani-input w-full pl-4 pr-12"
            autofocus
            inputmode="numeric"
          />
          <div
            :if={@gtin_search != "" and @gtin_lookup != :searching}
            class="absolute right-3 top-1/2 -translate-y-1/2"
          >
            <div :if={@gtin_lookup == {:error, :invalid_gtin}} class="text-red-500">
              <.icon name="hero-x-circle" class="size-5" />
            </div>
          </div>
        </div>

        <div
          :if={@gtin_lookup == {:error, :invalid_gtin}}
          class="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-lg"
        >
          <.icon name="hero-exclamation-circle" class="size-5 text-red-600 mt-0.5 flex-shrink-0" />
          <p class="text-sm text-red-700">
            Please enter a valid GTIN. GTINs are numeric codes with 8, 12, 13, or 14 digits.
          </p>
        </div>

        <div class="flex gap-3">
          <.button
            type="submit"
            variant="primary"
            class="flex-1"
            disabled={@gtin_search == ""}
            phx-disable-with="Looking up..."
          >
            Look Up
          </.button>
          <.button type="button" phx-click="skip_gtin" variant="ghost">
            Skip
          </.button>
        </div>
      </form>
    </div>

    <div :if={@gtin_step == :form} class="space-y-4">
      <div
        :if={@live_action == :new and @gtin_lookup != :idle}
        class="rounded-lg border p-3"
        style={
          case @gtin_lookup do
            :searching ->
              "background-color: var(--color-td-info-tint); border-color: var(--color-td-info-line);"

            {:found, _} ->
              "background-color: var(--color-td-success-tint); border-color: var(--color-td-success-line);"

            {:error, _} ->
              "background-color: var(--color-td-danger-tint); border-color: var(--color-td-danger-line);"

            _ ->
              ""
          end
        }
      >
        <div :if={@gtin_lookup == :searching} class="flex items-center gap-2">
          <.icon name="hero-arrow-path" class="size-4 text-blue-600 motion-safe:animate-spin" />
          <p class="text-sm text-blue-700 font-medium">Looking up GTIN details...</p>
        </div>
        <% message = gtin_lookup_message(@gtin_lookup) %>
        <div :if={message} class="flex items-start gap-2">
          <div>
            <.icon
              name={
                case elem(message, 0) do
                  :info -> "hero-check-circle"
                  :warning -> "hero-exclamation-triangle"
                end
              }
              class={
                if elem(message, 0) == :info,
                  do: "size-5 text-green-600 mt-0.5",
                  else: "size-5 text-amber-600 mt-0.5"
              }
            />
          </div>
          <p
            class="text-sm"
            style={
              if elem(message, 0) == :info,
                do: "color: var(--color-td-success); font-weight: 500;",
                else: "color: var(--color-td-warning);"
            }
          >
            {elem(message, 1)}
          </p>
        </div>
      </div>

      <.form for={@form} id="product-form" phx-submit="save" phx-change="validate" class="space-y-4">
        <div class="grid grid-cols-2 gap-4">
          <.input field={@form[:price]} type="number" label="Price" min="0" required />
          <.input
            field={@form[:uom]}
            type="select"
            label="Unit of measure"
            options={@units}
            prompt="Select a unit"
            required
          />
        </div>

        <div class="space-y-2">
          <label class="block">
            <span class="text-sm font-medium text-td-ink">
              Product Name <span class="text-red-500">*</span>
            </span>
            <span class="text-xs text-td-ink-2 ml-1">(at least generic or brand name)</span>
          </label>
          <div class="grid grid-cols-2 gap-4">
            <.input
              field={@form[:generic_name]}
              label="Generic name"
              placeholder="e.g., Ibuprofen"
            />
            <.input field={@form[:brand_name]} label="Brand name" placeholder="e.g., Advil" />
          </div>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <.input
            field={@form[:category]}
            type="combobox"
            label="Category"
            options={@categories}
            placeholder="e.g., Analgesic"
          />
          <.input
            field={@form[:manufacturer]}
            label="Manufacturer"
            placeholder="e.g., ABC Pharma"
          />
        </div>

        <.input
          :if={@lab_enabled}
          field={@form[:inventory_type]}
          type="select"
          label="Inventory type"
          options={[{"Medicine", :medicine}, {"Lab consumable", :lab_consumable}]}
          required
        />

        <.input field={@form[:gtin]} label="GTIN" required placeholder="e.g., 5901234123457" />

        <.input field={@form[:reorder_level]} type="number" label="Reorder level" min="0" />

        <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
          <div>
            <p class="text-sm font-medium text-thamani-forest">Active</p>
            <p class="text-xs text-thamani-pewter">Enable this product for orders</p>
          </div>
          <.input
            field={@form[:is_active]}
            type="checkbox"
            label=""
            class="size-5 rounded accent-thamani-forest cursor-pointer"
          />
        </div>

        <div class="rounded-xl border border-thamani-stone overflow-hidden divide-y divide-thamani-stone mb-3">
          <div class="flex items-center justify-between px-4 py-3">
            <p class="text-sm font-medium text-thamani-forest">Over-the-counter</p>
            <.input
              field={@form[:is_otc]}
              type="checkbox"
              label=""
              class="size-5 rounded accent-thamani-forest cursor-pointer"
            />
          </div>
          <div class="flex items-center justify-between px-4 py-3">
            <p class="text-sm font-medium text-thamani-forest">Dangerous drug</p>
            <.input
              field={@form[:is_dangerous_drug]}
              type="checkbox"
              label=""
              class="size-5 rounded accent-thamani-forest cursor-pointer"
            />
          </div>
        </div>

        <div class="pt-4">
          <.button variant="primary" class="w-full">Save Product</.button>
        </div>
      </.form>
    </div>
    """
  end

  defp import_status_label(:valid), do: "Ready"
  defp import_status_label(:duplicate_in_file), do: "Duplicate in file"
  defp import_status_label(:exists_in_catalogue), do: "Already in catalogue, skipped"

  defp import_status_classes(:valid), do: "bg-green-50 text-green-700 border-green-200"

  defp import_status_classes(status) when status in [:duplicate_in_file, :exists_in_catalogue],
    do: "bg-amber-50 text-amber-700 border-amber-200"

  defp import_row_name(attrs), do: attrs["generic_name"] || attrs["brand_name"] || "(unnamed)"

  defp import_row_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} ->
      "#{import_field_label(field)} #{Enum.join(messages, ", ")}"
    end)
  end

  defp import_valid_count(preview), do: Enum.count(preview, &(&1.status == :valid))
  defp import_preview_limit, do: @import_preview_limit

  defp import_issue_count(preview), do: Enum.count(preview, &(&1.status == :invalid))

  defp import_skipped_count(preview) do
    Enum.count(preview, &(&1.status in [:duplicate_in_file, :exists_in_catalogue]))
  end

  defp import_error_summary(preview) do
    preview
    |> Enum.filter(&(&1.status == :invalid))
    |> Enum.map(&import_row_errors(&1.changeset))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {message, count} -> {-count, message} end)
  end

  defp import_issue_rows(preview) do
    preview |> Enum.filter(&(&1.status == :invalid)) |> Enum.take(import_preview_limit())
  end

  defp import_field_label(:gtin), do: "GTIN"

  defp import_field_label(field) do
    field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp import_step_number(:upload), do: 1
  defp import_step_number(:map), do: 2
  defp import_step_number(step) when step in [:preview, :done], do: 3

  defp import_step_state(current_step, index) do
    cond do
      index < import_step_number(current_step) -> :done
      index == import_step_number(current_step) -> :current
      true -> :upcoming
    end
  end

  defp import_error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp import_error_to_string(:too_many_files), do: "Choose only one file."
  defp import_error_to_string(:not_accepted), do: "Must be a CSV file."
  defp import_error_to_string(_), do: "Couldn't accept this file."

  defp import_upload_ready?(upload_config) do
    upload_config.entries != [] and
      Enum.all?(upload_config.entries, &(upload_errors(upload_config, &1) == []))
  end

  attr :step, :atom, required: true
  attr :uploads, :map, required: true
  attr :filename, :string, default: nil
  attr :headers, :list, default: nil
  attr :rows, :list, default: nil
  attr :mapping, :map, default: nil
  attr :preview, :list, default: nil
  attr :summary, :map, default: nil
  attr :upload_error, :string, default: nil

  defp onboarding_import_wizard(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
          Import from Excel
        </h2>
        <button
          :if={@step != :done}
          id="onboarding-import-back-to-choice"
          type="button"
          phx-click="back_to_inventory_choice"
          class="shrink-0 text-xs font-medium text-thamani-pewter underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 hover:text-thamani-forest"
        >
          Choose a different method
        </button>
      </div>

      <div class="mt-5 flex items-center gap-3 border-b border-thamani-stone pb-5">
        <.import_wizard_step_item index={1} label="Upload file" state={import_step_state(@step, 1)} />
        <div class="h-px flex-1 bg-thamani-stone" />
        <.import_wizard_step_item index={2} label="Map columns" state={import_step_state(@step, 2)} />
        <div class="h-px flex-1 bg-thamani-stone" />
        <.import_wizard_step_item
          index={3}
          label="Review & import"
          state={import_step_state(@step, 3)}
        />
      </div>

      <div :if={@step == :upload} class="mt-6 space-y-4">
        <form
          id="onboarding-import-upload-form"
          phx-submit="onboarding_import_upload"
          phx-change="onboarding_import_validate"
          class="flex flex-col gap-4"
        >
          <div
            class="group relative flex flex-col items-center justify-center gap-3 rounded-xl border-2 border-dashed border-thamani-stone bg-thamani-surface px-8 py-12 text-center transition-colors hover:border-thamani-forest/40 hover:bg-thamani-canvas"
            phx-drop-target={@uploads.onboarding_csv_file.ref}
          >
            <span class="flex size-12 items-center justify-center rounded-full bg-td-accent-tint text-thamani-forest">
              <.icon name="hero-arrow-up-tray" class="size-6" />
            </span>
            <div>
              <p class="text-sm font-medium text-thamani-forest">
                <span class="font-semibold text-thamani-forest underline">Click to upload</span>
                or drag and drop
              </p>
              <p class="mt-1 text-xs text-thamani-pewter">CSV only, up to 5MB.</p>
            </div>
            <.live_file_input
              upload={@uploads.onboarding_csv_file}
              class="absolute inset-0 size-full cursor-pointer opacity-0"
              aria-label="Choose a CSV file"
            />

            <div :for={entry <- @uploads.onboarding_csv_file.entries} class="w-full text-left">
              <div class="flex items-center justify-between rounded-lg border border-thamani-stone bg-td-surface px-3 py-2">
                <span class="flex items-center gap-2 truncate text-sm text-thamani-forest">
                  <.icon name="hero-document-text" class="size-4 shrink-0 text-thamani-forest/70" />
                  {entry.client_name}
                </span>
                <button
                  type="button"
                  phx-click="onboarding_cancel_upload"
                  phx-value-ref={entry.ref}
                  class="relative z-10 shrink-0 text-xs font-medium text-red-600"
                >
                  Remove
                </button>
              </div>
              <p
                :for={err <- upload_errors(@uploads.onboarding_csv_file, entry)}
                class="mt-1 text-xs text-red-700"
              >
                {import_error_to_string(err)}
              </p>
            </div>
          </div>

          <p :if={@upload_error} class="text-sm text-red-700">{@upload_error}</p>

          <.button
            :if={import_upload_ready?(@uploads.onboarding_csv_file)}
            type="submit"
            variant="primary"
          >
            Continue
          </.button>
        </form>

        <div class="flex items-center justify-between gap-4 rounded-xl bg-thamani-stone/40 p-4">
          <div class="flex items-center gap-3">
            <span class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-td-surface text-thamani-forest ring-1 ring-thamani-stone">
              <.icon name="hero-table-cells" class="size-5" />
            </span>
            <div>
              <p class="text-sm font-medium text-thamani-forest">Need a starting point?</p>
              <p class="text-xs text-thamani-pewter">
                Download our template with the columns we recognise.
              </p>
            </div>
          </div>
          <.button variant="ghost" href={~p"/org/products/import/template"}>
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download template
          </.button>
        </div>
      </div>

      <div :if={@step == :map} class="mt-6 space-y-4">
        <div>
          <p class="text-base font-semibold text-thamani-forest">Map your columns</p>
          <p class="text-sm text-thamani-pewter">
            Match each of our fields to a column from your file. Fields marked required must be mapped to continue.
          </p>
        </div>

        <div class="rounded-xl bg-thamani-stone/40 p-4">
          <p class="flex items-center gap-2 text-sm font-semibold text-thamani-forest">
            <.icon name="hero-table-cells" class="size-4.5 text-thamani-forest/70" /> File preview
          </p>
          <p class="mt-1 truncate text-xs text-thamani-pewter" title={@filename}>{@filename}</p>
          <p class="text-xs text-thamani-pewter">
            {length(@rows)} rows &bull; {length(@headers)} columns
          </p>

          <div class="mt-3 overflow-x-auto rounded-lg border border-thamani-stone bg-td-surface">
            <table class="text-xs">
              <thead class="bg-thamani-stone/40 text-left font-medium text-thamani-forest">
                <tr>
                  <th :for={header <- @headers} class="whitespace-nowrap px-2.5 py-1.5">
                    {header}
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone">
                <tr :for={row <- Enum.take(@rows, 10)}>
                  <td :for={cell <- row} class="max-w-32 truncate px-2.5 py-1.5 text-thamani-pewter">
                    {cell}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={length(@rows) > 10} class="mt-1.5 text-xs text-thamani-pewter">
            + {length(@rows) - 10} more rows
          </p>
        </div>

        <form id="onboarding-mapping-form" phx-submit="onboarding_confirm_mapping">
          <div class="overflow-hidden rounded-xl border border-thamani-stone">
            <table class="w-full text-sm">
              <thead class="bg-thamani-stone/40 text-left text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="px-4 py-2.5">Product field (in system)</th>
                  <th class="px-4 py-2.5">Column from your file</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone bg-td-surface">
                <tr :for={field <- Importer.fields()}>
                  <td class="px-4 py-2.5 text-sm font-medium text-thamani-forest">
                    {field.label}
                    <span :if={field.required} class="text-red-600">&nbsp;*</span>
                  </td>
                  <td class="px-4 py-2.5">
                    <select
                      name={"mapping[#{field.key}]"}
                      class="thamani-input w-full"
                      required={field.required}
                    >
                      <option value="" selected={is_nil(Map.get(@mapping, field.key))}>
                        Not in file
                      </option>
                      <option
                        :for={header <- @headers}
                        value={header}
                        selected={Map.get(@mapping, field.key) == header}
                      >
                        {header}
                      </option>
                    </select>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div class="flex gap-3 pt-4">
            <.button type="submit" variant="primary">Preview import</.button>
            <.button type="button" variant="ghost" phx-click="onboarding_start_over">
              Start over
            </.button>
          </div>
        </form>
      </div>

      <div :if={@step == :preview} class="mt-6 space-y-4">
        <div class="grid grid-cols-3 gap-3" id="onboarding-import-summary">
          <div class="rounded-xl border border-green-200 bg-green-50 px-4 py-3">
            <p class="text-2xl font-semibold tabular-nums text-green-800">
              {import_valid_count(@preview)}
            </p>
            <p class="text-xs font-medium text-green-700">Ready</p>
          </div>
          <div class="rounded-xl border border-red-200 bg-red-50 px-4 py-3">
            <p class="text-2xl font-semibold tabular-nums text-red-800">
              {import_issue_count(@preview)}
            </p>
            <p class="text-xs font-medium text-red-700">Have issues</p>
          </div>
          <div class="rounded-xl border border-amber-200 bg-amber-50 px-4 py-3">
            <p class="text-2xl font-semibold tabular-nums text-amber-800">
              {import_skipped_count(@preview)}
            </p>
            <p class="text-xs font-medium text-amber-700">Skipped</p>
          </div>
        </div>

        <div
          :if={import_issue_count(@preview) > 0}
          id="onboarding-import-errors"
          class="rounded-xl border border-red-200 bg-red-50/60 p-4"
        >
          <p class="text-sm font-semibold text-red-800">Errors found</p>
          <ul class="mt-2 space-y-1.5 text-sm text-red-700">
            <li
              :for={{message, count} <- import_error_summary(@preview)}
              class="flex justify-between gap-4"
            >
              <span>{message}</span>
              <span class="shrink-0 font-medium tabular-nums">
                {count} {if(count == 1, do: "row", else: "rows")}
              </span>
            </li>
          </ul>
        </div>

        <p class="text-sm text-thamani-pewter">
          Rows with errors or already in your catalogue will be skipped.
        </p>

        <div :if={import_issue_count(@preview) > 0} class="space-y-2">
          <div class="flex items-end justify-between gap-4">
            <div>
              <h3 class="text-sm font-semibold text-thamani-forest">Rows to fix</h3>
              <p class="text-xs text-thamani-pewter">
                Use the original spreadsheet row number to locate and correct each product.
              </p>
            </div>
            <span class="shrink-0 text-xs font-medium text-red-700">
              Showing {min(import_issue_count(@preview), import_preview_limit())} of {import_issue_count(
                @preview
              )}
            </span>
          </div>

          <div class="overflow-x-auto rounded-xl border border-red-200">
            <table class="w-full text-sm">
              <thead class="bg-red-50/70 text-left text-xs font-medium uppercase tracking-wide text-red-800">
                <tr>
                  <th class="px-3 py-2">Row number</th>
                  <th class="px-3 py-2">Product</th>
                  <th class="px-3 py-2">GTIN</th>
                  <th class="px-3 py-2">Issue</th>
                </tr>
              </thead>
              <tbody id="onboarding-import-issue-rows" class="divide-y divide-red-100 bg-td-surface">
                <tr :for={row <- import_issue_rows(@preview)}>
                  <td class="px-3 py-2 tabular-nums text-thamani-pewter">{row.index + 1}</td>
                  <td class="px-3 py-2 text-thamani-forest">{import_row_name(row.attrs)}</td>
                  <td class="px-3 py-2 tabular-nums text-thamani-pewter">
                    {row.attrs["gtin"] || "—"}
                  </td>
                  <td class="max-w-56 px-3 py-2 text-xs font-medium leading-5 text-red-700">
                    {import_row_errors(row.changeset)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="flex items-center justify-between gap-4">
          <h3 class="text-sm font-semibold text-thamani-forest">File sample</h3>
          <span class="text-xs text-thamani-pewter">
            First {min(length(@preview), import_preview_limit())} of {length(@preview)} rows
          </span>
        </div>

        <div class="overflow-x-auto rounded-xl border border-thamani-stone">
          <table class="w-full text-sm">
            <thead class="bg-thamani-canvas text-left text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              <tr>
                <th class="px-3 py-2">Row</th>
                <th class="px-3 py-2">Name</th>
                <th class="px-3 py-2">GTIN</th>
                <th class="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody id="onboarding-import-preview-rows" class="divide-y divide-thamani-stone">
              <tr :for={row <- Enum.take(@preview, import_preview_limit())}>
                <td class="px-3 py-2 tabular-nums text-thamani-pewter">{row.index}</td>
                <td class="px-3 py-2 text-thamani-forest">{import_row_name(row.attrs)}</td>
                <td class="px-3 py-2 tabular-nums text-thamani-forest">{row.attrs["gtin"]}</td>
                <td class="px-3 py-2">
                  <p
                    :if={row.status == :invalid}
                    class="max-w-48 text-xs font-medium leading-5 text-red-700"
                  >
                    {import_row_errors(row.changeset)}
                  </p>
                  <span
                    :if={row.status != :invalid}
                    class={[
                      "inline-flex whitespace-nowrap rounded-full border px-2.5 py-1 text-xs font-medium",
                      import_status_classes(row.status)
                    ]}
                  >
                    {import_status_label(row.status)}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="flex gap-3">
          <.button
            type="button"
            variant="primary"
            phx-click="onboarding_confirm_import"
            disabled={import_valid_count(@preview) == 0}
          >
            Import {import_valid_count(@preview)} products
          </.button>
          <.button type="button" variant="ghost" phx-click="onboarding_back_to_map">Back</.button>
        </div>
      </div>

      <div :if={@step == :done} class="mt-6 space-y-4">
        <div class="rounded-xl border border-green-200 bg-green-50 p-4">
          <p class="text-sm font-medium text-green-800">
            Imported {@summary.created} of {@summary.total} rows.
          </p>
        </div>
        <button
          id="onboarding-import-view-catalog"
          type="button"
          phx-click="back_to_inventory_choice"
          class="inline-flex min-h-11 items-center justify-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md"
        >
          View catalogue
        </button>
      </div>
    </div>
    """
  end

  attr :index, :integer, required: true
  attr :label, :string, required: true
  attr :state, :atom, required: true

  defp import_wizard_step_item(assigns) do
    ~H"""
    <div class="flex items-center gap-2.5">
      <span class={[
        "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-semibold",
        @state == :done && "bg-thamani-forest text-thamani-on-accent",
        @state == :current && "bg-thamani-forest text-thamani-on-accent",
        @state == :upcoming && "bg-thamani-stone text-thamani-pewter"
      ]}>
        <.icon :if={@state == :done} name="hero-check" class="size-4" />
        <span :if={@state != :done}>{@index}</span>
      </span>
      <span class={[
        "text-sm font-medium whitespace-nowrap",
        @state == :upcoming && "text-thamani-pewter",
        @state != :upcoming && "text-thamani-forest"
      ]}>
        {@label}
      </span>
    </div>
    """
  end
end
