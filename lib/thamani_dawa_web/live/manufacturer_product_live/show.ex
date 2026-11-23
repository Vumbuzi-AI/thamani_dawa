defmodule ThamaniDawaWeb.ManufacturerProductLive.Show do
  @moduledoc """
  A manufactured product's batches and the pallet-SSCC groups packed
  around them. Generating serials and creating an SSCC both call the GS1
  member API directly and enqueue the matching EPCIS event.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Batch

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product!(organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, product.name)
     |> assign(:product, product)
     |> load_batches()
     |> load_groups()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new_batch, _params) do
    socket
    |> assign(:batch_form, to_form(Manufacturing.change_batch(), as: :batch))
  end

  defp apply_action(socket, :generate_serials, _params) do
    socket
    |> assign(:serials_form, to_form(serials_default_params(), as: :serials))
  end

  defp apply_action(socket, :create_sscc, _params) do
    socket
    |> assign(:sscc_form, to_form(sscc_default_params(), as: :sscc))
  end

  defp apply_action(socket, :show, _params), do: socket

  defp serials_default_params do
    %{trade_item_qty: 10, shipper_qty: nil, create_shippers: false, from_gln: nil, to_gln: nil}
  end

  defp sscc_default_params do
    %{count_of_trade_items: nil, from_address: nil, to_address: nil}
  end

  def handle_event("validate_batch", %{"batch" => params}, socket) do
    changeset = Manufacturing.change_batch(%Batch{}, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :batch_form, to_form(changeset, as: :batch))}
  end

  def handle_event("save_batch", %{"batch" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product_id = socket.assigns.product.id

    case Manufacturing.create_batch(organization_id, product_id, params) do
      {:ok, batch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Batch #{batch.batch_no} added.")
         |> load_batches()
         |> push_patch(to: ~p"/manufacturer/products/#{product_id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :batch_form, to_form(changeset, as: :batch))}
    end
  end

  def handle_event("generate_serials", %{"serials" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = socket.assigns.product

    with {:ok, batch} <- fetch_batch(organization_id, params["manufacturer_batch_id"]),
         member_params <- serials_member_params(params),
         {:ok, _result} <-
           Manufacturing.generate_serials(organization_id, product, batch, member_params) do
      {:noreply,
       socket
       |> put_flash(:info, "Serials generated for batch #{batch.batch_no}.")
       |> load_batches()
       |> load_groups()
       |> push_patch(to: ~p"/manufacturer/products/#{product.id}")}
    else
      {:error, :batch_not_found} ->
        {:noreply, put_flash(socket, :error, "Choose a batch first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't generate serials: #{inspect(reason)}")}
    end
  end

  def handle_event("create_sscc", %{"sscc" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = socket.assigns.product

    with {:ok, batch} <- fetch_batch(organization_id, params["manufacturer_batch_id"]),
         member_params <- sscc_member_params(params, batch),
         {:ok, shipper_sscc} <-
           Manufacturing.create_sscc(organization_id, product, [batch], member_params) do
      {:noreply,
       socket
       |> put_flash(:info, "SSCC #{shipper_sscc.code} created.")
       |> load_groups()
       |> push_patch(to: ~p"/manufacturer/products/#{product.id}")}
    else
      {:error, :batch_not_found} ->
        {:noreply, put_flash(socket, :error, "Choose a batch first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't create the SSCC: #{inspect(reason)}")}
    end
  end

  defp fetch_batch(_organization_id, batch_id) when batch_id in [nil, ""],
    do: {:error, :batch_not_found}

  defp fetch_batch(organization_id, batch_id) do
    {:ok, Manufacturing.get_batch!(organization_id, batch_id)}
  rescue
    Ecto.NoResultsError -> {:error, :batch_not_found}
  end

  defp serials_member_params(params) do
    %{
      "trade_item_qty" => params["trade_item_qty"],
      "create_shippers" => params["create_shippers"] in ["true", "on"],
      "shipper_qty" => blank_to_nil(params["shipper_qty"]),
      "from" => %{"gln" => blank_to_nil(params["from_gln"])},
      "to" => %{"gln" => blank_to_nil(params["to_gln"])}
    }
  end

  defp sscc_member_params(params, batch) do
    %{
      "batch_info" => [
        %{
          "batch" => batch.batch_no,
          "production_date" => Date.to_iso8601(batch.production_date),
          "expiry_date" => Date.to_iso8601(batch.expiry_date)
        }
      ],
      "address" => %{
        "from_address" => params["from_address"],
        "to_address" => params["to_address"]
      },
      "count_of_trade_items" => params["count_of_trade_items"]
    }
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp load_batches(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batches = Manufacturing.list_batches(organization_id, socket.assigns.product.id)
    assign(socket, :batches, batches)
  end

  defp load_groups(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    groups = Manufacturing.list_sscc_groups(organization_id, socket.assigns.product.id)

    pallet_groups =
      Enum.group_by(groups, fn %{sscc: sscc} -> sscc.pallet && sscc.pallet.code end)

    assign(socket, :pallet_groups, pallet_groups)
  end

  defp pallet_label(nil), do: "Loose shippers (no pallet)"
  defp pallet_label(code), do: "Pallet #{code}"

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
    >
      <.header icon="hero-archive-box">
        {@product.name}
        <:subtitle>
          <span class="font-mono">{@product.gtin}</span> · {@product.description}
        </:subtitle>
        <:actions>
          <.button patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}>
            <.icon name="hero-plus" class="size-4" /> Add batch
          </.button>
          <.button
            variant="primary"
            patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
          >
            <.icon name="hero-qr-code" class="size-4" /> Generate serials
          </.button>
        </:actions>
      </.header>

      <section class="mt-6">
        <h2 class="dashboard-section-label">Batches</h2>
        <.table id="manufacturer-batches" rows={@batches}>
          <:col :let={{batch, _serial_count}} label="Batch no.">{batch.batch_no}</:col>
          <:col :let={{batch, _serial_count}} label="Production">
            {Calendar.strftime(batch.production_date, "%d %b %Y")}
          </:col>
          <:col :let={{batch, _serial_count}} label="Expiry">
            {Calendar.strftime(batch.expiry_date, "%d %b %Y")}
          </:col>
          <:col :let={{_batch, serial_count}} label="Serials">{serial_count}</:col>
          <:empty_state>
            <.blank_state icon="hero-cube" title="No batches yet">
              Add a batch before generating serials or an SSCC for this product.
            </.blank_state>
          </:empty_state>
        </.table>
      </section>

      <section class="mt-8">
        <h2 class="dashboard-section-label">Pallet-SSCC groups</h2>
        <div class="mt-3 space-y-4">
          <div
            :for={{pallet_code, rows} <- @pallet_groups}
            class="rounded-2xl border border-thamani-frosted bg-white p-5"
          >
            <div class="flex items-center justify-between gap-4">
              <h3 class="text-sm font-semibold text-thamani-forest">{pallet_label(pallet_code)}</h3>
              <span class="text-xs text-thamani-pewter">
                {length(rows)} shippers · {Enum.sum(Enum.map(rows, & &1.serial_count))} primary serials
              </span>
            </div>

            <div class="mt-4 space-y-3">
              <div
                :for={%{sscc: sscc, serial_count: serial_count} <- rows}
                class="grid grid-cols-2 gap-3 rounded-xl border border-thamani-frosted bg-thamani-canvas px-4 py-3 text-sm sm:grid-cols-4"
              >
                <div>
                  <p class="text-xs text-thamani-pewter">SSCC</p>
                  <p class="font-mono">{sscc.code}</p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Batch</p>
                  <p>{sscc.batch || "—"}</p>
                </div>
                <div>
                  <p class="text-xs text-thamani-pewter">Produced / Expires</p>
                  <p>
                    {sscc.production_date && Calendar.strftime(sscc.production_date, "%d %b %Y")} – {sscc.expiry_date &&
                      Calendar.strftime(sscc.expiry_date, "%d %b %Y")}
                  </p>
                </div>
                <div class="flex flex-wrap items-center gap-2 sm:justify-end">
                  <.button variant="ghost" navigate={~p"/manufacturer/sscc/#{sscc.id}/serials"}>
                    Serials ({serial_count})
                  </.button>
                  <.button variant="ghost" navigate={~p"/manufacturer/sscc/#{sscc.id}/label"}>
                    Pallet label
                  </.button>
                  <.button variant="ghost" href={~p"/manufacturer/sscc/#{sscc.id}/export"}>
                    Export CSV
                  </.button>
                </div>
              </div>
            </div>
          </div>

          <.blank_state :if={@pallet_groups == %{}} icon="hero-cube-transparent" title="No SSCCs yet">
            Create an SSCC to pack serialised units for shipping.
          </.blank_state>
        </div>
      </section>

      <.modal
        :if={@live_action == :new_batch}
        id="manufacturer-batch-modal"
        show
        on_cancel={JS.patch(~p"/manufacturer/products/#{@product.id}")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">Add batch</h2>
        <.form
          for={@batch_form}
          id="manufacturer-batch-form"
          phx-change="validate_batch"
          phx-submit="save_batch"
        >
          <div class="space-y-4">
            <.input field={@batch_form[:batch_no]} label="Batch number" required />
            <.input
              field={@batch_form[:production_date]}
              type="date"
              label="Production date"
              required
            />
            <.input field={@batch_form[:expiry_date]} type="date" label="Expiry date" required />
          </div>
          <div class="mt-6 flex items-center justify-end gap-3">
            <.button type="button" phx-click={JS.patch(~p"/manufacturer/products/#{@product.id}")}>
              Cancel
            </.button>
            <.button variant="primary">Save batch</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :generate_serials}
        id="manufacturer-serials-modal"
        show
        on_cancel={JS.patch(~p"/manufacturer/products/#{@product.id}")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">Generate serials</h2>
        <.form
          for={@serials_form}
          id="manufacturer-serials-form"
          phx-submit="generate_serials"
        >
          <div class="space-y-4">
            <div>
              <label
                class="block text-sm font-medium text-thamani-forest"
                for="serials_manufacturer_batch_id"
              >
                Batch
              </label>
              <select
                name="serials[manufacturer_batch_id]"
                id="serials_manufacturer_batch_id"
                class="thamani-input mt-1 w-full"
              >
                <option :for={{batch, _count} <- @batches} value={batch.id}>{batch.batch_no}</option>
              </select>
            </div>
            <.input
              field={@serials_form[:trade_item_qty]}
              type="number"
              label="Primary units to serialise"
              required
            />
            <.input
              field={@serials_form[:create_shippers]}
              type="checkbox"
              label="Also mint shipper SSCCs for these serials"
            />
            <.input field={@serials_form[:shipper_qty]} type="number" label="Units per shipper" />
            <div class="grid grid-cols-2 gap-4">
              <.input field={@serials_form[:from_gln]} label="From GLN" />
              <.input field={@serials_form[:to_gln]} label="To GLN" />
            </div>
          </div>
          <div class="mt-6 flex items-center justify-end gap-3">
            <.button type="button" phx-click={JS.patch(~p"/manufacturer/products/#{@product.id}")}>
              Cancel
            </.button>
            <.button variant="primary">Generate</.button>
          </div>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :create_sscc}
        id="manufacturer-sscc-modal"
        show
        on_cancel={JS.patch(~p"/manufacturer/products/#{@product.id}")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">Create SSCC</h2>
        <.form for={@sscc_form} id="manufacturer-sscc-form" phx-submit="create_sscc">
          <div class="space-y-4">
            <div>
              <label
                class="block text-sm font-medium text-thamani-forest"
                for="sscc_manufacturer_batch_id"
              >
                Batch
              </label>
              <select
                name="sscc[manufacturer_batch_id]"
                id="sscc_manufacturer_batch_id"
                class="thamani-input mt-1 w-full"
              >
                <option :for={{batch, _count} <- @batches} value={batch.id}>{batch.batch_no}</option>
              </select>
            </div>
            <.input
              field={@sscc_form[:count_of_trade_items]}
              type="number"
              label="Trade items packed"
            />
            <div class="grid grid-cols-2 gap-4">
              <.input field={@sscc_form[:from_address]} label="From address" />
              <.input field={@sscc_form[:to_address]} label="To address" />
            </div>
          </div>
          <div class="mt-6 flex items-center justify-end gap-3">
            <.button type="button" phx-click={JS.patch(~p"/manufacturer/products/#{@product.id}")}>
              Cancel
            </.button>
            <.button variant="primary">Create SSCC</.button>
          </div>
        </.form>
      </.modal>
    </Layouts.manufacturer_shell>
    """
  end
end
