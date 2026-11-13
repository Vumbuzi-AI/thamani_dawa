defmodule ThamaniDawaWeb.RequisitionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Products
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites =
      scope
      |> Accounts.list_sites_for_user()
      |> Enum.filter(&Site.pharmacy?/1)

    all_sites = Sites.list_sites(organization_id)

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites, sites)
     |> assign(:sites_by_id, Map.new(all_sites, &{&1.id, &1}))
     |> assign(:all_sites, all_sites)
     |> assign(:tabs, [{"all", "All"} | Requisitions.tabs()])
     |> assign(:draft_items, [])
     |> assign(:editing_item_id, nil)
     |> assign(:item_error, nil)
     |> stream(:requisitions, [])}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "status" => params["status"] || "all",
      "search" => params["search"] || "",
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> apply_action(socket.assigns.live_action)
     |> load_requisitions()}
  end

  defp apply_action(socket, :new) do
    socket
    |> assign(:draft_items, [])
    |> assign(:editing_item_id, nil)
    |> assign(:item_error, nil)
  end

  defp apply_action(socket, :index), do: socket

  defp load_requisitions(socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    filters = socket.assigns.filters
    all_sites = socket.assigns.all_sites

    scoped =
      organization_id
      |> Requisitions.list_requisitions()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(fn r ->
        Enum.any?(all_sites, &(&1.id == r.site_id and Site.pharmacy?(&1)))
      end)

    requisitions =
      scoped
      |> Requisitions.filter_by_tab(filters["status"])
      |> Requisitions.filter_by_date_range(
        parse_date(filters["date_from"]),
        parse_date(filters["date_to"])
      )
      |> Requisitions.filter_by_search(filters["search"])

    socket
    |> assign(:tab_counts, Map.put(Requisitions.tab_counts(scoped), "all", length(scoped)))
    |> stream(:requisitions, requisitions, reset: true)
  end

  defp parse_date(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp filter_path(socket, changes) do
    query =
      socket.assigns.filters
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/pharmacy/requisitions?#{query}"
  end

  defp tab_path(filters, status) do
    query =
      filters
      |> Map.put("status", status)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/pharmacy/requisitions?#{query}"
  end

  defp active_filter_count(filters),
    do: Enum.count(["date_from", "date_to"], &(filters[&1] not in [nil, ""]))

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}
  end

  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    changes = Map.take(filters, ["date_from", "date_to"])
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("clear_filter", %{"filter" => filter}, socket)
      when filter in ["date_from", "date_to"] do
    {:noreply, push_patch(socket, to: filter_path(socket, %{filter => ""}))}
  end

  def handle_event(
        "add_item",
        %{"product_id" => product_id, "requested_quantity" => quantity},
        socket
      ) do
    {:noreply, stage_item(socket, product_id, quantity)}
  end

  def handle_event("edit_item", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_item_id, String.to_integer(id))}
  end

  def handle_event("cancel_edit_item", _params, socket) do
    {:noreply, assign(socket, :editing_item_id, nil)}
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    id = String.to_integer(id)

    {:noreply,
     socket
     |> update(:draft_items, &Enum.reject(&1, fn item -> item.id == id end))
     |> then(fn socket ->
       if socket.assigns.editing_item_id == id,
         do: assign(socket, :editing_item_id, nil),
         else: socket
     end)}
  end

  def handle_event("save", params, socket) do
    scope = socket.assigns.current_scope
    site_id = parse_int(params["site_id"])

    cond do
      socket.assigns.draft_items == [] ->
        {:noreply, put_flash(socket, :error, "Add at least one item before sending.")}

      is_nil(site_id) or site_id not in Enum.map(socket.assigns.sites, & &1.id) ->
        {:noreply, put_flash(socket, :error, "Choose a valid site.")}

      true ->
        attrs = %{
          "site_id" => site_id,
          "notes" => params["notes"],
          "lines" => lines_from_draft(socket.assigns.draft_items)
        }

        case Requisitions.create_multi_requisition(scope.organization_id, scope.user.id, attrs) do
          {:ok, requisition} ->
            {:noreply,
             socket
             |> put_flash(:info, "Requisition sent to the organization.")
             |> stream_insert(:requisitions, requisition, at: 0)
             |> push_patch(to: ~p"/pharmacy/requisitions")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Couldn't send that requisition.")}
        end
    end
  end

  defp stage_item(socket, raw_product_id, raw_quantity) do
    editing_id = socket.assigns.editing_item_id
    product_id = parse_int(raw_product_id)
    quantity = parse_int(raw_quantity)

    cond do
      is_nil(product_id) or not Map.has_key?(socket.assigns.products_by_id, product_id) ->
        assign(socket, :item_error, "Choose a product.")

      is_nil(quantity) or quantity <= 0 ->
        assign(socket, :item_error, "Enter a quantity greater than zero.")

      Enum.any?(
        socket.assigns.draft_items,
        &(&1.product_id == product_id and &1.id != editing_id)
      ) ->
        assign(socket, :item_error, "That product is already in this requisition.")

      true ->
        put_item(socket, editing_id, product_id, quantity)
    end
  end

  defp put_item(socket, editing_id, product_id, quantity) do
    item = %{
      id: editing_id || System.unique_integer([:positive]),
      product_id: product_id,
      requested_quantity: quantity
    }

    items =
      if editing_id do
        Enum.map(socket.assigns.draft_items, &if(&1.id == editing_id, do: item, else: &1))
      else
        socket.assigns.draft_items ++ [item]
      end

    socket
    |> assign(:draft_items, items)
    |> assign(:editing_item_id, nil)
    |> assign(:item_error, nil)
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp lines_from_draft(draft_items) do
    draft_items
    |> Enum.with_index()
    |> Map.new(fn {item, index} ->
      {Integer.to_string(index),
       %{"product_id" => item.product_id, "requested_quantity" => item.requested_quantity}}
    end)
  end

  defp available_products(products_by_id, draft_items, editing_item_id) do
    taken =
      draft_items
      |> Enum.reject(&(&1.id == editing_item_id))
      |> Enum.map(& &1.product_id)
      |> MapSet.new()

    products_by_id
    |> Map.values()
    |> Enum.reject(&MapSet.member?(taken, &1.id))
  end

  defp editing_item(draft_items, editing_item_id),
    do: Enum.find(draft_items, &(&1.id == editing_item_id))

  defp product_name(products_by_id, product_id) do
    case Map.get(products_by_id, product_id) do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  defp site_name(sites_by_id, site_id) do
    case Map.get(sites_by_id, site_id) do
      nil -> "—"
      site -> site.name
    end
  end

  defp requisition_summary(products_by_id, %{lines: []} = requisition),
    do: product_name(products_by_id, requisition.product_id)

  defp requisition_summary(_products_by_id, requisition) do
    count = length(requisition.lines)
    "#{count} product#{if count == 1, do: "", else: "s"}"
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/requisitions"
    >
      <.header icon="hero-clipboard-document-list">
        Requisitions
        <:subtitle>
          Ask the organization for stock when your site's levels are running low.
        </:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/pharmacy/requisitions/new"}>
            <.icon name="hero-plus" class="size-4" /> New requisition
          </.button>
        </:actions>
        <:toolbar>
          <form id="requisition-search" phx-change="search" phx-submit="search">
            <.search_input
              name="search"
              value={@filters["search"]}
              placeholder="Search by reference"
            />
          </form>
          <.filter_drawer
            id="requisition-filters"
            title="Filter requisitions"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Requested between">
              <div class="grid grid-cols-2 gap-2">
                <.input
                  type="date"
                  id="filter-date-from"
                  name="filters[date_from]"
                  value={@filters["date_from"]}
                />
                <.input
                  type="date"
                  id="filter-date-to"
                  name="filters[date_to]"
                  value={@filters["date_to"]}
                />
              </div>
            </:group>
            <:chip
              :if={@filters["date_from"] != ""}
              label={"From #{@filters["date_from"]}"}
              clear={JS.push("clear_filter", value: %{filter: "date_from"})}
            />
            <:chip
              :if={@filters["date_to"] != ""}
              label={"To #{@filters["date_to"]}"}
              clear={JS.push("clear_filter", value: %{filter: "date_to"})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <nav
        id="requisition-tabs"
        class="mb-4 mt-4 flex gap-1 overflow-x-auto rounded-xl border border-thamani-stone bg-white p-1"
        aria-label="Requisition status"
      >
        <.link
          :for={{status, label} <- @tabs}
          id={"requisition-tab-#{status}"}
          patch={tab_path(@filters, status)}
          class={[
            "flex flex-1 items-center justify-center gap-2 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors duration-150",
            if(@filters["status"] == status,
              do: "bg-thamani-forest text-white shadow-sm",
              else: "text-thamani-pewter hover:bg-thamani-canvas hover:text-thamani-forest"
            )
          ]}
          aria-current={@filters["status"] == status && "page"}
        >
          {label}
          <span class={[
            "rounded-full px-2 py-0.5 text-xs font-semibold",
            if(@filters["status"] == status,
              do: "bg-white/20 text-white",
              else: "bg-thamani-stone text-thamani-forest"
            )
          ]}>
            {@tab_counts[status]}
          </span>
        </.link>
      </nav>

      <.modal
        :if={@live_action == :new}
        id="new-requisition-modal"
        show
        on_cancel={JS.patch(~p"/pharmacy/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          New requisition
        </h2>

        <%= if length(@sites) == 1 do %>
          <% site = hd(@sites) %>
          <div class="mb-4">
            <span class="thamani-label">Site</span>
            <p class="text-sm font-medium text-slate-800">{site.name}</p>
          </div>
        <% end %>

        <form phx-submit="add_item" id="add-item-form" class="mt-1">
          <.input
            type="select"
            name="product_id"
            label="Choose product"
            options={
              Enum.map(
                available_products(@products_by_id, @draft_items, @editing_item_id),
                &{product_name(@products_by_id, &1.id), &1.id}
              )
            }
            value={
              case editing_item(@draft_items, @editing_item_id) do
                nil -> nil
                item -> item.product_id
              end
            }
            prompt="Choose a product"
          />
          <.input
            type="number"
            name="requested_quantity"
            label="Quantity"
            min="1"
            value={
              case editing_item(@draft_items, @editing_item_id) do
                nil -> nil
                item -> item.requested_quantity
              end
            }
          />
          <p :if={@item_error} class="mt-2 text-sm text-thamani-error">{@item_error}</p>
          <div class="mt-3 flex items-center gap-3">
            <.button variant="primary" class="flex-1">
              {if @editing_item_id, do: "Save item changes", else: "Add item"}
            </.button>
            <button
              :if={@editing_item_id}
              type="button"
              phx-click="cancel_edit_item"
              class="text-sm font-semibold text-thamani-pewter hover:underline"
            >
              Cancel
            </button>
          </div>
        </form>

        <div
          :if={@draft_items != []}
          class="mt-5 rounded-xl border border-thamani-stone bg-thamani-canvas p-4"
        >
          <h3 class="text-sm font-semibold text-thamani-forest">Items in this requisition</h3>
          <div class="mt-3 overflow-hidden rounded-lg border border-thamani-stone bg-white">
            <table class="w-full table-fixed text-left text-sm">
              <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                <tr>
                  <th class="w-[55%] px-3 py-2">Product</th>
                  <th class="w-[20%] px-3 py-2">Quantity</th>
                  <th class="w-[25%] px-3 py-2 text-right">Actions</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-thamani-stone">
                <tr :for={item <- @draft_items} id={"draft-item-#{item.id}"}>
                  <td class="truncate px-3 py-2 font-medium text-thamani-forest">
                    {product_name(@products_by_id, item.product_id)}
                  </td>
                  <td class="px-3 py-2 whitespace-nowrap">{item.requested_quantity}</td>
                  <td class="px-3 py-2">
                    <div class="flex justify-end gap-2">
                      <button
                        type="button"
                        phx-click="edit_item"
                        phx-value-id={item.id}
                        class="text-xs font-semibold text-thamani-forest hover:underline"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        phx-click="remove_item"
                        phx-value-id={item.id}
                        class="text-xs font-semibold text-thamani-error hover:underline"
                      >
                        Remove
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <form phx-submit="save" id="requisition-form" class="mt-5 flex flex-col gap-4">
          <%= if length(@sites) > 1 do %>
            <.input
              type="select"
              name="site_id"
              label="Site"
              options={Enum.map(@sites, &{&1.name, &1.id})}
              prompt="Choose a site"
              required
            />
          <% else %>
            <input type="hidden" name="site_id" value={hd(@sites).id} />
          <% end %>
          <.input type="textarea" name="notes" label="Notes (optional)" />
          <.button
            variant="primary"
            phx-disable-with="Sending…"
            disabled={@draft_items == []}
            class="w-full"
          >
            Send requisition{if @draft_items != [], do: " (#{length(@draft_items)} items)"}
          </.button>
        </form>
      </.modal>

      <.table
        id="requisitions"
        rows={@streams.requisitions}
        row_click={fn {_id, r} -> JS.navigate(~p"/pharmacy/requisitions/#{r.id}") end}
      >
        <:col :let={{_id, r}} label="Reference">
          <span class="font-mono font-semibold text-thamani-forest">{r.number}</span>
        </:col>
        <:col :let={{_id, r}} label="Items">{requisition_summary(@products_by_id, r)}</:col>
        <:col :let={{_id, r}} label="Site">{site_name(@sites_by_id, r.site_id)}</:col>
        <:col :let={{_id, r}} label="Status">
          <.status_badge status={r.status} />
        </:col>
        <:col :let={{_id, r}} label="Requested">{r.inserted_at}</:col>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No requisitions yet">
            Raise a requisition when your site needs more stock than it currently has.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end
end
