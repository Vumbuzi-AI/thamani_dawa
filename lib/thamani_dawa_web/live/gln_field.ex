defmodule ThamaniDawaWeb.GlnField do
  @moduledoc """
  TD GlnField (Doop `ckg2o1xqxy`): the one shared GLN search field for every
  form that picks a party. Typing a name or a GLN searches the organization's
  own sites, then its saved customers, then the GS1 directory, in that order.

  States: `:idle`, `:searching`, `:results`, `:verified` (an own site, or a
  party GS1 confirmed), `:unverified` (a saved customer GS1 does not know)
  and `:error` (GS1 unreachable; local matches still show).

  The chosen GLN is submitted with the surrounding form through a hidden
  input named `name`. The parent is told `{:gln_selected, id, party}` (nil
  when the search is edited again), as a message to the LiveView, or through
  `send_update/3` when `notify` is `{component_module, component_id}`.

  Options: `scope` (`:all`, default, `:sites` for own sites only, or `:gs1`
  for the GS1 directory only, as when adding a customer) and
  `exclude_gln` (hide one GLN, such as the ship-from site).
  """

  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Customers
  alias ThamaniDawa.Distributor.GlnLookup

  @limit 6

  def update(%{gln_resolved: result}, socket), do: {:ok, apply_resolved(socket, result)}

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:label, fn -> "GLN" end)
      |> assign_new(:hint, fn -> nil end)
      |> assign_new(:required, fn -> false end)
      |> assign_new(:scope, fn -> :all end)
      |> assign_new(:exclude_gln, fn -> nil end)
      |> assign_new(:notify, fn -> nil end)
      |> assign_new(:placeholder, fn -> "Search by name or GLN" end)
      |> assign_new(:results, fn -> [] end)
      |> assign_new(:gs1_error?, fn -> false end)

    socket =
      socket
      |> assign_new(:party, fn -> assigns[:selected] end)
      |> assign_new(:state, fn -> if assigns[:selected], do: :verified, else: :idle end)

    {:ok, assign_new(socket, :query, fn -> label_for(socket.assigns.party) end)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    query = String.trim(query)
    if socket.assigns.party, do: notify(socket, nil)
    socket = assign(socket, query: query, results: [], party: nil, gs1_error?: false)

    if String.length(query) < 2 do
      {:noreply, assign(socket, :state, :idle)}
    else
      %{organization_id: org_id, api_token: token, scope: scope, exclude_gln: exclude} =
        socket.assigns

      {:noreply,
       socket
       |> assign(:state, :searching)
       |> start_async(:search, fn -> {query, search(org_id, token, scope, exclude, query)} end)}
    end
  end

  def handle_event("select", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.results, &(&1.gln == gln)) do
      nil ->
        {:noreply, socket}

      %{source: :customer} = party ->
        token = socket.assigns.api_token

        {:noreply,
         socket
         |> assign(party: party, query: label_for(party), results: [], state: :searching)
         |> start_async(:resolve, fn -> {party, GlnLookup.resolve_destination(token, gln)} end)}

      party ->
        notify(socket, party)

        {:noreply,
         assign(socket, party: party, query: label_for(party), results: [], state: :verified)}
    end
  end

  def handle_event("clear", _params, socket) do
    if socket.assigns.party, do: notify(socket, nil)
    {:noreply, assign(socket, party: nil, query: "", results: [], state: :idle)}
  end

  def handle_async(:search, {:ok, {query, {results, gs1_error?}}}, socket) do
    if socket.assigns.query == query do
      state =
        cond do
          results != [] -> :results
          gs1_error? -> :error
          true -> :results
        end

      {:noreply, assign(socket, results: results, gs1_error?: gs1_error?, state: state)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:search, _result, socket),
    do: {:noreply, assign(socket, results: [], gs1_error?: true, state: :error)}

  def handle_async(:resolve, {:ok, {party, result}}, socket),
    do: {:noreply, apply_resolved(socket, {party, result})}

  def handle_async(:resolve, _result, socket),
    do: {:noreply, assign(socket, state: :error, gs1_error?: true)}

  defp apply_resolved(socket, {party, {:ok, resolved}}) do
    party = Map.merge(party, %{company: resolved.company || party.company, address: resolved.address || party.address, gs1_verified: true})
    notify(socket, party)
    assign(socket, party: party, state: :verified)
  end

  defp apply_resolved(socket, {party, {:error, :not_found}}) do
    assign(socket, party: Map.put(party, :gs1_verified, false), state: :unverified)
  end

  defp apply_resolved(socket, {party, {:error, _reason}}) do
    assign(socket, party: party, state: :error, gs1_error?: true)
  end

  @doc false
  def search(_organization_id, api_token, :gs1, _exclude_gln, query) do
    case GlnLookup.search_destination(api_token, query, @limit) do
      {:ok, results} -> {Enum.map(results, &Map.merge(&1, %{source: :gs1, gs1_verified: true})), false}
      {:error, _reason} -> {[], true}
    end
  end

  def search(organization_id, api_token, scope, exclude_gln, query) do
    sites =
      organization_id
      |> GlnLookup.search_origin(query, @limit)
      |> Enum.map(
        &%{gln: &1.gln, company: &1.name, address: &1.address, po_box: nil, site_id: &1.id, source: :site, gs1_verified: true}
      )

    if scope == :sites do
      {reject(sites, exclude_gln), false}
    else
      customers =
        organization_id
        |> Customers.list_customers()
        |> Enum.filter(&customer_match?(&1, query))
        |> Enum.take(@limit)
        |> Enum.map(
          &%{gln: &1.gln, company: &1.name, address: &1.address, po_box: nil, site_id: nil, source: :customer}
        )

      {gs1, gs1_error?} =
        case GlnLookup.search_destination(api_token, query, @limit) do
          {:ok, results} -> {Enum.map(results, &Map.merge(&1, %{source: :gs1, gs1_verified: true})), false}
          {:error, _reason} -> {[], true}
        end

      results =
        (sites ++ customers ++ gs1)
        |> Enum.uniq_by(& &1.gln)
        |> reject(exclude_gln)

      {results, gs1_error?}
    end
  end

  defp reject(results, nil), do: results
  defp reject(results, gln), do: Enum.reject(results, &(&1.gln == gln))

  defp customer_match?(%{gln: nil}, _query), do: false

  defp customer_match?(customer, query) do
    q = String.downcase(query)

    String.contains?(String.downcase(customer.name || ""), q) or
      String.contains?(customer.gln || "", q)
  end

  defp notify(%{assigns: %{notify: {module, id}}} = socket, party),
    do: send_update(module, id: id, gln_selected: {socket.assigns.id, party})

  defp notify(socket, party), do: send(self(), {:gln_selected, socket.assigns.id, party})

  defp label_for(nil), do: ""
  defp label_for(party), do: party.company || party.gln

  defp source_label(:site), do: "Your site"
  defp source_label(:customer), do: "Customer"
  defp source_label(_source), do: "GS1"

  defp status_text(:idle, _p), do: "Searches GS1"
  defp status_text(:searching, _p), do: "Searching"
  defp status_text(:results, _p), do: "Searching"
  defp status_text(:verified, %{source: :site}), do: "Your site"
  defp status_text(:verified, _p), do: "Verified"
  defp status_text(:unverified, _p), do: "Not in GS1"
  defp status_text(:error, _p), do: "GS1 unavailable"

  defp hint_text(:verified, %{source: :site}, _hint), do: "One of your own sites."
  defp hint_text(:verified, _party, _hint), do: "GS1 confirmed this GLN."

  defp hint_text(:unverified, _party, _hint),
    do: "GS1 has no record of this GLN. Pick a party GS1 knows to continue."

  defp hint_text(:error, _party, _hint),
    do: "The GS1 directory is unavailable. Your sites and saved customers still show. Try again in a moment."

  defp hint_text(_state, _party, nil),
    do: "Your sites and saved customers are searched first, then the GS1 directory."

  defp hint_text(_state, _party, hint), do: hint

  def render(assigns) do
    ~H"""
    <div id={@id} class="td-gln-field" data-state={@state}>
      <label for={"#{@id}-input"} class="td-gln-lb">
        {@label}<span :if={@required} aria-hidden="true" class="td-req">*</span>
      </label>
      <input type="hidden" name={@name} value={@state == :verified && @party && @party.gln} />
      <div class="td-gln-box">
        <span class="td-gln-ic"><.td_icon name="magnifying-glass" /></span>
        <input
          id={"#{@id}-input"}
          type="search"
          value={@query}
          phx-keyup="search"
          phx-debounce="300"
          phx-target={@myself}
          autocomplete="off"
          placeholder={@placeholder}
          class="td-gln-v"
          role="combobox"
          aria-expanded={to_string(@state == :results)}
          aria-controls={"#{@id}-results"}
        />
        <span class="td-gln-pill"><i class="td-gln-dot"></i><span>{status_text(@state, @party)}</span></span>
      </div>
      <div :if={@state == :results} id={"#{@id}-results"} class="td-gln-res" role="listbox">
        <button
          :for={party <- @results}
          id={"#{@id}-option-#{party.gln}"}
          type="button"
          role="option"
          class="td-gln-result"
          phx-click="select"
          phx-value-gln={party.gln}
          phx-target={@myself}
        >
          <span class="td-gln-result-g">
            <b>{party.company}</b>
            <span>{party.address || "No address on file"}</span>
          </span>
          <span class="td-gln-result-r">
            <span class="td-mono">{party.gln}</span>
            <span class="td-gln-src">{source_label(party.source)}</span>
          </span>
        </button>
        <p :if={@results == []} class="td-gln-none">
          Nothing matches “{@query}” in your sites, customers or GS1.
        </p>
        <p :if={@gs1_error? and @results != []} class="td-gln-none">
          GS1 is unavailable, so only your sites and customers are shown.
        </p>
      </div>
      <div :if={@state in [:verified, :unverified] and @party} class="td-gln-party">
        <span>{@party.company}{@party.address && " · #{@party.address}"}{@party.source == :customer && " · saved customer"}</span>
        <span class="td-mono">{@party.gln}</span>
      </div>
      <span class="td-gln-hint">{hint_text(@state, @party, @hint)}</span>
    </div>
    """
  end
end
