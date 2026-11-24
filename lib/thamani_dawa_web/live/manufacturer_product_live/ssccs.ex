defmodule ThamaniDawaWeb.ManufacturerProductLive.Ssccs do
  @moduledoc """
  Shipper SSCCs for one product. Each row prints its own shipper label.
  Build a pallet stays a placeholder until that step is decided.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)
    rows = Manufacturing.list_sscc_groups(organization_id, product.id)

    {:ok,
     socket
     |> assign(:page_title, "Shipper SSCCs")
     |> assign(:product, product)
     |> assign(:rows, rows)
     |> assign(:batch, "")
     |> assign(:pallet, "")}
  end

  def handle_params(params, _url, socket) do
    batch = params["batch"] || ""

    fallback =
      if batch == "",
        do: ~p"/manufacturer/products",
        else: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{%{batch: batch}}"

    {:noreply,
     socket
     |> assign(:batch, batch)
     |> assign(:pallet, params["pallet"] || "")
     |> assign(:back_path, ThamaniDawaWeb.ReturnTo.path(params, fallback))}
  end

  def handle_event("filter", params, socket) do
    query =
      [batch: params["batch"], pallet: params["pallet"], return_to: socket.assigns.back_path]
      |> Enum.reject(fn {_k, value} -> value in [nil, ""] end)

    {:noreply,
     push_patch(socket,
       to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/ssccs?#{query}"
     )}
  end

  def handle_event("export_csv", _params, socket) do
    rows = visible(socket.assigns)
    header = "sscc,batch,units,packed_at,pallet,state\n"

    body =
      Enum.map_join(rows, "\n", fn %{sscc: sscc, serial_count: count} ->
        [
          sscc.code,
          sscc.batch,
          count,
          ThamaniDawaWeb.TimeFormat.datetime(sscc.inserted_at),
          (sscc.pallet && sscc.pallet.code) || "",
          if(sscc.pallet, do: "on_pallet", else: "packed")
        ]
        |> Enum.map(&csv_cell/1)
        |> Enum.join(",")
      end)

    {:noreply,
     push_event(socket, "td:csv", %{
       filename: "shippers-#{socket.assigns.product.gtin}.csv",
       content: header <> body <> "\n"
     })}
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(value), do: value |> to_string() |> String.replace(",", " ")

  defp visible(%{rows: rows, batch: batch, pallet: pallet}) do
    rows
    |> Enum.filter(fn %{sscc: sscc} -> batch in ["", nil] or sscc.batch == batch end)
    |> Enum.filter(fn %{sscc: sscc} ->
      case pallet do
        "" -> true
        "none" -> is_nil(sscc.pallet)
        "any" -> true
        code -> sscc.pallet && sscc.pallet.code == code
      end
    end)
  end

  def render(assigns) do
    rows = visible(assigns)
    on_pallet = Enum.count(rows, & &1.sscc.pallet)
    batches = assigns.rows |> Enum.map(& &1.sscc.batch) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    pallets =
      assigns.rows
      |> Enum.map(&(&1.sscc.pallet && &1.sscc.pallet.code))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    units = Enum.sum(Enum.map(rows, & &1.serial_count))

    assigns =
      assigns
      |> assign(:visible, rows)
      |> assign(:on_pallet, on_pallet)
      |> assign(:loose, length(rows) - on_pallet)
      |> assign(:batches, batches)
      |> assign(:pallets, pallets)
      |> assign(:units, units)

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Shipper SSCCs"
      crumb_parent={@product.name}
    >
      <.td_csv_download id="sscc-csv" />
      <.td_back_link
        id="ssccs-back"
        to={@back_path}
        label={if @batch == "", do: "Back to Products", else: "Back to batch #{@batch}"}
      />
      <div class="td-idh">
        <div>
          <h1 class="td-idh-title">Shipper SSCCs</h1>
          <p class="td-idh-sub">
            {@product.name} · GTIN <span class="font-mono">{@product.gtin}</span>
            · {length(@visible)} shippers · {@units} units
          </p>
        </div>
        <div class="td-idh-actions">
          <.td_button
            :if={@loose > 0}
            id="build-pallet"
            variant="primary"
            glyph="stack"
            label="Build a pallet"
            navigate={~p"/manufacturer/aggregations/pallets/new"}
          />
          <.td_button
            :if={@loose == 0}
            id="build-pallet"
            variant="primary"
            glyph="stack"
            label="Build a pallet"
            disabled
          />
        </div>
      </div>

      <div :if={@rows == []} id="manufacturer-sscc-empty-state" class="td-pad">
        <div class="td-card td-empty-card td-pad">
          <p class="td-empty-title">No shipper SSCCs yet</p>
          <p class="td-note">Shipper SSCCs are created when you pack serials into a shipper.</p>
          <.td_button
            id="pack-a-shipper"
            variant="primary"
            label="Pack a shipper"
            navigate={~p"/manufacturer/products/#{@product.gtin}/serials"}
          />
        </div>
      </div>

      <div :if={@rows != []}>
        <form id="sscc-filters" phx-change="filter" class="td-toolbar">
          <input type="hidden" name="return_to" value={@back_path} />
          <.td_select
            id="sscc-batch-filter"
            name="batch"
            label="Batch"
            value={@batch}
            prompt="Any batch"
            options={Enum.map(@batches, &{&1, &1})}
          />
          <.td_select
            id="sscc-pallet-filter"
            name="pallet"
            label="Pallet"
            value={@pallet}
            prompt="Any"
            options={[{"Not on a pallet", "none"} | Enum.map(@pallets, &{&1, &1})]}
          />
          <span class="td-toolbar-count">{@on_pallet} on a pallet · {@loose} not on a pallet</span>
          <.td_button
            id="export-ssccs"
            type="button"
            glyph="download-simple"
            label="Export CSV"
            phx-click="export_csv"
          />
        </form>

        <table class="td-rows" id="manufacturer-product-ssccs">
          <thead>
            <tr>
              <th>Shipper SSCC</th><th>Batch</th><th>Units</th><th>Packed (EAT)</th><th>
                Pallet SSCC
              </th><th>State</th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@visible == []} id="sscc-filter-empty">
              <td colspan="7">No shippers match these filters.</td>
            </tr>
            <tr :for={%{sscc: sscc, serial_count: count} <- @visible} id={"shipper-row-#{sscc.id}"}>
              <td class="font-mono">
                <.link navigate={
                  ~p"/manufacturer/sscc/#{sscc.id}/serials?#{%{return_to: ~p"/manufacturer/products/#{@product.gtin}/ssccs"}}"
                }>
                  {sscc.code}
                </.link>
              </td>
              <td class="font-mono">{sscc.batch}</td>
              <td>{count}</td>
              <td>{ThamaniDawaWeb.TimeFormat.short_datetime(sscc.inserted_at)}</td>
              <td class="font-mono">
                {if sscc.pallet, do: sscc.pallet.code, else: "Not on a pallet"}
              </td>
              <td>
                <.td_badge :if={sscc.pallet} tone="success" label="On pallet" />
                <.td_badge :if={!sscc.pallet} tone="neutral" label="Packed" />
              </td>
              <td>
                <.td_button
                  id={"print-label-#{sscc.id}"}
                  glyph="printer"
                  label="Print label"
                  navigate={~p"/manufacturer/sscc/#{sscc.id}/label"}
                />
              </td>
            </tr>
          </tbody>
        </table>
        <p class="td-note td-pad">
          Showing 1 to {length(@visible)} of {length(@visible)} shipper SSCCs
        </p>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
