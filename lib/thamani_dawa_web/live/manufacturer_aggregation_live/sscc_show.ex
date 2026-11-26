defmodule ThamaniDawaWeb.ManufacturerAggregationLive.SsccShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.GtinLookup
  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:sscc_id, id)
     |> assign(:page_title, "Shipper SSCC")
     |> assign(:mode, nil)
     |> assign(:verified_gtin, nil)
     |> assign(:lookup_error, nil)
     |> assign(:bulk_status, :idle)
     |> assign(:bulk_results, [])
     |> assign(:bulk_form, to_form(%{"gtins" => ""}, as: :bulk))
     |> assign(
       :product_form,
       to_form(%{"gtin" => "", "name" => "", "description" => ""}, as: :product)
     )
     |> assign(
       :batch_form,
       to_form(
         %{"product_id" => "", "batch_no" => "", "production_date" => "", "expiry_date" => ""},
         as: :batch
       )
     )
     |> assign(:serial_form, to_form(%{"batch_id" => "", "serials" => ""}, as: :serials))
     |> reload()}
  end

  def handle_event("open", %{"mode" => mode}, socket)
      when mode in ["gtin", "bulk_gtins", "batch", "serials"] do
    {:noreply, socket |> assign(:mode, mode) |> assign(:lookup_error, nil)}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, :mode, nil)}

  def handle_event("verify_gtin", %{"product" => %{"gtin" => code}}, socket) do
    code = String.trim(code)

    case Enum.find(socket.assigns.products, &(&1.gtin == code)) do
      nil ->
        case GtinLookup.lookup(code) do
          {:ok, details} ->
            attrs = %{
              "gtin" => details.gtin,
              "name" => details[:brand_name] || "",
              "description" => details[:generic_name] || "",
              "brand_owner" => details[:manufacturer] || ""
            }

            {:noreply,
             socket
             |> assign(:verified_gtin, details.gtin)
             |> assign(:lookup_error, nil)
             |> assign(:product_form, to_form(attrs, as: :product))}

          {:error, reason} ->
            {:noreply, assign(socket, :lookup_error, lookup_message(reason))}
        end

      product ->
        {:noreply,
         socket
         |> assign(:verified_gtin, product.gtin)
         |> assign(:lookup_error, nil)
         |> assign(:product_form, to_form(Map.from_struct(product), as: :product))}
    end
  end

  def handle_event("save_gtin", %{"product" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    gtin = socket.assigns.verified_gtin

    result =
      case Enum.find(socket.assigns.products, &(&1.gtin == gtin)) do
        nil -> Manufacturing.create_product(organization_id, Map.put(attrs, "gtin", gtin))
        product -> {:ok, product}
      end

    case result do
      {:ok, product} ->
        {:noreply,
         socket
         |> put_flash(:info, "GTIN ready. Add one or more batches next.")
         |> assign(:mode, "batch")
         |> assign(
           :batch_form,
           to_form(
             %{
               "product_id" => product.id,
               "batch_no" => "",
               "production_date" => "",
               "expiry_date" => ""
             },
             as: :batch
           )
         )
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :product_form, to_form(changeset, as: :product))}
    end
  end

  def handle_event("verify_bulk_gtins", %{"bulk" => %{"gtins" => values}}, socket) do
    owned = Map.new(socket.assigns.products, &{&1.gtin, &1})

    codes =
      values
      |> String.split(~r/[\s,;]+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    {:noreply,
     socket
     |> assign(:bulk_status, :verifying)
     |> assign(:bulk_results, [])
     |> start_async(:verify_bulk_gtins, fn -> verify_gtins(codes, owned) end)}
  end

  def handle_event("save_bulk_gtins", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {saved, failed} =
      socket.assigns.bulk_results
      |> Enum.filter(&(&1.status in [:owned, :verified]))
      |> Enum.reduce({0, 0}, fn
        %{status: :owned}, {saved, failed} ->
          {saved + 1, failed}

        result, {saved, failed} ->
          attrs = %{
            "gtin" => result.code,
            "name" => result.details[:brand_name] || "GTIN #{result.code}",
            "description" => result.details[:generic_name] || "",
            "brand_owner" => result.details[:manufacturer] || ""
          }

          case Manufacturing.create_product(organization_id, attrs) do
            {:ok, _product} -> {saved + 1, failed}
            {:error, _changeset} -> {saved, failed + 1}
          end
      end)

    socket = socket |> assign(:mode, "batch") |> assign(:bulk_status, :idle) |> reload()

    if failed == 0,
      do:
        {:noreply, put_flash(socket, :info, "#{saved} GTINs are ready. Add their batches next.")},
      else: {:noreply, put_flash(socket, :error, "#{failed} GTINs could not be saved.")}
  end

  def handle_event("save_batch", %{"batch" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product_id = attrs["product_id"]

    with {:ok, batch} <-
           Manufacturing.find_or_create_batch(
             organization_id,
             String.to_integer(product_id),
             attrs
           ),
         {:ok, _batch} <-
           Manufacturing.add_batch_to_sscc(organization_id, socket.assigns.sscc.id, batch.id) do
      {:noreply,
       socket |> put_flash(:info, "Batch added to this SSCC.") |> assign(:mode, nil) |> reload()}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :batch_form, to_form(changeset, as: :batch))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Batch could not be added.")}
    end
  end

  def handle_event(
        "save_serials",
        %{"serials" => %{"batch_id" => batch_id, "serials" => values}},
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = Manufacturing.get_batch!(organization_id, batch_id)

    serials =
      values
      |> String.split(~r/[\r\n,]+/, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    results =
      Enum.map(
        serials,
        &Manufacturing.create_manual_serial(organization_id, batch, socket.assigns.sscc, %{
          "serial" => &1
        })
      )

    failures = Enum.count(results, &match?({:error, _}, &1))

    socket = socket |> assign(:mode, nil) |> reload()

    if failures == 0,
      do: {:noreply, put_flash(socket, :info, "#{length(serials)} serials added.")},
      else:
        {:noreply,
         put_flash(socket, :error, "#{failures} serials could not be added (usually duplicates).")}
  end

  def handle_async(:verify_bulk_gtins, {:ok, results}, socket) do
    {:noreply, socket |> assign(:bulk_status, :review) |> assign(:bulk_results, results)}
  end

  def handle_async(:verify_bulk_gtins, _result, socket) do
    {:noreply, socket |> assign(:bulk_status, :failed) |> assign(:bulk_results, [])}
  end

  defp verify_gtins(codes, owned) do
    codes
    |> Task.async_stream(
      fn code ->
        case owned[code] do
          nil -> bulk_lookup(code)
          product -> %{code: code, status: :owned, name: product.name, details: %{}}
        end
      end,
      timeout: :infinity,
      ordered: true,
      max_concurrency: 5
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp bulk_lookup(code) do
    case GtinLookup.lookup(code) do
      {:ok, details} ->
        %{
          code: details.gtin,
          status: :verified,
          name: details[:brand_name] || details[:generic_name] || "Product details missing",
          details: details
        }

      {:error, reason} ->
        %{code: code, status: :failed, name: lookup_message(reason), details: %{}}
    end
  end

  defp reload(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, socket.assigns.sscc_id)

    socket
    |> assign(:sscc, sscc)
    |> assign(:products, Manufacturing.list_products(organization_id))
  end

  defp lookup_message(:invalid_gtin), do: "Enter a valid GTIN."
  defp lookup_message(:not_found), do: "This GTIN was not found on GS1."
  defp lookup_message(_reason), do: "GS1 verification is temporarily unavailable."

  defp product_options(products), do: Enum.map(products, &{"#{&1.gtin} · #{&1.name}", &1.id})

  defp batch_options(batches),
    do: Enum.map(batches, &{"#{&1.product.gtin} · #{&1.batch_no}", &1.id})

  defp bulk_status_label(:owned), do: "Owned GTIN"
  defp bulk_status_label(:verified), do: "Verified"
  defp bulk_status_label(:failed), do: "Not ready"

  defp serial_count(batch),
    do: Enum.count(batch.serials, &(!is_nil(&1.manufacturer_shipper_sscc_id)))

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.link
        navigate={
          if(@sscc.pallet,
            do: ~p"/manufacturer/aggregations/pallets/#{@sscc.pallet.id}",
            else: ~p"/manufacturer/aggregations"
          )
        }
        class="td-back-link"
      >
        <.td_icon name="arrow-left" /> {if @sscc.pallet, do: "Pallet", else: "Aggregation"}
      </.link>
      <.td_page_header
        title={"Shipper #{@sscc.code}"}
        subtitle="The GTINs, batches, and serials packed in this shipper."
      >
        <:actions>
          <.td_button
            id="upload-sscc-gtins"
            variant="secondary"
            label="Upload GTINs"
            glyph="upload-simple"
            phx-click="open"
            phx-value-mode="bulk_gtins"
          />
          <.td_button
            id="add-sscc-gtin"
            variant="primary"
            label="Add GTIN"
            glyph="plus"
            phx-click="open"
            phx-value-mode="gtin"
          />
        </:actions>
      </.td_page_header>

      <div class="grid gap-4 md:grid-cols-2" style="margin-bottom:16px">
        <section class="td-card td-party-card">
          <span class="td-k"><.td_icon name="factory" /> From</span>
          <span class="td-v">{@sscc.from_company_name}</span>
          <span class="td-mono">{@sscc.from_gln}</span>
          <span class="td-a">{@sscc.from_address}</span>
        </section>
        <section class="td-card td-party-card">
          <span class="td-k"><.td_icon name="warehouse" /> To</span>
          <span class="td-v">{@sscc.to_company_name}</span>
          <span class="td-mono">{@sscc.to_gln}</span>
          <span class="td-a">{@sscc.to_address}</span>
        </section>
      </div>

      <section id="sscc-contents" class="td-card">
        <.td_card_header
          title="Contents"
          subtitle="Add several batches and enter serials one at a time or in bulk."
        >
          <:actions>
            <.td_button
              id="add-sscc-batch"
              variant="secondary"
              label="Add batch"
              phx-click="open"
              phx-value-mode="batch"
            />
            <.td_button
              id="add-sscc-serials"
              variant="secondary"
              label="Add serials"
              phx-click="open"
              phx-value-mode="serials"
            />
          </:actions>
        </.td_card_header>
        <div :if={@sscc.batches == []} class="td-empty-card">
          <p class="td-empty-title">No GTINs or batches on this SSCC yet</p>
        </div>
        <div :if={@sscc.batches != []} class="td-table">
          <table>
            <thead>
              <tr>
                <th>Product</th>
                <th>Batch</th>
                <th>Production</th>
                <th>Expiry</th>
                <th class="td-num">Serials</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={batch <- @sscc.batches} id={"sscc-batch-#{batch.id}"}>
                <td>
                  <div>{batch.product.name}</div>
                  <div class="td-mono">{batch.product.gtin}</div>
                </td>
                <td class="td-mono">{batch.batch_no}</td>
                <td>{ThamaniDawaWeb.TimeFormat.date(batch.production_date)}</td>
                <td>{ThamaniDawaWeb.TimeFormat.date(batch.expiry_date)}</td>
                <td class="td-num">{serial_count(batch)} serials</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <.modal :if={@mode == "gtin"} id="sscc-gtin-modal" show on_cancel={JS.push("cancel")}>
        <div class="p-6">
          <h2 class="text-xl font-semibold text-thamani-forest">Add a GTIN</h2><p class="mt-1 text-sm text-thamani-pewter">
            Owned GTINs are reused; new ones are verified against GS1.
          </p>
          <.form
            :if={is_nil(@verified_gtin)}
            for={@product_form}
            id="sscc-verify-gtin-form"
            phx-submit="verify_gtin"
            class="mt-5 space-y-4"
          >
            <.input field={@product_form[:gtin]} type="text" label="GTIN" required /><p
              :if={@lookup_error}
              class="text-sm text-red-600"
            >
              {@lookup_error}
            </p><div class="flex justify-end"><.button variant="primary">Verify GTIN</.button></div>
          </.form>
          <.form
            :if={@verified_gtin}
            for={@product_form}
            id="sscc-product-form"
            phx-submit="save_gtin"
            class="mt-5 space-y-4"
          >
            <.input field={@product_form[:gtin]} type="text" label="GTIN" disabled /><.input
              field={@product_form[:name]}
              type="text"
              label="Product name"
              required
            /><.input field={@product_form[:description]} type="textarea" label="Description" /><div class="flex justify-end">
              <.button variant="primary">Save GTIN</.button>
            </div>
          </.form>
        </div>
      </.modal>

      <.modal
        :if={@mode == "bulk_gtins"}
        id="sscc-bulk-gtins-modal"
        show
        on_cancel={JS.push("cancel")}
      >
        <div class="p-6">
          <p class="text-xs font-semibold uppercase tracking-wider text-thamani-pewter">
            Bulk GTINs
          </p>
          <h2 class="mt-1 text-xl font-semibold text-thamani-forest">
            {if @bulk_status == :review, do: "Review verification", else: "Upload GTINs"}
          </h2>
          <.form
            :if={@bulk_status in [:idle, :failed]}
            for={@bulk_form}
            id="sscc-bulk-gtins-form"
            phx-submit="verify_bulk_gtins"
            class="mt-5 space-y-4"
          >
            <.input
              field={@bulk_form[:gtins]}
              type="textarea"
              rows="10"
              label="GTINs"
              placeholder="One GTIN per line, or comma-separated"
              required
            />
            <p :if={@bulk_status == :failed} class="text-sm text-red-600">
              The GTIN list could not be verified. Try again.
            </p>
            <div class="flex justify-end">
              <.button variant="primary" phx-disable-with="Verifying...">Verify GTINs</.button>
            </div>
          </.form>
          <div
            :if={@bulk_status == :verifying}
            id="bulk-gtin-verifying"
            class="td-empty-state"
          >
            <.td_icon name="circle-notch" class="td-empty-state-icon motion-safe:animate-spin" />
            <p class="td-empty-state-title">Checking each GTIN against GS1…</p>
          </div>
          <div :if={@bulk_status == :review} id="bulk-gtin-review" class="mt-5 space-y-3">
            <div
              :for={result <- @bulk_results}
              id={"bulk-gtin-#{result.code}"}
              class="flex items-center justify-between gap-3"
              style="padding:12px 0;border-bottom:1px solid var(--color-td-hairline)"
            >
              <div>
                <p class="td-mono">{result.code}</p>
                <p class="td-note">{result.name}</p>
              </div>
              <span class={[
                "td-status-dot",
                result.status == :failed && "is-danger",
                result.status == :verified && "is-success"
              ]}>
                <i></i>
                {bulk_status_label(result.status)}
              </span>
            </div>
            <div class="flex justify-end gap-2 pt-3">
              <.td_button
                variant="secondary"
                label="Back"
                phx-click="open"
                phx-value-mode="bulk_gtins"
              />
              <.td_button
                id="save-bulk-gtins"
                variant="primary"
                label="Save ready GTINs"
                phx-click="save_bulk_gtins"
              />
            </div>
          </div>
        </div>
      </.modal>

      <.modal :if={@mode == "batch"} id="sscc-batch-modal" show on_cancel={JS.push("cancel")}>
        <div class="p-6">
          <h2 class="text-xl font-semibold text-thamani-forest">Add a batch</h2><.form
            for={@batch_form}
            id="sscc-batch-form"
            phx-submit="save_batch"
            class="mt-5 grid gap-4 sm:grid-cols-2"
          >
            <div class="sm:col-span-2">
              <.input
                field={@batch_form[:product_id]}
                type="select"
                label="GTIN"
                prompt="Choose a GTIN"
                options={product_options(@products)}
                required
              />
            </div><.input field={@batch_form[:batch_no]} type="text" label="Batch number" required /><span></span><.date_picker
              field={@batch_form[:production_date]}
              label="Production date"
              required
            /><.date_picker field={@batch_form[:expiry_date]} label="Expiry date" required /><div class="flex justify-end sm:col-span-2">
              <.button variant="primary">Save batch</.button>
            </div>
          </.form>
        </div>
      </.modal>

      <.modal :if={@mode == "serials"} id="sscc-serials-modal" show on_cancel={JS.push("cancel")}>
        <div class="p-6">
          <h2 class="text-xl font-semibold text-thamani-forest">Add serials</h2><p class="mt-1 text-sm text-thamani-pewter">
            Paste one serial per line or comma-separated. Blank rows are ignored (“fill down”).
          </p><.form
            for={@serial_form}
            id="sscc-serials-form"
            phx-submit="save_serials"
            class="mt-5 space-y-4"
          >
            <.input
              field={@serial_form[:batch_id]}
              type="select"
              label="Batch"
              prompt="Choose a batch"
              options={batch_options(@sscc.batches)}
              required
            /><.input
              field={@serial_form[:serials]}
              type="textarea"
              label="Serial numbers"
              rows="10"
              required
            /><div class="flex justify-end"><.button variant="primary">Add serials</.button></div>
          </.form>
        </div>
      </.modal>
    </Layouts.manufacturer_shell>
    """
  end
end
