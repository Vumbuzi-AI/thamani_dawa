defmodule ThamaniDawaWeb.ManufacturerProductLive.Pack do
  @moduledoc """
  Pack unpacked serials of one batch into a shipper SSCC.

  Three steps, matching the flagship frames: select serials, parties, review.
  Creating the shipper still goes through `Manufacturing.pack_serials_into_shipper/6`,
  which only creates the shipper and its Pack event. Shipments are created
  from packed SSCCs on the shipments page.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites

  @default_shipper_size 50
  @page_size 10

  def mount(%{"gtin" => gtin}, _session, socket) do
    product =
      Manufacturing.get_product_by_gtin!(socket.assigns.current_scope.organization_id, gtin)

    {:ok,
     socket
     |> assign(:page_title, "Pack a shipper")
     |> assign(:product, product)
     |> assign(:batch, nil)
     |> assign(:shipper_size, @default_shipper_size)
     |> assign(:pack_serials, nil)
     |> assign(:pack_selected, MapSet.new())
     |> assign(:pack_error, nil)
     |> assign(:packed_result, nil)
     |> assign(:load_error, nil)
     |> assign(:scan_query, "")
     |> assign(:scan_error, nil)
     |> assign(:page, 1)
     |> assign(:pack_facilities, [])
     |> assign(:pack_form, pack_form(%{}))
     |> assign(:pack_to_party, nil)
     |> assign(:to_gln_query, "")
     |> assign(:to_gln_results, [])
     |> assign(:to_gln_search_status, :idle)
     |> assign(:loaded_batch, nil)}
  end

  def handle_params(params, _url, socket) do
    step = if params["step"] in ~w(parties review), do: params["step"], else: "serials"
    fallback = ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials"

    socket =
      socket
      |> assign(:step, step)
      |> assign(:batch_no, params["batch"])
      |> assign(
        :shipper_size,
        shipper_size(org_id(socket), socket.assigns.product, params["batch"])
      )
      |> assign(:page, page_number(params["page"]))
      |> assign(:return_to, ThamaniDawaWeb.ReturnTo.safe(params["return_to"] || "", ""))
      |> assign(:back_path, ThamaniDawaWeb.ReturnTo.path(params, fallback))

    {:noreply, socket |> load_pack() |> enforce_step()}
  end

  def handle_event("to_parties", _params, socket) do
    if MapSet.size(socket.assigns.pack_selected) == 0 do
      {:noreply, socket}
    else
      {:noreply, patch_step(socket, "parties")}
    end
  end

  def handle_event("goto_step", %{"step" => step}, socket)
      when step in ~w(serials parties review) do
    cond do
      step == "serials" ->
        {:noreply, patch_step(socket, "serials")}

      step_locked?(step, socket.assigns) and step == "review" and
          MapSet.size(socket.assigns.pack_selected) > 0 ->
        {:noreply,
         socket
         |> assign(:pack_error, {:invalid, "Enter the 13-digit GLN the shipper is going to."})
         |> patch_step("parties")}

      step_locked?(step, socket.assigns) ->
        {:noreply, socket}

      true ->
        {:noreply, patch_step(socket, step)}
    end
  end

  def handle_event("to_serials", _params, socket), do: {:noreply, patch_step(socket, "serials")}

  def handle_event("to_review", _params, socket) do
    if valid_destination?(socket.assigns.pack_form.params["to_gln"]) do
      {:noreply, patch_step(socket, "review")}
    else
      {:noreply,
       assign(socket, :pack_error, {:invalid, "Enter the 13-digit GLN the shipper is going to."})}
    end
  end

  def handle_event("toggle_pack_serial", %{"serial" => serial}, socket) do
    selected = socket.assigns.pack_selected

    selected =
      if MapSet.member?(selected, serial),
        do: MapSet.delete(selected, serial),
        else: MapSet.put(selected, serial)

    {:noreply, assign(socket, :pack_selected, selected)}
  end

  def handle_event("select_set", %{"index" => index}, socket) do
    sets = Enum.chunk_every(socket.assigns.pack_serials || [], socket.assigns.shipper_size)

    case Integer.parse(index) do
      {n, ""} when n >= 1 and n <= length(sets) ->
        {:noreply, assign(socket, :pack_selected, MapSet.new(Enum.at(sets, n - 1)))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_first", _params, socket) do
    first = first_shipper(socket.assigns.pack_serials || [], socket.assigns.shipper_size)

    selected =
      if MapSet.equal?(socket.assigns.pack_selected, MapSet.new(first)),
        do: MapSet.new(),
        else: MapSet.new(first)

    {:noreply, assign(socket, :pack_selected, selected)}
  end

  def handle_event("scan_serial", %{"serial" => raw}, socket) do
    query = String.trim(raw)
    serials = socket.assigns.pack_serials || []

    case match_serial(query, serials) do
      nil when query == "" ->
        {:noreply, assign(socket, scan_query: "", scan_error: nil)}

      nil ->
        {:noreply,
         assign(socket,
           scan_query: query,
           scan_error: "That serial is not an unpacked unit in this batch."
         )}

      serial ->
        selected = socket.assigns.pack_selected

        selected =
          if MapSet.member?(selected, serial),
            do: MapSet.delete(selected, serial),
            else: MapSet.put(selected, serial)

        {:noreply, assign(socket, pack_selected: selected, scan_query: "", scan_error: nil)}
    end
  end

  def handle_event("pack_next", _params, socket) do
    %{packed_result: %{serials: packed}, pack_serials: all, shipper_size: size} = socket.assigns
    remaining = all -- packed

    {:noreply,
     socket
     |> assign(:pack_serials, remaining)
     |> assign(:pack_selected, MapSet.new(first_shipper(remaining, size)))
     |> assign(:packed_result, nil)
     |> assign(:pack_error, nil)
     |> assign(:page, 1)
     |> patch_step("serials")}
  end

  def handle_event("page_prev", _params, socket),
    do: {:noreply, assign(socket, :page, max(socket.assigns.page - 1, 1))}

  def handle_event("page_next", _params, socket),
    do: {:noreply, assign(socket, :page, socket.assigns.page + 1)}

  def handle_event("validate_pack", %{"pack" => params}, socket) do
    {:noreply,
     assign(socket, :pack_form, pack_form(Map.merge(socket.assigns.pack_form.params, params)))}
  end

  def handle_event("search_pack_to_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    form = pack_form(Map.put(socket.assigns.pack_form.params, "to_gln", ""))

    socket =
      socket
      |> assign(:pack_form, form)
      |> assign(:pack_to_party, nil)
      |> assign(:to_gln_query, query)
      |> assign(:to_gln_results, [])

    if String.length(query) < 2 do
      {:noreply, assign(socket, :to_gln_search_status, :idle)}
    else
      api_token = Organizations.gs1_api_key(org_id(socket))

      {:noreply,
       socket
       |> assign(:to_gln_search_status, :searching)
       |> start_async(:to_gln_search, fn ->
         result = GlnLookup.search_destination(api_token, query)
         {query, result}
       end)}
    end
  end

  def handle_event("close_pack_to_gln", _params, socket) do
    {:noreply, socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :idle)}
  end

  def handle_event("select_pack_to_gln", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.to_gln_results, &(&1.gln == gln)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That destination GLN is no longer available.")}

      party ->
        {:noreply,
         socket
         |> assign(:pack_form, pack_form(Map.put(socket.assigns.pack_form.params, "to_gln", gln)))
         |> assign(:pack_to_party, party)
         |> assign(:to_gln_query, "#{party.company} · #{party.gln}")
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)
         |> assign(:pack_error, nil)}
    end
  end

  def handle_event("submit_pack", %{"pack" => params}, socket) do
    params = Map.merge(socket.assigns.pack_form.params, params)
    %{product: product, batch: batch, pack_serials: all, pack_selected: selected} = socket.assigns
    serials = Enum.filter(all || [], &MapSet.member?(selected, &1))
    attrs = put_pack_parties(params, socket.assigns)

    case Manufacturing.pack_serials_into_shipper(
           org_id(socket),
           product,
           batch,
           serials,
           attrs,
           site_gln: current_site_gln(socket)
         ) do
      {:ok, shipper} ->
        {:noreply,
         assign(socket, :packed_result, %{
           shipper: shipper,
           serials: serials,
           remaining: length(all) - length(serials)
         })}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:pack_form, pack_form(params))
         |> assign(:step, "review")
         |> assign(:pack_error, reason)}
    end
  end

  def handle_async(:to_gln_search, {:ok, {query, {:ok, results}}}, socket) do
    if socket.assigns.to_gln_query == query do
      {:noreply,
       socket |> assign(:to_gln_results, results) |> assign(:to_gln_search_status, :complete)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:to_gln_search, _result, socket) do
    {:noreply,
     socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :unavailable)}
  end

  defp load_pack(%{assigns: %{batch_no: batch_no}} = socket) when batch_no in [nil, ""] do
    assign(socket, :load_error, {:invalid, "Choose a batch before packing a shipper."})
  end

  defp load_pack(%{assigns: %{loaded_batch: batch_no, batch_no: batch_no}} = socket), do: socket

  defp load_pack(socket) do
    if connected?(socket) do
      org = org_id(socket)
      gtin = socket.assigns.product.gtin
      batch_no = socket.assigns.batch_no

      with {:ok, batches} <- Manufacturing.fetch_product_batches(org, gtin),
           %{} = batch <- Enum.find(batches, &(&1.batch_no == batch_no)),
           {:ok, serials} <- Manufacturing.fetch_unpacked_serials(org, gtin, batch_no) do
        facilities = org |> Sites.list_sites() |> Enum.filter(&(&1.gln not in [nil, ""]))
        from_gln = current_site_gln(socket) || Enum.find_value(facilities, & &1.gln)
        shipper_size = shipper_size(org, socket.assigns.product, batch_no)

        socket
        |> assign(:batch, batch)
        |> assign(:shipper_size, shipper_size)
        |> assign(:pack_serials, serials)
        |> assign(:pack_selected, MapSet.new(first_shipper(serials, shipper_size)))
        |> assign(:pack_facilities, facilities)
        |> assign(:pack_form, pack_form(%{"from_gln" => from_gln || ""}))
        |> assign(:load_error, nil)
        |> assign(:loaded_batch, batch_no)
      else
        nil ->
          assign(socket,
            load_error: {:invalid, "That batch is not on this product."},
            pack_serials: []
          )

        {:error, reason} ->
          assign(socket, load_error: reason, pack_serials: [])
      end
    else
      socket
    end
  end

  defp patch_step(socket, step) do
    query =
      [batch: socket.assigns.batch_no, step: step, return_to: socket.assigns.return_to]
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    push_patch(socket,
      to: ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials/pack?#{query}"
    )
  end

  defp put_pack_parties(params, assigns) do
    from = Enum.find(assigns.pack_facilities, &(&1.gln == params["from_gln"]))

    to =
      with %{gln: gln} = party <- assigns.pack_to_party,
           ^gln <- params["to_gln"] do
        party
      else
        _ -> nil
      end

    Map.merge(params, %{
      "from_company_name" => from && from.name,
      "from_address" => from && from.address,
      "to_company_name" => to && to.company,
      "to_address" => to && to.address
    })
  end

  defp pack_form(params) do
    %{"from_gln" => "", "to_gln" => "", "order_number" => ""}
    |> Map.merge(params)
    |> to_form(as: :pack)
  end

  defp first_shipper(serials, size), do: Enum.take(serials, size)

  defp shipper_size(_org, _product, nil), do: @default_shipper_size

  defp shipper_size(org, product, batch_no) do
    case Manufacturing.get_batch_by_product_and_no(org, product.id, batch_no) do
      %{packs_per_shipper: size} when is_integer(size) and size > 0 -> size
      _ -> @default_shipper_size
    end
  end

  defp match_serial("", _serials), do: nil

  defp match_serial(query, serials) do
    Enum.find(serials, fn serial ->
      query == serial or String.contains?(query, "(21)#{serial}")
    end)
  end

  defp valid_destination?(gln), do: is_binary(gln) and Regex.match?(~r/^\d{13}$/, gln)

  defp page_number(nil), do: 1

  defp page_number(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n > 0 -> n
      _ -> 1
    end
  end

  defp current_site_gln(socket) do
    with id when not is_nil(id) <- socket.assigns.current_scope.current_site_id,
         %{gln: gln} when gln not in [nil, ""] <- Sites.get_site!(org_id(socket), id) do
      gln
    else
      _ -> nil
    end
  end

  defp org_id(socket), do: socket.assigns.current_scope.organization_id

  defp gtin14(product), do: String.pad_leading(product.gtin, 14, "0")
  defp sgtin(product, serial), do: "(01)#{gtin14(product)}(21)#{serial}"

  defp long_date(nil), do: "—"
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in organization settings to pack serials."

  defp error_message(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key."

  defp error_message({:invalid, _message}),
    do: "Check the selected serials and shipper details, then try again."

  defp error_message(_reason),
    do:
      "GS1 didn't create the shipper label, so nothing was packed. Your serials are still unpacked. Try again in a moment."

  defp step_locked?("serials", _assigns), do: false
  defp step_locked?("parties", assigns), do: MapSet.size(assigns.pack_selected) == 0

  defp step_locked?("review", assigns),
    do:
      MapSet.size(assigns.pack_selected) == 0 or
        not valid_destination?(assigns.pack_form.params["to_gln"])

  defp enforce_step(%{assigns: %{pack_serials: serials, step: step}} = socket)
       when is_list(serials) and step in ~w(parties review) do
    if step_locked?(step, socket.assigns) do
      fallback = if step_locked?("parties", socket.assigns), do: "serials", else: "parties"
      patch_step(socket, fallback)
    else
      socket
    end
  end

  defp enforce_step(socket), do: socket

  defp step_state(current, name, order) do
    current_at = Enum.find_index(order, &(&1 == current)) || 0
    name_at = Enum.find_index(order, &(&1 == name))

    cond do
      name == current -> "current"
      name_at < current_at -> "done"
      true -> "upcoming"
    end
  end

  def render(assigns) do
    serials = assigns.pack_serials || []
    selected = MapSet.size(assigns.pack_selected)
    pages = max(ceil(length(serials) / @page_size), 1)
    page = min(assigns.page, pages)
    window = Enum.slice(serials, (page - 1) * @page_size, @page_size)
    from_index = if serials == [], do: 0, else: (page - 1) * @page_size + 1
    to_index = min(page * @page_size, length(serials))
    chosen = Enum.filter(serials, &MapSet.member?(assigns.pack_selected, &1))
    preview = Enum.take(chosen, 8)
    first = first_shipper(serials, assigns.shipper_size)

    assigns =
      assigns
      |> assign(:serials, serials)
      |> assign(:sets, Enum.chunk_every(serials, assigns.shipper_size))
      |> assign(:selected_count, selected)
      |> assign(:window, window)
      |> assign(:from_index, from_index)
      |> assign(:to_index, to_index)
      |> assign(:page, page)
      |> assign(:pages, pages)
      |> assign(:chosen, chosen)
      |> assign(:preview, preview)
      |> assign(
        :first_on,
        serials != [] and MapSet.equal?(assigns.pack_selected, MapSet.new(first))
      )
      |> assign(:meter, min(round(selected / assigns.shipper_size * 100), 100))
      |> assign(
        :from_party,
        Enum.find(assigns.pack_facilities, &(&1.gln == assigns.pack_form[:from_gln].value))
      )

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/products"}
      crumb="Pack shipper"
      crumb_parent={@product.name}
    >
      <.td_back_link
        id="pack-back"
        to={@back_path}
        label={ThamaniDawaWeb.ReturnTo.label(@back_path, "Back to serials")}
      />
      <div class="td-idh">
        <div class="td-idh-text">
          <h1 class="td-idh-title">Pack a shipper</h1>
          <p class="td-idh-sub">
            {@product.name} · batch <span class="font-mono">{@batch_no}</span>
            · {@shipper_size} units per shipper
          </p>
        </div>
      </div>

      <div class="td-steps" id="pack-steps">
        <.td_step
          :for={
            {name, label, number} <- [
              {"serials", "Select serials", 1},
              {"parties", "Parties", 2},
              {"review", "Review", 3}
            ]
          }
          id={"pack-step-#{name}"}
          state={step_state(@step, name, ~w(serials parties review))}
          number={number}
          label={label}
          event="goto_step"
          value={name}
          disabled={step_locked?(name, assigns)}
        />
      </div>

      <p :if={is_nil(@pack_serials) and is_nil(@load_error)} id="pack-loading" class="td-note td-pad">
        Loading unpacked serials…
      </p>
      <div :if={@load_error} id="pack-load-error" class="td-ban is-danger">
        <span>{error_message(@load_error)}</span>
      </div>

      <div :if={@pack_serials == []} id="pack-serials-empty" class="td-pad">
        <p class="td-empty-title">Every serial in this batch is already packed</p>
        <p class="td-note">There is nothing left to put in a shipper.</p>
      </div>

      <div :if={@packed_result} id="pack-result" class="td-card td-pad">
        <h2 class="td-idh-title">Shipper SSCC created</h2>
        <p class="td-note">
          SSCC <span class="font-mono">{@packed_result.shipper.code}</span>
          now holds {length(@packed_result.serials)} serials.
        </p>
        <p :if={@packed_result.remaining > 0} id="pack-result-remaining" class="td-note">
          {@packed_result.remaining} serials in this batch are still unpacked.
        </p>
        <div class="td-pack-foot">
          <.td_button id="pack-result-done" label="Back to batches" navigate={@back_path} />
          <div style="display:flex;gap:8px;">
            <.td_button
              id="pack-result-view"
              label="View shipper"
              navigate={
                ~p"/manufacturer/sscc/#{@packed_result.shipper.id}/serials?#{%{return_to: @back_path}}"
              }
            />
            <.td_button
              :if={@packed_result.remaining > 0}
              id="pack-next-shipper"
              variant="primary"
              label={"Pack next shipper (#{min(@packed_result.remaining, @shipper_size)} units)"}
              phx-click="pack_next"
            />
          </div>
        </div>
      </div>

      <div
        :if={is_nil(@packed_result) and is_list(@pack_serials) and @pack_serials != []}
        id="pack-serials-panel"
      >
        <div :if={@step == "serials"} class="td-pack">
          <div class="td-card">
            <form id="pack-scan-form" phx-change="scan_serial" class="td-pad">
              <label class="td-field" for="pack-scan">
                <span class="td-field-label">Scan or type a serial</span>
                <input
                  id="pack-scan"
                  name="serial"
                  type="text"
                  value={@scan_query}
                  phx-debounce="300"
                  phx-hook="ScanField"
                  autocomplete="off"
                  placeholder="Scan a unit to add or remove it from this shipper"
                  class="td-field-control"
                />
              </label>
            </form>
            <p :if={@scan_error} id="pack-scan-error" class="td-ban is-danger td-pad">
              {@scan_error}
            </p>
            <div class="td-pad" style="display:flex;justify-content:space-between;gap:12px;">
              <button id="pack-select-first" type="button" class="td-check" phx-click="select_first">
                <input type="checkbox" checked={@first_on} tabindex="-1" style="pointer-events:none" />
                <span>Select first {@shipper_size} unpacked</span>
              </button>
              <span id="pack-selected-count" class="td-note">
                {@selected_count} selected · {length(@serials) - @selected_count} unpacked left
              </span>
            </div>
            <div
              :if={length(@sets) > 1}
              id="pack-sets"
              class="td-pad"
              style="display:flex;flex-wrap:wrap;align-items:center;gap:8px;"
            >
              <span class="td-note">Shippers in this batch</span>
              <.td_button
                :for={{set, index} <- Enum.with_index(@sets, 1)}
                id={"pack-set-#{index}"}
                label={"Shipper #{index} · #{length(set)} units"}
                variant={
                  if MapSet.equal?(@pack_selected, MapSet.new(set)), do: "primary", else: "secondary"
                }
                phx-click="select_set"
                phx-value-index={index}
              />
            </div>
            <table class="td-rows is-static">
              <thead>
                <tr>
                  <th></th><th>Serial (SGTIN)</th><th>Batch</th><th>Expires</th><th>State</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={serial <- @window}>
                  <td>
                    <button
                      id={"pack-serial-#{serial}"}
                      type="button"
                      phx-click="toggle_pack_serial"
                      phx-value-serial={serial}
                      aria-pressed={to_string(MapSet.member?(@pack_selected, serial))}
                    >
                      {if MapSet.member?(@pack_selected, serial), do: "✓", else: ""}
                    </button>
                  </td>
                  <td class="font-mono">{sgtin(@product, serial)}</td>
                  <td class="font-mono">{@batch.batch_no}</td>
                  <td>{long_date(@batch.expiry_date)}</td>
                  <td><.td_badge tone="neutral" label="Unpacked" /></td>
                </tr>
              </tbody>
            </table>
            <p class="td-note td-pad">
              Showing {@from_index} to {@to_index} of {length(@serials)} unpacked serials
            </p>
            <div class="td-pad" style="display:flex;justify-content:flex-end;gap:8px;">
              <.td_button
                id="pack-page-prev"
                label="Previous"
                disabled={@page <= 1}
                phx-click="page_prev"
              />
              <.td_button
                id="pack-page-next"
                label="Next"
                disabled={@page >= @pages}
                phx-click="page_next"
              />
            </div>
          </div>
          <aside class="td-card td-pad td-pack-side">
            <h2 class="td-idh-title">This shipper</h2>
            <p class="td-note">One shipper SSCC holds the serials you select.</p>
            <div class="td-kv">
              <span class="td-kv-label">Batch</span><span class="td-kv-value is-mono">{@batch.batch_no}</span>
            </div>
            <div class="td-kv">
              <span class="td-kv-label">Units per shipper</span><span class="td-kv-value">{@shipper_size}</span>
            </div>
            <div class="td-kv">
              <span class="td-kv-label">Selected</span>
              <span id="pack-selected-summary" class="td-kv-value">{@selected_count} of {@shipper_size}</span>
            </div>
            <div class="td-kv">
              <span class="td-kv-label">Unpacked in batch</span><span class="td-kv-value">{length(
                @serials
              )}</span>
            </div>
            <div class="td-meter" aria-hidden="true"><span style={"width: #{@meter}%"}></span></div>
          </aside>
        </div>

        <div :if={@step == "parties"} class="td-pack is-single">
          <div class="td-card td-pad">
            <.form for={@pack_form} id="pack-parties-form" phx-change="validate_pack">
              <h2 class="td-idh-title">From</h2>
              <.td_select
                field={@pack_form[:from_gln]}
                id="pack_from_gln"
                label="Packing site"
                options={Enum.map(@pack_facilities, &{"#{&1.name} · #{&1.gln}", &1.gln})}
              />
              <div :if={@from_party} class="td-kv-grid is-pad">
                <div class="td-kv">
                  <span class="td-kv-label">Company</span><span class="td-kv-value">{@from_party.name}</span>
                </div>
                <div class="td-kv">
                  <span class="td-kv-label">Address</span><span class="td-kv-value">{@from_party.address}</span>
                </div>
              </div>
              <h2 class="td-idh-title">To</h2>
              <div class="td-field w-full">
                <label class="td-field-label" for="pack_to_gln_search">Destination GLN</label>
                <input type="hidden" name="pack[to_gln]" value={@pack_form[:to_gln].value} />
                <div id="pack-to-gln-combobox" class="relative w-full">
                  <input
                    id="pack_to_gln_search"
                    type="search"
                    value={@to_gln_query}
                    phx-keyup="search_pack_to_gln"
                    phx-debounce="300"
                    autocomplete="off"
                    placeholder="Search by GLN, company, or address"
                    class="td-field-control w-full"
                  />
                  <.td_gln_results
                    id="pack-to-gln-results"
                    results={@to_gln_results}
                    status={@to_gln_search_status}
                    query={@to_gln_query}
                    select_event="select_pack_to_gln"
                    close_event="close_pack_to_gln"
                    option_prefix="pack-to-gln"
                  />
                </div>
              </div>
              <div :if={@pack_to_party} id="pack-to-party" class="td-kv-grid is-pad">
                <div class="td-kv">
                  <span class="td-kv-label">Company</span><span class="td-kv-value">{@pack_to_party.company}</span>
                </div>
                <div class="td-kv">
                  <span class="td-kv-label">Address</span><span class="td-kv-value">{@pack_to_party.address}</span>
                </div>
              </div>
              <div class="mt-4">
                <.td_input field={@pack_form[:order_number]} label="Order number (optional)" />
              </div>
              <p class="td-note">
                Printed on the shipper label. You can ship to a different order later.
              </p>
            </.form>
            <p :if={@pack_error && @step == "parties"} class="td-ban is-danger">
              {error_message(@pack_error)}
            </p>
          </div>
        </div>

        <div :if={@step == "review"} class="td-pack">
          <.form
            for={@pack_form}
            id="pack-serials-form"
            phx-submit="submit_pack"
            class="td-card td-pad"
          >
            <input type="hidden" name="pack[from_gln]" value={@pack_form[:from_gln].value} />
            <input type="hidden" name="pack[to_gln]" value={@pack_form[:to_gln].value} />
            <input type="hidden" name="pack[order_number]" value={@pack_form[:order_number].value} />
            <p :if={is_nil(@pack_error)} id="pack-review-note" class="td-ban">
              Creating the shipper asks GS1 for a new SSCC and records an EPCIS Pack event for these {@selected_count} serials.
            </p>
            <p
              :if={match?({:invalid, _}, @pack_error)}
              id="pack-review-invalid"
              class="td-ban is-danger"
            >
              {error_message(@pack_error)}
            </p>
            <p
              :if={@pack_error && !match?({:invalid, _}, @pack_error)}
              id="pack-gs1-error"
              class="td-ban is-danger"
            >
              GS1 didn't create the shipper label, so nothing was packed. Your {@selected_count} serials are still unpacked. Try again in a moment.
            </p>
            <h2 class="td-idh-title">Shipper</h2>
            <div class="td-kv-grid">
              <div class="td-kv">
                <span class="td-kv-label">Product</span><span class="td-kv-value">{@product.name}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">GTIN</span><span class="td-kv-value is-mono">{@product.gtin}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Batch</span><span class="td-kv-value is-mono">{@batch.batch_no}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Units</span><span class="td-kv-value">{@selected_count}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Expires</span><span class="td-kv-value">{long_date(
                  @batch.expiry_date
                )}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Order</span><span class="td-kv-value">{@pack_form[
                  :order_number
                ].value}</span>
              </div>
            </div>
            <div class="td-kv-grid">
              <div id="pack-review-from" class="td-choice">
                <span class="td-kv-label">From</span>
                <strong>{@from_party && @from_party.name}</strong>
                <span class="td-note font-mono">{@from_party && @from_party.gln}</span>
                <span class="td-note">{@from_party && @from_party.address}</span>
              </div>
              <div id="pack-review-to" class="td-choice">
                <span class="td-kv-label">To</span>
                <strong>{@pack_to_party && @pack_to_party.company}</strong>
                <span class="td-note font-mono">{@pack_form[:to_gln].value}</span>
                <span class="td-note">{@pack_to_party && @pack_to_party.address}</span>
              </div>
            </div>
          </.form>
          <aside class="td-card td-pad">
            <h2 class="td-idh-title">Serials</h2>
            <p class="td-note">{@selected_count} selected, all unpacked</p>
            <p :for={serial <- @preview} class="font-mono">{sgtin(@product, serial)}</p>
            <p :if={length(@chosen) > length(@preview)} class="td-note">
              Showing {length(@preview)} of {length(@chosen)}
            </p>
          </aside>
        </div>

        <div class="td-pack-foot">
          <span id="pack-foot-count">
            {if @step == "parties" && @pack_to_party,
              do: "Shipper for #{@pack_to_party.company}",
              else: "#{@selected_count} serials selected for 1 shipper SSCC"}
          </span>
          <div style="display:flex;gap:8px;">
            <.td_button
              :if={@step == "serials"}
              id="pack-cancel"
              label="Cancel"
              navigate={@back_path}
            />
            <.td_button
              :if={@step != "serials"}
              id="pack-back-step"
              label="Back"
              phx-click={if @step == "review", do: "to_parties", else: "to_serials"}
            />
            <.td_button
              :if={@step == "serials"}
              id="pack-next"
              variant="primary"
              label="Next"
              disabled={@selected_count == 0}
              phx-click="to_parties"
            />
            <.td_button
              :if={@step == "parties"}
              id="pack-next"
              variant="primary"
              label="Next"
              phx-click="to_review"
            />
            <.td_button
              :if={@step == "review"}
              id="submit-pack-serials"
              type="submit"
              form="pack-serials-form"
              variant="primary"
              label={if @pack_error, do: "Try again", else: "Create shipper SSCC"}
              phx-disable-with="Creating shipper SSCC…"
            />
          </div>
        </div>
      </div>
    </Layouts.manufacturer_shell>
    """
  end
end
