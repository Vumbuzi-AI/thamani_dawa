defmodule ThamaniDawaWeb.QuickSaleLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Gtin
  alias ThamaniDawa.PaymentMethods
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  @catalog_limit 30

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)

    {catalog_products, catalog_categories, catalog_more?} =
      catalog_for_site(organization_id, site_id, "", "")

    {:ok,
     socket
     |> assign(:sites, Sites.list_sites(organization_id))
     |> assign(:site_locked, not is_nil(site_id))
     |> assign(:site_id, site_id)
     |> assign(:catalog_query, "")
     |> assign(:catalog_category, "")
     |> assign(:catalog_products, catalog_products)
     |> assign(:catalog_categories, catalog_categories)
     |> assign(:catalog_more?, catalog_more?)
     |> assign(:catalog_limit, @catalog_limit)
     |> assign(:cart, [])
     |> assign(:payment_type, "")
     |> assign(:payment_modal, false)
     |> assign(:payment_form, nil)
     |> assign(:completed_sale, nil)
     |> assign(:errors, %{})}
  end

  def handle_event("update_header", params, socket) do
    case params["site_id"] do
      blank when blank in [nil, ""] ->
        {:noreply, socket}

      site_id ->
        site_id = String.to_integer(site_id)

        {:noreply,
         socket
         |> assign(:site_id, site_id)
         |> assign(:catalog_query, "")
         |> assign(:catalog_category, "")
         |> refresh_site_catalog()
         |> assign(:cart, [])}
    end
  end

  def handle_event("select_payment_type", %{"payment_type" => payment_type}, socket) do
    {:noreply,
     socket
     |> assign(:payment_type, payment_type)
     |> assign(:errors, Map.delete(socket.assigns.errors, :payment_type))}
  end

  def handle_event("search_catalog", params, socket) do
    {:noreply,
     socket
     |> assign(:catalog_query, params["query"] || "")
     |> assign(:catalog_category, params["category"] || "")
     |> refresh_catalog()}
  end

  def handle_event("scan_submit", %{"query" => query}, socket) do
    scope = socket.assigns.current_scope

    scanned_gtin = scanned_gtin(query)

    {matches, _more?} =
      catalog_products_for_site(
        scope.organization_id,
        socket.assigns.site_id,
        scanned_gtin || query,
        ""
      )

    case find_product_by_gtin(matches, scanned_gtin || query) do
      {:ok, %{stock: stock}} when stock <= 0 ->
        {:noreply,
         socket
         |> assign(:catalog_query, query)
         |> assign(:catalog_category, "")
         |> refresh_catalog()
         |> put_flash(:error, "This product is out of stock.")}

      {:ok, product} ->
        {:noreply,
         socket
         |> add_scanned_product(product, query)
         |> assign(:catalog_query, "")
         |> refresh_catalog()}

      :error ->
        case find_product_by_batch_no(scope, socket.assigns.site_id, query) do
          {:ok, %{stock: stock}} when stock <= 0 ->
            {:noreply,
             socket
             |> assign(:catalog_query, query)
             |> assign(:catalog_category, "")
             |> refresh_catalog()
             |> put_flash(:error, "This product is out of stock.")}

          {:ok, product} ->
            {:noreply,
             socket
             |> add_scanned_product(product, query)
             |> assign(:catalog_query, "")
             |> refresh_catalog()}

          :error ->
            {:noreply,
             socket
             |> assign(:catalog_query, query)
             |> assign(:catalog_category, "")
             |> refresh_catalog()
             |> put_flash(:error, "No product found for that barcode.")}
        end
    end
  end

  def handle_event("quick_add", %{"product_id" => product_id}, socket) do
    product_id = String.to_integer(product_id)
    product = Enum.find(socket.assigns.catalog_products, &(&1.id == product_id))

    if product && product.stock > 0 do
      {:noreply, add_to_cart(socket, product, 1, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("increment_item", %{"product_id" => product_id}, socket) do
    {:noreply, adjust_cart_quantity(socket, String.to_integer(product_id), 1)}
  end

  def handle_event("decrement_item", %{"product_id" => product_id}, socket) do
    {:noreply, adjust_cart_quantity(socket, String.to_integer(product_id), -1)}
  end

  def handle_event(
        "set_item_quantity",
        %{"product_id" => product_id, "quantity" => quantity},
        socket
      ) do
    case Integer.parse(quantity) do
      {quantity, ""} when quantity >= 0 ->
        {:noreply, set_cart_quantity(socket, String.to_integer(product_id), quantity)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_item", %{"product_id" => product_id}, socket) do
    product_id = String.to_integer(product_id)
    cart = Enum.reject(socket.assigns.cart, &(&1.product_id == product_id))
    {:noreply, assign(socket, :cart, cart)}
  end

  def handle_event("complete_sale", _params, socket) do
    complete_sale(socket)
  end

  def handle_event("cancel_payment", _params, socket) do
    {:noreply, assign(socket, payment_modal: false, payment_form: nil)}
  end

  def handle_event("set_cash_tendered", %{"amount" => amount}, socket) do
    {:noreply,
     socket
     |> assign(
       :payment_form,
       to_form(%{"tendered" => amount, "provider_reference" => ""}, as: :payment)
     )
     |> assign(:errors, Map.delete(socket.assigns.errors, :payment))}
  end

  def handle_event("confirm_payment", %{"payment" => payment_attrs}, socket) do
    case payment_details(
           socket.assigns.payment_type,
           payment_attrs,
           cart_total(socket.assigns.cart)
         ) do
      {:ok, details} ->
        finalize_sale(socket, details)

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:payment_form, to_form(payment_attrs, as: :payment))
         |> assign(:errors, Map.put(socket.assigns.errors, :payment, message))}
    end
  end

  def handle_event("new_sale", _params, socket) do
    {:noreply,
     socket
     |> assign(:cart, [])
     |> assign(:payment_type, "")
     |> assign(:completed_sale, nil)
     |> assign(:errors, %{})}
  end

  defp catalog_for_site(_organization_id, nil, _query, _category), do: {[], [], false}

  defp catalog_for_site(organization_id, site_id, query, category) do
    {products, more?} = catalog_products_for_site(organization_id, site_id, query, category)
    categories = Products.quick_sale_categories_for_site(organization_id, site_id)

    {products, categories, more?}
  end

  defp catalog_products_for_site(_organization_id, nil, _query, _category), do: {[], false}

  defp catalog_products_for_site(organization_id, site_id, query, category) do
    entries =
      Products.quick_sale_products_for_site(
        organization_id,
        site_id,
        query,
        category,
        @catalog_limit + 1
      )

    {Enum.take(entries, @catalog_limit), length(entries) > @catalog_limit}
  end

  defp refresh_catalog(socket) do
    scope = socket.assigns.current_scope

    {products, more?} =
      catalog_products_for_site(
        scope.organization_id,
        socket.assigns.site_id,
        socket.assigns.catalog_query,
        socket.assigns.catalog_category
      )

    socket
    |> assign(:catalog_products, products)
    |> assign(:catalog_more?, more?)
  end

  defp refresh_site_catalog(socket) do
    scope = socket.assigns.current_scope

    categories =
      if socket.assigns.site_id do
        Products.quick_sale_categories_for_site(scope.organization_id, socket.assigns.site_id)
      else
        []
      end

    socket
    |> assign(:catalog_categories, categories)
    |> refresh_catalog()
  end

  defp find_product_by_gtin(products, raw) do
    with trimmed when trimmed != "" <- String.trim(raw || ""),
         {:ok, normalized} <- Gtin.normalize(trimmed),
         %{} = product <- Enum.find(products, &(&1.gtin == normalized)) do
      {:ok, product}
    else
      _ -> :error
    end
  end

  defp scanned_gtin(raw) do
    case ThamaniDawa.GS1Decoder.parse(String.trim(raw || "")) do
      {:ok, %{gtin: gtin}} when is_binary(gtin) -> gtin
      _ -> nil
    end
  end

  # Fallback for a scan whose GTIN segment didn't match any product (e.g. a
  # missing/incorrect product GTIN) — try the batch/lot number (AI 10)
  # instead, since every received batch has one regardless of GTIN data
  # quality.
  defp find_product_by_batch_no(scope, site_id, raw) do
    with %{batch_no: batch_no} when is_binary(batch_no) and batch_no != "" <-
           gs1_result(raw),
         %{product_id: product_id} <-
           Batches.get_active_batch_by_batch_no(scope.organization_id, site_id, batch_no),
         %{} = product <-
           Products.quick_sale_product_for_site(scope.organization_id, site_id, product_id) do
      {:ok, product}
    else
      _ -> :error
    end
  end

  defp gs1_result(raw) do
    case ThamaniDawa.GS1Decoder.parse(String.trim(raw || "")) do
      {:ok, result} -> result
      _ -> nil
    end
  end

  defp add_scanned_product(socket, product, raw_barcode) do
    case Enum.find(socket.assigns.cart, &(&1.product_id == product.id)) do
      %{scanned_barcode: nil} -> verify_cart_line(socket, product.id, raw_barcode)
      nil -> add_to_cart(socket, product, 1, raw_barcode)
      _verified_line -> add_to_cart(socket, product, 1, raw_barcode)
    end
  end

  defp verify_cart_line(socket, product_id, raw_barcode) do
    cart =
      Enum.map(socket.assigns.cart, fn line ->
        if line.product_id == product_id,
          do: %{
            line
            | scanned_gtin: scanned_gtin(raw_barcode) || raw_barcode,
              scanned_barcode: raw_barcode
          },
          else: line
      end)

    socket
    |> assign(:cart, cart)
    |> put_flash(:info, "Medicine verified. You can continue the sale.")
  end

  defp add_to_cart(socket, product, quantity, scanned_gtin) do
    cart = socket.assigns.cart

    cart =
      case Enum.find_index(cart, &(&1.product_id == product.id)) do
        nil ->
          cart ++
            [
              %{
                product_id: product.id,
                product: product,
                quantity: quantity,
                scanned_gtin: scanned_gtin && (scanned_gtin(scanned_gtin) || scanned_gtin),
                scanned_barcode: scanned_gtin
              }
            ]

        index ->
          List.update_at(cart, index, fn line ->
            %{
              line
              | quantity: line.quantity + quantity,
                scanned_gtin:
                  (scanned_gtin && (scanned_gtin(scanned_gtin) || scanned_gtin)) ||
                    line.scanned_gtin,
                scanned_barcode: scanned_gtin || line.scanned_barcode
            }
          end)
      end

    assign(socket, :cart, cart)
  end

  defp adjust_cart_quantity(socket, product_id, delta) do
    cart =
      socket.assigns.cart
      |> Enum.map(fn line ->
        if line.product_id == product_id,
          do: %{line | quantity: line.quantity + delta},
          else: line
      end)
      |> Enum.reject(&(&1.quantity <= 0))

    assign(socket, :cart, cart)
  end

  defp set_cart_quantity(socket, product_id, quantity) do
    cart =
      socket.assigns.cart
      |> Enum.map(fn line ->
        if line.product_id == product_id, do: %{line | quantity: quantity}, else: line
      end)
      |> Enum.reject(&(&1.quantity <= 0))

    assign(socket, :cart, cart)
  end

  defp complete_sale(socket) do
    %{
      site_id: site_id,
      cart: cart,
      payment_type: payment_type
    } = socket.assigns

    cond do
      is_nil(site_id) ->
        {:noreply, put_flash(socket, :error, "Choose a site first.")}

      cart == [] ->
        {:noreply, put_flash(socket, :error, "Add at least one item.")}

      not PaymentMethods.valid?(payment_type) ->
        {:noreply, assign(socket, :errors, %{payment_type: "Select a payment method."})}

      true ->
        total = cart_total(cart)

        {:noreply,
         socket
         |> assign(:payment_modal, true)
         |> assign(
           :payment_form,
           to_form(%{"tendered" => to_string(total), "provider_reference" => ""}, as: :payment)
         )
         |> assign(:errors, Map.delete(socket.assigns.errors, :payment))}
    end
  end

  defp payment_details("Cash", %{"tendered" => tendered}, total) do
    with {:ok, amount} <- Decimal.cast(tendered),
         :gt <- Decimal.compare(amount, Decimal.sub(total, Decimal.new("0.01"))) do
      {:ok, %{provider_reference: nil, tendered: amount, change: Decimal.sub(amount, total)}}
    else
      _ -> {:error, "Enter an amount at least equal to the sale total."}
    end
  end

  defp payment_details("Mobile Money", attrs, _total) do
    {:ok,
     %{provider_reference: blank_to_nil(attrs["provider_reference"]), tendered: nil, change: nil}}
  end

  defp payment_details("Insurance", _attrs, _total),
    do: {:ok, %{provider_reference: nil, tendered: nil, change: nil}}

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp finalize_sale(socket, payment_details) do
    %{current_scope: scope, site_id: site_id, cart: cart, payment_type: payment_type} =
      socket.assigns

    attrs = %{
      "payment_type" => payment_type,
      "provider_reference" => payment_details.provider_reference,
      "items" => Enum.map(cart, &cart_line_attrs/1)
    }

    case Prescriptions.create_quick_sale(scope.organization_id, site_id, scope.user.id, attrs) do
      {:ok, prescription} ->
        site_name =
          case Enum.find(socket.assigns.sites, &(&1.id == site_id)) do
            nil -> "Pharmacy"
            site -> site.name
          end

        {:noreply,
         socket
         |> assign(:completed_sale, %{
           cart: cart,
           total: cart_total(cart),
           payment_type: payment_type,
           tendered: payment_details.tendered,
           change: payment_details.change,
           provider_reference: payment_details.provider_reference,
           prescription: prescription,
           receipt_number: "TD-#{String.pad_leading(Integer.to_string(prescription.id), 6, "0")}",
           site_name: site_name,
           cashier: scope.user.name,
           completed_at: DateTime.utc_now()
         })
         |> assign(:cart, [])
         |> assign(:payment_type, "")
         |> assign(:payment_modal, false)
         |> assign(:payment_form, nil)
         |> assign(:errors, %{})}

      error ->
        handle_quick_sale_result(socket, error)
    end
  end

  defp cart_line_attrs(line) do
    %{
      "product_id" => line.product_id,
      "quantity_prescribed" => line.quantity,
      "scanned_gtin" => line.scanned_gtin,
      "scanned_barcode" => line.scanned_barcode
    }
  end

  defp handle_quick_sale_result(socket, {:error, {index, reason}}) do
    message = quick_sale_error_message(index, reason, socket.assigns.cart)

    {:noreply, put_flash(socket, :error, message)}
  end

  defp handle_quick_sale_result(socket, {:error, %Ecto.Changeset{} = changeset}) do
    message = "Couldn't complete the sale: #{changeset_error_summary(changeset)}"
    {:noreply, put_flash(socket, :error, message)}
  end

  defp handle_quick_sale_result(socket, {:error, _reason}) do
    {:noreply, put_flash(socket, :error, "Couldn't complete the sale.")}
  end

  defp quick_sale_error_message(index, reason, cart) do
    product_name =
      case cart
           |> Enum.at(index)
           |> then(&(&1 && &1.product)) do
        nil -> "Item #{index + 1}"
        product -> product.generic_name
      end

    case reason do
      :out_of_stock -> "#{product_name}: not enough stock available."
      :gtin_mismatch -> "#{product_name}: scanned barcode doesn't match this product."
      :invalid_gtin -> "#{product_name}: invalid barcode scanned."
      :over_dispensed -> "#{product_name}: quantity exceeds what was prescribed."
      _ -> "#{product_name}: couldn't complete the sale."
    end
  end

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp cart_lines(cart) do
    Enum.map(cart, fn line ->
      product = line.product
      %{line: line, product: product, subtotal: Decimal.mult(product.price, line.quantity)}
    end)
  end

  defp cart_total(cart) do
    cart
    |> cart_lines()
    |> Enum.reduce(Decimal.new(0), fn %{subtotal: subtotal}, acc -> Decimal.add(acc, subtotal) end)
  end

  defp cart_item_count(cart), do: Enum.reduce(cart, 0, &(&1.quantity + &2))

  defp catalog_empty_title(nil, _query, _category), do: "Choose a site to get started"
  defp catalog_empty_title(_site_id, _query, _category), do: "No matching products"

  defp catalog_empty_message(nil, _query, _category),
    do: "Pick a site above to see what's available to sell."

  defp catalog_empty_message(_site_id, query, _category) when query != "",
    do: "Try a different search term or scan a barcode."

  defp catalog_empty_message(_site_id, _query, category) when category != "",
    do: "There are no in-stock products in this category."

  defp catalog_empty_message(_site_id, _query, _category),
    do: "No active stock is available at this site."

  defp stock_label(stock) when stock <= 0, do: "Out of stock"
  defp stock_label(stock), do: "#{stock} in stock"

  defp product_initials(product) do
    (product.generic_name || "?")
    |> String.trim()
    |> String.first()
    |> to_string()
    |> String.upcase()
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/quick-sale"
    >
      <.header icon="hero-bolt">
        Quick sale
        <:subtitle>
          Pick products, scan to confirm, and take payment — stock is dispensed and the sale is
          marked paid immediately.
        </:subtitle>
      </.header>

      <.modal
        :if={@payment_modal}
        id="quick-sale-payment-modal"
        show
        on_cancel={JS.push("cancel_payment")}
      >
        <div class="space-y-5">
          <div class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-xl bg-thamani-lime text-thamani-forest">
              <.icon
                name={
                  if(@payment_type == "Cash", do: "hero-banknotes", else: "hero-device-phone-mobile")
                }
                class="size-5"
              />
            </span>
            <div>
              <h2 class="text-xl font-semibold text-thamani-forest">{@payment_type} payment</h2>
              <p class="text-sm text-thamani-pewter">Confirm payment before completing this sale.</p>
            </div>
          </div>

          <div class="flex items-center justify-between rounded-xl bg-thamani-canvas px-4 py-3">
            <span class="text-sm text-thamani-pewter">Order total</span>
            <span class="text-2xl font-semibold tabular-nums text-thamani-forest">KES {cart_total(
              @cart
            )}</span>
          </div>

          <.form
            for={@payment_form}
            id="quick-sale-payment-form"
            phx-submit="confirm_payment"
            class="space-y-4"
          >
            <%= if @payment_type == "Cash" do %>
              <.input
                field={@payment_form[:tendered]}
                type="number"
                label="Amount tendered (KES)"
                min="0"
                step="0.01"
                required
                autofocus
              />
              <div class="grid grid-cols-4 gap-2">
                <button
                  type="button"
                  phx-click="set_cash_tendered"
                  phx-value-amount={cart_total(@cart)}
                  class="rounded-lg border border-thamani-stone px-2 py-2 text-xs font-semibold text-thamani-forest hover:bg-thamani-lime/30"
                >Exact</button>
                <button
                  :for={amount <- [50, 100, 200, 500, 1_000, 2_000, 5_000]}
                  type="button"
                  phx-click="set_cash_tendered"
                  phx-value-amount={amount}
                  class="rounded-lg border border-thamani-stone px-2 py-2 text-xs font-semibold text-thamani-forest hover:bg-thamani-lime/30"
                >KES {amount}</button>
              </div>
              <p class="text-xs text-thamani-pewter">
                Enter the cash received. Change is calculated when you confirm.
              </p>
            <% else %>
              <div
                :if={@payment_type == "Mobile Money"}
                class="rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm text-blue-900"
              >
                Confirm only after you have seen the customer’s M-Pesa payment. The transaction code is optional.
              </div>
              <.input
                :if={@payment_type == "Mobile Money"}
                field={@payment_form[:provider_reference]}
                label="M-Pesa transaction code (optional)"
                placeholder="e.g. SFA7B2XQ9K"
              />
            <% end %>
            <p :if={@errors[:payment]} class="text-sm font-medium text-thamani-error">
              {@errors[:payment]}
            </p>
            <.button
              type="submit"
              variant="primary"
              phx-disable-with="Completing sale…"
              class="w-full"
            >Confirm payment</.button>
            <button
              type="button"
              phx-click="cancel_payment"
              class="w-full text-sm font-medium text-thamani-pewter hover:text-thamani-forest"
            >Cancel</button>
          </.form>
        </div>
      </.modal>

      <.modal :if={@completed_sale} id="quick-sale-receipt-modal" show>
        <div class="space-y-5 text-center">
          <span class="mx-auto flex size-12 items-center justify-center rounded-full bg-thamani-lime text-thamani-forest">
            <.icon name="hero-check" class="size-7" />
          </span>
          <div>
            <h2 class="text-xl font-semibold text-thamani-forest">Sale complete</h2><p class="text-sm text-thamani-pewter">
              Payment received
            </p>
          </div>
          <div
            id="quick-sale-receipt"
            class="quick-sale-receipt-card rounded-xl border border-thamani-stone bg-white p-5 text-left text-sm text-slate-900"
          >
            <header class="receipt-header text-center">
              <img
                src="/images/logo.png"
                alt="Thamani Dawa"
                class="receipt-logo mx-auto mb-2 size-14 object-contain"
              />
              <p class="receipt-site font-semibold text-thamani-forest">
                {@completed_sale.site_name}
              </p>
              <h3 class="receipt-title mb-3 text-base font-bold uppercase">Sale Receipt</h3>
              <div class="receipt-meta space-y-1 border-y border-dashed border-thamani-stone py-3 text-left">
                <div class="flex justify-between gap-2">
                  <span>Receipt no.</span><strong>{@completed_sale.receipt_number}</strong>
                </div>
                <div id="receipt-date-time" class="flex justify-between gap-2">
                  <span>Date</span><strong>{Calendar.strftime(
                    @completed_sale.completed_at,
                    "%d %b %Y %H:%M"
                  )}</strong>
                </div>
                <div class="flex justify-between gap-2">
                  <span>Cashier</span><strong>{@completed_sale.cashier}</strong>
                </div>
              </div>
            </header>

            <table
              id="quick-sale-receipt-items"
              class="receipt-table my-3 w-full table-fixed border-collapse text-[10px]"
            >
              <thead>
                <tr>
                  <th
                    scope="col"
                    class="border-b border-dashed border-thamani-stone py-2 text-left uppercase"
                  >
                    Qty
                  </th>
                  <th
                    scope="col"
                    class="border-b border-dashed border-thamani-stone py-2 text-left uppercase"
                  >
                    Medicine
                  </th>
                  <th
                    scope="col"
                    class="border-b border-dashed border-thamani-stone py-2 text-right uppercase"
                  >
                    Unit price
                  </th>
                  <th
                    scope="col"
                    class="border-b border-dashed border-thamani-stone py-2 text-right uppercase"
                  >
                    Line total
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr :for={line <- @completed_sale.cart}>
                  <td class="py-2 align-top">{line.quantity}</td>
                  <td class="receipt-medicine py-2 align-top">
                    <strong class="block">{line.product.generic_name}</strong>
                    <small :if={line.product.brand_name} class="mt-0.5 block text-thamani-pewter">
                      {line.product.brand_name}
                    </small>
                  </td>
                  <td class="py-2 text-right align-top">KES {line.product.price}</td>
                  <td class="py-2 text-right align-top">
                    KES {Decimal.mult(line.product.price, line.quantity)}
                  </td>
                </tr>
              </tbody>
            </table>

            <section class="receipt-payment space-y-1 border-t border-dashed border-thamani-stone pt-3">
              <div
                id="receipt-total"
                class="receipt-total flex justify-between border-b border-dashed border-thamani-stone pb-2 text-base font-semibold text-thamani-forest"
              >
                <span>Total</span><strong>KES {@completed_sale.total}</strong>
              </div>
              <div id="receipt-payment-method" class="flex justify-between gap-2">
                <span>Payment method</span><strong>{@completed_sale.payment_type}</strong>
              </div>
              <div
                :if={@completed_sale.tendered}
                id="receipt-cash-tendered"
                class="flex justify-between gap-2"
              >
                <span>Cash tendered</span><strong>KES {@completed_sale.tendered}</strong>
              </div>
              <div :if={@completed_sale.change} id="receipt-change" class="flex justify-between gap-2">
                <span>Change</span><strong>KES {@completed_sale.change}</strong>
              </div>
              <div
                :if={@completed_sale.provider_reference}
                id="receipt-mpesa-reference"
                class="flex justify-between gap-2"
              >
                <span>M-Pesa reference</span><strong>{@completed_sale.provider_reference}</strong>
              </div>
            </section>

            <p class="receipt-thanks mt-4 text-center font-semibold">
              Thank you for choosing {@completed_sale.site_name}.
            </p>
            <footer class="receipt-powered mt-2 border-t border-dashed border-thamani-stone pt-2 text-center text-xs text-thamani-pewter">
              Powered by Thamani Dawa
            </footer>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <.button
              id="quick-sale-print"
              type="button"
              variant="ghost"
              phx-hook="QuickSaleReceiptPrint"
              data-receipt-target="#quick-sale-receipt"
              class="w-full"
            >
              <.icon name="hero-printer" class="size-4" /> Print
            </.button>
            <.button
              type="button"
              variant="primary"
              phx-click="new_sale"
              class="w-full"
            >New sale <.icon name="hero-arrow-right" class="size-4" /></.button>
          </div>
        </div>
      </.modal>

      <div class="grid grid-cols-1 gap-5 lg:h-[calc(100dvh-10rem)] lg:min-h-[30rem] lg:grid-cols-[minmax(28rem,1fr)_minmax(34rem,1.15fr)] lg:items-stretch">
        <section
          id="quick-sale-cart"
          class="order-2 flex min-h-[30rem] flex-col overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow lg:order-1 lg:min-h-0"
        >
          <div
            id="quick-sale-cart-header"
            class="border-b border-thamani-forest bg-thamani-forest px-5 py-4"
          >
            <div class="flex items-center justify-between gap-3">
              <div class="flex items-center gap-3">
                <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-thamani-lime text-thamani-forest">
                  <.icon name="hero-shopping-cart" class="size-5" />
                </span>
                <div>
                  <h2 class="text-base font-semibold text-thamani-snow">Current sale</h2>
                  <p class="mt-0.5 text-xs text-thamani-snow/70">
                    Review quantities before taking payment.
                  </p>
                </div>
              </div>
              <span
                id="quick-sale-item-count"
                class="rounded-full bg-thamani-lime px-2.5 py-1 text-xs font-semibold tabular-nums text-thamani-forest"
              >
                {cart_item_count(@cart)} {if(cart_item_count(@cart) == 1, do: "item", else: "items")}
              </span>
            </div>

            <form
              :if={not @site_locked}
              id="quick-sale-header-form"
              phx-change="update_header"
              class="mt-4"
            >
              <.input
                type="select"
                name="site_id"
                label="Site"
                value={@site_id}
                options={Enum.map(@sites, &{&1.name, &1.id})}
                prompt="Choose a site"
              />
            </form>
          </div>

          <div
            id="quick-sale-items"
            class="min-h-0 flex-1 divide-y divide-thamani-stone overflow-y-auto"
          >
            <div :if={@cart == []} class="p-8 text-center text-sm text-thamani-pewter">
              Scan a barcode or tap a product to start the sale.
            </div>
            <div
              :for={%{line: line, product: product, subtotal: subtotal} <- cart_lines(@cart)}
              id={"cart-line-#{line.product_id}"}
              class="flex items-center gap-4 px-5 py-4"
            >
              <div class="min-w-0 flex-1">
                <p class="truncate text-base font-semibold text-thamani-forest">
                  {product.generic_name}
                </p>
                <p class="mt-1 text-sm text-thamani-pewter">KES {product.price} each</p>
              </div>
              <div class="flex shrink-0 items-center gap-2">
                <button
                  type="button"
                  phx-click="decrement_item"
                  phx-value-product_id={line.product_id}
                  aria-label={"Decrease quantity for #{product.generic_name}"}
                  class="flex size-9 items-center justify-center rounded-xl border border-thamani-stone text-thamani-forest transition-colors hover:bg-thamani-stone"
                >
                  <.icon name="hero-minus" class="size-4" />
                </button>
                <form
                  id={"cart-quantity-form-#{line.product_id}"}
                  phx-change="set_item_quantity"
                >
                  <input type="hidden" name="product_id" value={line.product_id} />
                  <input
                    id={"cart-quantity-#{line.product_id}"}
                    type="number"
                    name="quantity"
                    value={line.quantity}
                    min="0"
                    max={product.stock}
                    inputmode="numeric"
                    phx-debounce="250"
                    aria-label={"Quantity for #{product.generic_name}"}
                    class="h-9 !w-12 !p-0 text-center text-base font-semibold tabular-nums text-thamani-forest"
                  />
                </form>
                <button
                  type="button"
                  phx-click="increment_item"
                  phx-value-product_id={line.product_id}
                  aria-label={"Increase quantity for #{product.generic_name}"}
                  class="flex size-9 items-center justify-center rounded-xl border border-thamani-stone text-thamani-forest transition-colors hover:bg-thamani-stone"
                >
                  <.icon name="hero-plus" class="size-4" />
                </button>
              </div>
              <p class="w-20 shrink-0 text-right text-base font-semibold tabular-nums text-thamani-forest">
                KES {subtotal}
              </p>
              <button
                type="button"
                phx-click="remove_item"
                phx-value-product_id={line.product_id}
                aria-label={"Remove #{product.generic_name}"}
                class="flex size-9 shrink-0 items-center justify-center rounded-xl text-thamani-error transition-colors hover:bg-thamani-error/10"
              >
                <.icon name="hero-trash" class="size-4.5" />
              </button>
            </div>
          </div>

          <div class="space-y-4 border-t border-thamani-stone px-5 py-4">
            <div class="flex items-center justify-between">
              <span class="text-base font-medium text-thamani-forest">Total</span>
              <span class="text-2xl font-semibold tabular-nums text-thamani-forest">
                KES {cart_total(@cart)}
              </span>
            </div>


            <div>
              <p class="mb-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
                Payment method
              </p>
              <div class="grid grid-cols-1 gap-2 sm:grid-cols-3">
                <button
                  :for={method <- PaymentMethods.all()}
                  type="button"
                  phx-click="select_payment_type"
                  phx-value-payment_type={method}
                  class={[
                    "flex items-center justify-center gap-2 rounded-xl border px-3 py-3 text-sm font-semibold transition-all",
                    if(@payment_type == method,
                      do:
                        "border-thamani-forest bg-thamani-forest text-thamani-snow shadow-sm ring-2 ring-thamani-forest/20",
                      else:
                        "border-thamani-stone bg-thamani-canvas text-thamani-forest hover:border-thamani-forest/50 hover:bg-thamani-lime/20"
                    )
                  ]}
                >
                  <.icon
                    name={
                      case method do
                        "Cash" -> "hero-banknotes"
                        "Mobile Money" -> "hero-device-phone-mobile"
                        _ -> "hero-shield-check"
                      end
                    }
                    class="size-4"
                  />
                  {method}
                </button>
              </div>
              <p :if={@errors[:payment_type]} class="mt-1.5 text-xs font-medium text-thamani-error">
                {@errors[:payment_type]}
              </p>
            </div>

            <.button
              type="button"
              variant="primary"
              phx-click="complete_sale"
              phx-disable-with="Completing sale…"
              class="w-full"
            >
              Complete sale
            </.button>
          </div>
        </section>

        <section class="order-1 flex min-h-[30rem] flex-col overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow lg:order-2 lg:min-h-0">
          <div
            id="quick-sale-catalog-header"
            class="border-b border-thamani-forest bg-thamani-forest px-5 py-4"
          >
            <div class="flex items-center gap-3">
              <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-thamani-lime text-thamani-forest">
                <.icon name="hero-squares-2x2" class="size-5" />
              </span>
              <div>
                <h2 class="text-base font-semibold text-thamani-snow">Product catalog</h2>
                <p class="mt-0.5 text-xs text-thamani-snow/70">
                  Search, scan, or choose an item to add to this sale.
                </p>
              </div>
            </div>
          </div>
          <form
            id="quick-sale-scan-form"
            phx-change="search_catalog"
            phx-submit="scan_submit"
            class="border-b border-thamani-stone p-4"
          >
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="pointer-events-none absolute left-3.5 top-1/2 size-4! -translate-y-1/2 text-thamani-pewter"
              />
              <input
                type="text"
                name="query"
                value={@catalog_query}
                placeholder="Scan barcode or search by product name…"
                autocomplete="off"
                autofocus
                phx-debounce="150"
                class="thamani-input quick-sale-search-input h-12 w-full rounded-xl pl-11 pr-4 text-sm focus:border-thamani-forest focus:outline-none focus:ring-0 transition-colors"
              />
            </div>
            <div class="mt-3 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
              <div class="w-full sm:max-w-56">
                <.input
                  type="select"
                  name="category"
                  label="Category"
                  value={@catalog_category}
                  options={Enum.map(@catalog_categories, &{&1, &1})}
                  prompt="All categories"
                />
              </div>
              <p class="flex items-center gap-2 pb-2 text-xs text-thamani-pewter">
                <.icon name="hero-qr-code" class="size-4 shrink-0" />
                Scan a barcode or search by name.
              </p>
            </div>
          </form>

          <div class="min-h-0 flex-1 divide-y divide-thamani-stone overflow-y-auto px-4">
            <button
              :for={product <- @catalog_products}
              type="button"
              phx-click="quick_add"
              phx-value-product_id={product.id}
              id={"quick-add-#{product.id}"}
              disabled={product.stock <= 0}
              class={[
                "flex w-full items-center gap-3 py-3 text-left transition-colors",
                product.stock > 0 && "hover:bg-thamani-lime/20",
                product.stock <= 0 && "cursor-not-allowed bg-thamani-canvas/60 opacity-70"
              ]}
            >
              <span class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-thamani-lime text-sm font-semibold text-thamani-forest">
                {product_initials(product)}
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-semibold text-thamani-forest">
                  {product.generic_name}
                </span>
                <span class="mt-0.5 block truncate text-xs text-thamani-pewter">
                  {product.brand_name || "Medicine"} · {stock_label(product.stock)}
                </span>
              </span>
              <span class="shrink-0 text-right">
                <span class="block whitespace-nowrap text-sm font-semibold text-thamani-forest">
                  KES {product.price}
                </span>
                <span class="mt-0.5 block text-xs font-medium text-thamani-forest/70">
                  {if(product.stock > 0, do: "Add item", else: "Unavailable")}
                </span>
              </span>
              <span class={[
                "flex size-8 shrink-0 items-center justify-center rounded-lg",
                if(product.stock > 0,
                  do: "bg-thamani-lime text-thamani-forest",
                  else: "bg-thamani-stone text-thamani-pewter"
                )
              ]}>
                <.icon name="hero-plus" class="size-4" />
              </span>
            </button>

            <div :if={@catalog_products == []}>
              <.blank_state
                icon="hero-cube"
                title={catalog_empty_title(@site_id, @catalog_query, @catalog_category)}
              >
                {catalog_empty_message(@site_id, @catalog_query, @catalog_category)}
              </.blank_state>
            </div>

            <p :if={@catalog_more?} class="px-3 py-3 text-center text-xs text-thamani-pewter">
              Showing the first {@catalog_limit} products. Search by name or GTIN to narrow results.
            </p>
          </div>
        </section>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
