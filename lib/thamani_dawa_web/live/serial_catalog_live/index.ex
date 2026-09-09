defmodule ThamaniDawaWeb.SerialCatalogLive.Index do
  @moduledoc """
  The serialisation product list — Screen A of ui.md §4, and the module's
  landing page.

  Each row is a GTIN this organization serialises, with how many SSCCs and
  serialised codes have been issued against it and the two generation entry
  points (`+ SSCC`, `+ Serial`). The count badges open the results those runs
  produced; viewing them stays available whatever the allowance state, because
  only entering a generation flow is guarded (ui.md §2).

  New GTINs are looked up against GS1 first. The lookup **previews only**
  (§2.4.9): the row is written when someone presses Add, never when they
  search. That is why the found item is held in `@preview` rather than being
  saved on arrival.

  Search and page live in the URL so Back returns the member to the same list
  position (ui.md §4).
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Gs1Api.Error
  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.SerialCatalog.CatalogItem
  alias ThamaniDawa.Serialisation

  @sources [{"Local (we own this GTIN)", "local"}, {"External (distributed)", "external"}]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:source_filter, "")
     |> assign(:sources, @sources)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0, page_size: 10})
     |> assign(:counts, %{})
     |> reset_lookup()}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:page, page_param(params))
      |> assign(:search, Map.get(params, "search", ""))
      |> assign(:source_filter, Map.get(params, "source", ""))
      |> reload_items()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp page_param(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {page, _rest} when page > 0 -> page
      _other -> 1
    end
  end

  defp apply_action(socket, :new), do: reset_lookup(socket)
  defp apply_action(socket, :index), do: reset_lookup(socket)

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns, search: search, page: 1))}
  end

  def handle_event("apply_filters", %{"filters" => %{"source" => source}}, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns, source: source, page: 1))}
  end

  def handle_event("clear_chip", _params, socket) do
    {:noreply, push_patch(socket, to: list_path(socket.assigns, source: "", page: 1))}
  end

  def handle_event("gtin_change", %{"gtin" => gtin}, socket) do
    {:noreply, assign(socket, :gtin_input, gtin)}
  end

  def handle_event("lookup", %{"gtin" => raw_gtin}, socket) do
    scope = socket.assigns.current_scope

    case String.trim(raw_gtin) do
      "" ->
        {:noreply, assign(socket, :lookup, {:error, :invalid_gtin})}

      trimmed ->
        {:noreply,
         socket
         |> assign(:lookup, :searching)
         |> assign(:preview, nil)
         |> start_async(:lookup, fn -> SerialCatalog.preview_item(scope, trimmed) end)}
    end
  end

  def handle_event("add", _params, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case socket.assigns.preview do
      nil ->
        {:noreply, socket}

      %CatalogItem{} = item ->
        case SerialCatalog.ensure_item(organization_id, item) do
          {:ok, _item} ->
            {:noreply,
             socket
             |> put_flash(:info, "GTIN added to the serialisation catalog.")
             |> push_patch(to: ~p"/org/serialisation")}

          {:error, changeset} ->
            {:noreply, assign(socket, :lookup, {:error, changeset_message(changeset)})}
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    item = SerialCatalog.get_item!(organization_id, id)

    case SerialCatalog.delete_item(item) do
      {:ok, _item} ->
        {:noreply, socket |> put_flash(:info, "GTIN removed.") |> reload_items()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not remove that GTIN.")}
    end
  end

  def handle_async(:lookup, {:ok, {:ok, item, origin}}, socket) do
    {:noreply,
     socket
     |> assign(:preview, item)
     |> assign(:lookup, {:found, origin})}
  end

  def handle_async(:lookup, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:preview, nil) |> assign(:lookup, {:error, reason})}
  end

  def handle_async(:lookup, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:preview, nil)
     |> assign(:lookup, {:error, :provider_error})}
  end

  defp reset_lookup(socket) do
    socket
    |> assign(:gtin_input, "")
    |> assign(:lookup, :idle)
    |> assign(:preview, nil)
  end

  defp reload_items(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    page_result =
      SerialCatalog.list_items_paginated(organization_id, socket.assigns.page,
        search: socket.assigns.search,
        source: socket.assigns.source_filter
      )

    counts =
      Serialisation.code_counts_by_gtin(
        organization_id,
        Enum.map(page_result.entries, & &1.gtin)
      )

    socket
    |> assign(:page_info, page_result)
    |> assign(:counts, counts)
    |> stream(:items, page_result.entries, reset: true)
  end

  defp count_for(counts, gtin, key) do
    counts |> Map.get(gtin, %{}) |> Map.get(key, 0)
  end

  # The list's own address, so Back and the results screens can return the
  # member to the search and page they left (ui.md §4).
  defp list_path(state, overrides) do
    params =
      %{
        "search" => state.search,
        "source" => state.source_filter,
        "page" => state.page
      }
      |> Map.merge(Map.new(overrides, fn {key, value} -> {to_string(key), value} end))
      |> Enum.reject(fn {_key, value} -> value in [nil, "", 1, "1"] end)
      |> Map.new()

    if params == %{}, do: ~p"/org/serialisation", else: ~p"/org/serialisation?#{params}"
  end

  defp results_path(state, gtin, :sscc),
    do: ~p"/org/serialisation/#{gtin}/batches?#{return_params(state)}"

  defp results_path(state, gtin, :serialised),
    do: ~p"/org/serialisation/#{gtin}/groups?#{return_params(state)}"

  defp generate_path(gtin, :sscc), do: ~p"/org/serialisation/#{gtin}/sscc/new"
  defp generate_path(gtin, :serialised), do: ~p"/org/serialisation/#{gtin}/serials/new"

  defp return_params(state) do
    %{"return_to" => list_path(state, [])}
  end

  defp item_name(%CatalogItem{name: name}) when is_binary(name) and name != "", do: name
  defp item_name(_item), do: "(unnamed)"

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")
  defp format_date(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")

  defp changeset_message(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
    |> Enum.map(fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end

  # GS1's own copy is member-appropriate and has been through support, so it is
  # shown verbatim (§7). Only locally-detected problems get our own wording.
  defp lookup_message({:found, :catalog}),
    do: {:warning, "This GTIN is already in your catalog."}

  defp lookup_message({:found, :gs1}),
    do: {:info, "Found on GS1 — review the details, then add it to your catalog."}

  defp lookup_message({:error, :invalid_gtin}),
    do: {:error, "Enter a valid GTIN — a numeric code of 8, 12, 13, or 14 digits."}

  defp lookup_message({:error, %Error{} = error}), do: {:error, error.message}
  defp lookup_message({:error, message}) when is_binary(message), do: {:error, message}
  defp lookup_message({:error, _reason}), do: {:error, "Couldn't reach GS1. Please try again."}
  defp lookup_message(_lookup), do: nil

  defp message_classes(:info), do: "bg-sky-50 border-sky-200 text-sky-800"
  defp message_classes(:warning), do: "bg-amber-50 border-amber-200 text-amber-800"
  defp message_classes(:error), do: "bg-rose-50 border-rose-200 text-rose-800"

  attr :id, :string, required: true
  attr :count, :integer, required: true
  attr :navigate, :string, required: true
  attr :label, :string, required: true
  attr :tone, :string, required: true

  # A zero count is rendered as a disabled badge rather than a link: ui.md §4
  # is explicit that it must not imply results exist.
  defp count_badge(%{count: 0} = assigns) do
    ~H"""
    <span
      id={@id}
      class="inline-flex min-w-11 items-center justify-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-400"
      title="Nothing generated for this GTIN yet"
    >
      <.icon name="hero-eye-slash" class="size-3.5" />
      <span class="sr-only">{@label} —</span> 0
    </span>
    """
  end

  defp count_badge(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={@navigate}
      aria-label={@label}
      class={[
        "inline-flex min-w-11 items-center justify-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2",
        @tone == "sscc" &&
          "bg-indigo-50 text-thamani-forest hover:bg-thamani-forest hover:text-white focus-visible:ring-thamani-accent",
        @tone == "serial" &&
          "bg-emerald-50 text-emerald-700 hover:bg-emerald-600 hover:text-white focus-visible:ring-emerald-500"
      ]}
    >
      <.icon name="hero-eye" class="size-3.5" />
      {@count}
    </.link>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/serialisation"}
    >
      <.header icon="hero-qr-code">
        Serialisation catalog
        <:subtitle>
          The GTINs you generate SSCCs and serialised Data Matrix codes for. Every code is issued by GS1.
        </:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/org/serialisation/new"}>+ Add GTIN</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="serial-catalog-search">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by GTIN, name, or company"
            />
          </form>

          <.filter_drawer
            id="serial-catalog-filters"
            title="Filter catalog"
            apply_event="apply_filters"
            active_count={if @source_filter == "", do: 0, else: 1}
          >
            <:group label="Source">
              <.input
                type="select"
                name="filters[source]"
                value={@source_filter}
                options={@sources}
                prompt="All sources"
              />
            </:group>
            <:chip
              :if={@source_filter != ""}
              label={"Source: #{@source_filter}"}
              clear={JS.push("clear_chip")}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="serial-catalog-modal"
        show
        on_cancel={JS.patch(~p"/org/serialisation")}
      >
        <div class="space-y-6">
          <div>
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
              Add a GTIN
            </h2>
            <p class="mt-1 text-sm text-slate-600">
              Look the GTIN up on GS1 first. Nothing is saved to your catalog until you press Add.
            </p>
          </div>

          <form id="serial-gtin-form" phx-submit="lookup" phx-change="gtin_change" class="space-y-3">
            <input
              type="text"
              name="gtin"
              value={@gtin_input}
              placeholder="Scan or type a GTIN (e.g., 6161100000015)"
              class="thamani-input w-full"
              autofocus
              inputmode="numeric"
            />

            <.button
              type="submit"
              variant="primary"
              class="w-full"
              disabled={@gtin_input == ""}
              phx-disable-with="Looking up..."
            >
              Look up on GS1
            </.button>
          </form>

          <div :if={@lookup == :searching} class="flex items-center gap-2">
            <.icon name="hero-arrow-path" class="size-4 text-sky-600 motion-safe:animate-spin" />
            <p class="text-sm text-sky-700 font-medium">Checking with GS1...</p>
          </div>

          <% message = lookup_message(@lookup) %>
          <div
            :if={message}
            class={["rounded-lg border p-3 text-sm", message_classes(elem(message, 0))]}
          >
            {elem(message, 1)}
          </div>

          <div :if={@preview} class="rounded-lg border border-slate-200 p-4 space-y-2">
            <dl class="grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="text-slate-500">GTIN</dt>
                <dd class="font-medium text-thamani-forest">{@preview.gtin}</dd>
              </div>
              <div>
                <dt class="text-slate-500">Name</dt>
                <dd class="font-medium text-thamani-forest">{item_name(@preview)}</dd>
              </div>
              <div>
                <dt class="text-slate-500">Company</dt>
                <dd class="text-thamani-forest">{@preview.comp_name || "—"}</dd>
              </div>
              <div>
                <dt class="text-slate-500">Unit of measure</dt>
                <dd class="text-thamani-forest">{@preview.uom || "—"}</dd>
              </div>
            </dl>

            <.button
              :if={@lookup != {:found, :catalog}}
              variant="primary"
              class="w-full"
              phx-click="add"
              phx-disable-with="Adding..."
            >
              Add to catalog
            </.button>
          </div>
        </div>
      </.modal>

      <.table id="serial-catalog" rows={@streams.items}>
        <:col :let={{_id, item}} label="GTIN">
          <span class="font-mono">{item.gtin}</span>
        </:col>
        <:col :let={{_id, item}} label="Product">{item_name(item)}</:col>
        <:col :let={{_id, item}} label="Description">{item.description || "—"}</:col>
        <:col :let={{_id, item}} label="Created at">{format_date(item.inserted_at)}</:col>
        <:col :let={{_id, item}} label="SSCC">
          <.count_badge
            id={"show-ssccs-#{item.id}"}
            count={count_for(@counts, item.gtin, :ssccs)}
            navigate={results_path(assigns, item.gtin, :sscc)}
            label={"View SSCC batches for GTIN #{item.gtin}"}
            tone="sscc"
          />
        </:col>
        <:col :let={{_id, item}} label="Serials">
          <.count_badge
            id={"show-serialised-#{item.id}"}
            count={count_for(@counts, item.gtin, :serialised)}
            navigate={results_path(assigns, item.gtin, :serialised)}
            label={"View serialised groups for GTIN #{item.gtin}"}
            tone="serial"
          />
        </:col>
        <:action :let={{_id, item}}>
          <div class="flex flex-wrap items-center gap-2">
            <.link
              id={"generate-sscc-#{item.id}"}
              navigate={generate_path(item.gtin, :sscc)}
              class="inline-flex items-center gap-1.5 rounded-full bg-thamani-forest px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-thamani-forest/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
            >
              <.icon name="hero-plus-circle" class="size-3.5" />
              SSCC<span class="sr-only">for GTIN {item.gtin}</span>
            </.link>
            <.link
              id={"generate-serial-#{item.id}"}
              navigate={generate_path(item.gtin, :serialised)}
              class="inline-flex items-center gap-1.5 rounded-full bg-emerald-600 px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-emerald-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500 focus-visible:ring-offset-2"
            >
              <.icon name="hero-plus-circle" class="size-3.5" />
              Serial<span class="sr-only">for GTIN {item.gtin}</span>
            </.link>
            <.button
              variant="ghost"
              phx-click="delete"
              phx-value-id={item.id}
              data-confirm="Remove this GTIN from the serialisation catalog? Codes already issued are kept."
              class="px-3 py-1.5 text-xs"
              id={"btn-remove-#{item.id}"}
            >
              Remove
            </.button>
          </div>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-qr-code"
            title={
              if @search != "" or @source_filter != "",
                do: "No GTINs match your search or filters",
                else: "No GTINs in the serialisation catalog yet"
            }
          >
            {if @search != "" or @source_filter != "",
              do: "Try a different search term, or clear the applied filters.",
              else: "Add a GTIN to start generating SSCCs and serialised codes for it."}
          </.blank_state>
        </:empty_state>
      </.table>

      <.pagination page={@page_info} path={list_path(assigns, page: nil)} />
    </Layouts.org_shell>
    """
  end
end
