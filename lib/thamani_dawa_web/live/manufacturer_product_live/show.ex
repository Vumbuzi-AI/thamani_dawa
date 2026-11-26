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
     |> assign(:label_sscc, nil)
     |> load_batches()
     |> load_groups()}
  end

  def handle_params(params, _url, socket) do
    socket =
      assign(socket, :back_path, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/products"))

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
    |> put_flash(
      :info,
      "Prepare shipper SSCCs from the batch aggregation workflow so allocation, label verification, and actual contents stay connected."
    )
    |> push_navigate(to: ~p"/manufacturer/aggregations")
  end

  defp apply_action(socket, :show, _params), do: socket

  defp serials_default_params do
    %{trade_item_qty: 10, shipper_qty: nil, create_shippers: false, from_gln: nil, to_gln: nil}
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
        {:noreply, put_flash(socket, :error, generation_error(reason))}
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
       |> put_flash(:info, "Shipper label #{shipper_sscc.code} created.")
       |> load_groups()
       |> push_patch(to: ~p"/manufacturer/products/#{product.id}")}
    else
      {:error, :batch_not_found} ->
        {:noreply, put_flash(socket, :error, "Choose a batch first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, sscc_error(reason))}
    end
  end

  def handle_event("open_label", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {sscc_id, ""} ->
        sscc =
          socket.assigns.pallet_groups
          |> Enum.flat_map(fn {_pallet, rows} -> rows end)
          |> Enum.find(&(&1.sscc.id == sscc_id))

        case sscc do
          nil -> {:noreply, socket}
          %{sscc: sscc} -> {:noreply, assign(socket, :label_sscc, sscc)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_label", _params, socket),
    do: {:noreply, assign(socket, :label_sscc, nil)}

  defp generation_error(:unconfigured),
    do:
      "GS1 isn't set up for your organization. Add your GS1 key in organization settings, then try again."

  defp generation_error(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings, then try again."

  defp generation_error(:not_found),
    do: "This product isn't in your GS1 account. Sync it from GS1 first, then try again."

  defp generation_error(:unavailable), do: "We couldn't reach GS1. Try again in a moment."

  defp generation_error({:invalid, _message}),
    do: "GS1 couldn't accept the batch details. Check them and try again."

  defp generation_error(_reason),
    do: "We couldn't complete that request. Try again in a moment."

  defp sscc_error(:unconfigured),
    do:
      "GS1 isn't set up for your organization. Add your GS1 key in organization settings, then try again."

  defp sscc_error(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings, then try again."

  defp sscc_error(:unavailable),
    do: "We couldn't reach GS1 to create the shipper label. Try again in a moment."

  defp sscc_error({:invalid, _message}),
    do: "GS1 couldn't accept the shipper details. Check them and try again."

  defp sscc_error(_reason),
    do: "We couldn't create the shipper label. Try again in a moment."

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

    label_sscc =
      case socket.assigns[:label_sscc] do
        %{id: sscc_id} ->
          case Enum.find(groups, &(&1.sscc.id == sscc_id)) do
            %{sscc: sscc} -> sscc
            nil -> nil
          end

        _ ->
          nil
      end

    socket
    |> assign(:pallet_groups, pallet_groups)
    |> assign(:label_sscc, label_sscc)
  end

  defp pallet_label(nil), do: "Loose shippers (no pallet)"
  defp pallet_label(code), do: "Pallet #{code}"

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Products"
    >
      <.td_back_link
        id="product-back"
        to={@back_path}
        label={ThamaniDawaWeb.ReturnTo.label(@back_path, "Back to Products")}
      />
      <.td_detail_page
        title={@product.name}
        subtitle={"#{@product.gtin} · #{@product.description}"}
      >
        <:actions>
          <.td_button
            variant="secondary"
            label="Generate serials"
            patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
            tip="Issue a GS1 batch and DataMatrix serials. You will set quantity, dates, and facility."
          />
          <.td_button
            variant="primary"
            label="Create SSCC"
            patch={~p"/manufacturer/products/#{@product.id}/sscc"}
            tip="Pack serials into a shipper SSCC for this product."
            tip_align="end"
          />
        </:actions>
        <.td_key_value label="GTIN" value={@product.gtin} mono />
        <.td_key_value label="Description" value={@product.description} />
        <:body>
          <section>
            <.td_card_header title="Batches" />
            <.td_data_table
              id="manufacturer-batches"
              rows={@batches}
              row_id={fn {batch, _} -> "manufacturer-batch-#{batch.id}" end}
            >
              <:col :let={{batch, serial_count}} label="Batch no.">
                <.td_pid id={"manufacturer-batch-#{batch.id}-peek"} label={batch.batch_no} mono>
                  <:peek>
                    <.td_peek
                      kind="Batch"
                      title={batch.batch_no}
                      subtitle={@product.name}
                      icon="stack"
                    >
                      <:row label="Production">
                        {ThamaniDawaWeb.TimeFormat.date(batch.production_date)}
                      </:row>
                      <:row label="Expiry">{ThamaniDawaWeb.TimeFormat.date(batch.expiry_date)}</:row>
                      <:row label="Serials">{serial_count}</:row>
                    </.td_peek>
                  </:peek>
                </.td_pid>
              </:col>
              <:col :let={{batch, _serial_count}} label="Production">
                {ThamaniDawaWeb.TimeFormat.date(batch.production_date)}
              </:col>
              <:col :let={{batch, _serial_count}} label="Expiry">
                {ThamaniDawaWeb.TimeFormat.date(batch.expiry_date)}
              </:col>
              <:col :let={{_batch, serial_count}} label="Serials">{serial_count}</:col>
              <:empty>
                <.td_empty
                  icon="stack"
                  title="No batches yet"
                  hint="Generate serials to record the first batch for this product."
                >
                  <:action>
                    <.td_button
                      variant="secondary"
                      glyph="arrow-right"
                      label="Generate serials"
                      patch={~p"/manufacturer/products/#{@product.gtin}/serials/new"}
                    />
                  </:action>
                </.td_empty>
              </:empty>
            </.td_data_table>
          </section>

          <section class="mt-8">
            <h2 class="dashboard-section-label">Pallet-SSCC groups</h2>
            <div class="mt-3 space-y-4">
              <div
                :for={{pallet_code, rows} <- @pallet_groups}
                class="rounded-2xl border border-thamani-frosted bg-td-surface p-5"
              >
                <div class="flex items-center justify-between gap-4">
                  <h3 class="text-sm font-semibold text-thamani-forest">
                    {pallet_label(pallet_code)}
                  </h3>
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
                        {sscc.production_date && ThamaniDawaWeb.TimeFormat.date(sscc.production_date)} – {sscc.expiry_date &&
                          ThamaniDawaWeb.TimeFormat.date(sscc.expiry_date)}
                      </p>
                    </div>
                    <div class="flex flex-wrap items-center gap-2 sm:justify-end">
                      <.td_button
                        variant="secondary"
                        label={"Serials (#{serial_count})"}
                        navigate={~p"/manufacturer/sscc/#{sscc.id}/serials"}
                      />
                      <.td_button
                        id={"product-sscc-label-#{sscc.id}"}
                        variant="secondary"
                        label="Shipper label"
                        phx-click="open_label"
                        phx-value-id={sscc.id}
                      />
                      <.td_button
                        variant="secondary"
                        label="Export CSV"
                        href={~p"/manufacturer/sscc/#{sscc.id}/export"}
                      />
                    </div>
                  </div>
                </div>
              </div>

              <.td_empty
                :if={@pallet_groups == %{}}
                icon="package"
                title="No SSCCs yet"
                hint="Prepare shipper labels from the batch aggregation workflow."
              >
                <:action>
                  <.td_button
                    variant="secondary"
                    glyph="arrow-right"
                    label="Open aggregation"
                    navigate={~p"/manufacturer/aggregations"}
                  />
                </:action>
              </.td_empty>
            </div>
          </section>
        </:body>
      </.td_detail_page>

      <.td_overlay_form
        :if={@live_action == :create_sscc}
        id="manufacturer-sscc-modal"
        title="Create SSCC"
        submit="Create SSCC"
        on_cancel={JS.patch(~p"/manufacturer/products/#{@product.id}")}
      >
        <.form for={@sscc_form} id="manufacturer-sscc-modal-form" phx-submit="create_sscc">
          <.td_select
            name="sscc[manufacturer_batch_id]"
            id="sscc_manufacturer_batch_id"
            label="Batch"
            options={Enum.map(@batches, fn {batch, _count} -> {batch.batch_no, batch.id} end)}
            required
          />
          <.td_input
            field={@sscc_form[:count_of_trade_items]}
            type="number"
            label="Trade items packed"
          />
          <.td_input field={@sscc_form[:from_address]} label="From address" />
          <.td_input field={@sscc_form[:to_address]} label="To address" />
        </.form>
      </.td_overlay_form>

      <ThamaniDawaWeb.ManufacturerSsccLive.Label.modal
        :if={@label_sscc}
        sscc={@label_sscc}
        product_name={@product.name}
        on_cancel={JS.push("close_label")}
      />
    </Layouts.manufacturer_shell>
    """
  end
end
