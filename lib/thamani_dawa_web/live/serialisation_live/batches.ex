defmodule ThamaniDawaWeb.SerialisationLive.Batches do
  @moduledoc """
  Screen B and Screen C of ui.md: the batches generated for one GTIN, and the
  pallet-label preview modal opened from a batch.

  Modal state lives in the URL (`?batch_id=…&modal=pallet-labels`) so a refresh
  or a shared link reopens the same labels (§14). Every load is re-scoped to
  the signed-in organization; the GTIN in the path is a filter, never an
  authorization.

  Viewing is never gated on allowance — only generation is (§2).
  """

  use ThamaniDawaWeb, :live_view

  import ThamaniDawaWeb.SerialLabelComponents

  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.Serialisation

  @page_size 25

  def mount(%{"gtin" => gtin}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:gtin, gtin)
     |> assign(:item, SerialCatalog.get_item_by_gtin(organization_id, gtin))
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:return_to, ~p"/org/serialisation")
     |> assign(:labels, [])
     |> assign(:label_search, "")
     |> assign(:page_size, @page_size)
     |> assign(:batch, nil)}
  end

  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:search, Map.get(params, "search", ""))
      |> assign(:page, page_param(params))
      |> assign(:return_to, Map.get(params, "return_to", ~p"/org/serialisation"))
      |> assign(:label_search, Map.get(params, "label_search", ""))
      |> assign(:page_size, page_size_param(params))
      |> load_batches()
      |> load_modal(params)

    {:noreply, socket}
  end

  defp page_param(params) do
    case Integer.parse(Map.get(params, "page", "1")) do
      {page, _rest} when page > 0 -> page
      _other -> 1
    end
  end

  defp page_size_param(params) do
    case Integer.parse(Map.get(params, "page_size", "")) do
      {size, _rest} when size in [10, 25, 50, 100] -> size
      _other -> @page_size
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: batches_path(socket.assigns, search: search, page: 1))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, push_patch(socket, to: batches_path(socket.assigns, search: "", page: 1))}
  end

  def handle_event("label_search", %{"label_search" => search}, socket) do
    {:noreply, push_patch(socket, to: batches_path(socket.assigns, label_search: search))}
  end

  def handle_event("page_size", %{"page_size" => size}, socket) do
    {:noreply, push_patch(socket, to: batches_path(socket.assigns, page_size: size))}
  end

  defp load_batches(socket) do
    page_result =
      Serialisation.list_batches_for_gtin(
        socket.assigns.current_scope.organization_id,
        socket.assigns.gtin,
        socket.assigns.page,
        search: socket.assigns.search
      )

    socket
    |> assign(:page_info, page_result)
    |> assign(:batches, page_result.entries)
  end

  defp load_modal(socket, %{"modal" => "pallet-labels", "batch_id" => batch_id}) do
    {labels, shipment} =
      Serialisation.list_pallet_labels(
        socket.assigns.current_scope.organization_id,
        batch_id,
        socket.assigns.gtin,
        search: socket.assigns.label_search
      )

    socket
    |> assign(:batch, shipment)
    |> assign(:labels, labels)
  rescue
    Ecto.NoResultsError ->
      socket
      |> put_flash(:error, "That batch is no longer available.")
      |> assign(:batch, nil)
      |> assign(:labels, [])
  end

  defp load_modal(socket, _params), do: socket |> assign(:batch, nil) |> assign(:labels, [])

  # One address for this screen, so search, page and modal state all survive a
  # refresh or a Back (§14).
  defp batches_path(state, overrides) do
    overrides = Map.new(overrides, fn {key, value} -> {to_string(key), value} end)

    params =
      %{
        "search" => state.search,
        "page" => state.page,
        "return_to" => state.return_to,
        "label_search" => state.label_search,
        "page_size" => state.page_size,
        "modal" => state.batch && "pallet-labels",
        "batch_id" => state.batch && state.batch.id
      }
      |> Map.merge(overrides)
      |> Enum.reject(fn {key, value} -> drop_param?(key, value) end)
      |> Map.new()

    ~p"/org/serialisation/#{state.gtin}/batches?#{params}"
  end

  # Defaults are left out of the URL so the common address stays readable; a
  # search term is never dropped, however page-like it looks.
  defp drop_param?(_key, value) when value in [nil, ""], do: true
  defp drop_param?("page", value), do: to_string(value) == "1"
  defp drop_param?("page_size", value), do: to_string(value) == to_string(@page_size)
  defp drop_param?(_key, _value), do: false

  defp labels_path(state, batch_id) do
    batches_path(state, modal: "pallet-labels", batch_id: batch_id, label_search: "")
  end

  defp close_path(state),
    do: batches_path(state, modal: nil, batch_id: nil, label_search: "")

  defp product_name(nil), do: nil
  defp product_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp product_name(_item), do: nil

  defp format_date(nil), do: "—"
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/serialisation"}
    >
      <.header icon="hero-archive-box">
        {product_name(@item) || "Generated batches"}
        <:subtitle>SSCC batches generated for this product, newest first.</:subtitle>
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

          <form phx-change="search" phx-submit="search" class="flex-1" id="batch-search">
            <.search_input
              name="search"
              value={@search}
              placeholder="Search by batch, GTIN, part number, or order number..."
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

      <div
        :if={@batches != []}
        class="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3"
        id="batch-cards"
      >
        <article
          :for={entry <- @batches}
          id={"batch-#{entry.shipment.id}"}
          class="flex flex-col rounded-2xl border border-thamani-stone bg-white p-5 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-center gap-3">
              <span class="flex size-10 items-center justify-center rounded-lg bg-indigo-50 text-thamani-forest">
                <.icon name="hero-archive-box" class="size-5" />
              </span>
              <div>
                <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-slate-500">
                  Batch
                </p>
                <p class="text-lg font-semibold text-thamani-forest">
                  {entry.shipment.batch || "—"}
                </p>
              </div>
            </div>
            <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-600">
              {entry.labels} labels
            </span>
          </div>

          <dl class="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
            <.field name="GTIN" value={@gtin} mono />
            <.field name="Part number" value={entry.shipment.customer_part_number} />
            <.field name="Produced" value={format_date(entry.shipment.production_date)} />
            <.field name="Expires" value={format_date(entry.shipment.expiry_date)} />
            <.field name="Order number" value={entry.shipment.order_number} accent />
          </dl>

          <p class="mt-4">
            <span class="inline-flex rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-semibold text-emerald-700">
              {entry.pallets} Pallets
            </span>
          </p>

          <div class="mt-4 border-t border-slate-100 pt-4">
            <.link
              id={"view-pallets-#{entry.shipment.id}"}
              patch={labels_path(assigns, entry.shipment.id)}
              class="inline-flex w-full items-center justify-center gap-2 rounded-full bg-thamani-forest px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-thamani-forest/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent focus-visible:ring-offset-2"
            >
              <.icon name="hero-inbox-stack" class="size-4" /> View pallets
            </.link>
          </div>
        </article>
      </div>

      <.blank_state
        :if={@batches == []}
        icon="hero-archive-box"
        title={
          if @search == "",
            do: "No SSCC batches for this product yet",
            else: "No batches match your search"
        }
      >
        <:actions>
          <.link
            :if={@search == ""}
            navigate={~p"/org/serialisation/#{@gtin}/sscc/new"}
            class="inline-flex items-center gap-2 rounded-full bg-thamani-forest px-4 py-2 text-sm font-semibold text-white"
          >
            <.icon name="hero-plus-circle" class="size-4" /> Generate an SSCC
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
          do: "Generate an SSCC for this GTIN and its batches will be listed here.",
          else: "Try a different batch, part number, or order number."}
      </.blank_state>

      <p class="mt-4 text-center text-sm text-slate-600">
        Page <strong>{@page_info.page_number}</strong>
        of <strong>{max(@page_info.total_pages, 1)}</strong>
        · {@page_info.total_entries} batches
      </p>

      <.pagination page={@page_info} path={batches_path(assigns, page: nil)} />

      <.modal
        :if={@batch}
        id="pallet-labels-modal"
        show
        class="max-w-5xl"
        on_cancel={JS.patch(close_path(assigns))}
      >
        <div class="space-y-5">
          <div class="flex items-center gap-3 pr-8">
            <span class="flex size-10 items-center justify-center rounded-lg bg-indigo-50 text-thamani-forest">
              <.icon name="hero-rectangle-stack" class="size-5" />
            </span>
            <div>
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-slate-500">
                SSCC label preview
              </p>
              <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">
                Pallet labels
              </h2>
            </div>
            <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
              Batch {@batch.batch}
            </span>
            <span class="rounded-full bg-indigo-50 px-2.5 py-1 text-xs font-semibold text-thamani-forest">
              {length(@labels)} {if length(@labels) == 1, do: "item", else: "items"}
            </span>
          </div>

          <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
            <form phx-change="label_search" class="flex-1" id="pallet-label-search">
              <.search_input
                name="label_search"
                value={@label_search}
                placeholder="Search by SSCC number"
              />
            </form>
            <p class="text-sm text-slate-600">
              {length(@labels)} {if length(@labels) == 1, do: "label", else: "labels"}
            </p>
            <form phx-change="page_size" id="pallet-label-page-size">
              <select
                name="page_size"
                class="h-[40px] rounded-md border border-slate-300 px-3 text-sm"
                aria-label="Labels per page"
              >
                <option :for={size <- [10, 25, 50, 100]} value={size} selected={size == @page_size}>
                  {size} / page
                </option>
              </select>
            </form>
          </div>

          <div class="max-h-[30rem] space-y-4 overflow-y-auto pr-1">
            <div
              :for={{label, index} <- Enum.with_index(Enum.take(@labels, @page_size))}
              class="rounded-2xl border border-slate-200 bg-slate-50/60 p-4"
            >
              <p class="text-[0.65rem] font-semibold uppercase tracking-[0.14em] text-slate-500">
                Pallet SSCC
              </p>
              <p class="mb-3 font-mono text-sm font-semibold text-slate-900">{label.sscc}</p>

              <.sscc_label id={"pallet-label-#{index}"} label={label}>
                <:actions>
                  <.label_actions label={"pallet SSCC #{label.sscc}"} />
                </:actions>
              </.sscc_label>
            </div>

            <p
              :if={@labels == []}
              class="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-600"
            >
              No pallet labels match that SSCC.
            </p>
          </div>

          <div class="flex items-center justify-between border-t border-slate-100 pt-4">
            <p class="text-sm text-slate-600">
              Showing {min(length(@labels), @page_size)} of {length(@labels)} total items
            </p>
            <.link
              patch={close_path(assigns)}
              class="inline-flex items-center gap-2 rounded-full bg-slate-800 px-4 py-2 text-sm font-semibold text-white"
            >
              <.icon name="hero-x-mark" class="size-4" /> Close
            </.link>
          </div>
        </div>
      </.modal>
    </Layouts.org_shell>
    """
  end

  attr :name, :string, required: true
  attr :value, :any, required: true
  attr :mono, :boolean, default: false
  attr :accent, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <div>
      <dt class="text-[0.65rem] font-semibold uppercase tracking-[0.12em] text-slate-500">
        {@name}
      </dt>
      <dd class={[
        "mt-0.5 text-sm",
        @mono && "font-mono",
        @accent && "font-semibold text-thamani-forest",
        !@accent && "text-slate-800"
      ]}>
        {if @value in [nil, ""], do: "—", else: @value}
      </dd>
    </div>
    """
  end
end
