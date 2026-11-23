defmodule ThamaniDawaWeb.DistributorDisposalLive.Show do
  @moduledoc """
  Editing workspace for an expiry write-off or a supplier return. Stock
  does not move until an admin approves. An expiry write-off only offers
  lots past their date, and takes the whole remaining quantity.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  def mount(%{"id" => id} = params, _session, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id

    disposal = InventoryDisposals.get_disposal!(org_id, id)
    site = Sites.get_site!(org_id, disposal.site_id)
    products_by_id = org_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    {:ok,
     socket
     |> assign(:disposal, disposal)
     |> assign(:site, site)
     |> assign(:products_by_id, products_by_id)
     |> assign(:addable_batches, addable_batches(org_id, disposal))
     |> assign(:expanded_batches, MapSet.new())
     |> assign(:confirm_submit, false)
     |> assign(:return_to, ThamaniDawaWeb.ReturnTo.safe(params["return_to"], ~p"/distributor/returns"))}
  end

  defp addable_batches(org_id, disposal) do
    already_added_ids = MapSet.new(disposal.items, & &1.batch_id)
    today = Date.utc_today()

    org_id
    |> Batches.list_active_batches_for_site_by_inventory_type(
      disposal.site_id,
      disposal.inventory_type
    )
    |> Enum.reject(&MapSet.member?(already_added_ids, &1.id))
    |> Enum.filter(fn batch ->
      disposal.kind != :expiry or expired?(batch, today)
    end)
  end

  defp expired?(%{expiry_date: %Date{} = expiry_date}, today) do
    Date.compare(expiry_date, today) == :lt
  end

  defp expired?(_batch, _today), do: false

  def handle_event("add_batch", %{"batch_id" => batch_id_str} = params, socket)
      when batch_id_str != "" do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    disposal = socket.assigns.disposal

    with {batch_id, ""} <- Integer.parse(batch_id_str),
         batch = Batches.get_batch!(org_id, batch_id),
         {:ok, quantity} <- requested_quantity(disposal, batch, params["quantity"]) do
      case InventoryDisposals.add_item(disposal, batch, quantity) do
        {:ok, _item} ->
          {:noreply, socket |> put_flash(:info, added_message(disposal.kind)) |> reload(org_id)}

        {:error, :not_draft} ->
          {:noreply, put_flash(socket, :error, "This request is no longer a draft.")}

        {:error, :no_supplier} ->
          {:noreply,
           put_flash(socket, :error, "That batch has no recorded supplier to return it to.")}

        {:error, :not_expired} ->
          {:noreply, put_flash(socket, :error, "That lot has not passed its expiry date.")}

        {:error, :partial_expiry} ->
          {:noreply,
           put_flash(socket, :error, "An expiry write-off takes the whole remaining quantity.")}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, format_changeset_error(changeset))}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a batch and a valid quantity.")}
    end
  end

  def handle_event("add_batch", _params, socket) do
    {:noreply, put_flash(socket, :error, "Choose a batch and a valid quantity.")}
  end

  def handle_event("remove_item", %{"item_id" => item_id_str}, socket) do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    disposal = socket.assigns.disposal

    case Integer.parse(item_id_str) do
      {item_id, ""} ->
        item = Enum.find(disposal.items, &(&1.id == item_id))

        case InventoryDisposals.remove_item(item) do
          {:ok, _item} ->
            {:noreply, socket |> put_flash(:info, "Item removed.") |> reload(org_id)}

          {:error, :not_draft} ->
            {:noreply, put_flash(socket, :error, "This disposal is no longer a draft.")}
        end

      _ ->
        {:noreply, socket}
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
    disposal = socket.assigns.disposal

    case InventoryDisposals.submit_disposal(scope.organization_id, disposal.id, scope.user.id) do
      {:ok, _submitted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Submitted for approval.")
         |> assign(:confirm_submit, false)
         |> reload(scope.organization_id)}

      {:error, :no_items} ->
        {:noreply,
         socket
         |> put_flash(:error, "Add at least one batch before submitting.")
         |> assign(:confirm_submit, false)}

      {:error, {:stock_changed, _item_id}} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Stock has changed since an item was added. Remove and re-add it with the current quantity."
         )
         |> assign(:confirm_submit, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Couldn't submit this disposal.")
         |> assign(:confirm_submit, false)}
    end
  end

  def handle_event("reopen", _params, socket) do
    scope = socket.assigns.current_scope
    disposal = socket.assigns.disposal

    case InventoryDisposals.reopen_disposal(scope.organization_id, disposal.id, scope.user.id) do
      {:ok, _reopened} ->
        {:noreply,
         socket
         |> put_flash(:info, "Reopened for editing.")
         |> reload(scope.organization_id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reopen this disposal.")}
    end
  end

  def handle_event("toggle_batch_serials", %{"batch" => batch_id}, socket) do
    expanded = socket.assigns.expanded_batches

    expanded =
      if MapSet.member?(expanded, batch_id),
        do: MapSet.delete(expanded, batch_id),
        else: MapSet.put(expanded, batch_id)

    {:noreply, assign(socket, :expanded_batches, expanded)}
  end

  defp reload(socket, org_id) do
    disposal = InventoryDisposals.get_disposal!(org_id, socket.assigns.disposal.id)

    assign(socket,
      disposal: disposal,
      addable_batches: addable_batches(org_id, disposal)
    )
  end

  defp requested_quantity(%{kind: :expiry}, batch, _raw), do: {:ok, batch.remaining_quantity}

  defp requested_quantity(_disposal, _batch, raw) do
    case Integer.parse(to_string(raw || "")) do
      {quantity, ""} when quantity > 0 -> {:ok, quantity}
      _ -> :error
    end
  end

  defp added_message(:expiry), do: "Lot added."
  defp added_message(_kind), do: "Batch added."

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

  defp supplier_name(%{batch: %{supplier: %{name: name}}}), do: name
  defp supplier_name(_item), do: "—"

  defp disposal_supplier(%{items: items}) do
    case items |> Enum.map(&supplier_name/1) |> Enum.uniq() do
      [] -> "—"
      [name] -> name
      names -> "#{length(names)} suppliers"
    end
  end

  defp format_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp kind_label(:expiry), do: "Expiry write-off"
  defp kind_label(:returned), do: "Supplier return"

  def render(assigns) do
    assigns =
      assigns
      |> assign(:list_path, list_path(assigns.disposal.kind))
      |> assign(
        :no_lots_to_add,
        assigns.disposal.kind == :expiry and assigns.addable_batches == []
      )

    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={@list_path}
    >
      <div class="space-y-6 td-recipe td-detail-page" id="disposal-detail">
        <.td_back_link
          id="disposal-back"
          to={@return_to}
          label={ThamaniDawaWeb.ReturnTo.label(@return_to, "Back to list")}
        />
        <header class="td-idh">
          <div class="td-idh-text">
            <h1 class="td-idh-title">
              <span>{kind_label(@disposal.kind)}</span>
              <.status_badge status={@disposal.status} class="shrink-0" />
            </h1>
            <p class="td-idh-sub">{@site.name}. {status_message(@disposal.status)}</p>
          </div>
        </header>

        <section class="td-card" id="disposal-summary">
          <dl class="td-kv-grid is-pad is-6">
            <div :if={@disposal.kind == :returned} class="td-kv">
              <dt class="td-kv-label">Supplier</dt>
              <dd class="td-kv-value">{disposal_supplier(@disposal)}</dd>
            </div>
            <div class="td-kv">
              <dt class="td-kv-label">From</dt>
              <dd class="td-kv-value">{@site.name}</dd>
            </div>
            <div class="td-kv">
              <dt class="td-kv-label">Reason</dt>
              <dd class="td-kv-value">{@disposal.reason || "—"}</dd>
            </div>
            <div class="td-kv">
              <dt class="td-kv-label">Batches</dt>
              <dd class="td-kv-value">{length(@disposal.items)}</dd>
            </div>
            <div class="td-kv">
              <dt class="td-kv-label">Units</dt>
              <dd class="td-kv-value">{@disposal.items |> Enum.map(&(&1.quantity || 0)) |> Enum.sum()}</dd>
            </div>
            <div class="td-kv">
              <dt class="td-kv-label">Created (EAT)</dt>
              <dd class="td-kv-value">
                {ThamaniDawaWeb.TimeFormat.datetime(@disposal.inserted_at)}
                <span :if={@disposal.requested_by} class="td-sub td-s12">by {@disposal.requested_by.name}</span>
              </dd>
            </div>
          </dl>
        </section>

        <section
          :if={@disposal.status == :draft}
          id="add-batch-panel"
          class="rounded-2xl border border-thamani-frosted bg-td-surface p-4 sm:p-5"
        >
          <h2 class="text-sm font-semibold text-thamani-forest">
            {if @disposal.kind == :expiry, do: "Add an expired lot", else: "Add a batch"}
          </h2>
          <p class="mt-1 text-sm text-thamani-pewter">
            {if @disposal.kind == :expiry,
              do:
                "The whole remaining quantity is written off. Stock stays here until this is approved.",
              else: "Choose how many units go back to the supplier."}
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
                id="write-off-batch"
                label="Batch"
                value={nil}
                disabled={@no_lots_to_add}
                options={
                  Enum.map(@addable_batches, &{batch_option_label(&1, @products_by_id), &1.id})
                }
                prompt="Choose a batch"
              />
            </div>
            <div :if={@disposal.kind != :expiry} class="[&>div]:mb-0">
              <.input type="number" name="quantity" label="Quantity" min="1" required />
            </div>
            <.button
              variant="primary"
              class="w-full sm:w-auto"
              disabled={@no_lots_to_add}
              phx-disable-with="Adding…"
            >
              {if @disposal.kind == :expiry, do: "Add lot", else: "Add batch"}
            </.button>
          </form>
          <p
            :if={@no_lots_to_add}
            id="no-expired-stock"
            role="status"
            class="mt-4 rounded-xl bg-amber-50 px-4 py-3 text-sm font-medium text-amber-950"
          >
            {if @disposal.items == [],
              do: "No expired stock at this warehouse. There is nothing to write off.",
              else: "No expired stock left to add at this warehouse."}
          </p>
          <p
            :if={@disposal.kind != :expiry and @addable_batches == []}
            class="mt-2 text-sm text-thamani-pewter"
          >
            All batches at this site have been added.
          </p>
        </section>

        <section id="disposal-items">
          <div class="mb-3 flex items-baseline justify-between gap-3">
            <h2 class="text-base font-semibold text-thamani-forest">
              {if @disposal.kind == :expiry, do: "Lots to write off", else: "Batches to return"}
            </h2>
            <p class="text-sm tabular-nums text-thamani-pewter">{length(@disposal.items)}</p>
          </div>

          <.blank_state
            :if={@disposal.items == []}
            icon={
              if @disposal.kind == :expiry, do: "hero-calendar-days", else: "hero-arrow-uturn-left"
            }
            title={if(@no_lots_to_add, do: "No expired stock", else: "No batches added yet")}
          >
            {cond do
              @no_lots_to_add -> "This warehouse has no lot past its date."
              @disposal.kind == :expiry -> "Add the expired lots above."
              true -> "Add the batches going back to the supplier."
            end}
          </.blank_state>

          <div
            :if={@disposal.items != []}
            id="disposal-item-rows"
            class="overflow-hidden rounded-2xl border border-thamani-frosted bg-td-surface"
          >
            <article
              :for={item <- @disposal.items}
              id={"item-#{item.id}"}
              class="border-b border-thamani-frosted px-4 py-4 last:border-b-0 sm:px-5"
            >
              <% batch = item.batch %>
              <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                <div class="min-w-0">
                  <p class="text-sm font-semibold text-thamani-forest">
                    {product_name(@products_by_id, batch && batch.product_id)}
                  </p>
                  <p class="mt-1 text-xs text-thamani-pewter">
                    <span class="font-medium tabular-nums tracking-tight text-thamani-forest">
                      {batch && batch.batch_no}
                    </span>
                    <span :if={batch && batch.gtin} class="mx-1 text-thamani-subtle">·</span>
                    <span :if={batch && batch.gtin} class="tabular-nums tracking-tight">
                      {batch.gtin}
                    </span>
                  </p>
                  <div :if={batch} class="mt-2">
                    <button
                      type="button"
                      phx-click={batch.serials != [] && "toggle_batch_serials"}
                      phx-value-batch={batch.id}
                      disabled={batch.serials == []}
                      class="flex w-fit items-center gap-1.5 text-xs font-medium text-thamani-pewter disabled:cursor-default"
                      aria-expanded={
                        to_string(MapSet.member?(@expanded_batches, to_string(batch.id)))
                      }
                    >
                      <.icon
                        :if={batch.serials != []}
                        name="hero-chevron-right"
                        class={[
                          "size-3.5 transition-transform duration-200",
                          MapSet.member?(@expanded_batches, to_string(batch.id)) && "rotate-90"
                        ]}
                      />
                      {if batch.serials == [],
                        do: "No serials",
                        else:
                          "#{length(batch.serials)} #{if length(batch.serials) == 1, do: "serial", else: "serials"}"}
                    </button>
                    <ul
                      :if={
                        batch.serials != [] and
                          MapSet.member?(@expanded_batches, to_string(batch.id))
                      }
                      class="mt-1.5 flex flex-wrap gap-x-3 gap-y-1"
                    >
                      <li
                        :for={serial <- batch.serials}
                        class="text-xs font-medium tabular-nums tracking-tight text-thamani-forest [overflow-wrap:anywhere]"
                        title={serial}
                      >
                        {serial}
                      </li>
                    </ul>
                  </div>
                  <p :if={@disposal.kind == :returned} class="mt-1 text-xs text-thamani-pewter">
                    Supplier: {supplier_name(item)}
                  </p>
                </div>

                <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between lg:justify-end">
                  <dl class="grid w-full grid-cols-2 gap-2 sm:w-44 sm:shrink-0">
                    <div>
                      <dt class="text-xs font-medium text-thamani-subtle">Available</dt>
                      <dd class="mt-1 text-sm font-semibold tabular-nums text-thamani-forest">
                        {item.available_quantity}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-xs font-medium text-thamani-subtle">Requested</dt>
                      <dd class="mt-1 text-sm font-semibold tabular-nums text-thamani-forest">
                        {item.quantity}
                      </dd>
                    </div>
                  </dl>
                  <.button
                    :if={@disposal.status == :draft}
                    variant="ghost"
                    type="button"
                    phx-click="remove_item"
                    phx-value-item_id={item.id}
                    class="w-full sm:w-auto"
                  >
                    Remove
                  </.button>
                </div>
              </div>
            </article>
          </div>
        </section>

        <div :if={@disposal.status == :draft} class="flex justify-end pt-2">
          <.button
            variant="primary"
            class="w-full sm:w-auto"
            disabled={@disposal.items == []}
            phx-click="confirm_submit"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Submit for approval
          </.button>
        </div>

        <div :if={@disposal.status == :pending} class="flex justify-end pt-2">
          <.button variant="ghost" class="w-full sm:w-auto" phx-click="reopen">
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Reopen for editing
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
            {if @disposal.kind == :expiry,
              do:
                "An admin will review this write-off. Once approved, the remaining quantity of each lot leaves stock.",
              else:
                "An admin will review this return. Once approved, the requested quantities leave stock."}
          </p>
          <div class="flex justify-end gap-3">
            <.button type="button" phx-click="cancel_submit">
              Cancel
            </.button>
            <.button variant="primary" phx-click="submit" phx-disable-with="Submitting…">
              Submit
            </.button>
          </div>
        </.modal>

        <aside
          :if={@disposal.status == :approved}
          class="flex items-start gap-3 rounded-2xl border border-thamani-frosted bg-td-accent-tint px-4 py-4 sm:px-5"
        >
          <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-thamani-forest" />
          <div>
            <p class="text-sm font-semibold text-thamani-forest">
              {if @disposal.kind == :expiry, do: "Write-off approved", else: "Return approved"}
            </p>
            <p class="mt-0.5 text-sm text-thamani-pewter">
              Stock was reduced to match the request above. {if @disposal.approved_at,
                do: "Approved on #{Calendar.strftime(@disposal.approved_at, "%d %b %Y at %H:%M")}.",
                else: ""}
            </p>
          </div>
        </aside>

        <aside
          :if={@disposal.status == :rejected}
          class="flex items-start gap-3 rounded-2xl border border-rose-200 bg-rose-50 px-4 py-4 sm:px-5"
        >
          <.icon name="hero-x-circle" class="mt-0.5 size-5 shrink-0 text-thamani-error" />
          <div>
            <p class="text-sm font-semibold text-thamani-error">
              {if @disposal.kind == :expiry, do: "Write-off rejected", else: "Return rejected"}
            </p>
            <p class="mt-0.5 text-sm text-rose-900">
              {@disposal.rejection_reason}
            </p>
          </div>
        </aside>
      </div>
    </Layouts.distributor_shell>
    """
  end

  defp status_message(:draft),
    do: "Add the lots, then submit for approval. Stock stays until then."

  defp status_message(:pending), do: "Awaiting admin review. You can reopen to keep editing."
  defp status_message(:approved), do: "Approved. Stock was reduced."
  defp status_message(:rejected), do: "Rejected. See the reason below."

  defp list_path(:returned), do: "/distributor/returns"
  defp list_path(_kind), do: "/distributor/expiry-write-offs"
end
