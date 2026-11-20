defmodule ThamaniDawaWeb.DistributorStockTakeLive.Show do
  @moduledoc """
  Counting workspace for a distributor stock take session. The requester adds
  batches to count, enters physical quantities, then submits for admin
  approval — which reconciles each batch's `remaining_quantity` with the
  recorded count.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.StockTakes

  @base_path "/distributor/stock-takes"

  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    stock_take = StockTakes.get_stock_take!(org_id, id)
    site = Sites.get_site!(org_id, stock_take.site_id)
    products_by_id = org_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:stock_take, stock_take)
     |> assign(:site, site)
     |> assign(:products_by_id, products_by_id)
     |> assign(:addable_batches, addable_batches(org_id, stock_take))
     |> assign(:confirm_submit, false)}
  end

  defp addable_batches(org_id, stock_take) do
    already_added_ids = MapSet.new(stock_take.items, & &1.batch_id)

    org_id
    |> Batches.list_active_batches_for_site_by_inventory_type(
      stock_take.site_id,
      stock_take.inventory_type
    )
    |> Enum.reject(&MapSet.member?(already_added_ids, &1.id))
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

          {:error, :not_draft} ->
            {:noreply, put_flash(socket, :error, "This stock take is no longer a draft.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, format_changeset_error(changeset))}
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
         item when not is_nil(item) <- Enum.find(stock_take.items, &(&1.id == item_id)) do
      case StockTakes.record_count(item, counted, scope.user.id) do
        {:ok, _updated} ->
          {:noreply, socket |> put_flash(:info, "Count recorded.") |> reload(org_id)}

        {:error, :not_draft} ->
          {:noreply, put_flash(socket, :error, "This stock take is no longer a draft.")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Invalid count — quantity must be 0 or more.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a valid integer quantity.")}
    end
  end

  def handle_event("confirm_submit", _params, socket) do
    {:noreply, assign(socket, :confirm_submit, true)}
  end

  def handle_event("cancel_submit", _params, socket) do
    {:noreply, assign(socket, :confirm_submit, false)}
  end

  def handle_event("submit", _params, socket) do
    scope = socket.assigns.current_scope
    stock_take = socket.assigns.stock_take

    case StockTakes.submit_stock_take(scope.organization_id, stock_take.id, scope.user.id) do
      {:ok, _submitted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Submitted for approval.")
         |> assign(:confirm_submit, false)
         |> reload(scope.organization_id)}

      {:error, :no_counted_items} ->
        {:noreply,
         socket
         |> put_flash(:error, "Count at least one item before submitting.")
         |> assign(:confirm_submit, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Couldn't submit this stock take.")
         |> assign(:confirm_submit, false)}
    end
  end

  def handle_event("reopen", _params, socket) do
    scope = socket.assigns.current_scope
    stock_take = socket.assigns.stock_take

    case StockTakes.reopen_stock_take(scope.organization_id, stock_take.id, scope.user.id) do
      {:ok, _reopened} ->
        {:noreply,
         socket
         |> put_flash(:info, "Reopened for counting.")
         |> reload(scope.organization_id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reopen this stock take.")}
    end
  end

  defp reload(socket, org_id) do
    stock_take = StockTakes.get_stock_take!(org_id, socket.assigns.stock_take.id)

    assign(socket,
      stock_take: stock_take,
      addable_batches: addable_batches(org_id, stock_take)
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

  defp variance_class(nil), do: "text-thamani-subtle"
  defp variance_class(0), do: "text-thamani-pewter"
  defp variance_class(v) when v > 0, do: "text-thamani-forest"
  defp variance_class(_), do: "text-thamani-error"

  defp format_variance(nil), do: "—"
  defp format_variance(variance) when variance > 0, do: "+#{variance}"
  defp format_variance(variance), do: to_string(variance)

  defp format_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  def render(assigns) do
    assigns = assign(assigns, :base_path, @base_path)

    ~H"""
    <Layouts.distributor_shell flash={@flash} current_scope={@current_scope} current_path={@base_path}>
      <div class="space-y-6">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <h1 class="text-xl font-semibold tracking-tight text-thamani-forest sm:text-2xl">
              Stock take
            </h1>
            <p class="mt-1 text-sm text-thamani-pewter">
              {@site.name}. {status_message(@stock_take.status)}
            </p>
          </div>
          <.status_badge status={@stock_take.status} class="shrink-0" />
        </div>

        <section
          :if={@stock_take.status == :draft}
          id="add-batch-panel"
          class="rounded-2xl border border-thamani-frosted bg-white p-4 sm:p-5"
        >
          <h2 class="text-sm font-semibold text-thamani-forest">Add a batch</h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            Choose a batch at this site that is not on this count yet.
          </p>
          <form
            phx-submit="add_batch"
            id="add-batch-form"
            class="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end"
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
            <.button variant="primary" class="w-full sm:w-auto" phx-disable-with="Adding…">
              Add batch
            </.button>
          </form>
          <p :if={@addable_batches == []} class="mt-2 text-sm text-thamani-pewter">
            All active batches at this site have been added to this count.
          </p>
        </section>

        <section id="counting-items">
          <div class="mb-3 flex items-baseline justify-between gap-3">
            <h2 class="text-base font-semibold text-thamani-forest">Batches to count</h2>
            <p class="text-sm tabular-nums text-thamani-pewter">
              {length(@stock_take.items)}
            </p>
          </div>

          <.blank_state
            :if={@stock_take.items == []}
            icon="hero-clipboard-document-list"
            title="No batches added yet"
          >
            Add batches above to start counting.
          </.blank_state>

          <div
            :if={@stock_take.items != []}
            id="stock-take-items"
            class="overflow-hidden rounded-2xl border border-thamani-frosted bg-white"
          >
            <article
              :for={item <- @stock_take.items}
              id={"item-#{item.id}"}
              class="border-b border-thamani-frosted px-4 py-4 last:border-b-0 sm:px-5"
            >
              <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-thamani-forest">
                    {product_name(@products_by_id, item.batch && item.batch.product_id)}
                  </p>
                  <p class="mt-1 text-xs text-thamani-pewter">
                    <span class="font-medium tabular-nums tracking-tight text-thamani-forest">
                      {item.batch && item.batch.batch_no}
                    </span>
                    <span :if={item.batch && item.batch.gtin} class="mx-1 text-thamani-subtle">·</span>
                    <span
                      :if={item.batch && item.batch.gtin}
                      class="tabular-nums tracking-tight"
                    >
                      {item.batch.gtin}
                    </span>
                  </p>
                  <details
                    :if={item.batch && (item.batch.serials || []) != []}
                    class="group mt-2"
                  >
                    <summary class="flex w-fit cursor-pointer list-none items-center gap-1.5 rounded text-xs font-medium text-thamani-pewter marker:content-none hover:text-thamani-forest focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-thamani-accent [&::-webkit-details-marker]:hidden">
                      <.icon
                        name="hero-chevron-right"
                        class="size-3.5 transition-transform group-open:rotate-90"
                      />
                      {length(item.batch.serials)}
                      {if length(item.batch.serials) == 1, do: "serial", else: "serials"}
                    </summary>
                    <ul class="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
                      <li
                        :for={serial <- item.batch.serials}
                        class="text-xs font-medium tabular-nums tracking-tight text-thamani-forest [overflow-wrap:anywhere]"
                        title={serial}
                      >
                        {serial}
                      </li>
                    </ul>
                  </details>
                </div>

                <dl class="grid w-full grid-cols-3 gap-2 lg:w-64 lg:shrink-0">
                  <div>
                    <dt class="text-xs font-medium text-thamani-subtle">Expected</dt>
                    <dd class="mt-1 text-sm font-semibold tabular-nums text-thamani-forest">
                      {item.expected_quantity}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs font-medium text-thamani-subtle">Counted</dt>
                    <dd class="mt-1 text-sm font-semibold tabular-nums text-thamani-forest">
                      {item.counted_quantity || "—"}
                    </dd>
                  </div>
                  <div>
                    <dt class="text-xs font-medium text-thamani-subtle">Variance</dt>
                    <dd class={[
                      "mt-1 text-sm font-semibold tabular-nums",
                      variance_class(item.variance)
                    ]}>
                      {format_variance(item.variance)}
                    </dd>
                  </div>
                </dl>
              </div>

              <form
                :if={@stock_take.status == :draft}
                id={"count-form-#{item.id}"}
                phx-submit="record_count"
                class="mt-4 flex flex-col gap-3 border-t border-thamani-frosted pt-4 sm:flex-row sm:items-end"
              >
                <input type="hidden" name="item_id" value={item.id} />
                <div class="w-full sm:w-40 [&>div]:mb-0">
                  <.input
                    id={"counted-#{item.id}"}
                    type="number"
                    name="counted"
                    value={item.counted_quantity}
                    label="Physical count"
                    min="0"
                    required
                    class="w-full text-right tabular-nums"
                  />
                </div>
                <.button variant="primary" class="w-full sm:w-auto" phx-disable-with="Saving…">
                  Save count
                </.button>
              </form>
            </article>
          </div>
        </section>

        <div :if={@stock_take.status == :draft} class="flex justify-end pt-2">
          <.button variant="primary" class="w-full sm:w-auto" phx-click="confirm_submit">
            <.icon name="hero-paper-airplane" class="size-4" /> Submit for approval
          </.button>
        </div>

        <div :if={@stock_take.status == :pending} class="flex justify-end pt-2">
          <.button variant="ghost" class="w-full sm:w-auto" phx-click="reopen">
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Reopen for counting
          </.button>
        </div>

        <.modal
          :if={@confirm_submit}
          id="confirm-submit-modal"
          show
          on_cancel={JS.push("cancel_submit")}
        >
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
            Submit for approval
          </h2>
          <p class="mb-6 text-sm text-thamani-pewter">
            An organization admin will review your counts and, if approved, batch quantities will be updated to match. Continue?
          </p>
          <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            <.button type="button" class="w-full sm:w-auto" phx-click="cancel_submit">
              Cancel
            </.button>
            <.button
              variant="primary"
              class="w-full sm:w-auto"
              phx-click="submit"
              phx-disable-with="Submitting…"
            >
              Submit
            </.button>
          </div>
        </.modal>

        <aside
          :if={@stock_take.status == :approved}
          class="flex items-start gap-3 rounded-2xl border border-thamani-frosted bg-thamani-lime px-4 py-4 sm:px-5"
        >
          <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-thamani-forest" />
          <div>
            <p class="text-sm font-semibold text-thamani-forest">Stock take approved</p>
            <p class="mt-0.5 text-sm text-thamani-pewter">
              Batch quantities were updated to match the physical counts recorded above. {if @stock_take.approved_at,
                do: "Approved on #{Calendar.strftime(@stock_take.approved_at, "%d %b %Y at %H:%M")}.",
                else: ""}
            </p>
          </div>
        </aside>

        <aside
          :if={@stock_take.status == :rejected}
          class="flex items-start gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-4 sm:px-5"
        >
          <.icon name="hero-x-circle" class="mt-0.5 size-5 shrink-0 text-thamani-error" />
          <div>
            <p class="text-sm font-semibold text-thamani-error">Stock take rejected</p>
            <p class="mt-0.5 text-sm text-rose-900">
              {@stock_take.rejection_reason}
            </p>
          </div>
        </aside>
      </div>
    </Layouts.distributor_shell>
    """
  end

  defp status_message(:draft), do: "Count each batch below, then submit for admin approval."
  defp status_message(:pending), do: "Awaiting admin review. You can reopen to keep counting."
  defp status_message(:approved), do: "Approved. Batch quantities were reconciled."
  defp status_message(:rejected), do: "Rejected. See the reason below."
end
