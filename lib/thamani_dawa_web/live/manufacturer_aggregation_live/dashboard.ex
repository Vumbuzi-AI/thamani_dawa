defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Dashboard do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:page_title, "Aggregation")
     |> assign(:pallets, Manufacturing.list_pallets(organization_id))
     |> assign(:shippers, Manufacturing.list_standalone_shippers(organization_id))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.td_page_header
        title="Aggregation"
        subtitle="Build pallet and shipper SSCC hierarchies, then add their GTINs, batches, and serials."
      >
        <:actions>
          <.td_button
            id="build-pallet"
            variant="secondary"
            glyph="stack"
            label="Build a pallet"
            navigate={~p"/manufacturer/aggregations/pallets/new"}
          />
          <.td_button
            id="add-sscc"
            variant="primary"
            label="Add SSCC"
            glyph="plus"
            navigate={~p"/manufacturer/aggregations/new"}
          />
        </:actions>
      </.td_page_header>

      <div class="space-y-4">
        <section id="aggregation-pallets" class="td-card">
          <.td_card_header
            title="Pallet SSCCs"
            subtitle="Parties are entered once and inherited by every shipper."
          >
            <:actions>
              <.td_button
                id="create-pallet"
                variant="secondary"
                label="Build a pallet"
                navigate={~p"/manufacturer/aggregations/pallets/new"}
              />
            </:actions>
          </.td_card_header>

          <div :if={@pallets == []} id="aggregation-pallets-empty" class="td-empty-card">
            <p class="td-empty-title">No pallet SSCCs yet</p>
            <p class="td-note">Add an SSCC or group existing shippers into a pallet.</p>
            <.td_button
              id="aggregation-pallets-empty-build"
              variant="secondary"
              label="Build a pallet"
              navigate={~p"/manufacturer/aggregations/pallets/new"}
            />
          </div>

          <div :if={@pallets != []} class="td-table">
            <table>
              <thead>
                <tr>
                  <th>Pallet SSCC</th>
                  <th>From and to</th>
                  <th class="td-num">Shippers</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={pallet <- @pallets}
                  id={"aggregation-pallet-#{pallet.id}"}
                  class="is-link"
                  phx-click={JS.navigate(~p"/manufacturer/aggregations/pallets/#{pallet.id}")}
                >
                  <td class="td-mono">{pallet.code}</td>
                  <td>
                    <span class="td-party-cell">
                      {pallet.from_company_name}
                      <.td_icon name="arrow-right" />
                      {pallet.to_company_name}
                    </span>
                  </td>
                  <td class="td-num">{length(pallet.shipper_ssccs)}</td>
                  <td><span class="td-chev"><.td_icon name="caret-right" /></span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section id="aggregation-shippers" class="td-card">
          <.td_card_header
            title="Standalone shipper SSCCs"
            subtitle="Cases that are not grouped under a pallet."
          >
            <:actions>
              <.td_button
                :if={@shippers != []}
                id="build-pallet-from-shippers"
                variant="secondary"
                label="Build a pallet"
                navigate={~p"/manufacturer/aggregations/pallets/new"}
              />
            </:actions>
          </.td_card_header>

          <div :if={@shippers == []} id="aggregation-shippers-empty" class="td-empty-card">
            <p class="td-empty-title">No standalone shippers yet</p>
            <p class="td-note">Add a shipper SSCC, then pack its GTINs, batches and serials.</p>
          </div>

          <div :if={@shippers != []} class="td-table">
            <table>
              <thead>
                <tr>
                  <th>Shipper SSCC</th>
                  <th>From and to</th>
                  <th class="td-num">Serials</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={shipper <- @shippers}
                  id={"aggregation-shipper-#{shipper.id}"}
                  class="is-link"
                  phx-click={JS.navigate(~p"/manufacturer/aggregations/ssccs/#{shipper.id}")}
                >
                  <td class="td-mono">{shipper.code}</td>
                  <td>
                    <span class="td-party-cell">
                      {shipper.from_company_name}
                      <.td_icon name="arrow-right" />
                      {shipper.to_company_name}
                    </span>
                  </td>
                  <td class="td-num">{shipper.count_of_trade_items || 0}</td>
                  <td><span class="td-chev"><.td_icon name="caret-right" /></span></td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
