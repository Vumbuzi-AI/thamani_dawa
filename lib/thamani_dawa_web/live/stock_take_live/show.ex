defmodule ThamaniDawaWeb.StockTakeLive.Show do
  @moduledoc """
  Dedicated counting workspace for a stock take session. Users add batches to
  count, enter physical quantities, and finalize — which reconciles each
  batch's `remaining_quantity` with the recorded count.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockTakes

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    stock_take = StockTakes.get_stock_take!(org_id, id)
    site = Sites.get_site!(org_id, stock_take.site_id)

    active_batches = Batches.list_active_batches_for_site(org_id, stock_take.site_id)
    products_by_id = org_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    already_added_ids = MapSet.new(stock_take.items, & &1.batch_id)
    addable_batches = Enum.reject(active_batches, &MapSet.member?(already_added_ids, &1.id))

    {:ok,
     socket
     |> assign(:stock_take, stock_take)
     |> assign(:site, site)
     |> assign(:products_by_id, products_by_id)
     |> assign(:addable_batches, addable_batches)
     |> assign(:add_batch_id, nil)}
  end

  def handle_event("add_batch", %{"batch_id" => batch_id_str}, socket)
      when batch_id_str != "" do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    stock_take = socket.assigns.stock_take

    case Integer.parse(batch_id_str) do
      {batch_id, ""} ->
        batch = Batches.get_batch!(org_id, batch_id)

        case StockTakes.add_item(stock_take, batch) do
          {:ok, _item} ->
            {:noreply, socket |> put_flash(:info, "Batch added.") |> reload(org_id)}

          {:error, :already_finalized} ->
            {:noreply, put_flash(socket, :error, "This stock take has already been finalized.")}

          {:error, changeset} ->
            msg = format_changeset_error(changeset)
            {:noreply, put_flash(socket, :error, msg)}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Select a batch to add.")}
    end
  end

  def handle_event("add_batch", _params, socket) do
    {:noreply, put_flash(socket, :error, "Select a batch to add.")}
  end

  def handle_event("record_count", %{"item_id" => item_id_str, "counted" => counted_str}, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    stock_take = socket.assigns.stock_take

    with {item_id, ""} <- Integer.parse(item_id_str),
         {counted, ""} <- Integer.parse(counted_str),
         item when not is_nil(item) <-
           Enum.find(stock_take.items, &(&1.id == item_id)) do
      case StockTakes.record_count(item, counted, scope.user.id) do
        {:ok, _updated} ->
          {:noreply, socket |> put_flash(:info, "Count recorded.") |> reload(org_id)}

        {:error, :already_finalized} ->
          {:noreply, put_flash(socket, :error, "This stock take has already been finalized.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Invalid count — quantity must be 0 or more.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a valid integer quantity.")}
    end
  end

  def handle_event("finalize", _params, socket) do
    scope = socket.assigns.current_scope
    stock_take = socket.assigns.stock_take

    case StockTakes.finalize_stock_take(stock_take, scope.user.id) do
      {:ok, _finalized} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock take finalized. Batch quantities have been updated.")
         |> reload(scope.organization_id)}

      {:error, :uncounted_items} ->
        {:noreply, put_flash(socket, :error, "All items must be counted before finalizing.")}

      {:error, :already_finalized} ->
        {:noreply, put_flash(socket, :error, "This stock take has already been finalized.")}
    end
  end

  defp reload(socket, org_id) do
    stock_take = StockTakes.get_stock_take!(org_id, socket.assigns.stock_take.id)
    active_batches = Batches.list_active_batches_for_site(org_id, stock_take.site_id)
    already_added_ids = MapSet.new(stock_take.items, & &1.batch_id)
    addable_batches = Enum.reject(active_batches, &MapSet.member?(already_added_ids, &1.id))

    assign(socket,
      stock_take: stock_take,
      addable_batches: addable_batches
    )
  end

  defp product_name(products_by_id, product_id) do
    case products_by_id[product_id] do
      nil -> "(unknown product)"
      p -> p.generic_name || p.brand_name || "(unnamed)"
    end
  end

  defp batch_option_label(batch, products_by_id) do
    name = product_name(products_by_id, batch.product_id)
    "#{name} — #{batch.batch_no} (#{batch.remaining_quantity} in stock)"
  end

  defp variance_class(nil), do: ""
  defp variance_class(0), do: "text-slate-500"
  defp variance_class(v) when v > 0, do: "text-emerald-600 font-medium"
  defp variance_class(_), do: "text-rose-600 font-medium"

  defp format_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/stock-takes"
    >
      <div class="space-y-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-slate-900">
              Stock take — {@site.name}
            </h1>
            <p class="mt-1 text-sm text-thamani-pewter">
              {if @stock_take.status == :draft,
                do: "Count each batch below, then finalize to update recorded stock.",
                else: "This stock take is finalized. Batch quantities were reconciled."}
            </p>
          </div>
          <.status_badge status={@stock_take.status} />
        </div>

        <section
          :if={@stock_take.status == :draft}
          id="add-batch-panel"
          class="rounded-xl border border-thamani-stone bg-thamani-snow p-4 sm:p-5"
        >
          <h2 class="mb-3 text-sm font-semibold text-slate-700">Add a batch to count</h2>
          <form
            phx-submit="add_batch"
            id="add-batch-form"
            class="flex flex-col gap-3 sm:flex-row sm:items-end"
          >
            <div class="flex-1 [&>div]:mb-0">
              <.input
                type="select"
                name="batch_id"
                label="Batch"
                value={nil}
                options={
                  Enum.map(@addable_batches, &{batch_option_label(&1, @products_by_id), &1.id})
                }
                prompt="Choose a received batch"
              />
            </div>
            <.button variant="primary" phx-disable-with="Adding…">
              Add batch
            </.button>
          </form>
          <p :if={@addable_batches == []} class="mt-2 text-sm text-thamani-pewter">
            All active batches at this site have been added to this count.
          </p>
        </section>

        <section id="counting-items">
          <h2 class="mb-3 text-sm font-semibold text-slate-700">
            Batches to count
            <span class="ml-1 rounded-full bg-thamani-stone px-2 py-0.5 text-xs font-normal text-thamani-pewter">
              {length(@stock_take.items)}
            </span>
          </h2>

          <.blank_state
            :if={@stock_take.items == []}
            icon="hero-clipboard-document-list"
            title="No batches added yet"
          >
            Add batches above to start counting.
          </.blank_state>

          <div id="stock-take-items" class="space-y-3">
            <%= for item <- @stock_take.items do %>
              <% batch = item.batch %>
              <article
                id={"item-#{item.id}"}
                class="overflow-hidden rounded-xl border border-thamani-stone bg-thamani-snow"
              >
                <div class="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <p class="font-medium text-slate-900">
                      {product_name(@products_by_id, batch && batch.product_id)}
                    </p>
                    <p class="mt-0.5 font-mono text-xs text-thamani-subtle">
                      {batch && batch.batch_no} · {batch && batch.gtin}
                    </p>
                  </div>

                  <dl class="grid grid-cols-3 gap-x-6 text-center text-sm">
                    <div>
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Expected
                      </dt>
                      <dd class="mt-0.5 font-semibold tabular-nums text-slate-900">
                        {item.expected_quantity}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Counted
                      </dt>
                      <dd class="mt-0.5 font-semibold tabular-nums text-slate-900">
                        {item.counted_quantity || "—"}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Variance
                      </dt>
                      <dd class={["mt-0.5 tabular-nums", variance_class(item.variance)]}>
                        {if item.variance,
                          do:
                            if(item.variance >= 0, do: "+#{item.variance}", else: "#{item.variance}"),
                          else: "—"}
                      </dd>
                    </div>
                  </dl>
                </div>

                <div
                  :if={@stock_take.status == :draft}
                  class="border-t border-thamani-stone bg-thamani-canvas/50 px-4 py-3"
                >
                  <form
                    id={"count-form-#{item.id}"}
                    phx-submit="record_count"
                    class="flex items-end gap-3"
                  >
                    <input type="hidden" name="item_id" value={item.id} />
                    <div class="[&>div]:mb-0">
                      <.input
                        id={"counted-#{item.id}"}
                        type="number"
                        name="counted"
                        value={item.counted_quantity}
                        label="Physical count"
                        min="0"
                        required
                        class="h-10 w-28 rounded-lg border border-thamani-stone bg-white px-3 text-right text-sm tabular-nums outline-none transition focus:border-thamani-accent focus:ring-2 focus:ring-thamani-accent/15"
                      />
                    </div>
                    <.button variant="primary" class="!py-2" phx-disable-with="Saving…">
                      Save count
                    </.button>
                  </form>
                </div>
              </article>
            <% end %>
          </div>
        </section>

        <div :if={@stock_take.status == :draft} class="flex justify-end pt-2">
          <.button
            variant="primary"
            phx-click="finalize"
            phx-disable-with="Finalizing…"
            data-confirm="Finalizing will update batch quantities to match your physical counts. This cannot be undone. Continue?"
          >
            <.icon name="hero-lock-closed" class="size-4" /> Finalize stock take
          </.button>
        </div>

        <aside
          :if={@stock_take.status == :finalized}
          class="flex items-start gap-3 rounded-xl border border-emerald-100 bg-emerald-50/60 px-4 py-3.5"
        >
          <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-emerald-600" />
          <div>
            <p class="text-sm font-semibold text-emerald-800">Stock take finalized</p>
            <p class="mt-0.5 text-sm text-emerald-700">
              Batch quantities were updated to match the physical counts recorded above.
              Finalized by user #{@stock_take.finalized_by_id}
              {if @stock_take.finalized_at,
                do: "on #{Calendar.strftime(@stock_take.finalized_at, "%d %b %Y at %H:%M")}",
                else: ""}.
            </p>
          </div>
        </aside>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
