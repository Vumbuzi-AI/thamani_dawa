defmodule ThamaniDawaWeb.ManufacturerProductLive.SerialWizard do
  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.Organizations

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:step, fn -> 0 end)
     |> assign_new(:submitting, fn -> false end)
     |> assign_new(:to_gln_query, fn -> "" end)
     |> assign_new(:to_gln_results, fn -> [] end)
     |> assign_new(:to_gln_search_status, fn -> :idle end)
     |> assign_new(:stock_serialization_enabled, fn ->
       Organizations.stock_serialization_enabled?(
         Organizations.get_organization!(assigns.organization_id)
       )
     end)
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
      "order_number" => "",
      "order_intent" => "order"
    }
  end

  def handle_event("next_step", %{"serial_generation" => params}, socket) do
    params = trusted_params(params, socket)
    errors = validation_errors(params, :batch)

    {:noreply,
     if(errors == [],
       do: socket |> assign(:step, 1) |> assign_form(params, []),
       else: assign_form(socket, params, errors)
     )}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, :step, 0)}
  end

  def handle_event("validate", %{"serial_generation" => params}, socket) do
    raw_params = params
    params = trusted_params(raw_params, socket)
    stage = if socket.assigns.step == 0, do: :batch, else: :order_details
    errors = params |> validation_errors(stage) |> disallowed_stock_error(raw_params, socket)

    socket =
      if params["order_intent"] == "stock" do
        socket
        |> assign(:to_gln_query, "")
        |> assign(:to_gln_results, [])
        |> assign(:to_gln_search_status, :idle)
      else
        socket
      end

    socket =
      socket
      |> assign(:form_params, params)
      |> assign(:form, generation_form(params, errors))

    {:noreply, socket}
  end

  def handle_event("save", %{"serial_generation" => params}, socket) do
    raw_params = params
    params = trusted_params(raw_params, socket)

    case resolve_order_destination(params, socket) do
      {:ok, params} ->
        errors =
          params
          |> validation_errors(:order_details)
          |> disallowed_stock_error(raw_params, socket)

        if errors == [] do
          generate(socket, params)
        else
          {:noreply, assign_form(socket, params, errors)}
        end

      {:error, params} ->
        errors =
          [{:to_gln, {"could not be verified", []}} | validation_errors(params, :order_details)]
          |> disallowed_stock_error(raw_params, socket)

        {:noreply, assign_form(socket, params, errors)}
    end
  end

  def handle_event("search_to_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    params = clear_destination(socket.assigns.form_params)

    if String.length(query) < 2 do
      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :idle)
       |> assign_form(params, validation_errors(params, :order_details))}
    else
      api_token = gs1_api_key(socket)

      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :searching)
       |> assign_form(params, validation_errors(params, :order_details))
       |> start_async(:to_gln_search, fn ->
         {query, GlnLookup.search_destination(api_token, query)}
       end)}
    end
  end

  def handle_event("close_to_gln", _params, socket) do
    {:noreply, socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :idle)}
  end

  def handle_event("select_to_gln", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.to_gln_results, &(&1.gln == gln)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That destination GLN is no longer available.")}

      party ->
        params =
          socket.assigns.form_params
          |> put_to_party(party)
          |> Map.put("to_gln", party.gln)

        {:noreply,
         socket
         |> assign(:to_gln_query, destination_label(party))
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)
         |> assign_form(params, validation_errors(params, :order_details))}
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

  defp trusted_params(params, socket) do
    params
    |> sync_from_facility(socket.assigns.facilities, socket.assigns.site)
    |> enforce_stock_setting(socket.assigns.stock_serialization_enabled)
    |> clear_order_fields_when_stock()
  end

  defp enforce_stock_setting(params, false), do: Map.put(params, "order_intent", "order")
  defp enforce_stock_setting(params, true), do: params

  defp disallowed_stock_error(errors, %{"order_intent" => "stock"}, %{assigns: assigns}) do
    if assigns.stock_serialization_enabled do
      errors
    else
      [{:order_intent, {"Stock serialization is not enabled for this organization", []}} | errors]
    end
  end

  defp disallowed_stock_error(errors, _params, _socket), do: errors

  defp clear_order_fields_when_stock(%{"order_intent" => "stock"} = params),
    do: clear_order_fields(params)

  defp clear_order_fields_when_stock(params), do: params

  defp resolve_order_destination(%{"order_intent" => "stock"} = params, _socket),
    do: {:ok, clear_order_fields(params)}

  defp resolve_order_destination(params, socket) do
    if params["to_gln"] in [nil, ""] do
      {:ok, params}
    else
      case GlnLookup.resolve_destination(gs1_api_key(socket), params["to_gln"]) do
        {:ok, party} -> {:ok, put_to_party(params, party)}
        {:error, _reason} -> {:error, params}
      end
    end
  end

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

  defp generate(socket, params) do
    attrs = %{
      "batch_no" => params["batch_no"],
      "production_date" => params["production_date"],
      "expiry_date" => params["expiry_date"],
      "pack_quantity" => params["primary_quantity"],
      "packs_per_shipper" => params["shipper_quantity"],
      "from_gln" => params["from_gln"],
      "from_company_name" => params["from_company_name"],
      "from_address" => params["from_address"],
      "to_gln" => params["to_gln"],
      "to_company_name" => params["to_company_name"],
      "to_address" => params["to_address"],
      "order_number" => params["order_number"]
    }

    with {:ok, %{batch: batch, operation: operation}} <-
           Operations.prepare_generation(
             socket.assigns.organization_id,
             socket.assigns.product.id,
             attrs
           ),
         {:ok, _job} <- Operations.enqueue_generation(operation) do
      {:noreply,
       socket
       |> assign(:submitting, true)
       |> put_flash(:info, "Generating serials for batch #{batch.batch_no}…")
       |> push_navigate(
         to:
           ~p"/manufacturer/products/#{socket.assigns.product.gtin}/serials?batch=#{batch.batch_no}"
       )}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:submitting, false)
         |> put_flash(:error, start_error(reason))}
    end
  end

  defp sync_from_facility(params, facilities, site) do
    # Origin is a property of the signed-in manufacturing site, never a value
    # the operator types or selects in this wizard.
    facility = Enum.find(facilities, &(&1.gln == site.gln)) || site

    params
    |> Map.put("from_gln", facility.gln || "")
    |> Map.put("from_company_name", facility.name || "")
    |> Map.put("from_address", facility.address || "")
  end

  defp clear_destination(params),
    do:
      params
      |> Map.put("to_gln", "")
      |> Map.put("to_company_name", "")
      |> Map.put("to_address", "")

  defp clear_order_fields(params),
    do: params |> clear_destination() |> Map.put("order_number", "")

  defp destination_label(party), do: "#{party.gln} · #{party.company}"

  defp gs1_api_key(socket), do: Organizations.gs1_api_key(socket.assigns.organization_id)

  defp generation_form(params, errors) do
    to_form(params, as: :serial_generation, errors: errors)
  end

  defp order_intent(params), do: Map.get(params, "order_intent", "order")

  defp validation_errors(params, stage) do
    base =
      []
      |> required_error(params, :batch_no, "Batch number")
      |> required_error(params, :production_date, "Production date")
      |> required_error(params, :expiry_date, "Expiry date")
      |> required_error(params, :primary_quantity, "Primary quantity")
      |> quantity_error(params, :shipper_quantity, "Packs per shipper")
      |> shipper_not_over_primary_error(params)
      |> shipper_divides_primary_error(params)
      |> date_order_error(params)

    order_details_errors(base, params, stage)
  end

  defp order_details_errors(errors, _params, :batch), do: errors

  defp order_details_errors(errors, params, :order_details) do
    if order_intent(params) == "order" do
      errors
      |> required_error(params, :order_number, "Customer purchase order")
      |> required_error(params, :to_gln, "Destination")
      |> required_error(params, :to_address, "Destination address")
    else
      errors
    end
  end

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

  defp expected_shippers(params) do
    with {primary, ""} <- Integer.parse(params["primary_quantity"] || ""),
         {shipper, ""} <- Integer.parse(params["shipper_quantity"] || ""),
         true <- shipper > 0 and rem(primary, shipper) == 0 do
      div(primary, shipper)
    else
      _ -> "—"
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

  defp start_error(%Ecto.Changeset{}),
    do: "Check the batch details and try again."

  defp start_error(:unavailable),
    do: "We couldn't reach GS1. Your batch is saved; try again in a moment."

  defp start_error(_reason),
    do: "We couldn't start generating serials. Try again in a moment."

  defp wizard_subtitle(0), do: "Batch details"
  defp wizard_subtitle(1), do: "Order details"
  defp wizard_subtitle(_step), do: "Generate identifiers explicitly."

  defp step_state(current_step, step) when current_step < step, do: "upcoming"
  defp step_state(current_step, step) when current_step == step, do: "current"
  defp step_state(_current_step, _step), do: "done"

  def render(assigns) do
    ~H"""
    <div id="manufacturer-serial-wizard" class="td-stack">
      <div id="serial-wizard-product" class="td-kv-grid">
        <.td_key_value label="Selected product" value={@product.name} />
        <.td_key_value label="GTIN" value={@product.gtin} mono />
      </div>

      <p id="serial-wizard-subtitle" class="td-wizard-sub">{wizard_subtitle(@step)}</p>

      <div class="td-steps" aria-label="Serial generation progress">
        <.td_step
          id="serial-wizard-step-batch"
          number={1}
          label="Batch details"
          state={step_state(@step, 0)}
        />
        <.td_step
          id="serial-wizard-step-order"
          number={2}
          label="Order details"
          state={step_state(@step, 1)}
        />
      </div>

      <%= cond do %>
        <% @step == 0 -> %>
          {render_batch_details(assigns)}
        <% @step == 1 -> %>
          {render_order_details(assigns)}
        <% true -> %>
          {render_batch_details(assigns)}
      <% end %>
    </div>
    """
  end

  defp render_batch_details(assigns) do
    assigns =
      assign(
        assigns,
        :facility,
        Enum.find(assigns.facilities, &(&1.gln == assigns.site.gln)) || assigns.site
      )

    ~H"""
    <.form
      for={@form}
      id="manufacturer-serial-generation-form"
      phx-change="validate"
      phx-submit="next_step"
      phx-target={@myself}
      class="td-auth-form"
    >
      <div
        id="serial-generation-facility-summary"
        class="rounded-lg border border-td-hairline bg-td-wash p-3 text-sm"
      >
        <span class="font-medium text-[var(--color-td-ink)]">Manufacturing facility</span>
        <span class="ml-2 text-[var(--color-td-ink-2)]">
          {@facility.name} · {@facility.gln} · {@facility.address}
        </span>
      </div>

      <.td_input field={@form[:batch_no]} label="Batch number" required />
      <.date_picker field={@form[:production_date]} label="Production date" required />
      <.date_picker field={@form[:expiry_date]} label="Expiry date" required />
      <.td_input
        field={@form[:primary_quantity]}
        type="number"
        min="1"
        label="Number of packs to serialize"
        required
      />
      <.td_input
        field={@form[:shipper_quantity]}
        type="number"
        min="1"
        label="Packs per shipper"
        required
      />
      <p class="td-note" id="serial-generation-expected-ships">
        Expected shippers: {expected_shippers(@form.params)}.
      </p>

      <div class="td-header-actions">
        <.td_button
          id="serial-wizard-next"
          type="submit"
          variant="primary"
          label="Next"
        />
      </div>
    </.form>
    """
  end

  defp render_order_details(assigns) do
    assigns = assign(assigns, :intent, order_intent(assigns.form.params))

    ~H"""
    <.form
      for={@form}
      id="manufacturer-serial-generation-form"
      phx-change="validate"
      phx-submit="save"
      phx-target={@myself}
      class="td-auth-form"
    >
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

      <%= if @stock_serialization_enabled do %>
        <fieldset id="serial-generation-order-intent" class="td-oc-set">
          <legend class="thamani-label">
            Is this batch being manufactured for an existing customer order?
          </legend>
          <div class="grid gap-3 md:grid-cols-2">
            <label class={["td-option", @intent == "stock" && "is-selected"]}>
              <input
                type="radio"
                name="serial_generation[order_intent]"
                id="serial-generation-order-intent-stock"
                value="stock"
                checked={@intent == "stock"}
              />
              <span class="td-oc-rd" aria-hidden="true"></span>
              <span class="td-oc-tx">
                <span class="td-option-title">No, manufacturing for stock</span>
                <span class="td-note">No customer order fields. Serials are generated independently.</span>
              </span>
            </label>
            <label class={["td-option", @intent == "order" && "is-selected"]}>
              <input
                type="radio"
                name="serial_generation[order_intent]"
                id="serial-generation-order-intent-order"
                value="order"
                checked={@intent == "order"}
              />
              <span class="td-oc-rd" aria-hidden="true"></span>
              <span class="td-oc-tx">
                <span class="td-option-title">Yes, for an existing customer order</span>
                <span class="td-note">Capture the genuine purchase order and GS1 destination.</span>
              </span>
            </label>
          </div>
        </fieldset>
      <% else %>
        <input type="hidden" name="serial_generation[order_intent]" value="order" />
        <div id="serial-generation-order-only-note" class="td-card-body td-note">
          This batch is being manufactured for an existing customer order. Manufacturing for stock
          is disabled for this organization.
        </div>
      <% end %>

      <%= if @intent == "order" do %>
        <div id="serial-generation-order-details" class="td-stack">
          <.td_input
            field={@form[:order_number]}
            id="serial-generation-order-number"
            label="Customer purchase order"
            placeholder="e.g. PO-2026-0142"
            autocomplete="off"
            required
          />

          <div>
            <label for="serial_generation_to_gln_search" class="thamani-label">Destination</label>
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
              <.td_gln_results
                id="serial-generation-to-gln-results"
                results={@to_gln_results}
                status={@to_gln_search_status}
                query={@to_gln_query}
                select_event="select_to_gln"
                close_event="close_to_gln"
                target={@myself}
                option_prefix="serial-generation-to-gln"
              />
            </div>
            <p
              :if={String.length(@to_gln_query) == 1}
              id="serial-generation-to-gln-search-hint"
              class="td-note"
            >
              Type at least 2 characters to search the GS1 GLN directory.
            </p>
            <.td_input field={@form[:to_company_name]} label="To company name" readonly />
            <.td_input field={@form[:to_address]} label="To address" readonly />
          </div>
        </div>
      <% end %>

      <div
        id="serial-generation-summary"
        class="rounded-lg border border-td-hairline bg-td-wash p-4 text-sm text-[var(--color-td-ink-2)]"
      >
        <p>
          <strong>{@form[:primary_quantity].value || "0"}</strong>
          product serials · <strong>{@form[:shipper_quantity].value || "0"}</strong>
          packs per shipper · <strong>{expected_shippers(@form.params)}</strong>
          expected shippers
        </p>
        <p :if={@intent == "order"} class="mt-1">
          Order: {@form[:order_number].value || "Not yet entered"}
        </p>
      </div>

      <div class="td-header-actions">
        <.td_button
          id="serial-wizard-prev"
          type="button"
          variant="secondary"
          label="Back"
          phx-click="prev_step"
          phx-target={@myself}
        />
        <.td_button
          id="serial-wizard-submit"
          type="submit"
          variant="primary"
          label="Generate serials"
          phx-disable-with="Generating"
        />
      </div>
    </.form>
    """
  end
end
