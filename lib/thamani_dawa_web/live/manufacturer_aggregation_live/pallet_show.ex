defmodule ThamaniDawaWeb.ManufacturerAggregationLive.PalletShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    pallet = Manufacturing.get_pallet!(socket.assigns.current_scope.organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, "Pallet #{pallet.code}")
     |> assign(:pallet, pallet)
     |> assign(
       :total_serials,
       Enum.sum(Enum.map(pallet.shipper_ssccs, &(&1.count_of_trade_items || 0)))
     )}
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
      <.link navigate={~p"/manufacturer/aggregations"} class="td-back-link">
        <.td_icon name="arrow-left" /> Aggregation
      </.link>
      <.td_page_header title={@pallet.code} subtitle={"Pallet SSCC · #{length(@pallet.shipper_ssccs)} shippers · #{@total_serials} serials"}>
        <:actions>
          <.td_button
            id="add-pallet-shipper"
            variant="primary"
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
                <td class="td-mono">{sscc.code}</td>
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
    </Layouts.manufacturer_shell>
    """
  end
end
