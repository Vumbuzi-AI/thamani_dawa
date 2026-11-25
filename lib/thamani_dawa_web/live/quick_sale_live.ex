defmodule ThamaniDawaWeb.QuickSaleLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Gtin
  alias ThamaniDawa.PaymentMethods
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sales
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

  def handle_event("clear_cart", _params, socket) do
    {:noreply, assign(socket, cart: [], errors: %{})}
  end

  def handle_event("filter_category", %{"category" => category}, socket) do
    {:noreply,
     socket
     |> assign(:catalog_category, category)
     |> refresh_catalog()}
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
    add_to_cart(socket, product, 1, raw_barcode)
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
                quantity: clamp_quantity(quantity, product.stock),
                scanned_gtin: scanned_gtin && (scanned_gtin(scanned_gtin) || scanned_gtin),
                scanned_barcode: scanned_gtin
              }
            ]

        index ->
          List.update_at(cart, index, fn line ->
            %{
              line
              | quantity: clamp_quantity(line.quantity + quantity, line.product.stock),
                scanned_gtin:
                  (scanned_gtin && (scanned_gtin(scanned_gtin) || scanned_gtin)) ||
                    line.scanned_gtin,
                scanned_barcode: scanned_gtin || line.scanned_barcode
            }
          end)
      end

    assign(socket, :cart, cart)
  end

  defp clamp_quantity(quantity, stock) when is_integer(stock), do: min(quantity, stock)
  defp clamp_quantity(quantity, _stock), do: quantity

  defp adjust_cart_quantity(socket, product_id, delta) do
    cart =
      socket.assigns.cart
      |> Enum.map(fn line ->
        if line.product_id == product_id,
          do: %{line | quantity: clamp_quantity(line.quantity + delta, line.product.stock)},
          else: line
      end)
      |> Enum.reject(&(&1.quantity <= 0))

    assign(socket, :cart, cart)
  end

  defp set_cart_quantity(socket, product_id, quantity) do
    cart =
      socket.assigns.cart
      |> Enum.map(fn line ->
        if line.product_id == product_id,
          do: %{line | quantity: clamp_quantity(quantity, line.product.stock)},
          else: line
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

      true ->
        socket =
          assign(
            socket,
            :payment_type,
            if(PaymentMethods.valid?(payment_type), do: payment_type, else: "Cash")
          )

        case reconcile_cart_with_stock(socket) do
          {:ok, socket} ->
            total = cart_total(socket.assigns.cart)

            {:noreply,
             socket
             |> assign(:payment_modal, true)
             |> assign(
               :payment_form,
               to_form(%{"tendered" => to_string(total), "provider_reference" => ""},
                 as: :payment
               )
             )
             |> assign(:errors, Map.delete(socket.assigns.errors, :payment))}

          {:error, socket} ->
            {:noreply, socket}
        end
    end
  end

  # Stock can drift between adding an item to the cart and taking payment
  # (another sale, a stock count, …) — re-check against the current site
  # stock here so a shortfall surfaces before payment, not after.
  defp reconcile_cart_with_stock(socket) do
    %{current_scope: scope, site_id: site_id, cart: cart} = socket.assigns

    {adjusted_cart, shortages} =
      Enum.map_reduce(cart, [], fn line, shortages ->
        available = Batches.total_available_stock(scope.organization_id, site_id, line.product_id)

        cond do
          available <= 0 ->
            {nil, [{line.product.generic_name, 0} | shortages]}

          line.quantity > available ->
            {%{line | quantity: available, product: %{line.product | stock: available}},
             [{line.product.generic_name, available} | shortages]}

          true ->
            {line, shortages}
        end
      end)

    if shortages == [] do
      {:ok, socket}
    else
      message =
        shortages
        |> Enum.reverse()
        |> Enum.map_join("; ", fn
          {name, 0} -> "#{name} is now out of stock"
          {name, available} -> "#{name} only has #{available} left"
        end)

      {:error,
       socket
       |> assign(:cart, Enum.reject(adjusted_cart, &is_nil/1))
       |> put_flash(:error, "Stock changed since you added these items: #{message}.")}
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

    case Sales.create_quick_sale(scope.organization_id, site_id, scope.user.id, attrs) do
      {:ok, sale} ->
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
           sale: sale,
           receipt_number: "TD-#{String.pad_leading(Integer.to_string(sale.id), 6, "0")}",
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

  defp cart_lines(cart, organization_id, site_id) do
    Enum.map(cart_lines(cart), fn entry ->
      Map.put(
        entry,
        :batch_label,
        fefo_batch_label(organization_id, site_id, entry.line.product_id, entry.line.quantity)
      )
    end)
  end

  defp fefo_batch_label(_organization_id, nil, _product_id, _quantity), do: nil

  defp fefo_batch_label(organization_id, site_id, product_id, quantity) do
    case Batches.preview_fefo_allocation(organization_id, site_id, product_id, quantity) do
      [] -> nil
      allocations -> Enum.map_join(allocations, " + ", & &1.batch.batch_no)
    end
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
  defp stock_label(stock), do: "#{stock} left"

  defp cart_lines_label(cart) do
    units = cart_item_count(cart)
    lines = length(cart)
    unit_word = if units == 1, do: "unit", else: "units"
    line_word = if lines == 1, do: "line", else: "lines"
    "#{units} #{unit_word} · #{lines} #{line_word}"
  end

  defp payment_option_title("Mobile Money"), do: "M-Pesa"
  defp payment_option_title(method), do: method

  defp payment_option_body("Cash"),
    do: "Enter the cash received. Change is calculated when you confirm."

  defp payment_option_body("Mobile Money"),
    do: "Add the M-Pesa transaction code from the customer's message."

  defp payment_option_body("Insurance"),
    do: "Confirm the insurer after you take this sale."

  defp payment_option_body(_), do: nil

  defp cash_change(tendered, total) do
    case Decimal.cast(tendered) do
      {:ok, amount} -> Decimal.sub(amount, total)
      :error -> nil
    end
  end

  defp same_amount?(left, right) do
    with {:ok, a} <- Decimal.cast(left),
         {:ok, b} <- Decimal.cast(right) do
      Decimal.equal?(a, b)
    else
      _ -> false
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/quick-sale"
    >
      <.td_list_page
        title="Quick sale"
        subtitle="Sell over-the-counter items without a prescription."
      >
        <:actions>
          <.td_button
            type="button"
            variant="secondary"
            glyph="scan"
            label="Scan"
            onclick="document.getElementById('quick-sale-query')?.focus()"
          />
        </:actions>

        <.td_modal
          :if={@payment_modal}
          id="quick-sale-payment-modal"
          show
          width={560}
          title="Confirm payment"
          subtitle="Confirm payment before completing this sale."
          on_cancel={JS.push("cancel_payment")}
        >
          <:body>
            <.form
              for={@payment_form}
              id="quick-sale-payment-form"
              phx-submit="confirm_payment"
              class="td-modal-form"
            >
              <div class="td-tot is-big">
                <span>Order total</span>
                <b>{ThamaniDawaWeb.Money.ksh(cart_total(@cart))}</b>
              </div>
              <div class={["td-pay-grid", length(PaymentMethods.all()) > 2 && "is-3"]}>
                <.td_option_card
                  :for={method <- PaymentMethods.all()}
                  id={"pay-option-#{method}"}
                  title={payment_option_title(method)}
                  body={payment_option_body(method)}
                  selected={@payment_type == method}
                  phx-click="select_payment_type"
                  phx-value-payment_type={method}
                />
              </div>
              <div :if={@payment_type == "Cash"} class="td-tender">
                <.td_input
                  field={@payment_form[:tendered]}
                  type="number"
                  label="Amount tendered (KES)"
                  min="0"
                  step="0.01"
                  required
                />
                <button
                  id="cash-tender-exact"
                  type="button"
                  phx-click="set_cash_tendered"
                  phx-value-amount={cart_total(@cart)}
                  aria-pressed={
                    if(same_amount?(@payment_form[:tendered].value, cart_total(@cart)),
                      do: "true",
                      else: "false"
                    )
                  }
                  class={[
                    "td-btn is-secondary",
                    same_amount?(@payment_form[:tendered].value, cart_total(@cart)) && "is-active"
                  ]}
                >
                  Exact
                </button>
              </div>
              <div :if={@payment_type == "Cash"} class="td-tender-row">
                <button
                  :for={amount <- [50, 100, 200, 500, 1_000, 2_000, 5_000]}
                  id={"cash-tender-#{amount}"}
                  type="button"
                  phx-click="set_cash_tendered"
                  phx-value-amount={amount}
                  aria-pressed={
                    if(same_amount?(@payment_form[:tendered].value, amount),
                      do: "true",
                      else: "false"
                    )
                  }
                  class={[
                    "td-btn is-secondary",
                    same_amount?(@payment_form[:tendered].value, amount) && "is-active"
                  ]}
                >
                  {ThamaniDawaWeb.Money.ksh(amount)}
                </button>
              </div>
              <div :if={@payment_type == "Cash"} class="td-tot">
                <span>Change</span>
                <b>
                  {ThamaniDawaWeb.Money.ksh(
                    cash_change(@payment_form[:tendered].value, cart_total(@cart))
                  )}
                </b>
              </div>
              <.td_input
                field={@payment_form[:provider_reference]}
                label="M-Pesa transaction code (optional)"
                placeholder="e.g. SFA7B2XQ9K"
              />
              <p :if={@errors[:payment]} class="td-field-error">{@errors[:payment]}</p>
            </.form>
          </:body>
          <:footer>
            <.td_button
              type="button"
              variant="secondary"
              label="Cancel"
              phx-click="cancel_payment"
            />
            <.td_button
              type="submit"
              variant="primary"
              glyph="check"
              label="Confirm payment"
              form="quick-sale-payment-form"
              phx-disable-with="Completing sale…"
            />
          </:footer>
        </.td_modal>

        <.td_modal
          :if={@completed_sale}
          id="quick-sale-receipt-modal"
          show
          width={560}
          title="Sale complete"
          subtitle="Payment received."
          on_cancel={JS.push("new_sale")}
        >
          <:body>
            <div id="quick-sale-receipt" class="td-receipt">
              <div class="td-receipt-brand">
                <img src="/images/logo.png" alt="Thamani Dawa" />
                <span class="td-s12">{@completed_sale.site_name}</span>
              </div>
              <div class="td-receipt-meta">
                <p>
                  <span>Receipt no.</span>
                  <b>{@completed_sale.receipt_number}</b>
                </p>
                <p id="receipt-date-time">
                  <span>Date</span>
                  <b>{ThamaniDawaWeb.TimeFormat.datetime(@completed_sale.completed_at)}</b>
                </p>
                <p>
                  <span>Cashier</span>
                  <b>{@completed_sale.cashier}</b>
                </p>
              </div>
              <table id="quick-sale-receipt-items">
                <thead>
                  <tr>
                    <th>Qty</th>
                    <th>Medicine</th>
                    <th class="is-num">Unit price</th>
                    <th class="is-num">Line total</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={line <- @completed_sale.cart}>
                    <td>{line.quantity}</td>
                    <td>
                      <b>{line.product.generic_name}</b>
                    </td>
                    <td class="is-num">{ThamaniDawaWeb.Money.ksh(line.product.price)}</td>
                    <td class="is-num">
                      {ThamaniDawaWeb.Money.ksh(Decimal.mult(line.product.price, line.quantity))}
                    </td>
                  </tr>
                </tbody>
              </table>
              <div id="receipt-total" class="td-tot is-big">
                <span>Total</span>
                <b>{ThamaniDawaWeb.Money.ksh(@completed_sale.total)}</b>
              </div>
              <div id="receipt-payment-method" class="td-tot">
                <span>Payment method</span>
                <b>{@completed_sale.payment_type}</b>
              </div>
              <div
                :if={@completed_sale.tendered}
                id="receipt-cash-tendered"
                class="td-tot"
              >
                <span>Cash tendered</span>
                <b>{ThamaniDawaWeb.Money.ksh(@completed_sale.tendered)}</b>
              </div>
              <div :if={@completed_sale.change} id="receipt-change" class="td-tot">
                <span>Change</span>
                <b>{ThamaniDawaWeb.Money.ksh(@completed_sale.change)}</b>
              </div>
              <div
                :if={@completed_sale.provider_reference}
                id="receipt-mpesa-reference"
                class="td-tot"
              >
                <span>M-Pesa reference</span>
                <b>{@completed_sale.provider_reference}</b>
              </div>
              <p class="td-note" style="text-align:center">Powered by Thamani Dawa</p>
            </div>
          </:body>
          <:footer>
            <.td_button
              id="quick-sale-print"
              type="button"
              variant="secondary"
              glyph="printer"
              label="Print"
              phx-hook="QuickSaleReceiptPrint"
              data-receipt-target="#quick-sale-receipt"
            />
            <.td_button
              type="button"
              variant="primary"
              glyph="plus"
              label="New sale"
              phx-click="new_sale"
            />
          </:footer>
        </.td_modal>

        <div class="td-qs-page">
          <div class="td-qs">
            <section class="td-card td-qs-catalog">
              <div id="quick-sale-catalog-header">
                <.td_card_header
                  title="Product catalog"
                  subtitle="Search, scan, or choose an item to add to this sale."
                />
              </div>
              <form
                id="quick-sale-scan-form"
                phx-change="search_catalog"
                phx-submit="scan_submit"
                class="td-qs-toolbar"
              >
                <.td_search
                  id="quick-sale-query"
                  name="query"
                  value={@catalog_query}
                  placeholder="Scan barcode or search by product name…"
                  shortcut="/"
                  autocomplete="off"
                  autofocus
                  phx-debounce="150"
                />
                <.td_segmented>
                  <.td_segment
                    label="All"
                    active={@catalog_category == ""}
                    phx-click="filter_category"
                    phx-value-category=""
                  />
                  <.td_segment
                    :for={category <- @catalog_categories}
                    label={category}
                    active={@catalog_category == category}
                    phx-click="filter_category"
                    phx-value-category={category}
                  />
                </.td_segmented>
              </form>
              <div class="td-qs-list td-list">
                <button
                  :for={product <- @catalog_products}
                  type="button"
                  phx-click="quick_add"
                  phx-value-product_id={product.id}
                  id={"quick-add-#{product.id}"}
                  disabled={product.stock <= 0}
                  class="td-li"
                >
                  <div class="td-li-g">
                    <b>{product.generic_name}</b>
                    <span class="td-mono">{product.gtin}</span>
                  </div>
                  <span class="td-s12">{stock_label(product.stock)}</span>
                  <span class="td-num" style="width:72px;text-align:right">
                    {ThamaniDawaWeb.Money.ksh(product.price)}
                  </span>
                  <span class="td-icon-btn" aria-hidden="true">
                    <.td_icon name="plus" />
                  </span>
                </button>
                <div :if={@catalog_products == []}>
                  <.td_empty
                    title={catalog_empty_title(@site_id, @catalog_query, @catalog_category)}
                    hint={catalog_empty_message(@site_id, @catalog_query, @catalog_category)}
                  />
                </div>
                <p :if={@catalog_more?} class="td-note" style="padding:12px 16px;text-align:center">
                  Showing the first {@catalog_limit} products. Search by name or GTIN to narrow results.
                </p>
              </div>
            </section>

            <section id="quick-sale-cart" class="td-card td-qs-sale">
              <div id="quick-sale-cart-header">
                <.td_card_header
                  title="Current sale"
                  subtitle="Review quantities before taking payment."
                >
                  <:actions>
                    <.td_button
                      :if={@cart != []}
                      type="button"
                      variant="danger"
                      label="Clear"
                      phx-click="clear_cart"
                    />
                  </:actions>
                </.td_card_header>
              </div>
              <form
                :if={not @site_locked}
                id="quick-sale-header-form"
                phx-change="update_header"
                class="td-qs-toolbar"
              >
                <.td_select
                  name="site_id"
                  id="quick-sale-site"
                  label="Site"
                  value={@site_id}
                  options={Enum.map(@sites, &{&1.name, &1.id})}
                  prompt="Choose a site"
                />
              </form>
              <div id="quick-sale-items" class="td-qs-list">
                <div :if={@cart == []} class="td-qs-empty">
                  <.td_empty
                    title="No items yet"
                    hint="Scan a barcode or tap a product to start the sale."
                  />
                </div>
                <div :if={@cart != []} class="td-list">
                  <div
                    :for={
                      %{line: line, product: product, subtotal: subtotal, batch_label: batch_label} <-
                        cart_lines(@cart, @current_scope.organization_id, @site_id)
                    }
                    id={"cart-line-#{line.product_id}"}
                    class="td-li"
                  >
                    <div class="td-li-g">
                      <b>{product.generic_name}</b>
                      <span :if={batch_label}>Batch {batch_label}</span>
                    </div>
                    <div class="td-qty">
                      <.td_icon_button
                        label={"Decrease quantity for #{product.generic_name}"}
                        phx-click="decrement_item"
                        phx-value-product_id={line.product_id}
                      >
                        <:icon><.td_icon name="minus" /></:icon>
                      </.td_icon_button>
                      <form id={"cart-quantity-form-#{line.product_id}"} phx-change="set_item_quantity">
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
                        />
                      </form>
                      <.td_icon_button
                        label={"Increase quantity for #{product.generic_name}"}
                        phx-click="increment_item"
                        phx-value-product_id={line.product_id}
                      >
                        <:icon><.td_icon name="plus" /></:icon>
                      </.td_icon_button>
                    </div>
                    <span class="td-s12">{ThamaniDawaWeb.Money.ksh(product.price)}</span>
                    <span class="td-num" style="width:72px;text-align:right">
                      {ThamaniDawaWeb.Money.ksh(subtotal)}
                    </span>
                    <.td_icon_button
                      label={"Remove #{product.generic_name}"}
                      phx-click="remove_item"
                      phx-value-product_id={line.product_id}
                    >
                      <:icon><.td_icon name="trash" /></:icon>
                    </.td_icon_button>
                  </div>
                </div>
              </div>
              <div class="td-qs-foot">
                <div :if={@cart != []} class="td-tot">
                  <span>Items</span>
                  <b id="quick-sale-item-count">{cart_lines_label(@cart)}</b>
                </div>
                <div :if={@cart == []} class="hidden">
                  <span id="quick-sale-item-count">0 items</span>
                </div>
                <div class="td-tot is-big">
                  <span>Total</span>
                  <b>{ThamaniDawaWeb.Money.ksh(cart_total(@cart))}</b>
                </div>
                <.td_button
                  type="button"
                  variant="primary"
                  size="lg"
                  glyph="check"
                  label="Complete sale"
                  phx-click="complete_sale"
                  phx-disable-with="Completing sale…"
                  disabled={@cart == []}
                />
              </div>
            </section>
          </div>
        </div>
      </.td_list_page>
    </Layouts.pharmacy_shell>
    """
  end
end
