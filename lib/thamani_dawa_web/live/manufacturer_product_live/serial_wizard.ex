defmodule ThamaniDawaWeb.ManufacturerProductLive.SerialWizard do
  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:mode, fn -> nil end)
     |> assign_new(:step, fn -> 1 end)
     |> assign_new(:submitting, fn -> false end)
     |> assign_new(:issued, fn -> nil end)
     |> assign_new(:to_gln_query, fn -> "" end)
     |> assign_new(:to_gln_results, fn -> [] end)
     |> assign_new(:to_gln_search_status, fn -> :idle end)
     |> assign_new(:form_params, fn -> default_params(assigns.site) end)
     |> assign_new(:form, fn -> to_form(default_params(assigns.site), as: :serial_generation) end)}
  end

  defp default_params(site) do
    %{
      "batch_no" => "",
      "production_date" => "",
      "expiry_date" => "",
      "primary_quantity" => "",
      "shipper_quantity" => "",
      "from_gln" => site.gln || "",
      "from_company_name" => site.name || "",
      "from_address" => site.address || "",
      "to_gln" => "",
      "to_company_name" => "",
      "to_address" => "",
      "order_number" => ""
    }
  end

  def handle_event("choose_mode", %{"mode" => mode}, socket) when mode in ["order", "stock"] do
    {:noreply, socket |> assign(:mode, mode) |> assign(:step, 2)}
  end

  def handle_event("next_step", _params, socket) do
    {:noreply, assign(socket, :step, 3)}
  end

  def handle_event("issued_next", %{"to" => to}, socket) do
    issued = socket.assigns.issued

    message =
      case to do
        "inventory" -> {:serials_issued, :inventory, issued.count}
        "aggregations" -> {:serials_issued, :aggregations, issued.count, issued.shippers}
        "shipment" -> {:serials_issued, :shipment, issued.count, issued.shippers}
        _ -> {:serials_issued, :products, issued.count}
      end

    send(self(), message)
    {:noreply, socket}
  end

  def handle_event("prev_step", _params, socket) do
    case socket.assigns.step do
      3 -> {:noreply, assign(socket, :step, 2)}
      2 -> {:noreply, socket |> assign(:step, 1) |> assign(:mode, nil)}
      step -> {:noreply, assign(socket, :step, step)}
    end
  end

  def handle_event("validate", %{"serial_generation" => params}, socket) do
    params = sync_from_facility(params, socket.assigns.facilities)
    errors = validation_errors(params, socket.assigns.mode)

    socket =
      socket
      |> assign(:form_params, params)
      |> assign(:form, generation_form(params, errors))

    {:noreply, socket}
  end

  def handle_event("save", %{"serial_generation" => params}, socket) do
    params = sync_from_facility(params, socket.assigns.facilities)

    case resolve_to_party(params, socket.assigns.mode, gs1_api_key(socket)) do
      {:ok, params} ->
        errors = validation_errors(params, socket.assigns.mode)

        if errors == [] do
          generate(socket, socket.assigns.mode, params)
        else
          {:noreply, assign_form(socket, params, errors)}
        end

      {:error, params} ->
        errors = [{:to_gln, {"could not be verified", []}} | validation_errors(params, "order")]
        {:noreply, assign_form(socket, params, errors)}
    end
  end

  def handle_event("search_to_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    params = clear_to_party(socket.assigns.form_params)

    if String.length(query) < 2 do
      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :idle)
       |> assign_form(params, validation_errors(params, socket.assigns.mode))}
    else
      api_token = gs1_api_key(socket)

      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :searching)
       |> assign_form(params, validation_errors(params, socket.assigns.mode))
       |> start_async(:to_gln_search, fn ->
         {query, GlnLookup.search_destination(api_token, query)}
       end)}
    end
  end

  def handle_event("select_to_gln", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.to_gln_results, &(&1.gln == gln)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That destination GLN is no longer available.")}

      party ->
        params = socket.assigns.form_params |> put_to_party(party) |> Map.put("to_gln", party.gln)

        {:noreply,
         socket
         |> assign(:to_gln_query, destination_label(party))
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)
         |> assign_form(params, validation_errors(params, socket.assigns.mode))}
    end
  end

  def handle_async(:to_gln_search, {:ok, {query, {:ok, results}}}, socket) do
    if socket.assigns.to_gln_query == query do
      {:noreply,
       socket
       |> assign(:to_gln_results, results)
       |> assign(:to_gln_search_status, :complete)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:to_gln_search, _result, socket),
    do:
      {:noreply,
       socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :unavailable)}

  defp resolve_to_party(params, "order", api_token) do
    case GlnLookup.resolve_destination(api_token, params["to_gln"]) do
      {:ok, party} -> {:ok, put_to_party(params, party)}
      {:error, _reason} -> {:error, params}
    end
  end

  defp resolve_to_party(params, _mode, _api_token), do: {:ok, params}

  defp put_to_party(params, party) do
    params
    |> Map.put("to_company_name", party.company || "")
    |> Map.put("to_address", party.address || "")
  end

  defp assign_form(socket, params, errors) do
    socket
    |> assign(:form_params, params)
    |> assign(:form, generation_form(params, errors))
  end

  defp generate(socket, "stock", params) do
    quantity = String.to_integer(params["primary_quantity"])
    batch_attrs = Map.take(params, ["batch_no", "production_date", "expiry_date"])

    case Manufacturing.generate_primary_serials(
           socket.assigns.organization_id,
           socket.assigns.product,
           batch_attrs,
           quantity,
           socket.assigns.site.gln
         ) do
      {:ok, %{serials: serials}} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> put_flash(
           :info,
           "#{length(serials)} primary serial#{if length(serials) == 1, do: "", else: "s"} generated."
         )
         |> push_navigate(
           to:
             ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{%{batch: params["batch_no"]}}"
         )}

      {:error, reason} ->
        send(self(), {:serial_generation_failed, reason})
        {:noreply, assign(socket, :submitting, false)}
    end
  end

  defp generate(socket, "order", params) do
    primary_quantity = String.to_integer(params["primary_quantity"])
    shipper_quantity = String.to_integer(params["shipper_quantity"])
    batch_attrs = Map.take(params, ["batch_no", "production_date", "expiry_date"])
    parties = Map.take(params, party_fields())

    case Manufacturing.generate_order_serials(
           socket.assigns.organization_id,
           socket.assigns.product,
           batch_attrs,
           primary_quantity,
           shipper_quantity,
           socket.assigns.site.gln,
           parties
         ) do
      {:ok, %{serials: serials, shippers: shippers}} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> put_flash(
           :info,
           "#{length(serials)} primary serial#{if length(serials) == 1, do: "", else: "s"} and #{length(shippers)} shipper SSCC#{if length(shippers) == 1, do: "", else: "s"} generated."
         )
         |> push_navigate(
           to:
             ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?#{%{batch: params["batch_no"]}}"
         )}

      {:error, reason} ->
        send(self(), {:serial_generation_failed, reason})
        {:noreply, assign(socket, :submitting, false)}
    end
  end

  defp party_fields,
    do: ~w(from_gln from_company_name from_address to_gln to_company_name to_address order_number)

  defp sync_from_facility(params, facilities) do
    case Enum.find(facilities, &(&1.gln == params["from_gln"])) do
      nil ->
        params

      facility ->
        params
        |> Map.put("from_company_name", facility.name || "")
        |> Map.put("from_address", facility.address || "")
    end
  end

  defp facility_options(facilities) do
    Enum.map(facilities, fn facility ->
      {"#{facility.name} · #{facility.gln}", facility.gln}
    end)
  end

  defp clear_to_party(params),
    do:
      params
      |> Map.put("to_gln", "")
      |> Map.put("to_company_name", "")
      |> Map.put("to_address", "")

  defp destination_label(party), do: "#{party.gln} · #{party.company}"

  defp gs1_api_key(socket), do: Organizations.gs1_api_key(socket.assigns.organization_id)

  defp generation_form(params, errors) do
    to_form(params, as: :serial_generation, errors: errors)
  end

  defp validation_errors(params, mode) do
    []
    |> required_error(params, :batch_no, "Batch number")
    |> required_error(params, :production_date, "Production date")
    |> required_error(params, :expiry_date, "Expiry date")
    |> quantity_error(params, :primary_quantity, "Primary quantity")
    |> date_order_error(params)
    |> mode_errors(params, mode)
  end

  defp mode_errors(errors, params, "order") do
    errors
    |> quantity_error(params, :shipper_quantity, "Shipper quantity")
    |> shipper_not_over_primary_error(params)
    |> shipper_divides_primary_error(params)
    |> required_error(params, :from_gln, "From GLN")
    |> required_error(params, :from_company_name, "From company name")
    |> required_error(params, :from_address, "From address")
    |> required_error(params, :to_gln, "To GLN")
    |> required_error(params, :to_company_name, "To company name")
    |> required_error(params, :to_address, "To address")
    |> required_error(params, :order_number, "Order number")
  end

  defp mode_errors(errors, _params, _mode), do: errors

  defp required_error(errors, params, field, label) do
    if Map.get(params, Atom.to_string(field)) in [nil, ""],
      do: [{field, {"#{label} is required", []}} | errors],
      else: errors
  end

  defp quantity_error(errors, params, field, label, max \\ nil) do
    case Integer.parse(Map.get(params, Atom.to_string(field), "")) do
      {quantity, ""} when quantity > 0 ->
        if is_integer(max) and quantity > max,
          do: [{field, {"#{label} cannot exceed #{max}", []}} | errors],
          else: errors

      _other ->
        [{field, {"#{label} must be a positive integer", []}} | errors]
    end
  end

  defp shipper_not_over_primary_error(errors, params) do
    with {primary, ""} <- Integer.parse(Map.get(params, "primary_quantity", "")),
         {shipper, ""} <- Integer.parse(Map.get(params, "shipper_quantity", "")),
         true <- shipper > primary do
      [{:shipper_quantity, {"cannot exceed the primary quantity", []}} | errors]
    else
      _other -> errors
    end
  end

  defp shipper_divides_primary_error(errors, params) do
    with {primary, ""} <- Integer.parse(Map.get(params, "primary_quantity", "")),
         {shipper, ""} <- Integer.parse(Map.get(params, "shipper_quantity", "")),
         false <- rem(primary, shipper) == 0 do
      [{:shipper_quantity, {"must divide the primary quantity evenly", []}} | errors]
    else
      _other -> errors
    end
  end

  defp date_order_error(errors, params) do
    with {:ok, production} <- Date.from_iso8601(Map.get(params, "production_date", "")),
         {:ok, expiry} <- Date.from_iso8601(Map.get(params, "expiry_date", "")),
         false <- Date.after?(expiry, production) do
      [{:expiry_date, {"must be after the production date", []}} | errors]
    else
      _other -> errors
    end
  end

  defp step_label(1), do: "Mode"
  defp step_label(2), do: "Batch & quantity"
  defp step_label(3), do: "From / To"

  defp total_steps("order"), do: 3
  defp total_steps(_mode), do: 2

  def render(assigns) do
    ~H"""
    <div id="manufacturer-serial-wizard">
      <%= if @issued do %>
        <div id="serials-issued">
          <p :if={@issued.kind == "stock"} class="td-note">
            {@issued.batch} now holds {@issued.count} DataMatrix codes for {@product.name}. They sit in inventory until you pack them into shippers.
          </p>
          <p :if={@issued.kind == "order"} class="td-note">
            {@issued.batch} packed {@issued.count} units into {@issued.shippers} shippers for {@issued.destination}. A mobile user can find this work by the order number on the shipment.
          </p>
          <div class="td-header-actions">
            <%= if @issued.kind == "stock" do %>
              <.td_button
                id="serials-issued-back"
                variant="secondary"
                label="Back to product"
                phx-click="issued_next"
                phx-value-to="products"
                phx-target={@myself}
              />
              <.td_button
                id="serials-issued-inventory"
                variant="primary"
                label="Open inventory"
                phx-click="issued_next"
                phx-value-to="inventory"
                phx-target={@myself}
              />
            <% else %>
              <.td_button
                id="serials-issued-aggregation"
                variant="secondary"
                label="Open aggregation"
                phx-click="issued_next"
                phx-value-to="aggregations"
                phx-target={@myself}
              />
              <.td_button
                id="serials-issued-shipment"
                variant="primary"
                label="New shipment"
                phx-click="issued_next"
                phx-value-to="shipment"
                phx-target={@myself}
              />
            <% end %>
          </div>
        </div>
      <% else %>
        <div class="td-steps" aria-label="Serial generation progress">
          <.td_step
            :for={n <- 1..total_steps(@mode)}
            number={n}
            label={step_label(n)}
            state={if @step > n, do: "done", else: if(@step == n, do: "current", else: "upcoming")}
          />
        </div>

        <%= if @step == 1 do %>
          <div id="serial-wizard-product" class="td-kv-grid">
            <.td_key_value label="Selected product" value={@product.name} />
            <.td_key_value label="GTIN" value={@product.gtin} mono />
          </div>
          <.td_mode_picker title="How should these serials be issued?">
            <.td_option_card
              id="serial-wizard-mode-order"
              title="Make to order"
              body="Create the shipper SSCCs now, with a From/To party for the labels."
              phx-click="choose_mode"
              phx-value-mode="order"
              phx-target={@myself}
            />
            <.td_option_card
              id="serial-wizard-mode-stock"
              title="Make to stock"
              body="Store as groups of batches. No SSCC is created yet."
              phx-click="choose_mode"
              phx-value-mode="stock"
              phx-target={@myself}
            />
          </.td_mode_picker>
        <% else %>
          <.form
            for={@form}
            id="manufacturer-serial-generation-form"
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
            class="td-auth-form"
          >
            <%= if @step == 2 do %>
              <.td_input field={@form[:batch_no]} label="Batch #" required />
              <.td_input
                field={@form[:primary_quantity]}
                type="number"
                min="1"
                label="Primary quantity"
                required
              />
              <.date_picker field={@form[:production_date]} label="Production date" required />
              <.date_picker field={@form[:expiry_date]} label="Expiry date" required />
              <.td_input
                :if={@mode == "order"}
                field={@form[:shipper_quantity]}
                type="number"
                min="1"
                label="Units per shipper SSCC"
                required
              />
              <p :if={@mode == "order"} class="td-note">
                The primary quantity must divide evenly by this number.
              </p>
              <div class="td-header-actions">
                <.td_button
                  id="serial-wizard-prev"
                  type="button"
                  variant="secondary"
                  label="Prev"
                  phx-click="prev_step"
                  phx-target={@myself}
                />
                <%= if @mode == "order" do %>
                  <.td_button
                    id="serial-wizard-next"
                    type="button"
                    variant="primary"
                    label="Next"
                    phx-click="next_step"
                    phx-target={@myself}
                  />
                <% else %>
                  <.td_button
                    id="serial-wizard-submit"
                    type="submit"
                    variant="primary"
                    label="Generate serials"
                    phx-disable-with="Generating…"
                  />
                <% end %>
              </div>
            <% else %>
              <input type="hidden" name="serial_generation[batch_no]" value={@form[:batch_no].value} />
              <input
                type="hidden"
                name="serial_generation[production_date]"
                value={@form[:production_date].value}
              />
              <input
                type="hidden"
                name="serial_generation[expiry_date]"
                value={@form[:expiry_date].value}
              />
              <input
                type="hidden"
                name="serial_generation[primary_quantity]"
                value={@form[:primary_quantity].value}
              />
              <input
                type="hidden"
                name="serial_generation[shipper_quantity]"
                value={@form[:shipper_quantity].value}
              />
              <div>
                <p class="td-note">From</p>
                <.input
                  field={@form[:from_gln]}
                  type="combobox"
                  label="From facility"
                  options={facility_options(@facilities)}
                  placeholder="Search your facilities"
                  required
                />
                <.td_input field={@form[:from_company_name]} label="From company name" required />
                <.td_input field={@form[:from_address]} label="From address" required />
              </div>
              <div>
                <p class="td-note">To</p>
                <label for="serial_generation_to_gln_search" class="thamani-label">
                  To GLN<span
                    aria-hidden="true"
                    style="color: var(--color-td-danger); margin-left: 2px;"
                  >*</span>
                </label>
                <input type="hidden" name="serial_generation[to_gln]" value={@form[:to_gln].value} />
                <div id="serial-generation-to-gln-combobox" class="relative">
                  <input
                    id="serial_generation_to_gln_search"
                    type="search"
                    value={@to_gln_query}
                    phx-keyup="search_to_gln"
                    phx-debounce="300"
                    phx-target={@myself}
                    autocomplete="off"
                    placeholder="Search by GLN, company, or address"
                    class="thamani-input w-full"
                  />
                  <div
                    :if={@to_gln_results != []}
                    id="serial-generation-to-gln-results"
                    role="listbox"
                    class="td-select-pop max-h-56 overflow-y-auto py-1"
                  >
                    <button
                      :for={party <- @to_gln_results}
                      id={"serial-generation-to-gln-#{party.gln}"}
                      type="button"
                      role="option"
                      phx-click="select_to_gln"
                      phx-value-gln={party.gln}
                      phx-target={@myself}
                      class="block w-full px-3 py-2 text-left text-sm transition hover:bg-[var(--color-td-hover)]"
                    >
                      <span class="block font-mono font-medium text-[var(--color-td-ink)]">{party.gln}</span>
                      <span class="block text-xs text-[var(--color-td-ink-3)]">{party.company} · {party.address ||
                        "—"}</span>
                    </button>
                  </div>
                </div>
                <p
                  :if={String.length(@to_gln_query) == 1}
                  id="serial-generation-to-gln-search-hint"
                  class="td-note"
                >
                  Type at least 2 characters to search the GS1 GLN directory.
                </p>
                <p :if={@to_gln_search_status == :searching} class="td-note">
                  Searching GS1 GLNs…
                </p>
                <p
                  :if={
                    @to_gln_query != "" and @to_gln_search_status == :complete and
                      @to_gln_results == []
                  }
                  class="td-note"
                >
                  No GS1 GLNs match this search.
                </p>
                <p
                  :if={@to_gln_search_status == :unavailable}
                  class="td-note"
                  style="color: var(--color-td-danger);"
                >
                  The GS1 GLN directory is unavailable. Try again in a moment.
                </p>
                <.td_input field={@form[:to_company_name]} label="To company name" readonly required />
                <.td_input field={@form[:to_address]} label="To address" readonly required />
              </div>
              <.td_input
                field={@form[:order_number]}
                id="serial-generation-order-number"
                label="Order number"
                placeholder="e.g. PO-2026-0142"
                autocomplete="off"
                required
              />
              <div class="td-header-actions">
                <.td_button
                  id="serial-wizard-prev"
                  type="button"
                  variant="secondary"
                  label="Prev"
                  phx-click="prev_step"
                  phx-target={@myself}
                />
                <.td_button
                  id="serial-wizard-submit"
                  type="submit"
                  variant="primary"
                  label="Generate serials & SSCCs"
                  phx-disable-with="Generating…"
                />
              </div>
            <% end %>
          </.form>
        <% end %>
      <% end %>
    </div>
    """
  end
end
