defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Wizard do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations

  @party_fields ~w(from_gln from_company_name from_address to_gln to_company_name to_address)

  def mount(params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    pallet =
      params["pallet_id"] && Manufacturing.get_pallet!(organization_id, params["pallet_id"])

    type = if pallet, do: "shipper", else: type_param(params["type"])
    attrs = default_attrs(pallet)

    {:ok,
     socket
     |> assign(:page_title, if(pallet, do: "Add shipper SSCC", else: "Add SSCC"))
     |> assign(:pallet, pallet)
     |> assign(:type, type)
     |> assign(:facilities, GlnLookup.search_origin(organization_id, ""))
     |> assign(:to_gln_query, destination_query(attrs))
     |> assign(:to_gln_results, [])
     |> assign(:to_gln_search_status, :idle)
     |> assign(:sscc_error, nil)
     |> assign(:form_params, attrs)
     |> assign_form(attrs)}
  end

  def handle_event("choose_type", %{"type" => type}, socket)
      when type in ["pallet", "shipper"] do
    attrs = default_attrs(nil)

    {:noreply,
     socket
     |> assign(:type, type)
     |> assign(:sscc_error, nil)
     |> assign(:form_params, attrs)
     |> assign(:to_gln_query, "")
     |> assign_form(attrs)}
  end

  def handle_event("validate", %{"sscc" => attrs}, socket) do
    attrs = sync_from_facility(attrs, socket.assigns.facilities)
    errors = validation_errors(socket.assigns.type, attrs, socket.assigns.pallet)
    {:noreply, socket |> assign(:form_params, attrs) |> assign_form(attrs, errors)}
  end

  def handle_event("save", %{"sscc" => attrs}, socket) do
    attrs = sync_from_facility(attrs, socket.assigns.facilities)

    with {:ok, attrs} <- resolve_to_party(socket, attrs) do
      errors = validation_errors(socket.assigns.type, attrs, socket.assigns.pallet)

      if errors == [],
        do: save(socket, socket.assigns.type, attrs),
        else: {:noreply, socket |> assign(:form_params, attrs) |> assign_form(attrs, errors)}
    else
      {:error, attrs} ->
        errors = [
          {:to_gln, {"could not be verified", []}}
          | validation_errors(socket.assigns.type, attrs, socket.assigns.pallet)
        ]

        {:noreply, socket |> assign(:form_params, attrs) |> assign_form(attrs, errors)}
    end
  end

  def handle_event("search_to_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    attrs = clear_to_party(socket.assigns.form_params)

    if String.length(query) < 2 do
      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :idle)
       |> assign(:form_params, attrs)
       |> assign_form(attrs)}
    else
      api_token = Organizations.gs1_api_key(socket.assigns.current_scope.organization_id)

      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :searching)
       |> assign(:form_params, attrs)
       |> assign_form(attrs)
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
        attrs = socket.assigns.form_params |> put_to_party(party) |> Map.put("to_gln", party.gln)

        {:noreply,
         socket
         |> assign(:to_gln_query, destination_label(party))
         |> assign(:to_gln_results, [])
         |> assign(:to_gln_search_status, :selected)
         |> assign(:form_params, attrs)
         |> assign_form(attrs)}
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

  def handle_async(:to_gln_search, _result, socket) do
    {:noreply,
     socket |> assign(:to_gln_results, []) |> assign(:to_gln_search_status, :unavailable)}
  end

  defp save(socket, "pallet", attrs) do
    case Manufacturing.create_pallet(socket.assigns.current_scope.organization_id, attrs) do
      {:ok, pallet} ->
        {:noreply,
         socket
         |> put_flash(:info, "Pallet SSCC added. Add its shippers next.")
         |> push_navigate(to: ~p"/manufacturer/aggregations/pallets/#{pallet.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :sscc))}
    end
  end

  defp save(socket, "shipper", attrs) do
    case Manufacturing.mint_empty_shipper_sscc(
           socket.assigns.current_scope.organization_id,
           socket.assigns.pallet,
           attrs
         ) do
      {:ok, sscc} ->
        {:noreply,
         socket
         |> put_flash(:info, "Shipper SSCC added. Add its GTINs next.")
         |> push_navigate(to: ~p"/manufacturer/aggregations/ssccs/#{sscc.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :sscc))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:sscc_error, reason)
         |> put_flash(:error, sscc_error(reason))}
    end
  end

  defp save(socket, nil, attrs), do: {:noreply, assign_form(socket, attrs)}

  defp assign_form(socket, attrs, errors \\ []),
    do: assign(socket, :form, to_form(attrs, as: :sscc, errors: errors))

  defp default_attrs(nil), do: Map.new(["code" | @party_fields], &{&1, ""})

  defp default_attrs(pallet) do
    %{
      "code" => "",
      "pallet" => pallet.code,
      "from_gln" => pallet.from_gln,
      "from_company_name" => pallet.from_company_name,
      "from_address" => pallet.from_address,
      "to_gln" => pallet.to_gln,
      "to_company_name" => pallet.to_company_name,
      "to_address" => pallet.to_address
    }
  end

  defp validation_errors(nil, _attrs, _pallet), do: []

  defp validation_errors(type, attrs, pallet) do
    fields =
      cond do
        type == "pallet" -> ["code" | @party_fields]
        type == "shipper" and is_nil(pallet) -> @party_fields
        true -> []
      end

    Enum.reduce(fields, [], fn field, errors ->
      if String.trim(attrs[field] || "") == "",
        do: [{String.to_existing_atom(field), {"is required", []}} | errors],
        else: errors
    end)
  end

  defp sync_from_facility(attrs, facilities) do
    case Enum.find(facilities, &(&1.gln == attrs["from_gln"])) do
      nil ->
        attrs

      facility ->
        attrs
        |> Map.put("from_company_name", facility.name || "")
        |> Map.put("from_address", facility.address || "")
    end
  end

  defp resolve_to_party(%{assigns: %{pallet: pallet}}, attrs) when not is_nil(pallet),
    do: {:ok, attrs}

  defp resolve_to_party(socket, attrs) do
    api_token = Organizations.gs1_api_key(socket.assigns.current_scope.organization_id)

    case GlnLookup.resolve_destination(api_token, attrs["to_gln"]) do
      {:ok, party} -> {:ok, put_to_party(attrs, party)}
      {:error, _reason} -> {:error, attrs}
    end
  end

  defp put_to_party(attrs, party) do
    attrs
    |> Map.put("to_company_name", party.company || "")
    |> Map.put("to_address", party.address || "")
  end

  defp clear_to_party(attrs) do
    attrs
    |> Map.put("to_gln", "")
    |> Map.put("to_company_name", "")
    |> Map.put("to_address", "")
  end

  defp destination_label(party), do: "#{party.gln} · #{party.company}"

  defp destination_query(attrs),
    do:
      if(attrs["to_gln"] in [nil, ""],
        do: "",
        else: "#{attrs["to_gln"]} · #{attrs["to_company_name"]}"
      )

  defp facility_options(facilities), do: Enum.map(facilities, &{"#{&1.name} · #{&1.gln}", &1.gln})

  defp sscc_error(:unconfigured),
    do: "Configure the organization's GS1 API key before generating a shipper SSCC."

  defp sscc_error(:unauthorized), do: "GS1 rejected the organization's API credentials."
  defp sscc_error({:invalid, message}), do: "GS1 could not generate the shipper SSCC: #{message}"
  defp sscc_error(_reason), do: "The GS1 service could not generate the shipper SSCC. Try again."

  defp type_param(type) when type in ["pallet", "shipper"], do: type
  defp type_param(_type), do: nil

  def render(assigns) do
    assigns = assign(assigns, :party_fields, @party_fields)

    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <.td_page_header
        title={if @pallet, do: "Add shipper SSCC", else: "Add SSCC"}
        subtitle={
          if @pallet,
            do: "This shipper inherits the pallet's From and To parties.",
            else: "Start a pallet hierarchy or add a standalone shipper."
        }
      />
      <.link navigate={back_path(@pallet)} class="td-back-link" style="margin-bottom:16px">
        <.td_icon name="arrow-left" /> Back
      </.link>

      <div class="td-agg-form">
        <section
          :if={@pallet}
          id="aggregation-parent-pallet"
          class="td-card td-party-card"
        >
          <span class="td-k">Pallet SSCC</span>
          <span class="td-mono">{@pallet.code}</span>
          <span class="td-party-cell">
            {@pallet.from_company_name}
            <.td_icon name="arrow-right" />
            {@pallet.to_company_name}
          </span>
        </section>

        <section class="td-card" style="padding:16px">
          <div :if={!@pallet} id="aggregation-type-picker" class="grid gap-4 md:grid-cols-2">
            <.td_option_card
              :for={{type, title, copy} <- type_cards()}
              id={"aggregation-type-#{type}"}
              title={title}
              body={copy}
              selected={@type == type}
              phx-click="choose_type"
              phx-value-type={type}
            />
          </div>

          <.form
            :if={@type}
            for={@form}
            id="aggregation-sscc-form"
            phx-change="validate"
            phx-submit="save"
            class="mt-7 space-y-6"
          >
            <div :if={@type == "pallet"} class="max-w-xl">
              <.input
                field={@form[:code]}
                type="text"
                label="Pallet SSCC"
                required
              />
            </div>
            <div
              :if={@type == "shipper" and @sscc_error != :unconfigured}
              id="shipper-sscc-api-note"
              class="td-notice"
            >
              <.td_icon name="info" />
              <p>The shipper SSCC will be generated by the GS1 member API when you save.</p>
            </div>
            <div
              :if={@sscc_error == :unconfigured}
              id="gs1-key-missing"
              class="td-notice is-danger"
            >
              <div>
                <p class="td-notice-title">GS1 API key missing</p>
                <p>Configure the organization's GS1 API key before generating a shipper SSCC.</p>
              </div>
              <.td_button
                variant="secondary"
                label="Open API keys"
                navigate={~p"/manufacturer/api-keys"}
              />
            </div>
            <div :if={!@pallet} class="grid gap-6 border-t border-thamani-stone pt-6 lg:grid-cols-2">
              <fieldset class="rounded-2xl border border-thamani-stone bg-thamani-canvas/50 p-5">
                <legend class="flex items-center gap-2 px-2 font-semibold text-thamani-forest">
                  <.td_icon name="factory" /> From
                </legend>
                <div class="mt-2 space-y-4">
                  <.input
                    field={@form[:from_gln]}
                    type="combobox"
                    label="From facility"
                    options={facility_options(@facilities)}
                    placeholder="Search your facilities"
                    required
                  />
                  <.input field={@form[:from_company_name]} label="Company name" readonly required />
                  <.input field={@form[:from_address]} label="Address" readonly required />
                </div>
              </fieldset>
              <fieldset class="rounded-2xl border border-thamani-stone bg-thamani-canvas/50 p-5">
                <legend class="flex items-center gap-2 px-2 font-semibold text-thamani-forest">
                  <.td_icon name="warehouse" /> To
                </legend>
                <div class="mt-2 space-y-4">
                  <label for="aggregation_to_gln_search" class="thamani-label">
                    To GLN<span aria-hidden="true" class="ml-0.5 text-red-700">*</span>
                  </label>
                  <input type="hidden" name="sscc[to_gln]" value={@form[:to_gln].value} />
                  <div id="aggregation-to-gln-combobox" class="relative">
                    <input
                      id="aggregation_to_gln_search"
                      type="search"
                      value={@to_gln_query}
                      phx-keyup="search_to_gln"
                      phx-debounce="300"
                      autocomplete="off"
                      placeholder="Search by GLN, company, or address"
                      class="thamani-input w-full"
                    />
                    <div
                      :if={@to_gln_results != []}
                      id="aggregation-to-gln-results"
                      role="listbox"
                      class="absolute z-[70] mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-thamani-stone bg-white py-1 shadow-lg"
                    >
                      <button
                        :for={party <- @to_gln_results}
                        id={"aggregation-to-gln-#{party.gln}"}
                        type="button"
                        role="option"
                        phx-click="select_to_gln"
                        phx-value-gln={party.gln}
                        class="block w-full px-3 py-2 text-left text-sm transition hover:bg-thamani-mist"
                      >
                        <span class="td-mono">{party.gln}</span>
                        <span class="block text-xs text-thamani-pewter">{party.company} · {party.address ||
                          "—"}</span>
                      </button>
                    </div>
                  </div>
                  <p :if={String.length(@to_gln_query) == 1} class="text-xs text-thamani-pewter">
                    Type at least 2 characters to search the GS1 GLN directory.
                  </p>
                  <p :if={@to_gln_search_status == :searching} class="text-xs text-thamani-pewter">
                    <.td_icon name="circle-notch" class="motion-safe:animate-spin" />
                    Searching GS1 GLNs…
                  </p>
                  <p
                    :if={
                      @to_gln_query != "" and @to_gln_search_status == :complete and
                        @to_gln_results == []
                    }
                    class="rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
                  >
                    No GS1 GLNs match this search.
                  </p>
                  <p :if={@to_gln_search_status == :unavailable} class="text-xs text-red-700">
                    The GS1 GLN directory is unavailable. Try again in a moment.
                  </p>
                  <.input field={@form[:to_company_name]} label="Company name" readonly required />
                  <.input field={@form[:to_address]} label="Address" readonly required />
                </div>
              </fieldset>
            </div>
            <div :if={@pallet}>
              <input
                :for={field <- @party_fields}
                type="hidden"
                name={"sscc[#{field}]"}
                value={@form[String.to_existing_atom(field)].value}
              />
            </div>
            <div class="flex flex-col-reverse gap-3 border-t border-[var(--color-td-hairline)] pt-6 sm:flex-row sm:justify-end">
              <.td_button variant="secondary" label="Cancel" navigate={back_path(@pallet)} />
              <.td_button
                id="save-aggregation-sscc"
                variant="primary"
                label={if @type == "pallet", do: "Save pallet SSCC", else: "Save shipper SSCC"}
                glyph="check"
                phx-disable-with="Saving..."
              />
            </div>
          </.form>
        </section>
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  defp type_cards,
    do: [
      {"pallet", "Pallet SSCC",
       "A whole pallet. Add its shipper SSCCs next; all inherit these parties."},
      {"shipper", "Shipper SSCC", "A standalone case. Add its GTINs, batches, and serials next."}
    ]

  defp back_path(nil), do: ~p"/manufacturer/aggregations"
  defp back_path(pallet), do: ~p"/manufacturer/aggregations/pallets/#{pallet.id}"
end
