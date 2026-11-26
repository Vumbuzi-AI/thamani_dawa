defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Prepare do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.Operations
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  @refresh_ms 2_000

  def mount(%{"id" => id} = params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = Manufacturing.get_batch!(organization_id, id)
    product = Manufacturing.get_product!(organization_id, batch.manufacturer_product_id)

    socket =
      socket
      |> prepare_socket(params, product, batch, true)
      |> assign(:return_to, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/aggregations"))

    socket =
      if connected?(socket) do
        socket
        |> auto_prepare_batch()
        |> schedule_refresh()
      else
        socket
      end

    {:ok, socket}
  end

  def mount(%{"gtin" => gtin, "batch" => batch_no} = params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    product = Manufacturing.get_product_by_gtin!(organization_id, gtin)
    return_to = ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/aggregations")

    case find_gs1_batch(organization_id, product, batch_no) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That batch is no longer available in GS1.")
         |> push_navigate(to: return_to)}

      batch ->
        {:ok,
         socket
         |> prepare_socket(params, product, batch, false)
         |> assign(:return_to, return_to)}
    end
  end

  def handle_event("toggle_serial", %{"serial" => serial}, socket) do
    selected = socket.assigns.selected_serials

    selected =
      if MapSet.member?(selected, serial),
        do: MapSet.delete(selected, serial),
        else: MapSet.put(selected, serial)

    {:noreply,
     assign(socket, :selected_serials, cap_selected(selected, socket.assigns.packs_per_shipper))}
  end

  def handle_event("select_all_unpacked", _params, socket) do
    selected = socket.assigns.selected_serials
    limit = socket.assigns.packs_per_shipper || 0

    next_group =
      socket.assigns.unpacked_serials
      |> Enum.reject(&MapSet.member?(selected, &1))
      |> Enum.take(limit)

    {:noreply, assign(socket, :selected_serials, MapSet.new(next_group))}
  end

  def handle_event("open_registry_setup", _params, socket) do
    {:noreply, assign(socket, setup_open?: true, setup_error: nil)}
  end

  def handle_event("close_registry_setup", _params, socket) do
    {:noreply, assign(socket, setup_open?: false, setup_error: nil)}
  end

  def handle_event(
        "configure_registry_setup",
        %{"shipper_quantity" => %{"packs_per_shipper" => value}},
        socket
      ) do
    with true <- valid_gln?(socket.assigns.to_gln),
         {quantity, ""} <- Integer.parse(value),
         :ok <-
           validate_shipper_quantity(
             quantity,
             socket.assigns.batch,
             socket.assigns.local_batch?
           ),
         {:ok, batch} <- persist_shipper_quantity(socket, quantity) do
      {:noreply,
       socket
       |> assign(:batch, batch)
       |> assign(:packs_per_shipper, quantity)
       |> assign(:selected_serials, cap_selected(socket.assigns.selected_serials, quantity))
       |> assign(:shipper_quantity_form, shipper_quantity_form(quantity))
       |> assign(:setup_open?, false)
       |> assign(:setup_error, nil)}
    else
      false ->
        {:noreply, assign(socket, :setup_error, "Choose a destination GLN to continue.")}

      _ ->
        {:noreply,
         socket
         |> assign(:shipper_quantity_form, shipper_quantity_form(value))
         |> assign(
           :setup_error,
           "Enter a positive quantity no greater than the serials in this batch."
         )}
    end
  end

  def handle_event("clear_selected_serials", _params, socket) do
    {:noreply, assign(socket, :selected_serials, MapSet.new())}
  end

  def handle_event("create_shipper", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = socket.assigns.batch
    product = socket.assigns.product
    selected = selected_serials_in_order(socket)

    cond do
      selected == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one serial to create a shipper.")}

      not shipper_request_possible?(socket) ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This batch needs a valid ship-from and ship-to GLN before a shipper can be created."
         )}

      true ->
        attrs = %{
          "from_gln" => socket.assigns.from_gln,
          "to_gln" => socket.assigns.to_gln,
          "order_number" => "",
          "from_company_name" => socket.assigns.from_company_name,
          "from_address" => socket.assigns.from_address,
          "to_company_name" => socket.assigns.to_company_name,
          "to_address" => socket.assigns.to_address
        }

        case Manufacturing.pack_serials_into_shipper(
               organization_id,
               product,
               batch,
               selected,
               attrs,
               site_gln: socket.assigns.from_gln
             ) do
          {:ok, _shipper} ->
            {:noreply,
             socket
             |> assign(:selected_serials, MapSet.new())
             |> put_flash(:info, "Shipper created from #{length(selected)} serial(s).")
             |> load_page_data()}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, shipper_error(reason))}
        end
    end
  end

  def handle_event("search_destination_gln", %{"value" => query}, socket) do
    query = String.trim(query)
    socket = clear_destination(socket)

    if String.length(query) < 2 do
      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :idle)}
    else
      api_token = Organizations.gs1_api_key(socket.assigns.current_scope.organization_id)

      {:noreply,
       socket
       |> assign(:to_gln_query, query)
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :searching)
       |> start_async(:destination_gln_search, fn ->
         {query, GlnLookup.search_destination(api_token, query)}
       end)}
    end
  end

  def handle_event("close_destination_gln", _params, socket) do
    {:noreply,
     socket
     |> assign(:to_gln_results, [])
     |> assign(:to_gln_search_status, :idle)}
  end

  def handle_event("select_destination_gln", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.to_gln_results, &(&1.gln == gln)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That destination GLN is no longer available.")}

      party ->
        socket =
          socket
          |> assign(:to_gln, party.gln)
          |> assign(:to_company_name, party.company || "")
          |> assign(:to_address, party.address || "")
          |> assign(:to_gln_query, destination_label(party))
          |> assign(:to_gln_results, [])
          |> assign(:to_gln_search_status, :selected)
          |> persist_destination(party)

        {:noreply, socket}
    end
  end

  def handle_event("show_contents", %{"id" => id}, socket) do
    shipper =
      Enum.find(socket.assigns.shippers, fn candidate ->
        Integer.to_string(candidate.id) == id
      end)

    {:noreply,
     socket
     |> assign(:contents_shipper, shipper)
     |> assign(:contents_serials, shipper_print_serials(shipper))}
  end

  def handle_event("close_contents", _params, socket) do
    {:noreply,
     socket
     |> assign(:contents_shipper, nil)
     |> assign(:contents_serials, [])}
  end

  def handle_event("open_label", %{"id" => id}, socket) do
    case Integer.parse(id) do
      {shipper_id, ""} ->
        case Enum.find(socket.assigns.shippers, &(&1.id == shipper_id)) do
          nil -> {:noreply, socket}
          shipper -> {:noreply, assign(socket, :label_shipper, shipper)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_label", _params, socket),
    do: {:noreply, assign(socket, :label_shipper, nil)}

  def handle_async(:destination_gln_search, {:ok, {query, {:ok, results}}}, socket) do
    if socket.assigns.to_gln_query == query do
      {:noreply,
       socket
       |> assign(:to_gln_results, results)
       |> assign(:to_gln_search_status, :complete)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:destination_gln_search, _result, socket),
    do:
      {:noreply,
       socket
       |> assign(:to_gln_results, [])
       |> assign(:to_gln_search_status, :unavailable)}

  def handle_info(:refresh_shippers, socket) do
    {:noreply, socket |> load_page_data() |> schedule_refresh()}
  end

  defp prepare_socket(socket, params, product, batch, local_batch?) do
    organization_id = socket.assigns.current_scope.organization_id
    site = current_site(socket)
    organization = Organizations.get_organization!(organization_id)
    party = batch_fields(batch, site, organization)

    socket
    |> assign(:page_title, "Create shippers")
    |> assign(:product, product)
    |> assign(:batch, batch)
    |> assign(:local_batch?, local_batch?)
    |> assign(:return_to, ThamaniDawaWeb.ReturnTo.path(params, ~p"/manufacturer/aggregations"))
    |> assign(:contents_shipper, nil)
    |> assign(:contents_serials, [])
    |> assign(:label_shipper, nil)
    |> assign(:print_serials_shipper, nil)
    |> assign(:print_serials, [])
    |> assign(:selected_serials, MapSet.new())
    |> assign(:creating_shipper, false)
    |> assign(:packs_per_shipper, Map.get(batch, :packs_per_shipper))
    |> assign(:shipper_quantity_form, shipper_quantity_form(Map.get(batch, :packs_per_shipper)))
    |> assign(
      :setup_open?,
      is_nil(Map.get(batch, :packs_per_shipper)) or not valid_gln?(party.to_gln)
    )
    |> assign(:setup_error, nil)
    |> assign(:from_gln, party.from_gln)
    |> assign(:from_company_name, party.from_company_name)
    |> assign(:from_address, party.from_address)
    |> assign(:to_gln, party.to_gln)
    |> assign(:to_company_name, party.to_company_name)
    |> assign(:to_address, party.to_address)
    |> assign(:to_gln_query, destination_label(party))
    |> assign(:to_gln_results, [])
    |> assign(:to_gln_search_status, :idle)
    |> load_page_data(organization_id)
  end

  defp current_site(socket) do
    scope = socket.assigns.current_scope

    case scope.current_site_id do
      nil -> nil
      site_id -> Sites.get_site!(scope.organization_id, site_id)
    end
  end

  defp batch_fields(batch, site, organization) do
    %{
      from_gln: first_present([batch_value(batch, :from_gln), site_value(site, :gln)]),
      from_company_name:
        first_present([
          batch_value(batch, :from_company_name),
          organization.name,
          site_value(site, :name)
        ]),
      from_address:
        first_present([batch_value(batch, :from_address), site_value(site, :address)]),
      to_gln: first_present([batch_value(batch, :to_gln)]),
      to_company_name: first_present([batch_value(batch, :to_company_name)]),
      to_address: first_present([batch_value(batch, :to_address)])
    }
  end

  defp first_present(values, default \\ "")

  defp first_present([value | _rest], _default) when is_binary(value) and value != "", do: value

  defp first_present([_value | rest], default), do: first_present(rest, default)
  defp first_present([], default), do: default

  defp batch_value(batch, key), do: Map.get(batch, key)

  defp site_value(nil, _key), do: nil
  defp site_value(site, key), do: Map.get(site, key)

  defp destination_label(%{gln: gln, company: company}) when is_binary(gln),
    do: "#{company || "GS1 party"} · #{gln}"

  defp destination_label(%{to_gln: gln, to_company_name: company}) when is_binary(gln),
    do: "#{company || "GS1 party"} · #{gln}"

  defp destination_label(_party), do: ""

  defp party_name(name, _gln, _fallback) when is_binary(name) and byte_size(name) > 0, do: name

  defp party_name(_name, gln, fallback) when is_binary(gln) and byte_size(gln) > 0, do: fallback

  defp party_name(_name, _gln, fallback), do: fallback

  defp find_gs1_batch(organization_id, product, batch_no) do
    batches =
      case Manufacturing.fetch_product_batches(organization_id, product.gtin) do
        {:ok, rows} -> rows
        {:error, _reason} -> Manufacturing.local_product_batches(organization_id, product.gtin)
      end

    Enum.find(batches, &(&1.batch_no == batch_no))
  end

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh_shippers, @refresh_ms)
    socket
  end

  defp load_page_data(socket, organization_id \\ nil) do
    organization_id = organization_id || socket.assigns.current_scope.organization_id
    product = socket.assigns.product
    batch = socket.assigns.batch

    {serials, serials_error} =
      if socket.assigns.local_batch? do
        {Manufacturing.list_serials(organization_id, batch.id), nil}
      else
        case Manufacturing.fetch_batch_serials(organization_id, product.gtin, batch.batch_no) do
          {:ok, rows} -> {rows, nil}
          {:error, reason} -> {[], reason}
        end
      end

    {shippers, by_serial} =
      Manufacturing.list_batch_shippers(organization_id, product.gtin, batch.batch_no)

    serials =
      if socket.assigns.local_batch? do
        serials
      else
        serials
        |> Enum.with_index(1)
        |> Enum.map(fn {row, index} ->
          serial = row.serial

          %{
            id: "gs1-#{index}",
            serial: serial,
            manufacturer_shipper_sscc_id: Map.get(by_serial, serial)
          }
        end)
      end

    unpacked_rows = Enum.reject(serials, & &1.manufacturer_shipper_sscc_id)
    unpacked = Enum.map(unpacked_rows, & &1.serial)

    selected =
      socket.assigns.selected_serials
      |> Enum.filter(&(&1 in unpacked))
      |> MapSet.new()
      |> cap_selected(socket.assigns.packs_per_shipper)

    unselected = Enum.reject(unpacked, &MapSet.member?(selected, &1))

    label_shipper =
      case socket.assigns[:label_shipper] do
        %{id: shipper_id} -> Enum.find(shippers, &(&1.id == shipper_id))
        _ -> nil
      end

    socket
    |> assign(:serials, serials)
    |> assign(:serials_error, serials_error)
    |> assign(:unpacked_serial_rows, unpacked_rows)
    |> assign(:unpacked_serials, unpacked)
    |> assign(:unselected_unpacked_serials, unselected)
    |> assign(:shippers, shippers)
    |> assign(:label_shipper, label_shipper)
    |> assign(:selected_serials, selected)
  end

  defp auto_prepare_batch(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    batch = socket.assigns.batch

    if batch.shipper_preparation_method == "during_packing" do
      socket
    else
      case Operations.prepare_shippers(organization_id, batch.id, "during_packing") do
        {:ok, %{batch: prepared}} ->
          socket
          |> assign(:batch, prepared)
          |> load_page_data()

        {:error, :serialization_not_completed} ->
          put_flash(
            socket,
            :error,
            "Generate product serials before creating shippers for this batch."
          )

        {:error, :preparation_method_locked} ->
          put_flash(
            socket,
            :error,
            "This batch has already started packing. Open the active aggregation instead."
          )

        {:error, _reason} ->
          socket
      end
    end
  end

  defp persist_destination(socket, party) do
    if socket.assigns.local_batch? do
      batch =
        socket.assigns.batch
        |> Ecto.Changeset.change(
          to_gln: party.gln,
          to_company_name: party.company || "",
          to_address: party.address || ""
        )
        |> Repo.update!()

      assign(socket, :batch, batch)
    else
      socket
    end
  end

  defp persist_shipper_quantity(socket, quantity) do
    if socket.assigns.local_batch? do
      socket.assigns.batch
      |> ThamaniDawa.Manufacturing.Batch.changeset(%{packs_per_shipper: quantity})
      |> Repo.update()
    else
      {:ok, Map.put(socket.assigns.batch, :packs_per_shipper, quantity)}
    end
  end

  defp validate_shipper_quantity(quantity, batch, local_batch?)
       when is_integer(quantity) and quantity > 0 do
    total = Map.get(batch, :pack_quantity) || Map.get(batch, :serial_count)

    cond do
      is_integer(total) and quantity > total -> :error
      local_batch? and is_integer(total) and rem(total, quantity) != 0 -> :error
      true -> :ok
    end
  end

  defp validate_shipper_quantity(_quantity, _batch, _local_batch?), do: :error

  defp shipper_quantity_form(value) do
    to_form(%{"packs_per_shipper" => value && to_string(value)}, as: :shipper_quantity)
  end

  defp clear_destination(socket) do
    socket
    |> assign(:to_gln, "")
    |> assign(:to_company_name, "")
    |> assign(:to_address, "")
  end

  defp shipper_contents(nil), do: []

  defp shipper_contents(shipper) do
    packed = shipper.packed_serials || []
    mirrored = for(serial <- shipper.serials || [], do: serial.serial)

    Enum.uniq(packed ++ mirrored)
  end

  defp shipper_print_serials(nil), do: []

  defp shipper_print_serials(shipper) do
    shipper
    |> shipper_contents()
    |> Enum.map(fn serial ->
      %{
        serial: serial,
        batch: shipper.batch,
        expiry_date: shipper.expiry_date,
        production_date: shipper.production_date
      }
    end)
  end

  defp selected_serials_in_order(socket) do
    selected = socket.assigns.selected_serials

    socket.assigns.serials
    |> Enum.reject(& &1.manufacturer_shipper_sscc_id)
    |> Enum.map(& &1.serial)
    |> Enum.filter(&MapSet.member?(selected, &1))
  end

  defp cap_selected(_selected, nil), do: MapSet.new()

  defp cap_selected(selected, limit) do
    selected
    |> Enum.take(limit)
    |> MapSet.new()
  end

  defp shipper_request_possible?(%{assigns: assigns}), do: shipper_request_possible?(assigns)

  defp shipper_request_possible?(assigns) do
    valid_gln?(Map.get(assigns, :from_gln)) and valid_gln?(Map.get(assigns, :to_gln))
  end

  defp shipper_creation_possible?(assigns) do
    shipper_request_possible?(assigns) and is_integer(assigns.packs_per_shipper) and
      assigns.packs_per_shipper > 0
  end

  defp valid_gln?(gln) when is_binary(gln), do: Regex.match?(~r/^\d{13}$/, gln)
  defp valid_gln?(_), do: false

  defp gln_issue(%{assigns: assigns}), do: gln_issue(assigns)

  defp gln_issue(assigns) do
    cond do
      not valid_gln?(Map.get(assigns, :from_gln)) ->
        "This batch has no valid ship-from GLN. Add a GLN to the current manufacturing site."

      not valid_gln?(Map.get(assigns, :to_gln)) ->
        "This batch has no destination GLN. Search the GS1 directory in the shipment panel, then try again."

      true ->
        nil
    end
  end

  defp shipper_error({:invalid, _message}),
    do: "GS1 couldn't accept the shipper details. Check them and try again."

  defp shipper_error(:sscc_prerequisites_missing),
    do: "A valid ship-from and ship-to GLN is required before a shipper can be created."

  defp shipper_error(reason) when reason in [:unauthorized, :forbidden],
    do: "GS1 rejected your API key. Check it in organization settings, then try again."

  defp shipper_error(:unconfigured),
    do:
      "GS1 isn't set up for your organization. Add your GS1 key in organization settings, then try again."

  defp shipper_error(reason) when reason in [:sscc_unavailable, :unavailable],
    do:
      "GS1 couldn't create the shipper label right now. Your serials are still selected; try again."

  defp shipper_error(:reconciliation_required),
    do:
      "We couldn't confirm whether GS1 created the shipper label. Check your GS1 account before trying again."

  defp shipper_error(_reason),
    do: "We couldn't create the shipper label. Try again in a moment."

  defp label_tone("completed"), do: "success"
  defp label_tone("available"), do: "info"
  defp label_tone("awaiting_verification"), do: "warning"
  defp label_tone(_status), do: "info"

  defp humanize_status(status) when is_binary(status),
    do: status |> String.replace("_", " ") |> String.capitalize()

  defp humanize_status(_status), do: "—"

  defp long_date(nil), do: "—"
  defp long_date(date), do: ThamaniDawaWeb.TimeFormat.date(date)

  defp expected_shipper_count(serials, packs_per_shipper)
       when is_integer(packs_per_shipper) and packs_per_shipper > 0,
       do: div(length(serials) + packs_per_shipper - 1, packs_per_shipper)

  defp expected_shipper_count(_serials, _packs_per_shipper), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
      crumb="Create shippers"
      crumb_parent="Aggregation"
    >
      <.td_back_link
        id="prepare-shippers-back"
        to={@return_to}
        label={ThamaniDawaWeb.ReturnTo.label(@return_to, "Back")}
      />
      <div class="create-shippers-page">
        <.td_page_header
          title="Create shippers"
          subtitle={"#{@product.name} · Batch #{@batch.batch_no} · select serials to create a shipper."}
        >
          <:actions>
            <div id="prepare-shipment-parties" class="td-shipment-brief">
              <div class="td-shipment-brief-party">
                <span class="td-shipment-brief-label">From</span>
                <span
                  id="prepare-ship-from-name"
                  title={party_name(@from_company_name, @from_gln, "Manufacturing site")}
                  class="td-shipment-brief-name"
                >
                  {party_name(@from_company_name, @from_gln, "Manufacturing site")}
                </span>
                <span class="td-shipment-brief-gln">{@from_gln}</span>
              </div>

              <span aria-hidden="true" class="td-shipment-brief-arrow">→</span>

              <div class="td-shipment-brief-party">
                <span class="td-shipment-brief-label">To</span>
                <span
                  id="prepare-ship-to-name"
                  title={party_name(@to_company_name, @to_gln, "Destination not selected")}
                  class="td-shipment-brief-name"
                >
                  {party_name(@to_company_name, @to_gln, "Destination not selected")}
                </span>
                <span class="td-shipment-brief-gln">{@to_gln}</span>
              </div>

              <div
                :if={@local_batch? and not valid_gln?(@to_gln)}
                id="create-shippers-destination"
                class="td-shipment-brief-destination"
              >
                <label for="create-shippers-to-gln-search" class="sr-only">Ship-to GLN</label>
                <input
                  id="create-shippers-to-gln-search"
                  type="search"
                  value={@to_gln_query}
                  phx-keyup="search_destination_gln"
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder="Search destination GLN"
                  class="thamani-input w-full"
                />
                <.td_gln_results
                  id="create-shippers-to-gln-results"
                  results={@to_gln_results}
                  status={@to_gln_search_status}
                  query={@to_gln_query}
                  select_event="select_destination_gln"
                  close_event="close_destination_gln"
                  option_prefix="create-shippers-to-gln"
                />
                <p
                  :if={String.length(@to_gln_query) == 1}
                  id="create-shippers-gln-search-hint"
                  class="td-shipment-brief-hint"
                >
                  Type at least 2 characters to search the GS1 GLN directory.
                </p>
              </div>
            </div>
          </:actions>
        </.td_page_header>

        <div
          :if={@local_batch? and gln_issue(assigns)}
          id="gs1-create-sscc-warning"
          class="td-bnr is-danger"
        >
          <.td_icon name="warning-circle" class="size-4" />
          <p>{gln_issue(assigns)}</p>
        </div>

        <div
          :if={@local_batch? and is_nil(@packs_per_shipper)}
          id="shipper-quantity-warning"
          class="td-bnr is-warning"
        >
          <.td_icon name="info" class="size-4" />
          <p>Set the units per shipper before selecting serials.</p>
        </div>

        <div :if={@serials_error} id="create-shippers-serials-error" class="td-bnr is-danger">
          <.td_icon name="warning-circle" class="size-4" />
          <p>GS1 serials could not be loaded for this batch. Try opening the batch again.</p>
        </div>

        <section id="prepare-shippers" class="td-card">
          <div id="prepare-batch-details" class="td-kv-grid is-pad is-6">
            <div id="prepare-batch-number" class="td-kv">
              <span class="td-kv-label">Batch</span>
              <span class="td-kv-value is-mono">{@batch.batch_no}</span>
            </div>
            <div id="prepare-batch-gtin" class="td-kv">
              <span class="td-kv-label">GTIN</span>
              <span class="td-kv-value is-mono">{@product.gtin}</span>
            </div>
            <div id="prepare-batch-produced" class="td-kv">
              <span class="td-kv-label">Produced</span>
              <span class="td-kv-value">{long_date(@batch.production_date)}</span>
            </div>
            <div id="prepare-batch-expires" class="td-kv">
              <span class="td-kv-label">Expires</span>
              <span class="td-kv-value">{long_date(@batch.expiry_date)}</span>
            </div>
            <div id="prepare-batch-serials" class="td-kv">
              <span class="td-kv-label">Serials</span>
              <span class="td-kv-value">{length(@serials)}</span>
            </div>
            <div id="prepare-shipper-quantity" class="td-kv">
              <span class="td-kv-label">Units per shipper</span>
              <span class="td-kv-value">{@packs_per_shipper || "Not set"}</span>
              <button
                id="change-registry-shipper-setup"
                type="button"
                class="td-link mt-1 text-left text-xs"
                phx-click="open_registry_setup"
              >
                Change setup
              </button>
            </div>
            <div id="prepare-batch-packed" class="td-kv">
              <span class="td-kv-label">Packed</span>
              <span class="td-kv-value">
                {length(@serials) - length(@unpacked_serials)} of {length(@serials)}
              </span>
            </div>
            <div id="prepare-batch-shippers-count" class="td-kv">
              <span class="td-kv-label">Shippers</span>
              <span class="td-kv-value">
                {length(@shippers)}
                <span :if={expected_shipper_count(@serials, @packs_per_shipper)}>
                  of {expected_shipper_count(@serials, @packs_per_shipper)}
                </span>
                created
              </span>
              <button
                :if={@shippers != []}
                id="view-created-shippers"
                type="button"
                phx-click={
                  JS.dispatch("phx:scroll-into-view",
                    detail: %{id: "prepare-shipper-labels"}
                  )
                }
                class="td-link mt-1 text-left text-xs"
              >
                View shippers ↓
              </button>
            </div>
          </div>
        </section>

        <section :if={@unpacked_serials != []} id="serial-shipper-selection" class="td-card">
          <.td_card_header
            title="Unpacked serials"
            subtitle="Select serials with checkboxes to simulate mobile scanning. Select N picks the next N unpacked serials."
          >
            <:actions>
              <span aria-live="polite">
                <.td_badge tone="neutral" label={"#{MapSet.size(@selected_serials)} selected"} />
              </span>
              <.td_button
                id="select-all-unpacked"
                variant="secondary"
                label={
                  if @packs_per_shipper, do: "Select #{@packs_per_shipper}", else: "Set quantity"
                }
                phx-click="select_all_unpacked"
                disabled={is_nil(@packs_per_shipper) or @unselected_unpacked_serials == []}
              />
              <.td_button
                id="clear-selected-serials"
                variant="secondary"
                label="Clear"
                phx-click="clear_selected_serials"
                disabled={MapSet.size(@selected_serials) == 0}
              />
              <.td_button
                id="create-shipper-from-serials"
                variant="primary"
                label="Create shipper"
                phx-click="create_shipper"
                phx-disable-with="Creating…"
                disabled={
                  MapSet.size(@selected_serials) == 0 or not shipper_creation_possible?(assigns)
                }
              />
            </:actions>
          </.td_card_header>

          <div class="td-table">
            <table id="unpacked-serials-table">
              <thead>
                <tr>
                  <th class="w-12">Pack</th>
                  <th>Serial</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={serial <- @unpacked_serial_rows} id={"serial-row-#{serial.id}"}>
                  <td>
                    <input
                      id={"select-serial-#{serial.id}"}
                      type="checkbox"
                      class="checkbox checkbox-sm"
                      phx-click="toggle_serial"
                      phx-value-serial={serial.serial}
                      checked={MapSet.member?(@selected_serials, serial.serial)}
                    />
                  </td>
                  <td class="td-mono">{serial.serial}</td>
                  <td>
                    <.td_badge tone="success" label="Unpacked" />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section id="prepare-shipper-labels" class="td-card td-anchor-target">
          <.td_card_header
            title="Shipper labels"
            subtitle="Created as each carton is filled. This list refreshes automatically."
          >
            <:actions>
              <.td_button
                :if={@shippers != []}
                id="print-all-shipper-labels"
                type="button"
                glyph="printer"
                label="Print all"
                phx-hook="PrintAllLabels"
                data-print-container="#prepare-printable-shipper-labels"
                data-print-target=".printable-sscc-label"
                data-label-size="100mm auto"
                tip="Print a label for every shipper created for this batch."
              />
              <span aria-live="polite">
                <.td_badge tone="neutral" label={"#{length(@shippers)} created"} />
              </span>
            </:actions>
          </.td_card_header>
          <div :if={@shippers == []} id="prepare-shippers-empty" class="td-empty-card">
            <p class="td-empty-title">No shipper labels yet</p>
            <p class="td-note">
              Shipper SSCCs appear here as soon as a carton is packed.
            </p>
          </div>
          <div :if={@shippers != []} class="td-table">
            <table id="prepared-shippers-table">
              <thead>
                <tr>
                  <th>SSCC</th>
                  <th class="td-num">Units</th>
                  <th>Status</th>
                  <th class="td-num"><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={shipper <- @shippers} id={"prepared-shipper-#{shipper.id}"}>
                  <td class="td-mono">{shipper.code}</td>
                  <td class="td-num">{shipper.count_of_trade_items || 0}</td>
                  <td>
                    <.td_badge
                      tone={label_tone(shipper.status)}
                      label={humanize_status(shipper.status)}
                    />
                  </td>
                  <td class="td-row-actions">
                    <.td_button
                      id={"contents-shipper-#{shipper.id}"}
                      glyph="list-bullets"
                      label="View shipper serials"
                      phx-click="show_contents"
                      phx-value-id={shipper.id}
                    />
                    <.td_button
                      id={"print-shipper-#{shipper.id}"}
                      glyph="printer"
                      label="Print shipper label"
                      phx-click="open_label"
                      phx-value-id={shipper.id}
                      tip="Print the 100 × 150 mm shipper label with the GS1 DataMatrix for this SSCC."
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            :if={@shippers != []}
            id="prepare-printable-shipper-labels"
            class="td-print-sheet"
            aria-hidden="true"
          >
            <ThamaniDawaWeb.ManufacturerSsccLive.Label.sheet
              :for={shipper <- @shippers}
              sscc={shipper}
              product_name={@product.name}
              id_prefix="batch-shipper-label"
            />
          </div>
        </section>

        <.td_modal
          :if={@setup_open?}
          id="registry-shipper-setup-modal"
          show
          title="Set up shipper packing"
          subtitle="Choose where these shippers are going and how many serials each shipper contains."
          on_cancel={JS.push("close_registry_setup")}
        >
          <:body>
            <div class="space-y-5 p-5">
              <div class="td-kv-grid is-2">
                <div class="td-kv">
                  <span class="td-kv-label">Ship from</span>
                  <span class="td-kv-value">{@from_company_name}</span>
                  <span class="td-mono text-xs">{@from_gln}</span>
                </div>
                <div class="td-kv">
                  <span class="td-kv-label">Batch</span>
                  <span class="td-kv-value is-mono">{@batch.batch_no}</span>
                  <span class="td-note">{length(@unpacked_serials)} unpacked serials</span>
                </div>
              </div>

              <div>
                <label for="registry-setup-to-gln-search" class="td-field-label">
                  Destination GLN
                </label>
                <input
                  id="registry-setup-to-gln-search"
                  type="search"
                  value={@to_gln_query}
                  phx-keyup="search_destination_gln"
                  phx-debounce="300"
                  autocomplete="off"
                  placeholder="Search company or GLN"
                  class="thamani-input w-full"
                />
                <.td_gln_results
                  id="registry-setup-to-gln-results"
                  results={@to_gln_results}
                  status={@to_gln_search_status}
                  query={@to_gln_query}
                  select_event="select_destination_gln"
                  close_event="close_destination_gln"
                  option_prefix="registry-setup-to-gln"
                />
                <p :if={valid_gln?(@to_gln)} id="registry-setup-destination" class="td-note mt-2">
                  Selected: {@to_company_name} · <span class="td-mono">{@to_gln}</span>
                </p>
              </div>

              <.form
                for={@shipper_quantity_form}
                id="registry-shipper-setup-form"
                phx-submit="configure_registry_setup"
              >
                <.input
                  field={@shipper_quantity_form[:packs_per_shipper]}
                  id="registry-setup-shipper-quantity"
                  type="number"
                  min="1"
                  max={length(@serials)}
                  label="Units per shipper"
                />
                <p class="td-note mt-1">Maximum {length(@serials)} serials per shipper.</p>
                <p :if={@setup_error} id="registry-setup-error" class="mt-2 text-xs text-td-danger">
                  {@setup_error}
                </p>
              </.form>
            </div>
          </:body>
          <:footer>
            <.td_button label="Back to batches" navigate={@return_to} />
            <.td_button
              id="save-registry-shipper-setup"
              type="submit"
              form="registry-shipper-setup-form"
              variant="primary"
              label="Save and start packing"
            />
          </:footer>
        </.td_modal>

        <.td_modal
          :if={@contents_shipper}
          id="prepare-shipper-contents-modal"
          show
          title="Shipper serials"
          subtitle={"SSCC #{@contents_shipper.code} · #{length(@contents_serials)} serials"}
          on_cancel={JS.push("close_contents")}
        >
          <:body>
            <div id="prepare-shipper-contents-details" class="td-kv-grid is-pad is-3">
              <div class="td-kv">
                <span class="td-kv-label">SSCC</span>
                <span class="td-kv-value is-mono">{@contents_shipper.code}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">Batch</span>
                <span class="td-kv-value is-mono">{@contents_shipper.batch}</span>
              </div>
              <div class="td-kv">
                <span class="td-kv-label">GTIN</span>
                <span class="td-kv-value is-mono">{@product.gtin}</span>
              </div>
            </div>
            <div class="mt-3">
              <p class="td-note mb-2">Serials</p>
              <div id="prepare-shipper-contents-list" class="flex flex-wrap gap-2">
                <span
                  :for={serial <- @contents_serials}
                  id={"prepare-shipper-content-#{@contents_shipper.id}-#{dom_key(serial.serial)}"}
                  class="td-mono rounded-md border border-td-hairline bg-td-wash px-2 py-1 text-xs"
                >
                  {serial.serial}
                </span>
              </div>
            </div>
            <div id="prepare-shipper-serials-sheet" class="td-print-sheet" aria-hidden="true">
              <.shipper_serial_label
                :for={serial <- @contents_serials}
                id={"shipper-serial-label-#{@contents_shipper.id}-#{dom_key(serial.serial)}"}
                class="printable-serial-label"
                product={@product}
                serial={serial}
              />
            </div>
          </:body>
          <:footer>
            <.td_button id="close-shipper-contents" label="Close" phx-click="close_contents" />
            <.td_button
              id={"export-shipper-serials-#{@contents_shipper.id}"}
              glyph="download-simple"
              label="Export serials CSV"
              href={~p"/manufacturer/sscc/#{@contents_shipper.id}/export"}
            />
            <.td_button
              id="print-shipper-serials-confirm"
              variant="primary"
              glyph="printer"
              label={"Print #{length(@contents_serials)} serial labels"}
              phx-hook="PrintAllLabels"
              data-print-target=".printable-serial-label"
              data-label-size="50mm 25mm"
              data-print-mode="clone"
              disabled={@contents_serials == []}
            />
          </:footer>
        </.td_modal>

        <ThamaniDawaWeb.ManufacturerSsccLive.Label.modal
          :if={@label_shipper}
          sscc={@label_shipper}
          product_name={@product.name}
          on_cancel={JS.push("close_label")}
        />
      </div>
    </Layouts.manufacturer_shell>
    """
  end

  attr :id, :string, required: true
  attr :product, :map, required: true
  attr :serial, :map, required: true
  attr :class, :string, default: nil

  defp shipper_serial_label(assigns) do
    ~H"""
    <div id={@id} class={["td-serial-label", @class]}>
      <canvas
        id={"#{@id}-datamatrix"}
        phx-hook="DataMatrix"
        phx-update="ignore"
        data-gs1-text={serial_gs1_text(@product, @serial)}
        class="td-serial-label-dm"
      ></canvas>
      <div class="td-serial-label-tx">
        <b>{@product.name}</b>
        <span>GTIN {@product.gtin}</span>
        <span>BATCH {@serial.batch}</span>
        <span>EXP {label_date(@serial.expiry_date)}</span>
        <span>SN {@serial.serial}</span>
      </div>
    </div>
    """
  end

  defp serial_gs1_text(product, serial) do
    "(01)#{gtin14(product)}(10)#{serial.batch}(11)#{date_ai(serial.production_date)}(17)#{date_ai(serial.expiry_date)}(21)#{serial.serial}"
  end

  defp gtin14(product), do: String.pad_leading(product.gtin, 14, "0")
  defp date_ai(nil), do: ""
  defp date_ai(date), do: Calendar.strftime(date, "%y%m%d")

  defp label_date(nil), do: ""
  defp label_date(date), do: Calendar.strftime(date, "%d.%m.%Y")

  defp dom_key(value), do: String.replace(value, ~r/[^A-Za-z0-9_-]/, "_")
end
