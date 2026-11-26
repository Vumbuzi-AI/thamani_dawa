defmodule ThamaniDawaWeb.ManufacturerAggregationLive.SsccShow do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:sscc_id, id)
     |> assign(:page_title, "Shipper SSCC")
     |> reload()}
  end

  defp reload(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    sscc = Manufacturing.get_sscc_group!(organization_id, socket.assigns.sscc_id)

    assign(socket, :sscc, sscc)
  end

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
      <.td_page_header title="Shipper SSCC" subtitle={@sscc.code} />

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
          subtitle="Batches and serials packed into this shipper during aggregation."
        />
        <div :if={@sscc.batches == []} class="td-empty-card">
          <p class="td-empty-title">No contents on this SSCC yet</p>
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
                <td>{batch.production_date}</td>
                <td>{batch.expiry_date}</td>
                <td class="td-num">{serial_count(batch)} serials</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.manufacturer_shell>
    """
  end
end
