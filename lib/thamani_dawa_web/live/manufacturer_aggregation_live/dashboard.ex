defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Dashboard do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Operations

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    all_batches = Operations.list_shipper_aggregation_batches(organization_id)

    {active_batches, packed_batches} =
      Enum.split_with(all_batches, &(batch_progress(&1) != :packed))

    {:ok,
     socket
     |> assign(:page_title, "Aggregation")
     |> assign(:tab, "shippers")
     |> assign(:pallets, Manufacturing.list_pallets(organization_id))
     |> assign(:batches, active_batches)
     |> assign(:packed_batch_count, length(packed_batches))}
  end

  def handle_params(params, _url, socket) do
    tab = if params["tab"] == "pallets", do: "pallets", else: "shippers"

    {:noreply, assign(socket, :tab, tab)}
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
        subtitle="Pack serialized units into shippers, then group completed shippers onto pallets."
      >
        <:actions>
          <div
            id="start-aggregation-menu"
            class="td-chip-wrap"
            phx-click-away={JS.hide(to: "#start-aggregation-options")}
          >
            <.td_button
              id="start-aggregation"
              variant="primary"
              label="Start aggregation"
              glyph="plus"
              phx-click={JS.toggle(to: "#start-aggregation-options")}
              aria-haspopup="menu"
            />
            <div id="start-aggregation-options" class="td-popover td-start-menu hidden" role="menu">
              <p class="td-popover-label">Choose an operation</p>
              <.link
                id="start-shipper-aggregation"
                navigate={~p"/manufacturer/inventory?tab=batches"}
                class="td-menu-item td-menu-item-rich"
                role="menuitem"
              >
                <span><.td_icon name="package" /></span>
                <span>
                  <strong>Prepare shipper aggregation</strong>
                  <span class="td-note">Choose a serialized batch and prepare it for packing.</span>
                </span>
              </.link>
              <.link
                id="start-pallet-aggregation"
                navigate={~p"/manufacturer/aggregations/pallets/new"}
                class="td-menu-item td-menu-item-rich"
                role="menuitem"
              >
                <span><.td_icon name="squares-plus" /></span>
                <span>
                  <strong>Build a pallet</strong>
                  <span class="td-note">Scan completed shipper SSCCs onto a pallet.</span>
                </span>
              </.link>
            </div>
          </div>
        </:actions>
      </.td_page_header>

      <nav id="aggregation-tabs" class="td-tabs" aria-label="Aggregation type">
        <.td_tab
          id="aggregation-shippers-tab"
          label="Shippers"
          count={length(@batches)}
          active={@tab == "shippers"}
          patch={~p"/manufacturer/aggregations?tab=shippers"}
        />
        <.td_tab
          id="aggregation-pallets-tab"
          label="Pallets"
          count={length(@pallets)}
          active={@tab == "pallets"}
          patch={~p"/manufacturer/aggregations?tab=pallets"}
        />
      </nav>

      <div :if={@tab == "shippers"} id="aggregation-shippers-panel" class="space-y-4 pt-4">
        <section id="aggregation-active-batches" class="td-card">
          <.td_card_header
            title="Shipper aggregation"
            subtitle="Batches ready for or in shipper packing."
          />

          <div :if={@batches == []} id="aggregation-batches-empty" class="td-empty-card">
            <%= if @packed_batch_count > 0 do %>
              <p class="td-empty-title">All shippers are packed</p>
              <p class="td-note">
                Packed shippers are ready to be grouped onto a pallet.
              </p>
              <.td_button
                id="build-pallet-from-shippers"
                variant="primary"
                label="Build a pallet"
                navigate={~p"/manufacturer/aggregations/pallets/new"}
              />
            <% else %>
              <p class="td-empty-title">No shipper batches yet</p>
              <p class="td-note">
                Batches prepared from Create shippers will appear here while they are ready for or in packing.
              </p>
              <.td_button
                id="view-aggregation-batches"
                variant="secondary"
                label="View batch inventory"
                navigate={~p"/manufacturer/inventory?tab=batches"}
              />
            <% end %>
          </div>

          <.td_data_table
            :if={@batches != []}
            id="aggregation-active-batches-table"
            rows={@batches}
            row_id={fn row -> "aggregation-batch-#{row.batch.id}" end}
          >
            <:col :let={row} label="Batch">{row.batch.batch_no}</:col>
            <:col :let={row} label="Product">{row.product.name}</:col>
            <:col :let={row} label="Status">
              <.td_badge tone={batch_tone(row)} label={batch_status(row)} />
            </:col>
            <:col :let={row} label="Action">
              <.td_button
                id={"prepare-shippers-#{row.batch.id}"}
                variant="primary"
                label={batch_action_label(row)}
                navigate={
                  ~p"/manufacturer/aggregations/batches/#{row.batch.id}/prepare?#{%{return_to: ~p"/manufacturer/aggregations?tab=shippers"}}"
                }
              />
            </:col>
          </.td_data_table>
        </section>
      </div>

      <div :if={@tab == "pallets"} id="aggregation-pallets-panel" class="pt-4">
        <section id="aggregation-pallets" class="td-card">
          <.td_card_header
            title="Pallet SSCCs"
            subtitle="Completed shippers grouped for a shared destination."
          />

          <div :if={@pallets == []} id="aggregation-pallets-empty" class="td-empty-card">
            <p class="td-empty-title">No pallets yet</p>
            <p class="td-note">
              Build a pallet by scanning completed shipper SSCCs that share a destination.
            </p>
            <.td_button
              id="create-pallet"
              variant="primary"
              label="Build a pallet"
              navigate={~p"/manufacturer/aggregations/pallets/new"}
            />
          </div>

          <div :if={@pallets != []} class="td-table">
            <table>
              <thead>
                <tr>
                  <th>Pallet SSCC</th>
                  <th>Route</th>
                  <th class="td-num">Shippers</th>
                  <th>Status</th>
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
                  <td><.td_badge tone="success" label="Built" /></td>
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

  defp batch_status(row) do
    case batch_progress(row) do
      :packed -> "Packed"
      :packing_in_progress -> "Packing in progress"
      :ready_to_pack -> "Ready to pack"
    end
  end

  defp batch_tone(row) do
    case batch_progress(row) do
      :packed -> "success"
      :packing_in_progress -> "warning"
      :ready_to_pack -> "info"
    end
  end

  defp batch_action_label(row) do
    case batch_progress(row) do
      :packed -> "View shippers"
      :packing_in_progress -> "Continue packing"
      :ready_to_pack -> "Create shippers"
    end
  end

  defp batch_progress(row) do
    cond do
      row.batch.status == "completed" -> :packed
      row.generated_count > 0 and row.packed_count >= row.generated_count -> :packed
      row.packed_count > 0 or row.batch.status == "aggregating" -> :packing_in_progress
      true -> :ready_to_pack
    end
  end
end
