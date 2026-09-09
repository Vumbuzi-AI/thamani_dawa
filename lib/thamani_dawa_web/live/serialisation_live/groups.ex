defmodule ThamaniDawaWeb.SerialisationLive.Groups do
  @moduledoc """
  Screens D, E, F and G of ui.md: serialised-generation results for one GTIN,
  grouped by pallet SSCC, plus the shipper, primary-serial and single-label
  modals opened from a group card.

  The shipper and primary views are two tabs of one modal (§8) — switching tabs
  patches the URL rather than closing and refetching, so the group metadata
  already on screen stays put.

  Card counts and tab counts come from the same query
  (`Serialisation.list_groups_for_gtin/4`), which is what keeps a card claiming
  "8 Primary serials" and a tab reading "Primary (8)" from ever disagreeing.
  """

  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.SerialLabelComponents

  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.Serialisation
  alias ThamaniDawa.Serialisation.Label

  @serial_page_size 25

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:gtin, gtin)
     |> assign(:item, SerialCatalog.get_item_by_gtin(organization_id, gtin))
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:return_to, ~p"/org/serialisation")
     |> assign(:modal, nil)
     |> assign(:group, nil)
     |> assign(:group_counts, %{shippers: 0, primaries: 0})
     |> assign(:shipper_id, nil)
     |> assign(:shippers, [])
     |> assign(:serial_page, 1)
     |> assign(:serials, nil)}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:search, Map.get(params, "search", ""))
      |> assign(:page, integer_param(params, "page", 1))
      |> assign(:serial_page, integer_param(params, "serial_page", 1))
      |> assign(:return_to, Map.get(params, "return_to", ~p"/org/serialisation"))
      |> load_groups()
      |> load_modal(params)

    {:noreply, socket}
  end

  defp integer_param(params, key, default) do
    case Integer.parse(Map.get(params, key, "")) do
      {value, _rest} when value > 0 -> value
      _other -> default
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: groups_path(socket.assigns, search: search, page: 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_patch(socket, to: groups_path(socket.assigns, search: "", page: 1))}
  end

  defp load_groups(socket) do
    page_result =
      Serialisation.list_groups_for_gtin(
        socket.assigns.current_scope.organization_id,
        socket.assigns.gtin,
        socket.assigns.page,
        search: socket.assigns.search
      )

    socket
    |> assign(:page_info, page_result)
    |> assign(:groups, page_result.entries)
  end

  defp load_modal(socket, %{"modal" => modal, "sscc_id" => sscc_id} = params)
       when modal in ~w(shippers primary label) do
    organization_id = socket.assigns.current_scope.organization_id
    group = Serialisation.get_group!(organization_id, sscc_id)

    socket
    |> assign(:modal, modal)
    |> assign(:group, group)
    |> assign(:group_counts, counts_for(socket, group))
    |> assign(:shipper_id, shipper_id_param(params, group))
    |> load_modal_contents(modal, group)
  rescue
    Ecto.NoResultsError ->
      socket
      |> put_flash(:error, "That SSCC group is no longer available.")
      |> close_modal()
  end

  defp load_modal(socket, _params), do: close_modal(socket)

  # A shipper id is only honoured when it really belongs to this group, so a
  # hand-edited URL cannot pull another organization's serials into the modal.
  defp shipper_id_param(params, group) do
    with id when is_binary(id) <- Map.get(params, "shipper_id"),
         {parsed, ""} <- Integer.parse(id),
         true <- Enum.any?(group.children, &(&1.id == parsed)) do
      parsed
    else
      _other -> nil
    end
  end

  defp load_modal_contents(socket, "shippers", group) do
    assign(socket, :shippers, Serialisation.list_shipper_labels(group, socket.assigns.gtin))
  end

  defp load_modal_contents(socket, "primary", group) do
    serials =
      Serialisation.list_primary_labels(
        socket.assigns.current_scope.organization_id,
        group,
        page: socket.assigns.serial_page,
        page_size: @serial_page_size,
        shipper_id: socket.assigns.shipper_id
      )

    socket
    |> assign(:serials, serials)
    |> assign(:shippers, Serialisation.list_shipper_labels(group, socket.assigns.gtin))
  end

  defp load_modal_contents(socket, "label", _group), do: socket

  defp close_modal(socket) do
    socket
    |> assign(:modal, nil)
    |> assign(:group, nil)
    |> assign(:shipper_id, nil)
    |> assign(:shippers, [])
    |> assign(:serials, nil)
  end

  # The counts already loaded for the card, reused for the tabs so the two
  # cannot disagree (§7). A deep link that skipped the list counts them itself.
  defp counts_for(socket, group) do
    Enum.find_value(socket.assigns.groups, fn entry ->
      if entry.group.id == group.id, do: %{shippers: entry.shippers, primaries: entry.primaries}
    end) || Serialisation.group_totals(group)
  end

  defp groups_path(state, overrides) do
    overrides = Map.new(overrides, fn {key, value} -> {to_string(key), value} end)

    params =
      %{
        "search" => state.search,
        "page" => state.page,
        "return_to" => state.return_to,
        "modal" => state.modal,
        "sscc_id" => state.group && state.group.id,
        "shipper_id" => state.shipper_id,
        "serial_page" => state.serial_page
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {key, value} -> drop_param?(key, value) end)
      |> Map.new()

    ~p"/org/serialisation/#{state.gtin}/groups?#{params}"
  end

  defp drop_param?(_key, value) when value in [nil, ""], do: true
  defp drop_param?(key, value) when key in ~w(page serial_page), do: to_string(value) == "1"
  defp drop_param?(_key, _value), do: false

  defp modal_path(state, modal, group_id, extra \\ []) do
    groups_path(
      state,
      Keyword.merge(
        [modal: modal, sscc_id: group_id, shipper_id: nil, serial_page: 1],
        extra
      )
    )
  end

  defp close_path(state) do
    groups_path(state, modal: nil, sscc_id: nil, shipper_id: nil, serial_page: 1)
  end

  defp export_path(state, group_id) do
    ~p"/org/serialisation/#{state.gtin}/groups/#{group_id}/export"
  end

  defp product_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp product_name(_item), do: nil

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")

  defp pallet_label(group, gtin) do
    Label.pallet(group, group.shipment, gtin: gtin)
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/serialisation"}
    >
      <.header icon="hero-qr-code">
        {product_name(@item) || "Serialised results"}
        <:subtitle>Review SSCC groups, shipper labels, and primary serials.</:subtitle>
        <:actions>
          <span class="inline-flex items-center rounded-full bg-indigo-50 px-3 py-1.5 font-mono text-sm font-semibold text-thamani-forest">
            GTIN {@gtin}
          </span>
        </:actions>
        <:toolbar>
          <.link
            navigate={@return_to}
            class="inline-flex items-center gap-2 rounded-full bg-slate-800 px-4 py-2 text-sm font-semibold text-white transition hover:bg-slate-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Back to products
          </.link>

          <form phx-change="search" phx-submit="search" class="flex-1" id="group-search">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by SSCC, batch, GTIN, or order number..."
            />
          </form>

          <button
            type="button"
            phx-click="reset"
            class="inline-flex items-center gap-2 rounded-full border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
          >
            <.icon name="hero-arrow-path" class="size-4" /> Reset
          </button>
        </:toolbar>
      </.header>

      <div :if={@groups != []} class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
        <article
          :for={entry <- @groups}
          id={"group-#{entry.group.id}"}
          class="flex flex-col rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm"
        >
          <div class="flex items-center gap-3">
            <span class="flex size-10 items-center justify-center rounded-lg bg-indigo-50 text-thamani-forest">
              <.icon name="hero-qr-code" class="size-5" />
            </span>
            <div class="min-w-0">
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-slate-500">
                Pallet SSCC
              </p>
              <p class="break-all font-mono text-sm font-semibold text-thamani-forest">
                {entry.group.code}
              </p>
            </div>
          </div>

          <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
            <.field name="Batch" value={entry.group.shipment.batch} />
            <.field name="GTIN" value={@gtin} mono />
            <.field name="Produced" value={format_date(entry.group.shipment.production_date)} />
            <.field name="Expires" value={format_date(entry.group.shipment.expiry_date)} />
          </dl>

          <div class="mt-4 flex flex-wrap gap-2">
            <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
              {entry.shippers} Shippers
            </span>
            <span class="rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700">
              {entry.primaries} Primary serials
            </span>
          </div>

          <div class="mt-4 flex flex-wrap gap-2 border-t border-slate-100 pt-4">
            <.link
              id={"shippers-#{entry.group.id}"}
              patch={modal_path(assigns, "shippers", entry.group.id)}
              class="inline-flex items-center gap-1.5 rounded-full bg-thamani-forest px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-thamani-forest/90"
            >
              <.icon name="hero-truck" class="size-3.5" /> Shippers
            </.link>
            <.link
              id={"serials-#{entry.group.id}"}
              patch={modal_path(assigns, "primary", entry.group.id)}
              class="inline-flex items-center gap-1.5 rounded-full bg-sky-600 px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-sky-700"
            >
              <.icon name="hero-list-bullet" class="size-3.5" /> Serials
            </.link>
            <.link
              id={"label-#{entry.group.id}"}
              patch={modal_path(assigns, "label", entry.group.id)}
              class="inline-flex items-center gap-1.5 rounded-full border border-violet-200 bg-white px-3.5 py-1.5 text-xs font-semibold text-violet-700 transition hover:bg-violet-50"
            >
              <.icon name="hero-qr-code" class="size-3.5" /> Label
            </.link>
            <.link
              id={"export-#{entry.group.id}"}
              href={export_path(assigns, entry.group.id)}
              download
              class="inline-flex items-center gap-1.5 rounded-full bg-emerald-600 px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-emerald-700"
            >
              <.icon name="hero-arrow-down-tray" class="size-3.5" /> Export
            </.link>
          </div>
        </article>
      </div>

      <.blank_state
        :if={@groups == []}
        icon="hero-qr-code"
        title={
          if @search == "",
            do: "No serialised runs for this product yet",
            else: "No SSCC groups match your search"
        }
      >
        <:actions>
          <.link
            :if={@search == ""}
            navigate={~p"/org/serialisation/#{@gtin}/serials/new"}
            class="inline-flex items-center gap-2 rounded-full bg-emerald-600 px-4 py-2 text-sm font-semibold text-white"
          >
            <.icon name="hero-plus-circle" class="size-4" /> Generate serials
          </.link>
          <button
            :if={@search != ""}
            type="button"
            phx-click="reset"
            class="inline-flex items-center gap-2 rounded-full border border-slate-300 px-4 py-2 text-sm font-semibold text-slate-700"
          >
            Clear search
          </button>
        </:actions>
        {if @search == "",
          do: "Generate serialised Data Matrix codes and their SSCC groups will be listed here.",
          else: "Try a different SSCC, batch, or order number."}
      </.blank_state>

      <p class="mt-4 text-center text-sm text-slate-600">
        Page <strong>{@page_info.page_number}</strong>
        of <strong>{max(@page_info.total_pages, 1)}</strong>
        · {@page_info.total_entries} groups
      </p>

      <.pagination page={@page_info} path={groups_path(assigns, page: nil)} />

      <.modal
        :if={@modal in ["shippers", "primary"] && @group}
        id="serial-group-modal"
        show
        class="max-w-5xl"
        on_cancel={JS.patch(close_path(assigns))}
      >
        <div class="space-y-5">
          <div class="flex flex-wrap items-center gap-3 pr-8">
            <.icon
              name={if @modal == "shippers", do: "hero-truck", else: "hero-rectangle-stack"}
              class="size-6 text-thamani-forest"
            />
            <h2 class="text-xl font-medium tracking-tight text-thamani-forest">
              {if @modal == "shippers", do: "Shipper Serials", else: "Primary Serials"} - SSCC
              <span class="font-mono">{@group.code}</span>
            </h2>
            <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
              {if @modal == "shippers", do: @group_counts.shippers, else: @group_counts.primaries} items
            </span>
          </div>

          <div class="flex flex-wrap gap-2" role="tablist">
            <.link
              patch={modal_path(assigns, "shippers", @group.id)}
              role="tab"
              aria-selected={@modal == "shippers"}
              class={[
                "rounded-full px-4 py-1.5 text-sm font-semibold transition",
                @modal == "shippers" && "bg-sky-600 text-white",
                @modal != "shippers" && "border border-slate-300 text-slate-700 hover:bg-slate-50"
              ]}
            >
              Shipper ({@group_counts.shippers})
            </.link>
            <.link
              patch={modal_path(assigns, "primary", @group.id)}
              role="tab"
              aria-selected={@modal == "primary"}
              class={[
                "rounded-full px-4 py-1.5 text-sm font-semibold transition",
                @modal == "primary" && "bg-emerald-600 text-white",
                @modal != "primary" && "border border-slate-300 text-slate-700 hover:bg-slate-50"
              ]}
            >
              Primary ({@group_counts.primaries})
            </.link>
          </div>

          <div :if={@modal == "shippers"} class="max-h-[28rem] space-y-4 overflow-y-auto pr-1">
            <div
              :for={shipper <- @shippers}
              class="rounded-2xl border border-sky-100 bg-sky-50/40 p-4"
            >
              <.sscc_label id={"shipper-label-#{shipper.sscc.id}"} label={shipper.label}>
                <:actions>
                  <.label_actions label={"shipper SSCC #{shipper.sscc.code}"} />
                  <.link
                    patch={modal_path(assigns, "primary", @group.id, shipper_id: shipper.sscc.id)}
                    class="ml-auto inline-flex items-center gap-1.5 rounded-full border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-50"
                  >
                    <.icon name="hero-list-bullet" class="size-3.5" /> Serials ({shipper.serials})
                  </.link>
                </:actions>
              </.sscc_label>
            </div>

            <p
              :if={@shippers == []}
              class="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-600"
            >
              This SSCC group has no shipper units.
            </p>
          </div>

          <div :if={@modal == "primary"} class="space-y-4">
            <p :if={@shipper_id} class="rounded-lg bg-sky-50 px-3 py-2 text-sm text-sky-800">
              Showing only the serials assigned to the selected shipper.
              <.link patch={modal_path(assigns, "primary", @group.id)} class="font-semibold underline">
                Show all
              </.link>
            </p>

            <div class="grid max-h-[28rem] grid-cols-1 gap-4 overflow-y-auto pr-1 sm:grid-cols-2 xl:grid-cols-3">
              <.primary_serial_card
                :for={{label, index} <- Enum.with_index(@serials.entries)}
                id={"primary-serial-#{@serial_page}-#{index}"}
                label={label}
              />
            </div>

            <p
              :if={@serials.entries == []}
              class="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-600"
            >
              No primary serials here yet.
            </p>

            <.pagination
              :if={@serials.total_pages > 1}
              page={@serials}
              path={groups_path(assigns, serial_page: nil)}
              query_param="serial_page"
            />
          </div>

          <div class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-4">
            <p class="text-sm text-slate-600">
              {footer_count(assigns)}
            </p>
            <div class="flex flex-wrap items-center gap-2">
              <.link
                patch={close_path(assigns)}
                class="inline-flex items-center gap-2 rounded-full bg-slate-800 px-4 py-2 text-sm font-semibold text-white"
              >
                <.icon name="hero-x-mark" class="size-4" /> Close
              </.link>
              <.link
                href={export_path(assigns, @group.id)}
                download
                class="inline-flex items-center gap-2 rounded-full bg-emerald-600 px-4 py-2 text-sm font-semibold text-white"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" />
                {if @modal == "shippers", do: "Download All Shipper", else: "Download All Primary"}
              </.link>
            </div>
          </div>
        </div>
      </.modal>

      <.modal
        :if={@modal == "label" && @group}
        id="sscc-label-modal"
        show
        on_cancel={JS.patch(close_path(assigns))}
      >
        <div class="space-y-5">
          <div class="flex items-center gap-2 pr-8">
            <.icon name="hero-qr-code" class="size-5 text-violet-600" />
            <h2 class="text-xl font-medium tracking-tight text-thamani-forest">SSCC Label</h2>
          </div>

          <.sscc_label id="single-sscc-label" label={pallet_label(@group, @gtin)}>
            <:actions>
              <.label_actions label={"pallet SSCC #{@group.code}"} />
            </:actions>
          </.sscc_label>

          <div class="flex justify-end border-t border-slate-100 pt-4">
            <.link
              patch={close_path(assigns)}
              class="inline-flex items-center gap-2 rounded-full bg-slate-200 px-4 py-2 text-sm font-semibold text-slate-800"
            >
              Close
            </.link>
          </div>
        </div>
      </.modal>
    </Layouts.org_shell>
    """
  end

  defp footer_count(%{modal: "shippers"} = assigns) do
    "Showing #{length(assigns.shippers)} of #{assigns.group_counts.shippers} items"
  end

  defp footer_count(%{modal: "primary", serials: serials}) do
    "Showing #{length(serials.entries)} of #{serials.total_entries} items"
  end

  defp footer_count(_assigns), do: ""

  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :mono, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-[0.65rem] font-semibold uppercase tracking-[0.12em] text-slate-500">
        {@name}
      </dt>
      <dd class={["mt-0.5 text-sm text-slate-800", @mono && "font-mono"]}>
        {if @value in [nil, ""], do: "—", else: @value}
      </dd>
    </div>
    """
  end
end
