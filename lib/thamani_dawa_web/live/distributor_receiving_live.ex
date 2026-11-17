defmodule ThamaniDawaWeb.DistributorReceivingLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawa.Suppliers
  alias ThamaniDawa.Suppliers.Supplier
  alias ThamaniDawaWeb.DistributorPagination
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    receiving_portal =
      if socket.assigns.live_action in [:distributor_index, :distributor_new],
        do: :distributor,
        else: :organization

    receiving_new? = receiving_new_action?(socket.assigns.live_action)

    {receiving_index_path, receiving_new_path} =
      if receiving_portal == :organization,
        do: {~p"/org/receiving", ~p"/org/receiving/new"},
        else: {~p"/distributor/receiving", ~p"/distributor/receiving/new"}

    # `receiving_portal` above only tells us admin vs. non-admin (it controls
    # the warehouse picker/shell, shared with the pharmacy/lab org portal).
    # Whether this *organization* actually operates as a distributor — and
    # therefore uses the live GLN-to-GLN origin flow instead of a stored
    # `Suppliers.Supplier` — is a separate, org-type question, true for a
    # distributor org's own admin on `/org/receiving` just as much as for
    # their staff on `/distributor/receiving`.
    distributor_org? =
      ThamaniDawaWeb.UserAuth.distributor_organization?(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:receiving_portal, receiving_portal)
     |> assign(:receiving_new?, receiving_new?)
     |> assign(:distributor_org?, distributor_org?)
     |> assign(:receiving_index_path, receiving_index_path)
     |> assign(:receiving_new_path, receiving_new_path)
     |> assign(:products, Products.list_products(organization_id))
     |> assign(:suppliers, Suppliers.list_suppliers(organization_id))
     |> assign(:warehouses, warehouse_sites(organization_id))
     |> assign(:receipt_step, :product)
     |> assign(:selected_product, nil)
     |> assign(:scan_error, nil)
     |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
     |> assign(:delivery_items, [])
     |> assign(:receipt_posting_key, Ecto.UUID.generate())
     |> assign(:editing_delivery_item_id, nil)
     |> assign(:new_product_form, nil)
     |> assign(:adding_supplier, false)
     |> assign(:new_supplier_form, nil)
     |> assign(:add_item_open, false)
     |> assign(:page_number, 1)
     |> assign(:checked_sscc, nil)
     |> assign(:sscc_warning, nil)
     |> assign(:is_return, false)
     |> assign(:return_disposition, "active")
     |> assign_origin_defaults()
     |> allow_upload(:doc_grn,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true
     )
     |> allow_upload(:doc_invoice,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 5_000_000,
       auto_upload: true
     )
     |> allow_upload(:doc_other,
       accept: ~w(.pdf .jpg .jpeg .png),
       max_entries: 5,
       max_file_size: 5_000_000,
       auto_upload: true
     )
     |> reload_receipts()}
  end

  defp assign_origin_defaults(socket) do
    if socket.assigns.distributor_org? do
      assign(socket, :origin_check, :idle)
    else
      assign(socket, :origin_check, nil)
    end
  end

  def handle_params(params, _url, socket) do
    receiving_new? = receiving_new_action?(socket.assigns.live_action)

    socket =
      socket
      |> assign(:receiving_new?, receiving_new?)
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> reload_receipts()

    if socket.assigns.receiving_new? do
      {:noreply,
       socket
       |> assign(:receipt_step, :product)
       |> assign(:selected_product, nil)
       |> assign(:scan_error, nil)
       |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
       |> assign(:delivery_items, [])
       |> assign(:receipt_posting_key, Ecto.UUID.generate())
       |> assign(:editing_delivery_item_id, nil)
       |> assign(:new_product_form, nil)
       |> assign(:adding_supplier, false)
       |> assign(:new_supplier_form, nil)
       |> assign(:add_item_open, false)
       |> assign(:form, nil)
       |> assign(:checked_sscc, nil)
       |> assign(:sscc_warning, nil)
       |> assign(:is_return, false)
       |> assign(:return_disposition, "active")
       |> assign_origin_defaults()}
    else
      {:noreply,
       assign(socket,
         form: nil,
         selected_product: nil,
         receipt_step: :product,
         delivery_items: [],
         receipt_posting_key: Ecto.UUID.generate(),
         editing_delivery_item_id: nil,
         new_product_form: nil,
         adding_supplier: false,
         new_supplier_form: nil,
         add_item_open: false
       )}
    end
  end

  defp receiving_new_action?(action), do: action in [:org_new, :distributor_new]

  def handle_event("open_add_item", _params, socket) do
    {:noreply, assign(socket, :add_item_open, true)}
  end

  def handle_event("close_add_item", _params, socket) do
    {:noreply,
     socket
     |> assign(:add_item_open, false)
     |> assign(:receipt_step, :product)
     |> assign(:selected_product, nil)
     |> assign(:scan_error, nil)
     |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
     |> assign(:editing_delivery_item_id, nil)
     |> assign(:new_product_form, nil)
     |> assign(:adding_supplier, false)
     |> assign(:new_supplier_form, nil)
     |> assign(:form, nil)}
  end

  def handle_event("choose_product", %{"product_id" => ""}, socket) do
    {:noreply, assign(socket, :scan_error, nil)}
  end

  def handle_event("choose_product", %{"product_id" => product_id}, socket) do
    {:noreply, select_product(socket, product_id)}
  end

  def handle_event("scan_gtin", %{"scan" => %{"gtin" => raw_code}}, socket) do
    socket = assign(socket, :scan_form, to_form(%{"gtin" => raw_code}, as: :scan))

    case resolve_scanned_product(raw_code, socket.assigns.products) do
      :incomplete -> {:noreply, assign(socket, :scan_error, nil)}
      {:ok, product} -> {:noreply, select_product(socket, product.id)}
      {:not_found, gtin} -> {:noreply, start_new_product(socket, gtin)}
      {:error, message} -> {:noreply, assign(socket, :scan_error, message)}
    end
  end

  def handle_event("change_product", _params, socket) do
    {:noreply, assign(socket, receipt_step: :product, selected_product: nil, form: nil)}
  end

  def handle_event("cancel_new_product", _params, socket) do
    {:noreply, assign(socket, receipt_step: :product, new_product_form: nil)}
  end

  def handle_event("validate_new_product", %{"product" => attrs}, socket) do
    changeset = Map.put(Product.changeset(%Product{}, attrs), :action, :validate)
    {:noreply, assign(socket, :new_product_form, to_form(changeset, as: :product))}
  end

  def handle_event("save_new_product", %{"product" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Products.create_product(organization_id, attrs) do
      {:ok, product} ->
        {:noreply,
         socket
         |> assign(:products, [product | socket.assigns.products])
         |> assign(:new_product_form, nil)
         |> select_product(product.id)}

      {:error, changeset} ->
        gtin = Ecto.Changeset.get_field(changeset, :gtin)

        case gtin && Products.get_product_by_gtin(organization_id, gtin) do
          %Product{} = product ->
            {:noreply,
             socket
             |> assign(:products, [product | socket.assigns.products])
             |> assign(:new_product_form, nil)
             |> select_product(product.id)}

          nil ->
            {:noreply, assign(socket, :new_product_form, to_form(changeset, as: :product))}
        end
    end
  end

  def handle_event("toggle_new_supplier", _params, socket) do
    {:noreply,
     socket
     |> assign(:adding_supplier, true)
     |> assign(:new_supplier_form, to_form(Suppliers.change_supplier(%Supplier{}), as: :supplier))}
  end

  def handle_event("cancel_new_supplier", _params, socket) do
    {:noreply, socket |> assign(:adding_supplier, false) |> assign(:new_supplier_form, nil)}
  end

  def handle_event("validate_new_supplier", %{"supplier" => attrs}, socket) do
    changeset = Map.put(Suppliers.change_supplier(%Supplier{}, attrs), :action, :validate)
    {:noreply, assign(socket, :new_supplier_form, to_form(changeset, as: :supplier))}
  end

  def handle_event("save_new_supplier", %{"supplier" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Suppliers.create_supplier(organization_id, attrs) do
      {:ok, supplier} ->
        batch_attrs =
          (socket.assigns.form.params || %{})
          |> Map.put("supplier_id", to_string(supplier.id))

        {:noreply,
         socket
         |> assign(:suppliers, [supplier | socket.assigns.suppliers])
         |> assign(:adding_supplier, false)
         |> assign(:new_supplier_form, nil)
         |> assign(:form, to_form(receipt_changeset(socket, batch_attrs), as: :batch))}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_supplier_form, to_form(changeset, as: :supplier))}
    end
  end

  def handle_event("add_to_delivery", %{"batch" => attrs}, socket) do
    {:noreply, add_delivery_item(normalize_sscc(attrs), socket)}
  end

  def handle_event("remove_delivery_item", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, update(socket, :delivery_items, &Enum.reject(&1, fn item -> item.id == id end))}
  end

  def handle_event("edit_delivery_item", %{"id" => id}, socket) do
    id = String.to_integer(id)
    item = Enum.find(socket.assigns.delivery_items, &(&1.id == id))
    product = item && Enum.find(socket.assigns.products, &(&1.id == item.attrs["product_id"]))

    if item && product do
      {:noreply,
       socket
       |> assign(:add_item_open, true)
       |> assign(:editing_delivery_item_id, item.id)
       |> assign(:selected_product, product)
       |> assign(:receipt_step, :details)
       |> assign(:form, to_form(receipt_changeset(socket, item.attrs), as: :batch))}
    else
      {:noreply, put_flash(socket, :error, "That staged receipt item could not be found.")}
    end
  end

  def handle_event("finish_delivery", _params, socket) do
    cond do
      socket.assigns.distributor_org? and not match?({:matched, _}, socket.assigns.origin_check) ->
        {:noreply,
         put_flash(socket, :error, "Enter a valid, verified origin GLN before finishing.")}

      uploads_in_progress?(socket) ->
        {:noreply,
         put_flash(socket, :error, "Still uploading document(s) — try again in a moment.")}

      true ->
        post_delivery(socket)
    end
  end

  def handle_event("validate_origin", %{"origin" => %{"gln" => gln}}, socket) do
    {:noreply, check_origin_gln(socket, String.trim(to_string(gln)))}
  end

  def handle_event("toggle_return", _params, socket) do
    {:noreply, update(socket, :is_return, &(!&1))}
  end

  def handle_event("set_return_disposition", %{"return_disposition" => disposition}, socket) do
    {:noreply, assign(socket, :return_disposition, disposition)}
  end

  def handle_event("validate", %{"batch" => attrs}, socket) do
    changeset = Map.put(receipt_changeset(socket, attrs), :action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :batch))
     |> maybe_lookup_sscc(Map.get(attrs, "sscc"))}
  end

  def handle_event("validate_uploads", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_doc_upload", %{"ref" => ref, "upload" => upload}, socket) do
    {:noreply, cancel_upload(socket, String.to_existing_atom(upload), ref)}
  end

  def handle_async(:origin_lookup, {:ok, {:ok, resolved}}, socket) do
    {:noreply, assign(socket, :origin_check, {:matched, resolved})}
  end

  def handle_async(:origin_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, assign(socket, :origin_check, :not_found)}
  end

  def handle_async(:origin_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :origin_check, :unavailable)}
  end

  def handle_async(:sscc_lookup, {:ok, {:ok, shipper}}, socket) do
    {:noreply, apply_shipper_prefill(socket, shipper)}
  end

  def handle_async(:sscc_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:sscc_lookup, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  defp post_delivery(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id
    origin = origin_payload(socket)

    return_opts =
      if socket.assigns.is_return,
        do: %{is_return: true, status: socket.assigns.return_disposition},
        else: %{}

    case GoodsReceipts.receive_delivery(
           organization_id,
           user_id,
           socket.assigns.delivery_items,
           socket.assigns.receipt_posting_key,
           origin,
           return_opts
         ) do
      {:ok, receipt} ->
        store_delivery_attachments(socket, receipt, user_id)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Delivery #{receipt.number} received: #{length(receipt.items)} item(s) posted to inventory."
         )
         |> push_patch(to: socket.assigns.receiving_index_path)}

      {:error, changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Delivery could not be posted: #{format_changeset_error(changeset)}"
         )}
    end
  end

  defp uploads_in_progress?(socket) do
    [:doc_grn, :doc_invoice, :doc_other]
    |> Enum.flat_map(&Map.get(socket.assigns.uploads, &1).entries)
    |> Enum.any?(&(not &1.done?))
  end

  defp store_delivery_attachments(socket, receipt, user_id) do
    for {upload_name, doc_type} <- [
          {:doc_grn, :grn},
          {:doc_invoice, :invoice},
          {:doc_other, :other}
        ] do
      consume_uploaded_entries(socket, upload_name, fn %{path: tmp_path}, entry ->
        GoodsReceipts.store_attachment!(receipt, doc_type, tmp_path, entry, user_id)
        {:ok, :stored}
      end)
    end
  end

  defp origin_payload(%{assigns: %{origin_check: {:matched, resolved}}}), do: resolved
  defp origin_payload(_socket), do: nil

  defp check_origin_gln(socket, gln) do
    if Regex.match?(~r/^\d{13}$/, gln) do
      socket
      |> assign(:origin_check, :checking)
      |> start_async(:origin_lookup, fn -> GlnLookup.resolve_party(gln) end)
    else
      assign(socket, :origin_check, :idle)
    end
  end

  defp maybe_lookup_sscc(socket, sscc) when is_binary(sscc) do
    sscc = String.trim(sscc)

    cond do
      not socket.assigns.distributor_org? ->
        socket

      sscc == socket.assigns.checked_sscc ->
        socket

      not Regex.match?(~r/^\d{18}$/, sscc) ->
        socket

      true ->
        socket
        |> assign(:checked_sscc, sscc)
        |> start_async(:sscc_lookup, fn -> Distributor.lookup_shipper_by_sscc(sscc) end)
    end
  end

  defp maybe_lookup_sscc(socket, _sscc), do: socket

  defp apply_shipper_prefill(socket, shipper) do
    socket
    |> maybe_prefill_origin(shipper.shipment)
    |> maybe_warn_destination_mismatch(shipper.shipment)
    |> prefill_shipper_items(shipper)
  end

  defp maybe_prefill_origin(socket, %{origin_gln: origin_gln} = shipment)
       when is_binary(origin_gln) do
    if match?({:matched, _}, socket.assigns.origin_check) do
      socket
    else
      resolved = %{
        gln: shipment.origin_gln,
        company: shipment.origin_company,
        address: shipment.origin_address,
        po_box: shipment.origin_po_box,
        site_id: shipment.origin_site_id
      }

      assign(socket, :origin_check, {:matched, resolved})
    end
  end

  defp maybe_prefill_origin(socket, _shipment), do: socket

  defp maybe_warn_destination_mismatch(socket, %{destination_gln: destination_gln})
       when is_binary(destination_gln) do
    receiving_site = current_receiving_site(socket)

    if receiving_site && receiving_site.gln != destination_gln do
      assign(
        socket,
        :sscc_warning,
        "This case was shipped to a different location (destination GLN #{destination_gln})."
      )
    else
      assign(socket, :sscc_warning, nil)
    end
  end

  defp maybe_warn_destination_mismatch(socket, _shipment), do: socket

  defp current_receiving_site(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    site_id =
      (socket.assigns.form && socket.assigns.form.params["site_id"]) ||
        SiteScoping.default_site_id(socket.assigns.current_scope)

    site_id && Sites.get_site!(organization_id, site_id)
  rescue
    Ecto.NoResultsError -> nil
  end

  defp prefill_shipper_items(socket, %{gtin: gtin} = shipper) when is_binary(gtin) do
    product = Enum.find(socket.assigns.products, &(&1.gtin == gtin))

    attrs = %{
      "product_id" => product && product.id,
      "gtin" => gtin,
      "batch_no" => shipper.batch,
      "manufacture_date" => shipper.production_date,
      "expiry_date" => shipper.expiry_date,
      "quantity" => shipper.unit_count,
      "sscc" => shipper.sscc
    }

    attrs =
      case {socket.assigns.warehouses, SiteScoping.default_site_id(socket.assigns.current_scope)} do
        {[warehouse], _site_id} -> Map.put(attrs, "site_id", warehouse.id)
        {_warehouses, site_id} when not is_nil(site_id) -> Map.put(attrs, "site_id", site_id)
        _ -> attrs
      end

    if product do
      socket
      |> assign(:selected_product, product)
      |> assign(:receipt_step, :details)
      |> assign(:form, to_form(receipt_changeset(socket, attrs), as: :batch))
    else
      socket
    end
  end

  defp prefill_shipper_items(socket, %{items: items}) when items != [] do
    site_id =
      case {socket.assigns.warehouses, SiteScoping.default_site_id(socket.assigns.current_scope)} do
        {[warehouse], _site_id} -> warehouse.id
        {_warehouses, site_id} -> site_id
      end

    grouped =
      items
      |> Enum.group_by(&{&1.gtin, &1.batch, &1.production_date, &1.expiry_date})
      |> Enum.map(fn {{gtin, batch, production_date, expiry_date}, group} ->
        product = Enum.find(socket.assigns.products, &(&1.gtin == gtin))
        first = hd(group)

        attrs = %{
          "product_id" => product && product.id,
          "gtin" => gtin,
          "batch_no" => batch,
          "manufacture_date" => production_date,
          "expiry_date" => expiry_date,
          "quantity" => length(group),
          "sscc" => socket.assigns.checked_sscc,
          "site_id" => site_id
        }

        %{
          id: System.unique_integer([:positive]),
          attrs: attrs,
          product_name:
            (product && (product.generic_name || product.brand_name)) || first.product_name ||
              "Unknown product",
          quantity: length(group),
          batch_no: batch,
          uom: product && product.uom
        }
      end)

    update(socket, :delivery_items, &(&1 ++ grouped))
  end

  defp prefill_shipper_items(socket, _shipper), do: socket

  defp resolve_scanned_product(raw_code, products) do
    trimmed = String.trim(raw_code)

    if trimmed == "" or String.length(trimmed) < 8 do
      :incomplete
    else
      case scanned_gtin(raw_code) do
        {:ok, gtin} -> lookup_product_gtin(products, gtin)
        {:error, _reason} -> {:error, "Enter or scan a valid GTIN."}
      end
    end
  end

  defp lookup_product_gtin(products, gtin) do
    case Enum.find(products, &(&1.gtin == gtin)) do
      nil -> {:not_found, gtin}
      product -> {:ok, product}
    end
  end

  defp start_new_product(socket, gtin) do
    socket
    |> assign(:receipt_step, :new_product)
    |> assign(:scan_error, nil)
    |> assign(
      :new_product_form,
      to_form(Product.changeset(%Product{}, %{"gtin" => gtin}), as: :product)
    )
  end

  defp add_delivery_item(attrs, socket) do
    product = socket.assigns.selected_product

    attrs =
      attrs
      |> Map.put("product_id", product && product.id)
      |> Map.put("gtin", product && product.gtin)

    changeset = receipt_changeset(socket, attrs)
    quantity = Ecto.Changeset.get_field(changeset, :quantity)

    if changeset.valid? and is_integer(quantity) and quantity > 0 do
      stage_delivery_item(socket, product, attrs, quantity)
    else
      show_delivery_item_errors(socket, changeset, quantity)
    end
  end

  defp stage_delivery_item(socket, product, attrs, quantity) do
    item = %{
      id: socket.assigns.editing_delivery_item_id || System.unique_integer([:positive]),
      attrs: attrs,
      product_name: product_name(socket.assigns.products, product.id),
      quantity: quantity,
      batch_no: Map.get(attrs, "batch_no"),
      uom: product.uom
    }

    delivery_items =
      case socket.assigns.editing_delivery_item_id do
        nil -> socket.assigns.delivery_items ++ [item]
        editing_id -> replace_delivery_item(socket.assigns.delivery_items, editing_id, item)
      end

    socket
    |> assign(:delivery_items, delivery_items)
    |> assign(:receipt_step, :product)
    |> assign(:selected_product, nil)
    |> assign(:editing_delivery_item_id, nil)
    |> assign(:form, nil)
    |> assign(:scan_error, nil)
    |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
    |> assign(:add_item_open, false)
  end

  defp replace_delivery_item(items, editing_id, item) do
    Enum.map(items, fn existing ->
      if existing.id == editing_id, do: item, else: existing
    end)
  end

  defp show_delivery_item_errors(socket, changeset, quantity) do
    changeset =
      if is_integer(quantity) and quantity <= 0 do
        Ecto.Changeset.add_error(changeset, :quantity, "must be greater than zero")
      else
        changeset
      end

    changeset = Map.put(changeset, :action, :validate)
    assign(socket, :form, to_form(changeset, as: :batch))
  end

  defp select_product(socket, product_id) do
    product_id = to_string(product_id)
    product = Enum.find(socket.assigns.products, &(to_string(&1.id) == product_id))

    if product do
      attrs = %{
        "product_id" => product.id,
        "gtin" => product.gtin,
        "manufacturer" => product.manufacturer
      }

      attrs =
        case {socket.assigns.warehouses,
              SiteScoping.default_site_id(socket.assigns.current_scope)} do
          {[warehouse], _site_id} -> Map.put(attrs, "site_id", warehouse.id)
          {_warehouses, site_id} when not is_nil(site_id) -> Map.put(attrs, "site_id", site_id)
          _ -> attrs
        end

      socket
      |> assign(:selected_product, product)
      |> assign(:receipt_step, :details)
      |> assign(:scan_error, nil)
      |> assign(:form, to_form(receipt_changeset(socket, attrs), as: :batch))
    else
      assign(socket, :scan_error, "Choose a valid catalog product.")
    end
  end

  defp normalize_sscc(attrs) do
    case Map.get(attrs, "sscc") do
      nil -> attrs
      raw -> Map.put(attrs, "sscc", extract_sscc(raw))
    end
  end

  # Accepts either a bare 18-digit SSCC or a full GS1 case-label scan
  # (e.g. `00<sscc>` or a DataMatrix payload); anything else is handed to the
  # batch changeset as-is so its validation produces the visible error.
  defp extract_sscc(raw) do
    trimmed = String.trim(raw)

    case ThamaniDawa.GS1Decoder.parse(trimmed) do
      {:ok, %{sscc: sscc}} when is_binary(sscc) -> sscc
      _ -> trimmed
    end
  end

  defp scanned_gtin(raw_code) do
    raw_code = String.trim(raw_code)

    case ThamaniDawa.GS1Decoder.parse(raw_code) do
      {:ok, %{gtin: gtin}} when is_binary(gtin) -> ThamaniDawa.Gtin.normalize(gtin)
      _ -> ThamaniDawa.Gtin.normalize(raw_code)
    end
  end

  # A site currently selected (via the sidebar switcher) means the receipt
  # posts straight to that site — the same inference used everywhere else
  # a site is picked for the session. Only when receiving org-wide (no site
  # selected — "Manage organization") does stock land in the org-level
  # pool, awaiting an explicit dispatch to a site later.
  defp receipt_changeset(socket, attrs) do
    changeset =
      if is_nil(SiteScoping.default_site_id(socket.assigns.current_scope)) do
        Batch.org_intake_changeset(%Batch{}, Map.delete(attrs, "site_id"))
      else
        Batch.changeset(%Batch{}, attrs)
      end

    # A distributor org's origin party is resolved once for the whole
    # receipt (see `origin_check`/`origin_payload`), not picked per line —
    # every other org type still requires a `Suppliers.Supplier` per item.
    required_fields =
      if socket.assigns.distributor_org?, do: [:sscc], else: [:supplier_id, :sscc]

    Ecto.Changeset.validate_required(changeset, required_fields,
      message: "is required for a delivery receipt"
    )
  end

  defp format_changeset_error(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp reload_receipts(socket) do
    receipts =
      socket.assigns.current_scope.organization_id
      |> GoodsReceipts.list_receipts()
      |> filter_current_warehouse(socket.assigns.current_scope)

    page_info = DistributorPagination.page(receipts, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:receipts, page_info.entries, reset: true)
  end

  defp filter_current_warehouse(receipts, %Scope{current_site_id: nil}), do: receipts

  defp filter_current_warehouse(receipts, %Scope{current_site_id: site_id}) do
    Enum.filter(receipts, &Enum.any?(&1.items, fn item -> item.site_id == site_id end))
  end

  defp warehouse_sites(organization_id) do
    organization_id
    |> Sites.list_sites()
    |> Enum.filter(&(Site.distribution?(&1) and &1.is_active))
  end

  defp product_name(products, product_id) do
    case Enum.find(products, &(&1.id == product_id)) do
      nil -> "Unknown product"
      product -> product.generic_name || product.brand_name
    end
  end

  defp unit_label(nil), do: "unit(s)"
  defp unit_label("H87"), do: "piece(s)"
  defp unit_label("U2"), do: "tablet(s)"
  defp unit_label("C62"), do: "unit(s)"
  defp unit_label(unit), do: if(String.ends_with?(unit, "(s)"), do: unit, else: "#{unit}(s)")

  defp receipt_supplier(%{origin_gln: origin_gln} = receipt) when is_binary(origin_gln) do
    receipt.origin_company || "—"
  end

  defp receipt_supplier(receipt) do
    receipt.items
    |> Enum.map(& &1.supplier_id)
    |> Enum.uniq()
    |> case do
      [nil] ->
        "—"

      [_supplier_id] ->
        receipt.items |> hd() |> Map.get(:supplier) |> then(&if(&1, do: &1.name, else: "—"))

      _ ->
        "Multiple suppliers"
    end
  end

  defp receipt_warehouse(receipt) do
    receipt.items
    |> Enum.map(& &1.site_id)
    |> Enum.uniq()
    |> case do
      [_site_id] ->
        receipt.items |> hd() |> Map.get(:site) |> then(&if(&1, do: &1.name, else: "—"))

      _ ->
        "Multiple warehouses"
    end
  end

  defp origin_gln_value({:matched, resolved}), do: resolved.gln
  defp origin_gln_value(_origin_check), do: nil

  defp doc_upload_error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp doc_upload_error_to_string(:too_many_files), do: "Choose fewer files."
  defp doc_upload_error_to_string(:not_accepted), do: "Must be a PDF or image file."
  defp doc_upload_error_to_string(_), do: "Couldn't accept this file."

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :upload, :map, required: true

  defp doc_upload_slot(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-semibold uppercase tracking-wide text-thamani-subtle">{@label}</p>
      <div
        class="mt-1 flex flex-col gap-2 rounded-lg border border-dashed border-thamani-stone bg-thamani-canvas p-3"
        phx-drop-target={@upload.ref}
      >
        <label class="cursor-pointer text-xs font-semibold text-thamani-forest hover:underline">
          Choose file(s) <.live_file_input upload={@upload} class="sr-only" />
        </label>
        <p class="text-[11px] text-thamani-subtle">
          PDF, JPG, or PNG · up to 5MB{if @upload.max_entries > 1,
            do: " each, up to #{@upload.max_entries} files"}
        </p>
        <div :for={entry <- @upload.entries}>
          <div class="flex items-center justify-between gap-2">
            <span class="truncate text-xs text-thamani-pewter" title={entry.client_name}>
              {entry.client_name}
            </span>
            <button
              type="button"
              phx-click="cancel_doc_upload"
              phx-value-ref={entry.ref}
              phx-value-upload={@name}
              class="shrink-0 text-xs font-medium text-thamani-error"
            >
              Remove
            </button>
          </div>
          <p :for={err <- upload_errors(@upload, entry)} class="mt-1 text-xs text-red-700">
            {doc_upload_error_to_string(err)}
          </p>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <.receiving_shell
      portal={@receiving_portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@receiving_index_path}
    >
      <.header :if={@receiving_new?} icon="hero-arrow-down-tray">
        Receive stock
        <:subtitle>
          Scan or select each item as it comes off the truck, then add its batch details.
        </:subtitle>
        <:actions>
          <.button variant="ghost" patch={@receiving_index_path}>Cancel</.button>
        </:actions>
      </.header>

      <.header :if={!@receiving_new?} icon="hero-arrow-down-tray">
        Receive inventory
        <:subtitle>Check in a delivery directly into a distributor warehouse.</:subtitle>
        <:actions>
          <.button
            id="receive-distributor-stock"
            variant="primary"
            patch={@receiving_new_path}
          >
            <.icon name="hero-plus" class="size-4" /> Receive stock
          </.button>
        </:actions>
      </.header>

      <div
        :if={@receiving_new? and @distributor_org?}
        class="mb-4 rounded-2xl ff-surface-card p-5 sm:p-6"
      >
        <h3 class="text-sm font-semibold text-thamani-forest">Receiving from</h3>
        <p class="mt-1 text-xs text-thamani-pewter">
          One sender for this whole delivery, verified against your own sites and the GS1 registry.
        </p>
        <form id="distributor-origin-form" phx-change="validate_origin" class="mt-3">
          <.input
            id="origin-gln"
            name="origin[gln]"
            value={origin_gln_value(@origin_check)}
            label="Origin GLN"
            placeholder="13-digit GLN of the sender"
            inputmode="numeric"
            phx-debounce="500"
            required
          />
        </form>

        <%= case @origin_check do %>
          <% :checking -> %>
            <p class="inline-flex items-center gap-1.5 text-xs font-medium text-thamani-pewter">
              <.icon name="hero-arrow-path" class="size-3.5 motion-safe:animate-spin" />
              Verifying&hellip;
            </p>
          <% {:matched, resolved} -> %>
            <div class="rounded-lg bg-[color-mix(in_srgb,var(--thamani-lime)_18%,white)] px-3 py-2.5 text-xs font-semibold text-thamani-forest">
              <p class="inline-flex items-center gap-1.5">
                <.icon name="hero-check-circle" class="size-4" /> Verified · {resolved.company}
              </p>
              <p :if={resolved.address} class="mt-1 font-normal">{resolved.address}</p>
            </div>
          <% :not_found -> %>
            <p class="inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              We couldn't verify this GLN. Double-check the number before continuing.
            </p>
          <% :unavailable -> %>
            <p class="text-xs text-thamani-pewter">
              We couldn't verify this GLN right now. Try again in a moment.
            </p>
          <% _ -> %>
            <p class="text-xs text-thamani-pewter">
              We verify this as soon as you enter it — against your own sites and the GS1 registry.
            </p>
        <% end %>

        <label class="mt-3 inline-flex items-center gap-2 text-xs font-medium text-thamani-pewter">
          <input
            type="checkbox"
            checked={@is_return}
            phx-click="toggle_return"
            class="rounded border-thamani-stone"
          /> This is a return
        </label>

        <form :if={@is_return} phx-change="set_return_disposition" class="mt-2">
          <.input
            type="select"
            name="return_disposition"
            value={@return_disposition}
            label="Accept as"
            options={[{"Active (saleable)", "active"}, {"Returned (pending QA)", "returned"}]}
          />
        </form>
      </div>

      <div :if={@receiving_new?} class="mb-4 rounded-2xl ff-surface-card p-5 sm:p-6">
        <h3 class="text-sm font-semibold text-thamani-forest">Delivery documents</h3>
        <p class="mt-1 text-xs text-thamani-pewter">
          Attach the GRN and invoice for this delivery, plus any other supporting documents.
        </p>
        <form
          id="distributor-document-uploads-form"
          phx-change="validate_uploads"
          class="mt-3 grid gap-4 sm:grid-cols-3"
        >
          <.doc_upload_slot label="GRN" name="doc_grn" upload={@uploads.doc_grn} />
          <.doc_upload_slot label="Invoice" name="doc_invoice" upload={@uploads.doc_invoice} />
          <.doc_upload_slot
            label="Other documents"
            name="doc_other"
            upload={@uploads.doc_other}
          />
        </form>
      </div>

      <div :if={@receiving_new?} class="rounded-2xl ff-surface-card p-5 sm:p-6">
        <div :if={@delivery_items == []} class="py-6">
          <.blank_state icon="hero-arrow-down-tray" title="No items added yet">
            Scan or select the first product in this delivery.
            <:actions>
              <.button id="open-add-item-empty" variant="primary" phx-click="open_add_item">
                <.icon name="hero-plus" class="size-4" /> Add item
              </.button>
            </:actions>
          </.blank_state>
        </div>
        <div :if={@delivery_items != []}>
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-thamani-forest">Items in this delivery</h3>
            <.button id="open-add-item-bottom" variant="ghost" phx-click="open_add_item">
              <.icon name="hero-plus" class="size-4" /> Add item
            </.button>
          </div>
          <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone bg-white">
            <table class="w-full table-fixed text-left text-sm">
              <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="w-[25%] px-3 py-2">Product</th><th class="w-[18%] px-3 py-2">
                    Batch
                  </th><th class="hidden px-3 py-2 sm:table-cell">
                    Expiry
                  </th><th class="w-[22%] px-3 py-2">Quantity</th><th class="w-[23%] px-3 py-2 text-right">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone">
                <tr :for={item <- @delivery_items} id={"delivery-item-#{item.id}"}>
                  <td
                    class="truncate px-3 py-2 font-medium text-thamani-forest"
                    title={item.product_name}
                  >
                    {item.product_name}
                  </td>
                  <td class="truncate px-3 py-2 font-mono text-xs" title={item.batch_no}>
                    {item.batch_no}
                    <span
                      :if={sscc = Map.get(item.attrs, "sscc")}
                      class="block text-[10px] font-sans text-thamani-subtle"
                    >
                      SSCC {sscc}
                    </span>
                  </td>
                  <td class="hidden px-3 py-2 text-thamani-pewter sm:table-cell">
                    {Map.get(item.attrs, "expiry_date")}
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap">
                    {item.quantity} {unit_label(item.uom)}
                  </td>
                  <td class="px-3 py-2">
                    <div class="flex justify-end gap-2">
                      <button
                        type="button"
                        phx-click="edit_delivery_item"
                        phx-value-id={item.id}
                        class="text-xs font-semibold text-thamani-forest hover:underline"
                      >Edit</button><button
                        type="button"
                        phx-click="remove_delivery_item"
                        phx-value-id={item.id}
                        class="text-xs font-semibold text-thamani-error hover:underline"
                      >Remove</button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <.button
            id="finish-distributor-delivery"
            class="mt-4 w-full"
            variant="primary"
            phx-click="finish_delivery"
          >
            Finish receiving ({length(@delivery_items)} items)
          </.button>
        </div>
      </div>

      <.modal
        :if={@add_item_open}
        id="distributor-add-item-modal"
        show
        on_cancel={JS.push("close_add_item")}
      >
        <div class="border-b border-thamani-stone pb-4">
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Add item</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Scan or select the product, then add its batch details.
          </p>
        </div>

        <%= cond do %>
          <% @receipt_step == :product -> %>
            <.form
              for={@scan_form}
              id="distributor-scan-gtin-form"
              phx-change="scan_gtin"
              phx-submit="scan_gtin"
              class="mt-5"
            >
              <.input
                field={@scan_form[:gtin]}
                label="Scan GTIN to identify product"
                placeholder="Scan the product barcode, then press Enter"
                autocomplete="off"
                phx-debounce="350"
              />
              <p
                :if={@scan_error}
                id="distributor-scan-error"
                role="alert"
                class="mt-2 text-sm text-thamani-error"
              >
                {@scan_error}
              </p>
            </.form>
            <div class="my-5 flex items-center gap-3 text-xs font-semibold tracking-widest text-thamani-subtle">
              <span class="h-px flex-1 bg-thamani-stone"></span>OR CHOOSE MANUALLY<span class="h-px flex-1 bg-thamani-stone"></span>
            </div>
            <form id="distributor-choose-product-form" phx-change="choose_product">
              <.input
                name="product_id"
                type="select"
                label="Choose a product manually"
                prompt="Select product"
                options={Enum.map(@products, &{product_name(@products, &1.id), &1.id})}
              />
            </form>
          <% @receipt_step == :new_product -> %>
            <div class="mt-5 mb-4 flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                  New product
                </p>
                <p class="mt-0.5 font-mono text-xs text-thamani-pewter">
                  GTIN {@new_product_form[:gtin].value}
                </p>
              </div>
              <button
                type="button"
                phx-click="cancel_new_product"
                class="text-sm font-semibold text-thamani-forest hover:underline"
              >
                Cancel
              </button>
            </div>
            <.form
              for={@new_product_form}
              id="distributor-new-product-form"
              phx-change="validate_new_product"
              phx-submit="save_new_product"
            >
              <input type="hidden" name="product[gtin]" value={@new_product_form[:gtin].value} />
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@new_product_form[:generic_name]} label="Generic name" />
                <.input field={@new_product_form[:brand_name]} label="Brand name" />
                <.input
                  field={@new_product_form[:uom]}
                  type="select"
                  label="Base inventory unit"
                  prompt="Select unit"
                  options={[
                    {"Piece (H87)", "H87"},
                    {"Tablet (U2)", "U2"},
                    {"Unit (C62)", "C62"},
                    {"Kilogram (KGM)", "KGM"}
                  ]}
                  required
                />
                <.input field={@new_product_form[:category]} label="Category" />
                <.input
                  field={@new_product_form[:price]}
                  type="number"
                  label="Unit price (KSh)"
                  min="0"
                  required
                />
                <.input
                  field={@new_product_form[:reorder_level]}
                  label="Reorder level"
                  type="number"
                  min="0"
                />
              </div>
              <.button class="mt-3 w-full" variant="primary">
                Add product and continue
              </.button>
            </.form>
          <% true -> %>
            <div class="mt-5 mb-4 flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                  Product
                </p>
                <p class="text-sm font-medium text-thamani-forest">
                  {product_name(@products, @selected_product.id)}
                </p>
                <p class="mt-0.5 font-mono text-xs text-thamani-pewter">
                  GTIN {@selected_product.gtin}
                </p>
              </div>
              <button
                type="button"
                phx-click="change_product"
                class="text-sm font-semibold text-thamani-forest hover:underline"
              >
                Change
              </button>
            </div>
            <div
              :if={@adding_supplier}
              class="rounded-xl border border-thamani-stone bg-thamani-canvas p-4"
            >
              <div class="mb-3 flex items-center justify-between">
                <p class="text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                  New supplier
                </p>
                <button
                  type="button"
                  phx-click="cancel_new_supplier"
                  class="text-sm font-semibold text-thamani-forest hover:underline"
                >
                  Cancel
                </button>
              </div>
              <.form
                for={@new_supplier_form}
                id="distributor-new-supplier-form"
                phx-change="validate_new_supplier"
                phx-submit="save_new_supplier"
              >
                <.input field={@new_supplier_form[:name]} label="Supplier name" required />
                <div class="grid gap-x-4 sm:grid-cols-2">
                  <.input field={@new_supplier_form[:phone]} label="Phone" required />
                  <.input field={@new_supplier_form[:email]} label="Email" required />
                </div>
                <.button class="mt-3 w-full" variant="primary">Add supplier</.button>
              </.form>
            </div>
            <.form
              :if={!@adding_supplier}
              for={@form}
              id="distributor-receipt-form"
              phx-change="validate"
              phx-submit="add_to_delivery"
            >
              <input type="hidden" name="batch[product_id]" value={@selected_product.id} />
              <input type="hidden" name="batch[gtin]" value={@selected_product.gtin} />
              <input type="hidden" name="batch[site_id]" value={@form[:site_id].value} />
              <div :if={!@distributor_org?}>
                <.input
                  field={@form[:supplier_id]}
                  type="select"
                  label="Supplier"
                  options={Enum.map(@suppliers, &{&1.name, &1.id})}
                  prompt="Select supplier"
                  required
                />
                <button
                  type="button"
                  phx-click="toggle_new_supplier"
                  class="-mt-2 mb-3 text-xs font-semibold text-thamani-forest hover:underline"
                >
                  + Add new supplier
                </button>
              </div>
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@form[:batch_no]} label="Batch number" required />
                <.input field={@form[:expiry_date]} type="date" label="Expiry date" required />
              </div>
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@form[:manufacturer]} label="Manufacturer (optional)" />
                <.input
                  field={@form[:manufacture_date]}
                  type="date"
                  label="Manufacture date (optional)"
                />
              </div>
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input
                  field={@form[:quantity]}
                  type="number"
                  label={"Quantity received (#{unit_label(@selected_product.uom)})"}
                  min="1"
                  required
                />
                <.input
                  field={@form[:cost_per_unit]}
                  type="number"
                  step="0.01"
                  label="Cost per unit (optional)"
                  min="0"
                />
              </div>
              <.input
                field={@form[:sscc]}
                label="Case label SSCC"
                placeholder="Scan the pallet/case label, or type its 18-digit SSCC"
                autocomplete="off"
                required
              />
              <p
                :if={@sscc_warning}
                id="sscc-destination-warning"
                class="mt-1 inline-flex items-center gap-1.5 text-xs font-semibold text-amber-800"
              >
                <.icon name="hero-exclamation-triangle" class="size-4" /> {@sscc_warning}
              </p>
              <.button class="mt-3 w-full" variant="primary">
                {if is_nil(@editing_delivery_item_id),
                  do: "Add received item",
                  else: "Save item changes"}
              </.button>
            </.form>
        <% end %>
      </.modal>

      <.table
        :if={!@receiving_new?}
        id="distributor-receipts"
        rows={@streams.receipts}
        row_click={
          fn {_id, receipt} ->
            JS.navigate("#{@receiving_index_path}/#{receipt.id}")
          end
        }
      >
        <:col :let={{_id, receipt}} label="Receipt">
          <span class="font-semibold text-thamani-forest">{receipt.number}</span>
        </:col>
        <:col :let={{_id, receipt}} label="Supplier">{receipt_supplier(receipt)}</:col>
        <:col :let={{_id, receipt}} label="Warehouse">{receipt_warehouse(receipt)}</:col>
        <:col :let={{_id, receipt}} label="Received">
          {Calendar.strftime(receipt.received_at, "%d %b %Y, %H:%M UTC")}
        </:col>
        <:col :let={{_id, receipt}} label="Items">{length(receipt.items)}</:col>
        <:empty_state>
          <.blank_state icon="hero-arrow-down-tray" title="No receipts yet">
            Add a warehouse, product, and supplier, then receive the first delivery.
          </.blank_state>
        </:empty_state>
      </.table>
      <.pagination :if={!@receiving_new?} page={@page_info} path={@receiving_index_path} />
    </.receiving_shell>
    """
  end

  attr :portal, :atom, required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current_path, :string, required: true
  slot :inner_block, required: true

  defp receiving_shell(%{portal: :organization} = assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      {render_slot(@inner_block)}
    </Layouts.org_shell>
    """
  end

  defp receiving_shell(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@current_path}
    >
      {render_slot(@inner_block)}
    </Layouts.distributor_shell>
    """
  end
end
