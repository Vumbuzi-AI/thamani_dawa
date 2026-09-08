defmodule ThamaniDawaWeb.SerialCatalogLive.Index do
  @moduledoc """
  The serialisation catalog screen (serialisation.md §7, "Catalog listing").

  Lists the GTINs this organization serialises, each with how many SSCCs and
  serialised codes have been issued against it, and lets a new GTIN be looked
  up against GS1 before being added.

  The lookup **previews only** (§2.4.9): the row is written when someone
  presses Add, never when they search. That is why the found item is held in
  `@preview` rather than being saved on arrival.
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
     |> assign(:selected_item, nil)
     |> assign(:code_kind, nil)
     |> assign(:selected_count, 0)
     |> stream(:code_details, [])
     |> reset_lookup()
     |> reload_items()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))

    socket =
      socket
      |> assign(:page, page)
      |> reload_items()

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new), do: reset_lookup(socket)
  defp apply_action(socket, :index), do: reset_lookup(socket)

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload_items()}
  end

  def handle_event("apply_filters", %{"filters" => %{"source" => source}}, socket) do
    {:noreply, socket |> assign(:source_filter, source) |> assign(:page, 1) |> reload_items()}
  end

  def handle_event("clear_chip", _params, socket) do
    {:noreply, socket |> assign(:source_filter, "") |> assign(:page, 1) |> reload_items()}
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

  def handle_event("show_codes", %{"id" => id, "kind" => kind}, socket)
      when kind in ["sscc", "serialised"] do
    organization_id = socket.assigns.current_scope.organization_id
    item = SerialCatalog.get_item!(organization_id, id)

    codes =
      case kind do
        "sscc" -> Serialisation.list_ssccs_for_gtin(organization_id, item.gtin)
        "serialised" -> Serialisation.list_serialised_codes(organization_id, item.gtin)
      end

    {:noreply,
     socket
     |> assign(:selected_item, item)
     |> assign(:code_kind, String.to_existing_atom(kind))
     |> assign(:selected_count, length(codes))
     |> stream(:code_details, codes, reset: true)}
  end

  def handle_event("close_codes", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_item, nil)
     |> assign(:code_kind, nil)
     |> assign(:selected_count, 0)
     |> stream(:code_details, [], reset: true)}
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

  defp item_name(%CatalogItem{name: name}) when is_binary(name) and name != "", do: name
  defp item_name(_item), do: "(unnamed)"

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

  defp code_title(:sscc), do: "SSCC logistics units"
  defp code_title(:serialised), do: "Serialised trade items"

  defp code_value(:sscc, code), do: code.code
  defp code_value(:serialised, code), do: code.serial

  defp code_meta(:sscc, code), do: code.level |> Atom.to_string() |> String.capitalize()
  defp code_meta(:serialised, _code), do: "Serialised Data Matrix"

  defp code_date(:sscc, code), do: code.issued_at || code.inserted_at
  defp code_date(:serialised, code), do: code.inserted_at

  defp format_code_date(nil), do: "—"
  defp format_code_date(date), do: Calendar.strftime(date, "%d %b %Y, %H:%M")

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

      <.modal
        :if={@selected_item}
        id="serial-code-details-modal"
        show
        on_cancel={JS.push("close_codes")}
      >
        <div class="space-y-5">
          <div class="pr-8">
            <div class="flex items-center gap-2">
              <span class="rounded-full bg-thamani-lavender px-2.5 py-1 text-xs font-semibold text-thamani-forest">
                {@selected_count}
              </span>
              <p class="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500">
                {code_title(@code_kind)}
              </p>
            </div>
            <h2 class="mt-2 text-2xl font-medium tracking-tight text-thamani-forest">
              {item_name(@selected_item)}
            </h2>
            <p class="mt-1 font-mono text-sm text-slate-600">GTIN {@selected_item.gtin}</p>
          </div>

          <div
            id="serial-code-details"
            phx-update="stream"
            class="max-h-[26rem] space-y-2 overflow-y-auto pr-1"
          >
            <div
              id="serial-code-details-empty"
              class="hidden only:flex flex-col items-center rounded-xl border border-dashed border-slate-300 px-6 py-10 text-center"
            >
              <.icon name="hero-qr-code" class="size-8 text-slate-400" />
              <p class="mt-3 text-sm font-medium text-slate-700">No codes issued yet</p>
              <p class="mt-1 text-xs text-slate-500">
                Generated codes for this GTIN will appear here.
              </p>
            </div>

            <div
              :for={{id, code} <- @streams.code_details}
              id={id}
              class="group rounded-xl border border-slate-200 bg-white p-4 transition hover:border-thamani-accent/40 hover:shadow-sm"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <p class="break-all font-mono text-sm font-semibold text-slate-900">
                    {code_value(@code_kind, code)}
                  </p>
                  <p class="mt-1 text-xs text-slate-500">{code_meta(@code_kind, code)}</p>
                </div>
                <.icon name="hero-check-badge" class="size-5 shrink-0 text-emerald-600" />
              </div>
              <div class="mt-3 flex flex-wrap gap-x-5 gap-y-1 border-t border-slate-100 pt-3 text-xs text-slate-500">
                <span>Batch
                <strong class="font-medium text-slate-700">{code.shipment.batch || "—"}</strong></span>
                <span>Issued
                <strong class="font-medium text-slate-700">{format_code_date(
                  code_date(@code_kind, code)
                )}</strong></span>
              </div>
            </div>
          </div>

          <.button variant="ghost" class="w-full" phx-click="close_codes">
            Close
          </.button>
        </div>
      </.modal>

      <.table id="serial-catalog" rows={@streams.items}>
        <:col :let={{_id, item}} label="GTIN">{item.gtin}</:col>
        <:col :let={{_id, item}} label="Name">{item_name(item)}</:col>
        <:col :let={{_id, item}} label="Company">{item.comp_name || "—"}</:col>
        <:col :let={{_id, item}} label="Source">
          <.status_badge status={item.source} />
        </:col>
        <:col :let={{_id, item}} label="SSCCs">
          <button
            id={"show-ssccs-#{item.id}"}
            type="button"
            phx-click="show_codes"
            phx-value-id={item.id}
            phx-value-kind="sscc"
            class="inline-flex min-w-9 items-center justify-center rounded-full bg-indigo-50 px-2.5 py-1 text-xs font-semibold text-thamani-forest transition hover:bg-thamani-forest hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent"
            aria-label={"View SSCCs for #{item.gtin}"}
          >
            {count_for(@counts, item.gtin, :ssccs)}
          </button>
        </:col>
        <:col :let={{_id, item}} label="Serialised">
          <button
            id={"show-serialised-#{item.id}"}
            type="button"
            phx-click="show_codes"
            phx-value-id={item.id}
            phx-value-kind="serialised"
            class="inline-flex min-w-9 items-center justify-center rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700 transition hover:bg-emerald-600 hover:text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-emerald-500"
            aria-label={"View serialised codes for #{item.gtin}"}
          >
            {count_for(@counts, item.gtin, :serialised)}
          </button>
        </:col>
        <:action :let={{_id, item}}>
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

      <.pagination page={@page_info} path={~p"/org/serialisation"} />
    </Layouts.org_shell>
    """
  end
end
