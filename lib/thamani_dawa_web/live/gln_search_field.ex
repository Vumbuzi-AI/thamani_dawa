defmodule ThamaniDawaWeb.GlnSearchField do
  @moduledoc """
  A GLN picker backed by the GS1 all-GLN directory search
  (`GlnLookup.search_destination/2`). Users never type a GLN by hand: they
  search by GLN, company or address and pick a result. The chosen GLN is
  submitted with the surrounding form through a hidden input named `name`,
  and the parent LiveView is told via `{:gln_selected, id, party}` (or
  `{:gln_selected, id, nil}` once the search is edited again).

  A LiveComponent because each picker owns its own async search state and
  several pages embed it.
  """

  use ThamaniDawaWeb, :live_component

  alias ThamaniDawa.Distributor.GlnLookup

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:label, fn -> "GLN" end)
      |> assign_new(:required, fn -> false end)
      |> assign_new(:selected, fn -> assigns[:selected] end)
      |> assign_new(:results, fn -> [] end)
      |> assign_new(:status, fn -> :idle end)

    {:ok, assign_new(socket, :query, fn -> label_for(socket.assigns.selected) end)}
  end

  def handle_event("search", %{"value" => query}, socket) do
    query = String.trim(query)
    if socket.assigns.selected, do: notify(socket, nil)

    socket = assign(socket, query: query, results: [], selected: nil)

    if String.length(query) < 2 do
      {:noreply, assign(socket, :status, :idle)}
    else
      api_token = socket.assigns.api_token

      {:noreply,
       socket
       |> assign(:status, :searching)
       |> start_async(:search, fn -> {query, GlnLookup.search_destination(api_token, query)} end)}
    end
  end

  def handle_event("select", %{"gln" => gln}, socket) do
    case Enum.find(socket.assigns.results, &(&1.gln == gln)) do
      nil ->
        {:noreply, socket}

      party ->
        notify(socket, party)

        {:noreply,
         assign(socket, selected: party, query: label_for(party), results: [], status: :selected)}
    end
  end

  def handle_async(:search, {:ok, {query, {:ok, results}}}, socket) do
    if socket.assigns.query == query,
      do: {:noreply, assign(socket, results: results, status: :complete)},
      else: {:noreply, socket}
  end

  def handle_async(:search, _result, socket),
    do: {:noreply, assign(socket, results: [], status: :unavailable)}

  defp notify(socket, party), do: send(self(), {:gln_selected, socket.assigns.id, party})

  defp label_for(nil), do: ""
  defp label_for(party), do: "#{party.gln} · #{party.company}"

  def render(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <label for={"#{@id}-input"} class="thamani-label">
        {@label}<span :if={@required} aria-hidden="true" class="ml-0.5 text-red-700">*</span>
      </label>
      <input type="hidden" name={@name} value={@selected && @selected.gln} />
      <div class="relative">
        <input
          id={"#{@id}-input"}
          type="search"
          value={@query}
          phx-keyup="search"
          phx-debounce="300"
          phx-target={@myself}
          autocomplete="off"
          placeholder="Search the GS1 directory by GLN, company, or address"
          class="thamani-input w-full"
        />
        <div
          :if={@results != []}
          id={"#{@id}-results"}
          role="listbox"
          class="absolute z-[70] mt-1 max-h-56 w-full overflow-y-auto rounded-xl border border-thamani-stone bg-td-surface py-1 shadow-lg"
        >
          <button
            :for={party <- @results}
            id={"#{@id}-option-#{party.gln}"}
            type="button"
            role="option"
            phx-click="select"
            phx-value-gln={party.gln}
            phx-target={@myself}
            class="block w-full px-3 py-2 text-left text-sm transition hover:bg-td-hover"
          >
            <span class="block font-mono font-semibold text-thamani-forest">{party.gln}</span>
            <span class="block text-xs text-thamani-pewter">
              {party.company} · {party.address || "—"}
            </span>
          </button>
        </div>
      </div>
      <p :if={String.length(@query) == 1} class="text-xs text-thamani-pewter">
        Type at least 2 characters to search the GS1 GLN directory.
      </p>
      <p :if={@status == :searching} class="text-xs text-thamani-pewter">
        <.icon name="hero-arrow-path" class="inline size-3.5 motion-safe:animate-spin" />
        Searching GS1 GLNs…
      </p>
      <p
        :if={@status == :complete and @results == []}
        class="rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800"
      >
        No GS1 GLNs match this search.
      </p>
      <p :if={@status == :unavailable} class="text-xs text-red-700">
        The GS1 GLN directory is unavailable. Try again in a moment.
      </p>
      <p
        :if={@selected}
        class="inline-flex items-center gap-1.5 rounded-lg bg-thamani-lime/30 px-3 py-2 text-xs font-semibold text-thamani-forest"
      >
        <.icon name="hero-check-circle" class="size-4" /> Selected from the GS1 directory
      </p>
    </div>
    """
  end
end
