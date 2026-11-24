defmodule ThamaniDawaWeb.ManufacturerSsccLive.Serials do
  @moduledoc """
  Shipper detail. Primary serials come from the GS1 member API
  (`get_sscc_contents`), not the local database. Print label opens the
  one shipper-label modal.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Product
  alias ThamaniDawa.Repo

  @per_page 8

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sscc =
      organization_id
      |> Manufacturing.get_sscc_group!(id)
      |> then(&Manufacturing.ensure_shipper_parties(organization_id, &1))

    product =
      if sscc.gtin, do: Repo.get_by(Product, organization_id: organization_id, gtin: sscc.gtin)

    batch_count =
      if sscc.gtin && sscc.batch do
        {shippers, _} = Manufacturing.list_batch_shippers(organization_id, sscc.gtin, sscc.batch)
        max(length(shippers), 1)
      else
        1
      end

    {:ok,
     socket
     |> assign(:page_title, "Shipper SSCC")
     |> assign(:sscc, sscc)
     |> assign(:product, product)
     |> assign(:batch_count, batch_count)
     |> assign(:serials, [])
     |> assign(:page, 1)
     |> assign(:per_page, @per_page)
     |> load_serials()}
  end

  def handle_params(params, _url, socket) do
    fallback =
      if gtin = socket.assigns.sscc.gtin,
        do: ~p"/manufacturer/products/#{gtin}/ssccs",
        else: ~p"/manufacturer/products"

    {:noreply, assign(socket, :back_path, ThamaniDawaWeb.ReturnTo.path(params, fallback))}
  end

  defp load_serials(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    code = socket.assigns.sscc.code

    assign_async(socket, :remote_serials, fn ->
      case Manufacturing.fetch_sscc_serials(organization_id, code) do
        {:ok, serials} -> {:ok, %{remote_serials: serials}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def handle_event("retry", _params, socket) do
    {:noreply, socket |> assign(:page, 1) |> load_serials()}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, assign(socket, :page, socket.assigns.page + 1)}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, assign(socket, :page, max(socket.assigns.page - 1, 1))}
  end

  defp page_slice(serials, page) do
    serials |> Enum.drop((page - 1) * @per_page) |> Enum.take(@per_page)
  end

  defp gtin14(serial), do: String.pad_leading(serial.gtin || "", 14, "0")

  defp dom_key(serial),
    do:
      "#{gtin14(serial)}-#{serial.batch}-#{serial.serial}"
      |> String.replace(~r/[^A-Za-z0-9_-]/, "_")

  defp error_message(:not_found), do: "GS1 has no record of this SSCC yet."

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings to load serials."

  defp error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key."

  defp error_message(_reason), do: "Couldn't reach GS1 to load serials. Try again shortly."

  defp long_date(nil), do: "—"
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp sgtin(serial), do: "(01)#{gtin14(serial)}(21)#{serial.serial}"

  def render(assigns) do
    serials = if assigns.remote_serials.ok?, do: assigns.remote_serials.result, else: []
    pages = max(ceil(length(serials) / @per_page), 1)
    page = min(assigns.page, pages)
    page_serials = page_slice(serials, page)
    from_index = if serials == [], do: 0, else: (page - 1) * @per_page + 1
    to_index = min(page * @per_page, length(serials))
    product_name = (assigns.product && assigns.product.name) || assigns.sscc.gtin
    close_to = ~p"/manufacturer/sscc/#{assigns.sscc.id}/serials?#{%{return_to: assigns.back_path}}"

    assigns =
      assigns
      |> assign(:serials, serials)
      |> assign(:page, page)
      |> assign(:pages, pages)
      |> assign(:page_serials, page_serials)
      |> assign(:from_index, from_index)
      |> assign(:to_index, to_index)
      |> assign(:product_name, product_name)
      |> assign(:close_to, close_to)

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Shipper SSCC"
      crumb_parent={@product_name}
    >
      <.td_back_link
        id="sscc-serials-back"
        to={@back_path}
        label={ThamaniDawaWeb.ReturnTo.label(@back_path, "Back to shipper SSCCs")}
      />
      <div class="td-idh">
        <div>
          <h1 class="td-idh-title font-mono">
            {@sscc.code}
            <.td_badge :if={@sscc.pallet} tone="success" label="On pallet" />
            <.td_badge :if={!@sscc.pallet} tone="success" label="Packed" />
          </h1>
          <p class="td-idh-sub">
            Shipper SSCC · {@product_name}<span :if={@sscc.batch}> · batch <span class="font-mono">{@sscc.batch}</span></span>
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button
            :if={@product && @sscc.batch && !@sscc.pallet}
            id="pack-another-shipper"
            label="Pack another shipper"
            navigate={~p"/manufacturer/products/#{@sscc.gtin}/serials/pack?#{%{batch: @sscc.batch, return_to: @back_path}}"}
          />
          <.td_button
            :if={@sscc.pallet}
            id="sscc-export"
            glyph="download-simple"
            label="Export CSV"
            href={~p"/manufacturer/sscc/#{@sscc.id}/export"}
          />
          <.td_button
            id="sscc-serials-print-label"
            variant="primary"
            glyph="printer"
            label="Print label"
            navigate={~p"/manufacturer/sscc/#{@sscc.id}/label?#{%{return_to: @back_path}}"}
          />
        </div>
      </div>

      <div class="td-pack">
        <div>
          <div class="td-card">
            <div class="td-kv-grid is-pad">
              <div class="td-kv"><span class="td-kv-label">SSCC</span><span class="td-kv-value is-mono">{@sscc.code}</span></div>
              <div class="td-kv"><span class="td-kv-label">Units</span><span class="td-kv-value">{@sscc.count_of_trade_items}</span></div>
              <div class="td-kv"><span class="td-kv-label">Batch</span><span class="td-kv-value is-mono">{@sscc.batch}</span></div>
              <div class="td-kv"><span class="td-kv-label">GTIN</span><span class="td-kv-value is-mono">{@sscc.gtin}</span></div>
              <div class="td-kv"><span class="td-kv-label">Destination</span><span class="td-kv-value">{@sscc.to_company_name || @sscc.to_gln}</span></div>
              <div class="td-kv"><span class="td-kv-label">Order</span><span class="td-kv-value">{@sscc.order_number}</span></div>
              <div class="td-kv"><span class="td-kv-label">Packed</span><span class="td-kv-value">{ThamaniDawaWeb.TimeFormat.datetime(@sscc.inserted_at)} EAT</span></div>
              <div class="td-kv">
                <span class="td-kv-label">Pallet</span>
                <span class="td-kv-value is-mono">{if @sscc.pallet, do: @sscc.pallet.code, else: "Not on a pallet"}</span>
              </div>
            </div>
          </div>

          <div class="td-card">
            <div class="td-pad">
              <h2 class="td-idh-title">Serials in this shipper</h2>
              <p class="td-note">{length(@serials)} units</p>
            </div>
            <div :if={@remote_serials.loading} id="sscc-serials-loading" class="td-note td-pad">
              Loading serials from GS1…
            </div>
            <div :if={@remote_serials.failed} id="sscc-serials-error" class="td-ban is-danger td-pad">
              <span>{error_message(elem(@remote_serials.failed, 1))}</span>
              <.td_button id="retry-sscc-serials" label="Retry" phx-click="retry" />
            </div>
            <p :if={@remote_serials.ok? and @serials == []} id="sscc-serials-empty" class="td-note td-pad">
              GS1 reports no serials packed under this SSCC.
            </p>
            <table :if={@remote_serials.ok? and @serials != []} id="sscc-serials" class="td-rows is-static">
              <thead>
                <tr><th>#</th><th>Serial (SGTIN)</th><th>Batch</th><th>Expires</th><th>State</th></tr>
              </thead>
              <tbody>
                <tr :for={{serial, index} <- Enum.with_index(@page_serials, @from_index)} id={"sscc-primary-#{dom_key(serial)}"}>
                  <td>{index}</td>
                  <td class="font-mono">{sgtin(serial)}</td>
                  <td class="font-mono">{serial.batch}</td>
                  <td>{long_date(serial.expiry_date)}</td>
                  <td><.td_badge tone="success" label="Packed" /></td>
                </tr>
              </tbody>
            </table>
            <div :if={@remote_serials.ok? and @serials != []} class="td-pad" style="display:flex;justify-content:space-between;align-items:center;">
              <span class="td-note">Showing {@from_index} to {@to_index} of {length(@serials)}</span>
              <div style="display:flex;gap:8px;">
                <.td_button id="sscc-page-prev" label="Previous" disabled={@page <= 1} phx-click="prev_page" />
                <.td_button id="sscc-page-next" label="Next" disabled={@page >= @pages} phx-click="next_page" />
              </div>
            </div>
          </div>
        </div>

        <aside class="td-pack-side">
          <div class="td-card td-pad">
            <h2 class="td-idh-title">Shipper label</h2>
            <p class="td-note">100 × 150 mm. Print it from the top right.</p>
            <p><strong>{@sscc.to_company_name}</strong></p>
            <p class="font-mono">{@sscc.code}</p>
            <p class="font-mono">{@sscc.gtin}</p>
            <p>{@sscc.batch} · {@sscc.count_of_trade_items} units</p>
          </div>
          <div :if={@sscc.pallet} class="td-card td-pad" id="sscc-on-pallet">
            <h2 class="td-idh-title">On pallet {@sscc.pallet.code}</h2>
            <p class="td-note">Packed with other shippers for {@sscc.to_company_name}.</p>
            <.td_button
              id="open-pallet"
              label="Open pallet"
              navigate={~p"/manufacturer/aggregations/pallets/#{@sscc.pallet.id}"}
            />
          </div>
          <div :if={!@sscc.pallet} class="td-card td-pad" id="sscc-next-pallet">
            <h2 class="td-idh-title">Next: build a pallet</h2>
            <p class="td-note">
              Scan this shipper and the others from {@sscc.batch} onto one pallet SSCC, then ship the pallet.
            </p>
            <.td_button
              id="build-pallet"
              label="Build a pallet"
              glyph="stack"
              navigate={~p"/manufacturer/aggregations/pallets/new?#{%{sscc: @sscc.id, return_to: ~p"/manufacturer/sscc/#{@sscc.id}/serials"}}"}
            />
            <.td_button
              :if={@product}
              id="view-batch-serials"
              label="View serials"
              navigate={~p"/manufacturer/products/#{@sscc.gtin}/serials?#{%{batch: @sscc.batch, view: "serials", return_to: @back_path}}"}
            />
          </div>
        </aside>
      </div>

      <ThamaniDawaWeb.ManufacturerSsccLive.Label.modal
        :if={@live_action == :label}
        sscc={@sscc}
        product_name={@product_name}
        batch_count={@batch_count}
        on_cancel={JS.navigate(@close_to)}
      />
    </Layouts.manufacturer_shell>
    """
  end
end
