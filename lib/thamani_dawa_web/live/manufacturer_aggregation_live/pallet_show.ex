defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawaWeb.ReturnTo

  def mount(%{"id" => id}, _session, socket) do
    pallet = Manufacturing.get_pallet!(socket.assigns.current_scope.organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Pallet #{pallet.code}")
     |> assign(:pallet, pallet)
     |> assign(:label?, false)
     |> assign(:back_path, ~p"/manufacturer/aggregations")
     |> assign(
       :total_serials,
       Enum.sum(Enum.map(pallet.shipper_ssccs, &(&1.count_of_trade_items || 0)))
     )}
  end

  def handle_params(params, _url, socket) do
    {:noreply, assign(socket, :back_path, ReturnTo.path(params, ~p"/manufacturer/aggregations"))}
  end

  def handle_event("print_label", _params, socket) do
    {:noreply, assign(socket, :label?, true)}
  end

  def handle_event("close_label", _params, socket) do
    {:noreply, assign(socket, :label?, false)}
  end

  defp product_label(sscc) do
    case sscc.batches do
      [%{product: %{name: name}} | _] -> name
      _ -> sscc.gtin || "—"
    end
  end

  defp batch_count(sscc) do
    batches = sscc.batches || []
    if batches == [], do: if(sscc.batch, do: 1, else: 0), else: length(batches)
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.td_back_link id="pallet-back" to={@back_path} label="Back to Aggregation" />
      <.td_page_header title={@pallet.code} subtitle={"Pallet SSCC · #{length(@pallet.shipper_ssccs)} shippers · #{@total_serials} serials"}>
        <:actions>
          <.td_button
            id="print-pallet-label"
            label="Print label"
            glyph="printer"
            phx-click="print_label"
          />
          <.td_button
            id="ship-pallet"
            variant="primary"
            label="Ship this pallet"
            navigate={~p"/manufacturer/shipments/new?#{[pallet_id: @pallet.id, return_to: ~p"/manufacturer/aggregations/pallets/#{@pallet.id}"]}"}
          />
          <.td_button
            id="add-pallet-shipper"
            label="Add shipper SSCC"
            glyph="plus"
            navigate={~p"/manufacturer/aggregations/pallets/#{@pallet.id}/ssccs/new"}
          />
        </:actions>
      </.td_page_header>

      <div class="grid gap-4 md:grid-cols-2" style="margin-bottom:16px">
        <section class="td-card td-party-card">
          <span class="td-k"><.td_icon name="factory" /> From</span>
          <span class="td-v">{@pallet.from_company_name}</span>
          <span class="td-mono">{@pallet.from_gln}</span>
          <span class="td-a">{@pallet.from_address}</span>
        </section>
        <section class="td-card td-party-card">
          <span class="td-k"><.td_icon name="warehouse" /> To</span>
          <span class="td-v">{@pallet.to_company_name}</span>
          <span class="td-mono">{@pallet.to_gln}</span>
          <span class="td-a">{@pallet.to_address}</span>
        </section>
      </div>

      <section id="pallet-shippers" class="td-card">
        <.td_card_header title="Shipper SSCCs" subtitle="Each shipper inherits this pallet's parties." />

        <div :if={@pallet.shipper_ssccs == []} id="pallet-shippers-empty" class="td-empty-card">
          <p class="td-empty-title">No shipper SSCCs on this pallet</p>
          <p class="td-note">Add a shipper SSCC to start packing GTINs, batches and serials.</p>
        </div>

        <div :if={@pallet.shipper_ssccs != []} class="td-table">
          <table>
            <thead>
              <tr>
                <th>Shipper SSCC</th>
                <th>Product</th>
                <th class="td-num">Batches</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sscc <- @pallet.shipper_ssccs} id={"pallet-shipper-#{sscc.id}"}>
                <td>
                  <.td_pid
                    id={"pallet-shipper-#{sscc.id}-code"}
                    label={sscc.code}
                    mono
                    navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                  >
                    <:peek>
                      <.td_peek
                        kind="SSCC"
                        title={sscc.code}
                        icon="package"
                        mono
                        subtitle={product_label(sscc)}
                      >
                        <:row :if={sscc.gtin} label="GTIN" mono>{sscc.gtin}</:row>
                        <:row label="Batches">{batch_count(sscc)}</:row>
                      </.td_peek>
                    </:peek>
                  </.td_pid>
                </td>
                <td>
                  <div>{product_label(sscc)}</div>
                  <div :if={sscc.gtin} class="td-mono">{sscc.gtin}</div>
                </td>
                <td class="td-num">{batch_count(sscc)}</td>
                <td>
                  <div class="td-key-row-actions">
                    <.td_button
                      id={"pallet-shipper-#{sscc.id}-open"}
                      variant="secondary"
                      label="Open"
                      navigate={~p"/manufacturer/aggregations/ssccs/#{sscc.id}"}
                    />
                    <.td_button
                      id={"pallet-shipper-#{sscc.id}-serials"}
                      variant="secondary"
                      label="Serials"
                      navigate={~p"/manufacturer/sscc/#{sscc.id}/serials"}
                    />
                    <.td_button
                      id={"pallet-shipper-#{sscc.id}-label"}
                      variant="secondary"
                      label="Label"
                      navigate={~p"/manufacturer/sscc/#{sscc.id}/label"}
                    />
                    <.td_button
                      id={"pallet-shipper-#{sscc.id}-export"}
                      variant="secondary"
                      label="Export CSV"
                      href={~p"/manufacturer/sscc/#{sscc.id}/export"}
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <.td_modal
        :if={@label?}
        id="pallet-label-modal"
        show
        title="Pallet label"
        subtitle={"SSCC #{@pallet.code} · #{length(@pallet.shipper_ssccs)} shippers"}
        on_cancel={JS.push("close_label")}
      >
        <:body>
          <div id={"pallet-label-content-#{@pallet.id}"} class="td-label-sheet">
            <p><strong>{@pallet.code}</strong></p>
            <p>From {@pallet.from_company_name}</p>
            <p class="font-mono">{@pallet.from_gln}</p>
            <p>To {@pallet.to_company_name}</p>
            <p class="font-mono">{@pallet.to_gln}</p>
            <p>{length(@pallet.shipper_ssccs)} shippers · {@total_serials} units</p>
          </div>
        </:body>
        <:footer>
          <.td_button label="Cancel" phx-click="close_label" />
          <.td_button
            id="print-pallet-label-confirm"
            variant="primary"
            glyph="printer"
            label="Print label"
            phx-hook="LabelPrint"
            data-print-target={"#pallet-label-content-#{@pallet.id}"}
            data-label-size="4in 6in"
            phx-click="close_label"
          />
        </:footer>
      </.td_modal>
    </Layouts.manufacturer_shell>
    """
  end
end
