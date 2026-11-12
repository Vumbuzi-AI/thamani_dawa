defmodule ThamaniDawaWeb.DistributorReceivingLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawa.GoodsReceipts
  alias ThamaniDawa.Products
  alias ThamaniDawa.Products.Product
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Suppliers
  alias ThamaniDawaWeb.DistributorPagination

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    receiving_portal =
      if socket.assigns.current_scope.user.role == :admin, do: :organization, else: :distributor

    {receiving_index_path, receiving_new_path} =
      if receiving_portal == :organization,
        do: {~p"/org/receiving", ~p"/org/receiving/new"},
        else: {~p"/distributor/receiving", ~p"/distributor/receiving/new"}

    {:ok,
     socket
     |> assign(:receiving_portal, receiving_portal)
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
     |> assign(:page_number, 1)
     |> reload_receipts()}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page_number, DistributorPagination.page_number(params))
      |> reload_receipts()

    if socket.assigns.live_action == :new do
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
       |> assign(:form, nil)}
    else
      {:noreply,
       assign(socket,
         form: nil,
         selected_product: nil,
         receipt_step: :product,
         delivery_items: [],
         receipt_posting_key: Ecto.UUID.generate(),
         editing_delivery_item_id: nil,
         new_product_form: nil
       )}
    end
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
       |> assign(:editing_delivery_item_id, item.id)
       |> assign(:selected_product, product)
       |> assign(:receipt_step, :details)
       |> assign(:form, to_form(receipt_changeset(socket, item.attrs), as: :batch))}
    else
      {:noreply, put_flash(socket, :error, "That staged receipt item could not be found.")}
    end
  end

  def handle_event("finish_delivery", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    case GoodsReceipts.receive_delivery(
           organization_id,
           user_id,
           socket.assigns.delivery_items,
           socket.assigns.receipt_posting_key
         ) do
      {:ok, receipt} ->
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

  def handle_event("validate", %{"batch" => attrs}, socket) do
    changeset = Map.put(receipt_changeset(socket, attrs), :action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :batch))}
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
        case socket.assigns.warehouses do
          [warehouse] -> Map.put(attrs, "site_id", warehouse.id)
          _warehouses -> attrs
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

  defp receipt_changeset(%{assigns: %{receiving_portal: :organization}}, attrs) do
    %Batch{}
    |> Batch.org_intake_changeset(Map.delete(attrs, "site_id"))
    |> Ecto.Changeset.validate_required([:supplier_id], message: "is required for a delivery receipt")
  end

  defp receipt_changeset(_socket, attrs) do
    %Batch{}
    |> Batch.changeset(attrs)
    |> Ecto.Changeset.validate_required([:supplier_id], message: "is required for a delivery receipt")
  end

  defp format_changeset_error(changeset) do
    changeset.errors
    |> Enum.map_join(", ", fn {field, {message, _opts}} -> "#{field} #{message}" end)
  end

  defp reload_receipts(socket) do
    receipts = GoodsReceipts.list_receipts(socket.assigns.current_scope.organization_id)

    page_info = DistributorPagination.page(receipts, socket.assigns.page_number)

    socket
    |> assign(:page_info, page_info)
    |> stream(:receipts, page_info.entries, reset: true)
  end

  defp warehouse_sites(organization_id) do
    organization_id
    |> Sites.list_sites()
    |> Enum.filter(&(&1.site_type == :warehouse and &1.is_active))
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

  def render(assigns) do
    ~H"""
    <.receiving_shell
      portal={@receiving_portal}
      flash={@flash}
      current_scope={@current_scope}
      current_path={@receiving_index_path}
    >
      <.header icon="hero-arrow-down-tray">
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

      <.modal
        :if={@live_action == :new}
        id="distributor-receipt-modal"
        show
        on_cancel={JS.patch(@receiving_index_path)}
      >
        <div class="border-b border-thamani-stone pb-4">
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Receive stock</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Scan or select each item as it comes off the truck, then add its batch details.
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
            <div
              :if={@delivery_items != []}
              class="mt-5 rounded-xl border border-thamani-stone bg-thamani-canvas p-4"
            >
              <h3 class="text-sm font-semibold text-thamani-forest">Items in this delivery</h3>
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
            <.form
              for={@form}
              id="distributor-receipt-form"
              phx-change="validate"
              phx-submit="add_to_delivery"
            >
              <input type="hidden" name="batch[product_id]" value={@selected_product.id} />
              <input type="hidden" name="batch[gtin]" value={@selected_product.gtin} />
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input
                  :if={@receiving_portal == :distributor}
                  field={@form[:site_id]}
                  type="select"
                  label="Warehouse"
                  options={Enum.map(@warehouses, &{&1.name, &1.id})}
                  prompt="Select warehouse"
                  required
                />
                <.input
                  field={@form[:supplier_id]}
                  type="select"
                  label="Supplier"
                  options={Enum.map(@suppliers, &{&1.name, &1.id})}
                  prompt="Select supplier"
                  required
                />
              </div>
              <.input field={@form[:batch_no]} label="Batch number" required />
              <.input
                field={@form[:sscc]}
                label="Case label SSCC (optional)"
                placeholder="Scan the pallet/case label, or type its 18-digit SSCC"
                autocomplete="off"
              />
              <p class="-mt-2 mb-3 text-xs text-thamani-pewter">
                Leave blank if the delivery has no case/pallet label — it will still be
                received into stock, but won't be reportable to PPB until an SSCC is
                captured.
              </p>
              <.input
                field={@form[:serial]}
                label="Serial (optional)"
                placeholder="Unit serial from the item's own barcode, e.g. AI(21)"
                autocomplete="off"
              />
              <p class="-mt-2 mb-3 text-xs text-thamani-pewter">
                Only meaningful when quantity is 1 — a serial identifies one physical unit,
                never a batch of several.
              </p>
              <.input field={@form[:manufacturer]} label="Manufacturer (optional)" />
              <div class="grid gap-x-4 sm:grid-cols-2">
                <.input field={@form[:expiry_date]} type="date" label="Expiry date" required />
                <.input
                  field={@form[:manufacture_date]}
                  type="date"
                  label="Manufacture date (optional)"
                />
              </div>
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
              <.button class="mt-3 w-full" variant="primary">
                {if is_nil(@editing_delivery_item_id),
                  do: "Add received item",
                  else: "Save item changes"}
              </.button>
            </.form>
        <% end %>
      </.modal>

      <.table
        id="distributor-receipts"
        rows={@streams.receipts}
        row_click={
          fn {_id, receipt} ->
            JS.navigate("#{@receiving_index_path}/#{receipt.id}")
          end
        }
      >
        <:col :let={{_id, receipt}} label="Receipt">
          <span class="font-mono font-semibold text-thamani-forest">{receipt.number}</span>
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
      <.pagination page={@page_info} path={@receiving_index_path} />
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
