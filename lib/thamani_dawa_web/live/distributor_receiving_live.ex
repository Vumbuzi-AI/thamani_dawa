defmodule ThamaniDawaWeb.DistributorReceivingLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Batches
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

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    portal = receiving_portal(socket.assigns.live_action)
    receiving_new? = receiving_new_action?(socket.assigns.live_action)

    distributor_org? =
      ThamaniDawaWeb.UserAuth.distributor_organization?(socket.assigns.current_scope)

    case current_distribution_site(socket.assigns.current_scope, portal) do
      {:ok, receiving_site} ->
        {:ok,
         socket
         |> assign(:receiving_portal, portal)
         |> assign(:receiving_site, receiving_site)
         |> assign(:receiving_new?, receiving_new?)
         |> assign(:distributor_org?, distributor_org?)
         |> assign(:receiving_index_path, receiving_index_path(portal))
         |> assign(:receiving_new_path, receiving_new_path(portal))
         |> assign(:products, Products.list_products(organization_id))
         |> assign(:suppliers, Suppliers.list_suppliers(organization_id))
         |> assign(:warehouses, warehouse_sites(organization_id))
         |> assign(:receipt_step, :sscc)
         |> assign(:selected_product, nil)
         |> assign(:scan_error, nil)
         |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
         |> assign(:entry_sscc_form, to_form(%{"sscc" => ""}, as: :sscc_entry))
         |> assign(:entry_sscc_check, :idle)
         |> assign(:carried_attrs, %{})
         |> assign(:delivery_items, [])
         |> assign(:pending_discrepancies, [])
         |> assign(:pending_shipper, nil)
         |> assign(:receipt_posting_key, Ecto.UUID.generate())
         |> assign(:editing_delivery_item_id, nil)
         |> assign(:new_product_form, nil)
         |> assign(:adding_supplier, false)
         |> assign(:new_supplier_form, nil)
         |> assign(:add_item_open, false)
         |> assign(:locked_unit_quantity, nil)
         |> assign(:page_number, 1)
         |> assign(:checked_sscc, nil)
         |> assign(:sscc_warning, nil)
         |> assign(:origin_gln, "")
         |> assign(:receiving_draft, nil)
         |> assign(:draft_attachments, [])
         |> assign_origin_defaults()
         |> assign_serial_confirm()
         |> allow_upload(:doc_delivery_note,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: 5_000_000,
           auto_upload: true,
           progress: &handle_doc_upload_progress/3
         )
         |> allow_upload(:doc_invoice,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: 5_000_000,
           auto_upload: true,
           progress: &handle_doc_upload_progress/3
         )
         |> allow_upload(:doc_po,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 1,
           max_file_size: 5_000_000,
           auto_upload: true,
           progress: &handle_doc_upload_progress/3
         )
         |> allow_upload(:doc_other,
           accept: ~w(.pdf .jpg .jpeg .png),
           max_entries: 5,
           max_file_size: 5_000_000,
           auto_upload: true,
           progress: &handle_doc_upload_progress/3
         )}

      :error ->
        home = if portal == :organization, do: ~p"/org/dashboard", else: ~p"/distributor"

        {:ok,
         socket
         |> put_flash(:error, "Select a warehouse before receiving stock.")
         |> push_navigate(to: home)}
    end
  end

  defp assign_origin_defaults(socket) do
    if socket.assigns.distributor_org? or socket.assigns.receiving_portal == :organization do
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
       |> assign(:receipt_step, :sscc)
       |> assign(:selected_product, nil)
       |> assign(:scan_error, nil)
       |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
       |> assign(:entry_sscc_form, to_form(%{"sscc" => ""}, as: :sscc_entry))
       |> assign(:entry_sscc_check, :idle)
       |> assign(:carried_attrs, %{})
       |> assign(:delivery_items, [])
       |> assign(:pending_discrepancies, [])
       |> assign(:pending_shipper, nil)
       |> assign(:receipt_posting_key, Ecto.UUID.generate())
       |> assign(:editing_delivery_item_id, nil)
       |> assign(:new_product_form, nil)
       |> assign(:adding_supplier, false)
       |> assign(:new_supplier_form, nil)
       |> assign(:add_item_open, false)
       |> assign(:locked_unit_quantity, nil)
       |> assign(:form, nil)
       |> assign(:checked_sscc, nil)
       |> assign(:sscc_warning, nil)
       |> assign(:origin_gln, "")
       |> assign_origin_defaults()
       |> assign_serial_confirm()
       |> discard_receiving_draft()}
    else
      {:noreply,
       socket
       |> assign(
         form: nil,
         selected_product: nil,
         receipt_step: :sscc,
         delivery_items: [],
         pending_discrepancies: [],
         pending_shipper: nil,
         receipt_posting_key: Ecto.UUID.generate(),
         editing_delivery_item_id: nil,
         new_product_form: nil,
         adding_supplier: false,
         new_supplier_form: nil,
         add_item_open: false,
         entry_sscc_form: to_form(%{"sscc" => ""}, as: :sscc_entry),
         entry_sscc_check: :idle,
         carried_attrs: %{}
       )
       |> assign_serial_confirm()}
    end
  end

  defp receiving_portal(action) when action in [:org_index, :org_new], do: :organization
  defp receiving_portal(_action), do: :distributor

  defp receiving_new_action?(action), do: action in [:distributor_new, :org_new]

  defp receiving_index_path(:organization), do: ~p"/org/receiving"
  defp receiving_index_path(_), do: ~p"/distributor/receiving"

  defp receiving_new_path(:organization), do: ~p"/org/receiving/new"
  defp receiving_new_path(_), do: ~p"/distributor/receiving/new"


  def handle_event("open_add_item", _params, socket) do
    {:noreply, assign(socket, :add_item_open, true)}
  end

  def handle_event("close_add_item", _params, socket) do
    {:noreply,
     socket
     |> assign(:add_item_open, false)
     |> assign(:pending_shipper, nil)
     |> assign(:receipt_step, :sscc)
     |> assign(:selected_product, nil)
     |> assign(:scan_error, nil)
     |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
     |> assign(:entry_sscc_form, to_form(%{"sscc" => ""}, as: :sscc_entry))
     |> assign(:entry_sscc_check, :idle)
     |> assign(:carried_attrs, %{})
     |> assign(:editing_delivery_item_id, nil)
     |> assign(:locked_unit_quantity, nil)
     |> assign(:new_product_form, nil)
     |> assign(:adding_supplier, false)
     |> assign(:new_supplier_form, nil)
     |> assign(:form, nil)
     |> assign_serial_confirm()}
  end

  def handle_event("validate_entry_sscc", %{"sscc_entry" => %{"sscc" => raw}}, socket) do
    sscc = raw |> extract_sscc() |> String.trim()
    socket = assign(socket, :entry_sscc_form, to_form(%{"sscc" => raw}, as: :sscc_entry))

    if Regex.match?(~r/^\d{18}$/, sscc) do
      organization_id = socket.assigns.current_scope.organization_id
      api_token = ThamaniDawa.Organizations.gs1_api_key(organization_id)

      {:noreply,
       socket
       |> assign(:entry_sscc_check, :checking)
       |> assign(:checked_sscc, sscc)
       |> start_async(:entry_sscc_lookup, fn ->
         Distributor.lookup_shipper_by_sscc(sscc, api_token: api_token)
       end)}
    else
      {:noreply, assign(socket, :entry_sscc_check, :idle)}
    end
  end

  def handle_event("skip_to_manual_entry", _params, socket) do
    {:noreply, assign(socket, :receipt_step, :product)}
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
    changeset =
      Map.put(Product.changeset(%Product{}, stock_unit_attrs(attrs)), :action, :validate)

    {:noreply, assign(socket, :new_product_form, to_form(changeset, as: :product))}
  end

  def handle_event("save_new_product", %{"product" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    attrs = stock_unit_attrs(attrs)

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

    case Enum.find(socket.assigns.delivery_items, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That staged receipt item could not be found.")}

      item ->
        product = Enum.find(socket.assigns.products, &(&1.id == item.attrs["product_id"]))

        if product do
          {:noreply,
           socket
           |> assign(:add_item_open, true)
           |> assign(:editing_delivery_item_id, item.id)
           |> assign(:selected_product, product)
           |> assign(:receipt_step, :details)
           |> assign_locked_quantity(item.attrs)
           |> assign(:form, to_form(receipt_changeset(socket, item.attrs), as: :batch))}
        else
          # The SSCC-prefilled item's GTIN isn't in this org's catalog yet —
          # send the user to create it, carrying the batch/quantity/sscc
          # details forward so they land back on the details form once the
          # product exists (see `select_product/2`).
          {:noreply,
           socket
           |> assign(:add_item_open, true)
           |> assign(:editing_delivery_item_id, item.id)
           |> assign(:carried_attrs, Map.delete(item.attrs, "product_id"))
           |> start_new_product(item.attrs["gtin"], item.product_name)}
        end
    end
  end

  def handle_event("set_group_received_quantity", %{"key" => key, "value" => value}, socket) do
    quantity = parse_nonneg_integer(value)

    {:noreply,
     update_pending_group(socket, key, fn group ->
       received = min(quantity, group.expected_quantity)

       %{
         group
         | received_quantity: received,
           damaged_quantity: min(group.damaged_quantity, received)
       }
     end)}
  end

  def handle_event("set_group_damaged_quantity", %{"key" => key, "value" => value}, socket) do
    quantity = parse_nonneg_integer(value)

    {:noreply,
     update_pending_group(socket, key, fn group ->
       %{group | damaged_quantity: min(quantity, group.received_quantity)}
     end)}
  end

  def handle_event(
        "set_serial_condition",
        %{"key" => key, "serial" => serial, "condition" => condition},
        socket
      )
      when condition in ["accepted", "damaged", "missing"] do
    condition = String.to_existing_atom(condition)

    {:noreply,
     socket
     |> update_pending_group(key, fn group ->
       %{group | serial_conditions: Map.put(group.serial_conditions, serial, condition)}
     end)
     |> update(:pending_shipper, fn pending ->
       %{pending | reviewed_serials: MapSet.put(reviewed_serials(pending), serial)}
     end)}
  end

  def handle_event("cancel_pending_shipper", _params, socket) do
    {:noreply,
     socket
     |> assign(:pending_shipper, nil)
     |> assign(:receipt_step, :sscc)
     |> assign_serial_confirm()}
  end

  def handle_event("confirm_pending_shipper", _params, socket) do
    settle_pending_shipper(socket, socket.assigns.pending_shipper)
  end

  def handle_event("finish_delivery", _params, socket) do
    cond do
      Enum.any?(socket.assigns.delivery_items, &is_nil(&1.attrs["product_id"])) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "One or more items are not in your catalog yet. Add each one before finishing."
         )}

      socket.assigns.distributor_org? and not match?({:matched, _}, socket.assigns.origin_check) ->
        {:noreply,
         socket
         |> put_flash(:error, "Enter a valid, verified origin GLN before finishing.")
         |> push_event("scroll-into-view", %{id: "origin-gln"})}

      uploads_in_progress?(socket) ->
        {:noreply,
         put_flash(socket, :error, "Still uploading document(s) — try again in a moment.")}

      true ->
        post_delivery(socket)
    end
  end

  def handle_event("validate_origin", %{"origin" => %{"gln" => gln}}, socket) do
    gln = String.trim(to_string(gln))
    {:noreply, socket |> assign(:origin_gln, gln) |> check_origin_gln(gln)}
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

  def handle_event("delete_draft_attachment", %{"id" => attachment_id}, socket) do
    case socket.assigns.receiving_draft do
      nil ->
        {:noreply, socket}

      draft ->
        GoodsReceipts.delete_draft_attachment!(draft, attachment_id)

        refreshed_draft =
          GoodsReceipts.get_receiving_draft(
            socket.assigns.current_scope.organization_id,
            socket.assigns.current_scope.user.id
          )

        {:noreply,
         socket
         |> assign(:receiving_draft, refreshed_draft)
         |> assign(:draft_attachments, refreshed_draft.attachments)}
    end
  end

  def handle_async(
        :origin_lookup,
        {:ok, {:ok, resolved}},
        %{assigns: %{origin_check: :checking}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:origin_check, {:matched, resolved})
     |> save_receiving_draft_origin(resolved)}
  end

  def handle_async(
        :origin_lookup,
        {:ok, {:error, :not_found}},
        %{assigns: %{origin_check: :checking}} = socket
      ) do
    {:noreply, assign(socket, :origin_check, :not_found)}
  end

  def handle_async(
        :origin_lookup,
        {:exit, _reason},
        %{assigns: %{origin_check: :checking}} = socket
      ) do
    {:noreply, assign(socket, :origin_check, :unavailable)}
  end

  def handle_async(:origin_lookup, _result, socket) do
    {:noreply, socket}
  end

  def handle_async(:sscc_lookup, {:ok, {:ok, shipper}}, socket) do
    {:noreply, apply_shipper_prefill(socket, shipper)}
  end

  def handle_async(:sscc_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, socket}
  end

  def handle_async(:sscc_lookup, {:ok, {:error, :unavailable}}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "GS1 could not be reached for this SSCC. Try again, or add the item manually."
     )}
  end

  def handle_async(:sscc_lookup, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  def handle_async(:entry_sscc_lookup, {:ok, {:ok, shipper}}, socket) do
    {:noreply,
     socket
     |> assign(:entry_sscc_check, {:matched, shipper})
     |> apply_shipper_prefill(shipper)}
  end

  def handle_async(:entry_sscc_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, assign(socket, :entry_sscc_check, :not_found)}
  end

  def handle_async(:entry_sscc_lookup, {:ok, {:error, :unavailable}}, socket) do
    {:noreply, assign(socket, :entry_sscc_check, :unavailable)}
  end

  def handle_async(:entry_sscc_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :entry_sscc_check, :unavailable)}
  end

  defp post_delivery(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id
    origin = origin_payload(socket)

    case GoodsReceipts.receive_delivery(
           organization_id,
           user_id,
           socket.assigns.delivery_items,
           socket.assigns.receipt_posting_key,
           origin,
           %{}
         ) do
      {:ok, receipt} ->
        store_delivery_attachments(socket, receipt, user_id)
        finalize_receiving_draft(socket, receipt, user_id)
        persist_discrepancies(socket, receipt, organization_id)
        escalate_flagged_items(socket, receipt)

        {:noreply,
         socket
         |> put_flash(
           :info,
           receiving_flash_message(receipt, socket.assigns.pending_discrepancies)
         )
         |> push_patch(to: socket.assigns.receiving_index_path)}

      {:error, changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           delivery_error_flash(changeset)
         )}
    end
  end

  defp receiving_flash_message(receipt, []) do
    "Delivery #{receipt.number} received: #{length(receipt.items)} item(s) posted to inventory."
  end

  defp receiving_flash_message(receipt, discrepancies) do
    flagged = Enum.sum(Enum.map(discrepancies, &Map.fetch!(&1, "quantity")))

    "Delivery #{receipt.number} received: #{length(receipt.items)} item(s) posted to inventory, " <>
      "#{flagged} flagged missing."
  end

  defp persist_discrepancies(socket, receipt, organization_id) do
    Enum.each(socket.assigns.pending_discrepancies, fn attrs ->
      GoodsReceipts.create_discrepancy!(organization_id, receipt.id, attrs)
    end)
  end

  defp escalate_flagged_items(socket, receipt) do
    flagged_batch_nos =
      socket.assigns.delivery_items
      |> Enum.filter(& &1[:flagged_damaged?])
      |> Enum.map(& &1.batch_no)
      |> MapSet.new()

    receipt.items
    |> Enum.filter(
      &(&1.status == :quarantined and MapSet.member?(flagged_batch_nos, &1.batch_no))
    )
    |> Enum.each(
      &Batches.mark_damaged(
        &1,
        "Flagged damaged at receiving — #{receipt.number}",
        socket.assigns.current_scope.user
      )
    )
  end

  defp uploads_in_progress?(socket) do
    [:doc_delivery_note, :doc_invoice, :doc_po, :doc_other]
    |> Enum.flat_map(&Map.get(socket.assigns.uploads, &1).entries)
    |> Enum.any?(&(not &1.done?))
  end

  defp store_delivery_attachments(socket, receipt, user_id) do
    for {upload_name, doc_type} <- [
          {:doc_delivery_note, :delivery_note},
          {:doc_invoice, :invoice},
          {:doc_po, :po},
          {:doc_other, :other}
        ] do
      consume_uploaded_entries(socket, upload_name, fn %{path: tmp_path}, entry ->
        GoodsReceipts.store_attachment!(receipt, doc_type, tmp_path, entry, user_id)
        {:ok, :stored}
      end)
    end
  end

  # Opening Receive stock starts a new delivery. The previous visit's origin
  # and documents are stored so a posted receipt can keep its files, and
  # must not reappear on the next delivery.
  defp discard_receiving_draft(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    case GoodsReceipts.get_receiving_draft(organization_id, user_id) do
      nil -> :ok
      draft -> GoodsReceipts.delete_receiving_draft!(draft)
    end

    socket
    |> assign(:receiving_draft, nil)
    |> assign(:draft_attachments, [])
  end

  defp save_receiving_draft_origin(socket, resolved) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    draft =
      socket.assigns.receiving_draft ||
        GoodsReceipts.ensure_receiving_draft(organization_id, user_id)

    draft =
      GoodsReceipts.save_draft_origin!(
        draft,
        Map.new(resolved, fn {key, value} -> {to_string(key), value} end)
      )

    socket |> assign(:receiving_draft, draft) |> assign(:draft_attachments, draft.attachments)
  end

  defp handle_doc_upload_progress(upload_name, entry, socket) do
    if entry.done? do
      organization_id = socket.assigns.current_scope.organization_id
      user_id = socket.assigns.current_scope.user.id

      draft =
        socket.assigns.receiving_draft ||
          GoodsReceipts.ensure_receiving_draft(organization_id, user_id)

      consume_uploaded_entry(socket, entry, fn %{path: tmp_path} ->
        GoodsReceipts.store_draft_attachment!(
          draft,
          upload_doc_type(upload_name),
          tmp_path,
          entry
        )

        {:ok, :stored}
      end)

      draft = GoodsReceipts.get_receiving_draft(organization_id, user_id)

      {:noreply,
       socket |> assign(:receiving_draft, draft) |> assign(:draft_attachments, draft.attachments)}
    else
      {:noreply, socket}
    end
  end

  defp upload_doc_type(:doc_delivery_note), do: :delivery_note
  defp upload_doc_type(:doc_invoice), do: :invoice
  defp upload_doc_type(:doc_po), do: :po
  defp upload_doc_type(:doc_other), do: :other

  defp finalize_receiving_draft(%{assigns: %{receiving_draft: nil}}, _receipt, _user_id), do: :ok

  defp finalize_receiving_draft(socket, receipt, user_id) do
    GoodsReceipts.attach_draft_attachments!(socket.assigns.receiving_draft, receipt, user_id)
    GoodsReceipts.delete_receiving_draft!(socket.assigns.receiving_draft)
  end

  defp origin_payload(%{assigns: %{origin_check: {:matched, resolved}}}), do: resolved
  defp origin_payload(_socket), do: nil

  defp current_distribution_site(%Scope{current_site_id: nil} = scope, :organization) do
    case warehouse_sites(scope.organization_id) do
      [site | _] -> {:ok, site}
      [] -> :error
    end
  end

  defp current_distribution_site(%Scope{current_site_id: nil}, _portal), do: :error

  defp current_distribution_site(%Scope{} = scope, _portal) do
    site = Sites.get_site!(scope.organization_id, scope.current_site_id)

    if Site.distribution?(site), do: {:ok, site}, else: :error
  rescue
    Ecto.NoResultsError -> :error
  end

  defp check_origin_gln(socket, gln) do
    cond do
      gln == "" or Regex.match?(~r/^\d{1,12}$/, gln) ->
        socket
        |> cancel_async(:origin_lookup)
        |> assign(:origin_check, :idle)

      Regex.match?(~r/^\d{18}$/, gln) ->
        socket
        |> cancel_async(:origin_lookup)
        |> assign(
          :origin_check,
          {:invalid,
           "This is an 18-digit SSCC. It belongs on the case. The sender's GLN is 13 digits."}
        )

      not Regex.match?(~r/^\d{13}$/, gln) ->
        socket
        |> cancel_async(:origin_lookup)
        |> assign(:origin_check, {:invalid, "A GLN is 13 digits."})

      gln == current_receiving_site_gln(socket) ->
        socket
        |> cancel_async(:origin_lookup)
        |> assign(:origin_check, :same_receiving_site)

      true ->
        socket
        |> assign(:origin_check, :checking)
        |> start_async(:origin_lookup, fn -> GlnLookup.resolve_party(gln) end)
    end
  end

  defp current_receiving_site_gln(socket), do: socket.assigns.receiving_site.gln

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
        organization_id = socket.assigns.current_scope.organization_id
        api_token = ThamaniDawa.Organizations.gs1_api_key(organization_id)

        socket
        |> assign(:checked_sscc, sscc)
        |> start_async(:sscc_lookup, fn ->
          Distributor.lookup_shipper_by_sscc(sscc, api_token: api_token)
        end)
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

  defp current_receiving_site(socket), do: socket.assigns.receiving_site

  defp prefill_shipper_items(socket, %{gtin: gtin, items: []} = shipper) when is_binary(gtin) do
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

    attrs = Map.put(attrs, "site_id", socket.assigns.receiving_site.id)

    if product do
      socket
      |> assign(:selected_product, product)
      |> assign(:receipt_step, :details)
      |> assign_locked_quantity(attrs)
      |> assign(:form, to_form(receipt_changeset(socket, attrs), as: :batch))
    else
      # The case resolved, but its product isn't in this org's catalog yet —
      # carry the batch's details forward so they still land on the details
      # form once the product is created, instead of losing everything the
      # lookup already gave us.
      socket
      |> assign(:carried_attrs, Map.delete(attrs, "product_id"))
      |> start_new_product(gtin)
    end
  end

  defp prefill_shipper_items(socket, %{items: items} = shipper) when items != [] do
    if already_staged_sscc?(socket, shipper.sscc) do
      assign(socket, :entry_sscc_check, {:duplicate, shipper.sscc})
    else
      prefill_new_shipper_items(socket, shipper, items)
    end
  end

  defp prefill_shipper_items(socket, _shipper), do: socket

  defp already_staged_sscc?(socket, sscc) do
    Enum.any?(socket.assigns.delivery_items, &(&1.attrs["sscc"] == sscc))
  end

  @small_serial_group_threshold 10

  defp prefill_new_shipper_items(socket, shipper, items) do
    site_id = socket.assigns.receiving_site.id

    groups =
      items
      |> Enum.group_by(&{&1.gtin, &1.batch, &1.production_date, &1.expiry_date})
      |> Enum.map(fn {{gtin, batch, production_date, expiry_date}, group} ->
        product = Enum.find(socket.assigns.products, &(&1.gtin == gtin))
        first = hd(group)
        serials = Enum.map(group, & &1.serial)
        small? = length(serials) <= @small_serial_group_threshold

        %{
          key: Enum.join([gtin, batch, production_date, expiry_date], "|"),
          gtin: gtin,
          batch_no: batch,
          production_date: production_date,
          expiry_date: expiry_date,
          product: product,
          product_name:
            (product && (product.generic_name || product.brand_name)) || first.product_name ||
              "Unknown product",
          serials: serials,
          expected_quantity: length(serials),
          small_group?: small?,
          received_quantity: length(serials),
          damaged_quantity: 0,
          serial_conditions: Map.new(serials, &{&1, :accepted})
        }
      end)

    pending = %{
      sscc: shipper.sscc,
      site_id: site_id,
      groups: groups,
      scanned_serials: MapSet.new(),
      reviewed_serials: MapSet.new(),
      review_unscanned?: false
    }

    socket =
      socket
      |> assign(:entry_sscc_form, to_form(%{"sscc" => ""}, as: :sscc_entry))
      |> assign(:entry_sscc_check, :idle)
      |> assign_serial_confirm()

    if serialized_case?(pending) do
      socket
      |> assign(:pending_shipper, pending)
      |> assign(:receipt_step, :confirm_shipper)
    else
      settle_pending_shipper_socket(socket, pending)
    end
  end

  defp update_pending_group(socket, key, fun) do
    update(socket, :pending_shipper, fn pending ->
      %{pending | groups: Enum.map(pending.groups, &maybe_update_group(&1, key, fun))}
    end)
  end

  defp maybe_update_group(%{key: key} = group, key, fun), do: fun.(group)
  defp maybe_update_group(group, _key, _fun), do: group

  defp assign_serial_confirm(socket) do
    socket
    |> assign(:serial_confirm_form, to_form(%{"serial" => ""}, as: :serial_confirm))
    |> assign(:serial_confirm_notice, nil)
    |> assign(:serial_confirm_tick, 0)
    |> assign(:last_scanned_serial, nil)
  end

  defp settle_pending_shipper(socket, pending) do
    {:noreply, settle_pending_shipper_socket(socket, pending)}
  end

  defp settle_pending_shipper_socket(socket, %{sscc: sscc, site_id: site_id, groups: groups}) do
    {items, discrepancies} =
      Enum.reduce(groups, {[], []}, fn group, {items_acc, discrepancies_acc} ->
        {group_items, group_discrepancies} = settle_group(group, sscc, site_id)
        {items_acc ++ group_items, discrepancies_acc ++ group_discrepancies}
      end)

    socket
    |> update(:delivery_items, &(&1 ++ items))
    |> update(:pending_discrepancies, &(&1 ++ discrepancies))
    |> assign(:pending_shipper, nil)
    |> assign(:add_item_open, false)
    |> assign(:receipt_step, :sscc)
    |> assign_serial_confirm()
  end

  defp serialized_case?(pending) do
    Enum.any?(pending.groups, fn group ->
      group.small_group? and Enum.any?(group.serials, &is_binary/1)
    end)
  end

  defp scanned_serials(pending), do: Map.get(pending, :scanned_serials, MapSet.new())
  defp reviewed_serials(pending), do: Map.get(pending, :reviewed_serials, MapSet.new())

  defp serial_scanned?(pending, serial), do: MapSet.member?(scanned_serials(pending), serial)

  defp serial_needs_review?(pending, serial) do
    Map.get(pending, :review_unscanned?, false) and
      not serial_scanned?(pending, serial) and
      not MapSet.member?(reviewed_serials(pending), serial)
  end

  defp serial_dom_id(serial) do
    case String.replace(serial, ~r/[^A-Za-z0-9_-]/, "-") do
      "" -> "blank"
      id -> id
    end
  end

  defp parse_nonneg_integer(value) do
    case Integer.parse(to_string(value)) do
      {int, _rest} when int >= 0 -> int
      _ -> 0
    end
  end

  # Small serialized groups: identity is known per unit, so accepted/damaged/
  # missing map directly onto specific serials. Large groups: only a
  # quantity was confirmed, never which specific serials — the resulting
  # batches carry no serials at all rather than fabricating an attribution
  # we can't back up.
  defp settle_group(%{small_group?: true} = group, sscc, site_id) do
    by_condition = Enum.group_by(group.serials, &Map.fetch!(group.serial_conditions, &1))

    good_item = batch_item(group, sscc, site_id, :active, Map.get(by_condition, :accepted, []))

    damaged_item =
      batch_item(group, sscc, site_id, :quarantined, Map.get(by_condition, :damaged, []))

    items = Enum.filter([good_item, damaged_item], & &1)

    discrepancies =
      Map.get(by_condition, :missing, [])
      |> Enum.map(&missing_discrepancy(group, sscc, site_id, 1, &1))

    {items, discrepancies}
  end

  defp settle_group(group, sscc, site_id) do
    good_quantity = group.received_quantity - group.damaged_quantity
    missing_quantity = group.expected_quantity - group.received_quantity

    {good_serials, rest_serials} = Enum.split(group.serials, good_quantity)
    {damaged_serials, _rest_serials} = Enum.split(rest_serials, group.damaged_quantity)

    good_item =
      if good_quantity > 0,
        do: quantity_only_batch_item(group, sscc, site_id, :active, good_quantity, good_serials),
        else: nil

    damaged_item =
      if group.damaged_quantity > 0,
        do:
          quantity_only_batch_item(
            group,
            sscc,
            site_id,
            :quarantined,
            group.damaged_quantity,
            damaged_serials
          ),
        else: nil

    items = Enum.filter([good_item, damaged_item], & &1)

    discrepancies =
      if missing_quantity > 0,
        do: [missing_discrepancy(group, sscc, site_id, missing_quantity, nil)],
        else: []

    {items, discrepancies}
  end

  defp batch_item(_group, _sscc, _site_id, _status, []), do: nil

  defp batch_item(group, sscc, site_id, status, serials) do
    quantity_only_batch_item(group, sscc, site_id, status, length(serials), serials)
  end

  defp quantity_only_batch_item(group, sscc, site_id, status, quantity, serials) do
    attrs = %{
      "product_id" => group.product && group.product.id,
      "gtin" => group.gtin,
      "batch_no" => group.batch_no,
      "manufacture_date" => group.production_date,
      "expiry_date" => group.expiry_date,
      "quantity" => quantity,
      "sscc" => sscc,
      "serials" => serials,
      "site_id" => site_id,
      "status" => Atom.to_string(status)
    }

    %{
      id: System.unique_integer([:positive]),
      attrs: attrs,
      product_name: group.product_name,
      quantity: quantity,
      batch_no: group.batch_no,
      serials: serials,
      uom: group.product && group.product.uom,
      flagged_damaged?: status == :quarantined
    }
  end

  defp missing_discrepancy(group, sscc, site_id, quantity, serial) do
    %{
      "sscc" => sscc,
      "gtin" => group.gtin,
      "batch_no" => group.batch_no,
      "serial" => serial,
      "quantity" => quantity,
      "product_id" => group.product && group.product.id,
      "site_id" => site_id,
      "expiry_date" => group.expiry_date
    }
  end

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

  # Stock is counted in packs. A product added during receiving is stored as one pack.
  defp stock_unit_attrs(attrs) do
    if attrs["uom"] in [nil, ""], do: Map.put(attrs, "uom", "C62"), else: attrs
  end

  defp start_new_product(socket, gtin, name \\ nil) do
    attrs = %{"gtin" => gtin, "uom" => "C62"}

    attrs =
      if is_binary(name) and String.trim(name) not in ["", "Unknown product"] do
        Map.put(attrs, "generic_name", String.trim(name))
      else
        attrs
      end

    socket
    |> assign(:receipt_step, :new_product)
    |> assign(:scan_error, nil)
    |> assign(
      :new_product_form,
      to_form(Product.changeset(%Product{}, attrs), as: :product)
    )
  end

  defp add_delivery_item(attrs, socket) do
    product = socket.assigns.selected_product

    attrs =
      attrs
      |> Map.put("product_id", product && product.id)
      |> Map.put("gtin", product && product.gtin)
      |> put_existing_serials(socket)
      |> put_serial_quantity()

    changeset = receipt_changeset(socket, attrs)
    quantity = Ecto.Changeset.get_field(changeset, :quantity)

    if changeset.valid? and is_integer(quantity) and quantity > 0 do
      stage_delivery_item(socket, product, attrs, quantity)
    else
      show_delivery_item_errors(socket, changeset, quantity)
    end
  end

  # The batch form has no field for `serials` — editing an item's batch
  # details (via the form) must not lose the serials the SSCC lookup
  # originally attached to it.
  defp put_existing_serials(attrs, %{assigns: %{editing_delivery_item_id: id}} = socket)
       when not is_nil(id) do
    case Enum.find(socket.assigns.delivery_items, &(&1.id == id)) do
      %{attrs: %{"serials" => serials}} -> Map.put(attrs, "serials", serials)
      _ -> attrs
    end
  end

  defp put_existing_serials(attrs, _socket), do: attrs

  # A serial is one trade item. The quantity is the number of serials, and a
  # typed pack size must not replace it.
  defp put_serial_quantity(attrs) do
    case item_serials(attrs) do
      [] -> attrs
      serials -> Map.put(attrs, "quantity", length(serials))
    end
  end

  defp assign_locked_quantity(socket, attrs) do
    serials =
      case item_serials(attrs) do
        [] -> editing_serials(socket)
        serials -> serials
      end

    case serials do
      [] -> assign(socket, :locked_unit_quantity, nil)
      serials -> assign(socket, :locked_unit_quantity, length(serials))
    end
  end

  defp editing_serials(%{assigns: %{editing_delivery_item_id: id, delivery_items: items}})
       when not is_nil(id) do
    case Enum.find(items, &(&1.id == id)) do
      %{attrs: attrs} -> item_serials(attrs)
      _ -> []
    end
  end

  defp editing_serials(_socket), do: []

  defp item_serials(%{"serials" => serials}) when is_list(serials), do: serials
  defp item_serials(%{serials: serials}) when is_list(serials), do: serials
  defp item_serials(_attrs), do: []

  defp stage_delivery_item(socket, product, attrs, quantity) do
    item = %{
      id: socket.assigns.editing_delivery_item_id || System.unique_integer([:positive]),
      attrs: attrs,
      product_name: product_name(socket.assigns.products, product.id),
      quantity: quantity,
      batch_no: Map.get(attrs, "batch_no"),
      serials: Map.get(attrs, "serials", []),
      uom: product.uom
    }

    delivery_items =
      case socket.assigns.editing_delivery_item_id do
        nil -> socket.assigns.delivery_items ++ [item]
        editing_id -> replace_delivery_item(socket.assigns.delivery_items, editing_id, item)
      end

    # A single SSCC can contain several batches of the same GTIN. Once that GTIN
    # is added to the receiving catalog, all of its staged lines are valid—not
    # just the row the user happened to edit.
    delivery_items =
      associate_staged_items_with_product(delivery_items, product, socket.assigns.products)

    socket
    |> assign(:delivery_items, delivery_items)
    |> assign(:receipt_step, :sscc)
    |> assign(:selected_product, nil)
    |> assign(:editing_delivery_item_id, nil)
    |> assign(:locked_unit_quantity, nil)
    |> assign(:form, nil)
    |> assign(:scan_error, nil)
    |> assign(:scan_form, to_form(%{"gtin" => ""}, as: :scan))
    |> assign(:entry_sscc_form, to_form(%{"sscc" => ""}, as: :sscc_entry))
    |> assign(:entry_sscc_check, :idle)
    |> assign(:carried_attrs, %{})
    |> assign(:add_item_open, false)
  end

  defp replace_delivery_item(items, editing_id, item) do
    Enum.map(items, fn existing ->
      if existing.id == editing_id, do: item, else: existing
    end)
  end

  defp associate_staged_items_with_product(items, product, products) do
    display_name = product_name(products, product.id)

    Enum.map(items, fn item ->
      if item.attrs["gtin"] == product.gtin do
        %{
          item
          | attrs: Map.put(item.attrs, "product_id", product.id),
            product_name: display_name,
            uom: product.uom
        }
      else
        item
      end
    end)
  end

  defp delivery_item_groups(items) do
    {order, grouped_items} =
      Enum.reduce(items, {[], %{}}, fn item, {order, groups} ->
        sscc = Map.get(item.attrs, "sscc") || "manual"

        if Map.has_key?(groups, sscc) do
          {order, Map.update!(groups, sscc, &(&1 ++ [item]))}
        else
          {order ++ [sscc], Map.put(groups, sscc, [item])}
        end
      end)

    Enum.map(order, &%{sscc: &1, items: Map.fetch!(grouped_items, &1)})
  end

  defp delivery_batch_groups(items) do
    items
    |> Enum.group_by(
      &{&1.product_name, &1.attrs["gtin"], &1.batch_no, &1.attrs["expiry_date"], &1.uom}
    )
    |> Enum.map(fn {{product_name, gtin, batch_no, expiry, uom}, batch_items} ->
      %{
        product_name: product_name,
        gtin: gtin,
        batch_no: batch_no,
        expiry: expiry,
        uom: uom,
        quantity: batch_items |> Enum.map(&(&1.quantity || 0)) |> Enum.sum(),
        items: batch_items
      }
    end)
  end

  defp shipper_units(items), do: items |> Enum.map(&(&1.quantity || 0)) |> Enum.sum()

  attr :batch, :map, required: true

  defp delivery_batch(assigns) do
    assigns =
      assign(
        assigns,
        :missing_catalog_item,
        Enum.find(assigns.batch.items, &is_nil(&1.attrs["product_id"]))
      )

    ~H"""
    <div class="border-b border-thamani-stone last:border-b-0">
      <div class="grid grid-cols-2 gap-x-4 gap-y-3 px-4 py-3.5 sm:grid-cols-4 sm:px-5">
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-thamani-evergreen" title={@batch.product_name}>
            {@batch.product_name}
          </p>
          <p
            :if={@batch.gtin}
            class="mt-0.5 truncate text-xs tabular-nums tracking-tight text-thamani-pewter"
          >
            {@batch.gtin}
          </p>
          <button
            :if={@missing_catalog_item}
            type="button"
            id={"add-to-catalog-#{@missing_catalog_item.id}"}
            phx-click="edit_delivery_item"
            phx-value-id={@missing_catalog_item.id}
            class="mt-1 text-left text-xs font-semibold text-amber-900 underline decoration-amber-900/40 underline-offset-2 hover:decoration-amber-900"
          >
            Not in your catalog. Add it.
          </button>
        </div>
        <div class="min-w-0">
          <p class="text-xs font-medium text-thamani-pewter">Batch</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen [overflow-wrap:anywhere]">
            {@batch.batch_no}
          </p>
        </div>
        <div>
          <p class="text-xs font-medium text-thamani-pewter">Expiry</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums text-thamani-evergreen">
            {format_group_expiry(@batch.expiry)}
          </p>
        </div>
        <div>
          <p class="text-xs font-medium text-thamani-pewter">Units</p>
          <p class="mt-0.5 text-sm font-medium tabular-nums text-thamani-evergreen">
            {Products.format_unit_count(@batch.quantity)}
          </p>
        </div>
      </div>

      <div
        :for={item <- @batch.items}
        class="border-t border-thamani-stone bg-thamani-canvas/60 px-4 py-3 sm:px-5"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span
            :if={item[:flagged_damaged?]}
            class="inline-flex items-center rounded-full bg-amber-900 px-2 py-0.5 text-xs font-medium text-amber-50"
          >
            Damaged
          </span>
          <div class="flex shrink-0 items-center">
            <button
              type="button"
              phx-click="edit_delivery_item"
              phx-value-id={item.id}
              aria-label={"Edit #{item.batch_no}"}
              title="Edit"
              class="inline-flex size-8 items-center justify-center rounded-full text-thamani-pewter transition-colors hover:bg-thamani-canvas hover:text-thamani-evergreen focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
            >
              <.icon name="hero-pencil-square" class="size-4" />
            </button>
            <button
              type="button"
              phx-click="remove_delivery_item"
              phx-value-id={item.id}
              aria-label={"Remove #{item.batch_no}"}
              title="Remove"
              class="inline-flex size-8 items-center justify-center rounded-full text-thamani-pewter transition-colors hover:bg-rose-50 hover:text-thamani-error focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
        </div>

        <p :if={item_serials(item) == []} class="mt-2 text-xs text-thamani-pewter">
          {Products.format_unit_count(item.quantity)} · No serial recorded
        </p>

        <details :if={item_serials(item) != []} class="mt-2 group">
          <summary class="w-fit cursor-pointer list-none text-xs font-medium text-thamani-pewter hover:text-thamani-evergreen">
            <span class="inline-flex items-center gap-1">
              <.icon
                name="hero-chevron-right"
                class="size-3.5 transition-transform group-open:rotate-90"
              />
              {length(item_serials(item))} serial(s)
            </span>
          </summary>
          <ul class="mt-2 flex flex-wrap gap-1.5">
            <li
              :for={serial <- item_serials(item)}
              class="rounded-lg border border-thamani-stone bg-td-surface px-2 py-1 text-xs font-medium tabular-nums tracking-tight text-thamani-evergreen"
            >
              {serial}
            </li>
          </ul>
        </details>
      </div>
    </div>
    """
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

      attrs = Map.put(attrs, "site_id", socket.assigns.receiving_site.id)

      attrs = Map.merge(attrs, socket.assigns.carried_attrs)

      socket
      |> assign(:selected_product, product)
      |> assign(:receipt_step, :details)
      |> assign(:scan_error, nil)
      |> assign(:carried_attrs, %{})
      |> assign_locked_quantity(attrs)
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
    # site_id is now always required for all batches — even single-site orgs
    # and warehouse-only orgs must explicitly assign a destination site
    changeset = Batch.changeset(%Batch{}, attrs)

    # A distributor org's origin party is resolved once for the whole
    # receipt (see `origin_check`/`origin_payload`), not picked per line —
    # every other org type still requires a `Suppliers.Supplier` per item.
    required_fields =
      if socket.assigns.distributor_org?, do: [:sscc], else: [:supplier_id, :sscc]

    Ecto.Changeset.validate_required(changeset, required_fields,
      message: "is required for a delivery receipt"
    )
  end

  defp delivery_error_flash(changeset) do
    case List.keyfind(changeset.errors, :batch_no, 0) do
      {:batch_no, {"has already been dispatched to this site in this status", _opts}} ->
        batch_no = Ecto.Changeset.get_field(changeset, :batch_no)
        "#{batch_no} is already at this site. Remove the duplicate line."

      _ ->
        detail =
          Enum.map_join(changeset.errors, ", ", fn {field, {message, _opts}} ->
            "#{field} #{message}"
          end)

        "Delivery could not be posted: " <> detail
    end
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
    Enum.filter(receipts, fn receipt ->
      Enum.any?(receipt.items, &(&1.site_id == site_id)) or
        Enum.any?(receipt.discrepancies, &(&1.site_id == site_id))
    end)
  end

  defp open_discrepancy_count(receipt) do
    Enum.count(receipt.discrepancies, &(&1.status == :open))
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

  # Selected segment of the per-serial condition control. "Accepted" stays quiet
  # (it is the default on every row); damaged and missing take a solid fill
  # so exceptions are the only thing that shouts.
  defp serial_condition_classes("accepted"), do: "bg-td-surface text-thamani-forest"
  defp serial_condition_classes("damaged"), do: "bg-amber-900 text-amber-50"
  defp serial_condition_classes("missing"), do: "bg-thamani-error text-td-on-danger"

  defp product_sections(groups) do
    groups
    |> Enum.group_by(& &1.gtin)
    |> Enum.map(fn {_gtin, product_groups} ->
      shared_expiry =
        case product_groups |> Enum.map(& &1.expiry_date) |> Enum.uniq() do
          [expiry] when not is_nil(expiry) -> expiry
          _ -> nil
        end

      %{
        product_name: hd(product_groups).product_name,
        shared_expiry: shared_expiry,
        groups: product_groups
      }
    end)
  end

  defp format_group_expiry(%Date{} = date), do: Calendar.strftime(date, "%d %b %Y")
  defp format_group_expiry(nil), do: "—"

  defp format_group_expiry(other) do
    case Date.from_iso8601(to_string(other)) do
      {:ok, date} -> Calendar.strftime(date, "%d %b %Y")
      _ -> to_string(other)
    end
  end

  attr :serial, :string, required: true
  attr :last_serial, :string, default: nil
  attr :tick, :integer, required: true

  defp serial_row_flash(assigns) do
    ~H"""
    <span
      :if={@last_serial == @serial and @tick > 0}
      id={"serial-row-flash-#{serial_dom_id(@serial)}-#{@tick}"}
      class="serial-row-flash"
      aria-hidden="true"
    />
    """
  end

  attr :pending, :map, required: true
  attr :serial, :string, required: true

  defp serial_status(assigns) do
    ~H"""
    <span
      :if={serial_scanned?(@pending, @serial)}
      id={"serial-scanned-#{serial_dom_id(@serial)}"}
      class="serial-scanned-pill ml-2 inline-flex items-center gap-1 rounded-full bg-td-accent-tint px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-thamani-forest"
    >
      <.icon name="hero-check" class="size-3" /> Scanned
    </span>
    <span
      :if={serial_needs_review?(@pending, @serial)}
      id={"serial-unscanned-#{serial_dom_id(@serial)}"}
      class="ml-2 inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-amber-950"
    >
      Confirm
    </span>
    """
  end

  attr :group, :map, required: true
  attr :serial, :string, required: true

  defp condition_control(assigns) do
    ~H"""
    <div
      role="radiogroup"
      aria-label={"Condition for #{@serial}"}
      class="relative z-[1] grid w-full shrink-0 grid-cols-3 gap-0.5 rounded-full bg-thamani-stone p-0.5 sm:w-64"
    >
      <button
        :for={
          {condition, label} <- [
            {"accepted", "Accepted"},
            {"damaged", "Damaged"},
            {"missing", "Missing"}
          ]
        }
        type="button"
        role="radio"
        aria-checked={
          to_string(Map.get(@group.serial_conditions, @serial) == String.to_atom(condition))
        }
        phx-click="set_serial_condition"
        phx-value-key={@group.key}
        phx-value-serial={@serial}
        phx-value-condition={condition}
        class={[
          "inline-flex h-8 items-center justify-center rounded-full text-xs font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-1",
          Map.get(@group.serial_conditions, @serial) == String.to_atom(condition) &&
            serial_condition_classes(condition),
          Map.get(@group.serial_conditions, @serial) != String.to_atom(condition) &&
            "text-thamani-pewter hover:text-thamani-forest"
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

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

  defp doc_upload_error_to_string(:too_large), do: "File is too large (max 5MB)."
  defp doc_upload_error_to_string(:too_many_files), do: "Choose fewer files."
  defp doc_upload_error_to_string(:not_accepted), do: "Must be a PDF or image file."
  defp doc_upload_error_to_string(_), do: "Couldn't accept this file."

  defp draft_attachments(attachments, doc_type) do
    Enum.filter(attachments || [], &(&1.doc_type == doc_type))
  end

  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :upload, :map, required: true
  attr :saved_attachments, :list, default: []

  defp doc_upload_slot(assigns) do
    ~H"""
    <section
      id={"#{@name}-upload"}
      class="py-3 transition-colors first:pt-1 last:pb-1 hover:bg-thamani-canvas/70 sm:px-3"
      phx-drop-target={@upload.ref}
    >
      <div class="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div class="flex min-w-0 items-center gap-3">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-td-accent-tint text-thamani-forest">
            <.icon name="hero-document" class="size-5" />
          </span>
          <div class="min-w-0 border-l border-td-hairline pl-3">
            <h4 class="text-xs font-bold uppercase tracking-wide text-thamani-forest">{@label}</h4>
            <p class="mt-1 text-[11px] leading-4 text-thamani-pewter">
              PDF, JPG, or PNG · up to 5MB{if @upload.max_entries > 1,
                do: " each, up to #{@upload.max_entries} files"}
            </p>
          </div>
        </div>
        <label class="group inline-flex w-fit shrink-0 cursor-pointer items-center rounded-full border border-thamani-forest bg-td-surface px-4 py-1.5 text-xs font-semibold transition-colors hover:bg-thamani-forest focus-within:ring-2 focus-within:ring-thamani-accent focus-within:ring-offset-2">
          <span class="text-thamani-forest group-hover:text-white">
            {if @upload.max_entries == 1 and @saved_attachments != [],
              do: "Replace file",
              else: "Choose file#{if @upload.max_entries > 1, do: "s"}"}
          </span>
          <.live_file_input upload={@upload} class="sr-only" />
        </label>
      </div>

      <div :if={@upload.entries != []} class="mt-3 space-y-2 sm:ml-12" aria-live="polite">
        <div
          :for={entry <- @upload.entries}
          id={"#{@name}-upload-#{entry.ref}"}
          class="rounded-lg border border-thamani-stone bg-td-surface px-3 py-2"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="truncate text-xs font-medium text-thamani-forest" title={entry.client_name}>
              {entry.client_name}
            </span>
            <button
              type="button"
              phx-click="cancel_doc_upload"
              phx-value-ref={entry.ref}
              phx-value-upload={@name}
              class="shrink-0 text-xs font-medium text-thamani-error hover:underline"
            >
              Remove
            </button>
          </div>

          <div :if={entry.progress < 100} class="mt-2">
            <div class="flex justify-between text-[11px] text-thamani-pewter">
              <span>Uploading</span><span>{entry.progress}%</span>
            </div>
            <div class="mt-1 h-1.5 overflow-hidden rounded-full bg-thamani-stone">
              <div
                class="h-full rounded-full bg-thamani-forest transition-all"
                style={"width: #{entry.progress}%"}
              >
              </div>
            </div>
          </div>

          <p
            :if={entry.progress == 100 and upload_errors(@upload, entry) == []}
            class="mt-1 inline-flex items-center gap-1 text-[11px] font-medium text-emerald-700"
          >
            <.icon name="hero-check-circle" class="size-3.5" /> Upload complete.
          </p>
          <p
            :for={err <- upload_errors(@upload, entry)}
            class="mt-1 text-[11px] font-medium text-red-700"
          >
            {doc_upload_error_to_string(err)}
          </p>
        </div>
      </div>
      <div :if={@saved_attachments != []} class="mt-3 space-y-2 sm:ml-12" aria-live="polite">
        <div
          :for={attachment <- @saved_attachments}
          class="flex min-w-0 items-center gap-2 text-[11px] font-medium text-emerald-700"
        >
          <.icon name="hero-check-circle" class="size-3.5 shrink-0" />
          <span class="truncate" title={attachment.filename}>{attachment.filename} saved</span>
          <button
            type="button"
            phx-click="delete_draft_attachment"
            phx-value-id={attachment.id}
            class="shrink-0 text-thamani-error hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
            aria-label={"Remove #{attachment.filename}"}
          >
            Remove
          </button>
        </div>
      </div>
      <p
        :for={err <- upload_errors(@upload)}
        class="mt-2 text-[11px] font-medium text-red-700 sm:ml-12"
      >
        {doc_upload_error_to_string(err)}
      </p>
    </section>
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
      <%= if @receiving_new? and @receiving_portal == :organization do %>
        <div class="td-recipe">
          <div class="td-back">
            <.link navigate={@receiving_index_path} class="td-back-link">
              <.td_icon name="arrow-left" class="size-3.5" /> Back to Receiving
            </.link>
          </div>
          <.td_page_header
            title="Receive inventory"
            subtitle={"Check in a delivery directly into #{@receiving_site.name}."}
          >
            <:actions>
              <.td_button variant="secondary" patch={@receiving_index_path} label="Cancel" />
              <.td_button
                id="finish-org-delivery"
                variant="primary"
                label="Receive stock"
                phx-click="finish_delivery"
              />
            </:actions>
          </.td_page_header>
        </div>
      <% else %>
      <.header :if={@receiving_new?} icon="hero-arrow-down-tray">
        Receive stock
        <:subtitle>
          Scan or select each item as it comes off the truck, then add its batch details.
        </:subtitle>
        <:actions>
          <.button variant="ghost" patch={@receiving_index_path}>Cancel</.button>
        </:actions>
      </.header>
      <% end %>

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
        :if={@receiving_new? and (@distributor_org? or @receiving_portal == :organization)}
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
            value={@origin_gln}
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
            <div class="rounded-lg bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] px-3 py-2.5 text-xs font-semibold text-thamani-forest">
              <p class="inline-flex items-center gap-1.5">
                <.icon name="hero-check-circle" class="size-4" /> Verified · {resolved.company}
              </p>
              <p :if={resolved.address} class="mt-1 font-normal">{resolved.address}</p>
            </div>
          <% {:invalid, message} -> %>
            <p
              id="origin-gln-error"
              class="inline-flex items-center gap-1.5 rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-800"
            >
              <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
              {message}
            </p>
          <% :same_receiving_site -> %>
            <p class="inline-flex items-center gap-1.5 rounded-lg bg-red-50 px-3 py-2 text-xs font-semibold text-red-800">
              <.icon name="hero-exclamation-triangle" class="size-4" />
              This is the GLN for the site receiving this delivery. Enter the GLN of the sending
              site or supplier instead.
            </p>
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
        <% end %>
      </div>

      <section
        :if={@receiving_new?}
        id="delivery-documents"
        class="mb-4 rounded-2xl ff-surface-card p-5 sm:p-6"
      >
        <h3 class="text-lg font-semibold text-thamani-forest">Delivery documents</h3>
        <p class="mt-1 text-sm text-thamani-pewter">
          Attach the delivery note, invoice, and purchase order for this delivery, plus any other supporting documents.
        </p>
        <form
          id="distributor-document-uploads-form"
          phx-change="validate_uploads"
          class="mt-4 divide-y divide-td-hairline"
        >
          <.doc_upload_slot
            label="Delivery note"
            name="doc_delivery_note"
            upload={@uploads.doc_delivery_note}
            saved_attachments={draft_attachments(@draft_attachments, :delivery_note)}
          />
          <.doc_upload_slot
            label="Invoice"
            name="doc_invoice"
            upload={@uploads.doc_invoice}
            saved_attachments={draft_attachments(@draft_attachments, :invoice)}
          />
          <.doc_upload_slot
            label="Purchase order"
            name="doc_po"
            upload={@uploads.doc_po}
            saved_attachments={draft_attachments(@draft_attachments, :po)}
          />
          <.doc_upload_slot
            label="Other documents"
            name="doc_other"
            upload={@uploads.doc_other}
            saved_attachments={draft_attachments(@draft_attachments, :other)}
          />
        </form>
      </section>

      <div :if={@receiving_new?} class="rounded-2xl ff-surface-card p-5 sm:p-6">
        <div :if={@delivery_items == []} class="py-6">
          <.blank_state icon="hero-arrow-down-tray" title="No items added yet">
            Scan or select the first product in this delivery.
            <:actions>
              <.button id="open-add-item-empty" variant="primary" phx-click="open_add_item">
                <.icon name="hero-plus" class="size-4" /> Enter shipper SSCC
              </.button>
            </:actions>
          </.blank_state>
        </div>
        <div :if={@delivery_items != []}>
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-semibold text-thamani-forest">Items in this delivery</h3>
            <.button id="open-add-item-bottom" variant="ghost" phx-click="open_add_item">
              <.icon name="hero-plus" class="size-4" /> Enter shipper SSCC
            </.button>
          </div>
          <div class="mt-3 space-y-4">
            <article
              :for={{shipper, index} <- Enum.with_index(delivery_item_groups(@delivery_items), 1)}
              id={"delivery-shipper-#{index}"}
              class="overflow-hidden rounded-2xl ff-surface-card"
            >
              <header class="flex flex-wrap items-center justify-between gap-3 border-b border-thamani-stone px-4 py-3 sm:px-5">
                <div class="flex items-center gap-3">
                  <span class="flex size-8 items-center justify-center rounded-lg bg-thamani-canvas text-sm font-semibold text-thamani-forest">
                    {index}
                  </span>
                  <div>
                    <p class="font-medium text-thamani-evergreen">
                      {if shipper.sscc == "manual", do: "No case label", else: "Case"}
                    </p>
                    <p class="text-xs tabular-nums text-thamani-pewter">
                      {shipper_units(shipper.items)}
                      {if shipper_units(shipper.items) == 1, do: "unit", else: "units"}
                    </p>
                  </div>
                </div>
                <span
                  :if={shipper.sscc != "manual"}
                  class="rounded-lg bg-td-accent-tint px-3 py-1 text-xs font-semibold tabular-nums tracking-tight text-thamani-forest"
                >
                  SSCC {shipper.sscc}
                </span>
              </header>

              <.delivery_batch :for={batch <- delivery_batch_groups(shipper.items)} batch={batch} />
            </article>
          </div>
          <.button
            :if={@receiving_portal != :organization}
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
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
            {cond do
              @receipt_step == :sscc -> "Enter SSCC"
              @receipt_step == :confirm_shipper -> "Confirm this case's contents"
              @receipt_step == :new_product -> "Add to catalog"
              true -> "Add item"
            end}
          </h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            {cond do
              @receipt_step == :sscc ->
                "Scan or type the case label's SSCC to pull in its contents."

              @receipt_step == :confirm_shipper ->
                "Unmarked contents stay accepted. Flag anything damaged or missing before adding it."

              @receipt_step == :new_product ->
                "This GTIN is not in your catalog yet. Save the product and its batch stays on this delivery."

              true ->
                "Scan or select the product, then add its batch details."
            end}
          </p>
        </div>

        <%= cond do %>
          <% @receipt_step == :sscc -> %>
            <.form
              for={@entry_sscc_form}
              id="distributor-entry-sscc-form"
              phx-change="validate_entry_sscc"
              class="mt-5"
            >
              <.input
                field={@entry_sscc_form[:sscc]}
                label="Case label SSCC"
                placeholder="e.g. 007923810000000013"
                autocomplete="off"
                phx-debounce="350"
                class="font-medium tabular-nums tracking-tight text-thamani-forest"
              />
            </.form>

            <%= case @entry_sscc_check do %>
              <% :checking -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-thamani-pewter">
                  <.icon name="hero-arrow-path" class="size-3.5 motion-safe:animate-spin" />
                  Looking up this SSCC&hellip;
                </p>
              <% {:matched, _shipper} -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 text-xs font-semibold text-thamani-forest">
                  <.icon name="hero-check-circle" class="size-4" /> Found it — contents loaded below.
                </p>
              <% :not_found -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                  GS1 has no record of this SSCC. Add the item manually instead.
                </p>
              <% :unavailable -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                  GS1 could not be reached for this SSCC. Try again, or add the item manually.
                </p>
              <% {:duplicate, sscc} -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                  Case {sscc} has already been added to this delivery — check "Items in this delivery" below.
                </p>
              <% _ -> %>
                <p class="mt-2 text-xs text-thamani-pewter">
                  Recognized SSCCs auto-fill their batch, quantity, and expiry details.
                </p>
            <% end %>

            <div class="my-5 flex items-center gap-3 text-xs font-semibold tracking-widest text-thamani-subtle">
              <span class="h-px flex-1 bg-thamani-stone"></span>OR<span class="h-px flex-1 bg-thamani-stone"></span>
            </div>
            <button
              type="button"
              phx-click="skip_to_manual_entry"
              class="text-sm font-semibold text-thamani-forest hover:underline"
            >
              Scan or select the product instead
            </button>
          <% @receipt_step == :confirm_shipper -> %>
            <div class="mt-5">
              <div class="mt-4 max-h-[min(28rem,55vh)] overflow-y-auto overscroll-contain rounded-2xl border border-thamani-frosted bg-td-surface">
                <section
                  :for={section <- product_sections(@pending_shipper.groups)}
                  class="border-b border-thamani-frosted last:border-b-0"
                >
                  <header class="bg-thamani-canvas px-4 py-3">
                    <h3 class="text-sm font-semibold tracking-tight text-thamani-evergreen">
                      {section.product_name}
                    </h3>
                    <p :if={section.shared_expiry} class="mt-0.5 text-sm text-thamani-pewter">
                      Expires
                      <span class="font-medium tabular-nums text-thamani-evergreen">
                        {format_group_expiry(section.shared_expiry)}
                      </span>
                    </p>
                  </header>

                  <div
                    :for={group <- section.groups}
                    id={"pending-group-#{group.key}"}
                    class="border-t border-thamani-frosted"
                  >
                    <div
                      :if={group.small_group? and length(group.serials) == 1}
                      id={"pending-serial-#{serial_dom_id(hd(group.serials))}"}
                      class={[
                        "relative isolate flex flex-col gap-2 overflow-hidden px-4 py-2.5 sm:flex-row sm:items-center sm:justify-between sm:gap-4",
                        serial_needs_review?(@pending_shipper, hd(group.serials)) && "bg-amber-50"
                      ]}
                    >
                      <.serial_row_flash
                        serial={hd(group.serials)}
                        last_serial={@last_scanned_serial}
                        tick={@serial_confirm_tick}
                      />
                      <p class="relative z-[1] min-w-0 text-sm text-thamani-pewter">
                        <span class="font-medium tabular-nums tracking-tight text-thamani-evergreen">
                          {group.batch_no}
                        </span>
                        <span class="mx-1.5 text-thamani-pewter" aria-hidden="true">·</span>
                        <span
                          class="font-medium tabular-nums tracking-tight text-thamani-evergreen [overflow-wrap:anywhere]"
                          title={hd(group.serials)}
                        >
                          {hd(group.serials)}
                        </span>
                        <.serial_status pending={@pending_shipper} serial={hd(group.serials)} />
                        <span :if={is_nil(section.shared_expiry)} class="ml-1.5 tabular-nums">
                          {format_group_expiry(group.expiry_date)}
                        </span>
                      </p>
                      <.condition_control group={group} serial={hd(group.serials)} />
                    </div>

                    <div :if={group.small_group? and length(group.serials) != 1} class="px-4 py-3">
                      <p class="text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen">
                        {group.batch_no}
                      </p>
                      <p
                        :if={is_nil(section.shared_expiry)}
                        class="mt-0.5 text-xs tabular-nums text-thamani-pewter"
                      >
                        Expires {format_group_expiry(group.expiry_date)}
                      </p>
                      <div
                        :for={serial <- group.serials}
                        id={"pending-serial-#{serial_dom_id(serial)}"}
                        class={[
                          "relative isolate mt-2 flex flex-col gap-2 overflow-hidden sm:flex-row sm:items-center sm:justify-between sm:gap-4",
                          serial_needs_review?(@pending_shipper, serial) &&
                            "-mx-4 bg-amber-50 px-4 py-2"
                        ]}
                      >
                        <.serial_row_flash
                          serial={serial}
                          last_serial={@last_scanned_serial}
                          tick={@serial_confirm_tick}
                        />
                        <span
                          class="relative z-[1] min-w-0 text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen [overflow-wrap:anywhere]"
                          title={serial}
                        >
                          {serial}
                          <.serial_status pending={@pending_shipper} serial={serial} />
                        </span>
                        <.condition_control group={group} serial={serial} />
                      </div>
                    </div>

                    <div :if={!group.small_group?} class="px-4 py-3">
                      <div class="flex items-baseline justify-between gap-3">
                        <p class="min-w-0 text-sm font-medium tabular-nums tracking-tight text-thamani-evergreen">
                          {group.batch_no}
                        </p>
                        <p class="shrink-0 text-xs text-thamani-pewter">
                          Expected
                          <span class="font-semibold tabular-nums text-thamani-evergreen">
                            {group.expected_quantity}
                          </span>
                        </p>
                      </div>
                      <p
                        :if={is_nil(section.shared_expiry)}
                        class="mt-0.5 text-xs tabular-nums text-thamani-pewter"
                      >
                        Expires {format_group_expiry(group.expiry_date)}
                      </p>
                      <form
                        id={"pending-group-quantities-#{group.key}"}
                        class="mt-3 grid gap-3 sm:grid-cols-2"
                        phx-value-key={group.key}
                      >
                        <label class="block">
                          <span class="text-xs font-medium text-thamani-pewter">Received</span>
                          <input
                            type="number"
                            min="0"
                            max={group.expected_quantity}
                            value={group.received_quantity}
                            phx-change="set_group_received_quantity"
                            name="value"
                            class="thamani-input mt-1 w-full"
                          />
                        </label>
                        <label class="block">
                          <span class="text-xs font-medium text-thamani-pewter">
                            Damaged, of those received
                          </span>
                          <input
                            type="number"
                            min="0"
                            max={group.received_quantity}
                            value={group.damaged_quantity}
                            phx-change="set_group_damaged_quantity"
                            name="value"
                            class="thamani-input mt-1 w-full"
                          />
                        </label>
                        <p
                          :if={group.received_quantity < group.expected_quantity}
                          class="text-xs font-medium text-amber-900 sm:col-span-2"
                        >
                          {group.expected_quantity - group.received_quantity} not received. These are flagged missing without serials.
                        </p>
                      </form>
                    </div>
                  </div>
                </section>
              </div>

              <div class="mt-4 flex gap-3">
                <button
                  type="button"
                  id="cancel-pending-shipper"
                  phx-click="cancel_pending_shipper"
                  class="flex-1 rounded-full border border-thamani-stone px-4 py-2.5 text-sm font-semibold text-thamani-forest transition-colors hover:bg-thamani-canvas focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  id="confirm-pending-shipper"
                  phx-click="confirm_pending_shipper"
                  class="flex-1 rounded-full bg-thamani-forest px-4 py-2.5 text-sm font-semibold text-td-on-accent transition-colors hover:opacity-90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
                >
                  Accept all and add to delivery
                </button>
              </div>
            </div>
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
              <input type="hidden" name="product[uom]" value="C62" />
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@new_product_form[:generic_name]} label="Generic name" />
                <.input field={@new_product_form[:brand_name]} label="Brand name" />
                <.input
                  field={@new_product_form[:net_content_uom]}
                  type="select"
                  label="Unit of measure (UOM)"
                  prompt="Tablets, capsules, ml"
                  options={[
                    {"Tablets", "U2"},
                    {"Capsules", "AV"},
                    {"Millilitres", "MLT"},
                    {"Pieces", "H87"}
                  ]}
                />
                <.input
                  field={@new_product_form[:net_content_quantity]}
                  type="number"
                  label="Qty (optional)"
                  placeholder="e.g. 20"
                  min="1"
                />
                <.input field={@new_product_form[:category]} label="Category" />
                <.input
                  field={@new_product_form[:price]}
                  type="number"
                  label="Price (KSh)"
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
                <.date_picker field={@form[:expiry_date]} label="Expiry date" required />
              </div>
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@form[:manufacturer]} label="Manufacturer (optional)" />
                <.date_picker
                  field={@form[:manufacture_date]}
                  label="Manufacture date (optional)"
                />
              </div>
              <p
                :if={Products.format_net_content(@selected_product)}
                id="unit-net-content"
                class="mb-3 text-xs text-thamani-pewter"
              >
                Each pack contains {Products.format_net_content(@selected_product)}.
              </p>
              <div class="grid gap-x-4 sm:grid-cols-2">
                <div :if={@locked_unit_quantity} id="locked-unit-quantity">
                  <p class="mb-1 text-sm font-medium text-thamani-forest">Quantity received</p>
                  <p class="mb-3 text-sm font-medium tabular-nums text-thamani-evergreen">
                    {Products.format_unit_count(@locked_unit_quantity)}
                  </p>
                  <input type="hidden" name="batch[quantity]" value={@locked_unit_quantity} />
                </div>
                <.input
                  :if={is_nil(@locked_unit_quantity)}
                  field={@form[:quantity]}
                  type="number"
                  label="Quantity received (units)"
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
                class="font-medium tabular-nums tracking-tight text-thamani-forest"
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
          <p
            :if={open_discrepancy_count(receipt) > 0}
            id={"receipt-open-lines-#{receipt.id}"}
            class="mt-1 text-xs font-semibold text-amber-800"
          >
            {open_discrepancy_count(receipt)} not confirmed
          </p>
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
