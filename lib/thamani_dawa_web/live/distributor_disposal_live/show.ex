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
          class="td-card td-pad"
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

        <section id="disposal-items" class="td-card">
          <.td_card_header
            title={if @disposal.kind == :expiry, do: "Lots to write off", else: "Batches in this return"}
            subtitle={
              if @disposal.status in [:draft, :pending],
                do: "Units are held from sale while the return is open.",
                else: "#{length(@disposal.items)} #{if length(@disposal.items) == 1, do: "batch", else: "batches"}"
            }
          >
            <:actions>
              <.td_button
                :if={@disposal.status == :draft}
                id="submit-disposal"
                variant="primary"
                label="Submit for approval"
                disabled={@disposal.items == []}
                phx-click="confirm_submit"
              />
              <.td_button
                :if={@disposal.status == :pending}
                id="reopen-disposal"
                glyph="arrow-u-up-left"
                label="Reopen for editing"
                phx-click="reopen"
              />
            </:actions>
          </.td_card_header>

          <div :if={@disposal.items == []} class="td-pad td-empty-wrap">
            <div class="td-empty-card">
              <p class="td-empty-title">{if(@no_lots_to_add, do: "No expired stock", else: "No batches added yet")}</p>
              <p class="td-note">
                {cond do
                  @no_lots_to_add -> "This warehouse has no lot past its date."
                  @disposal.kind == :expiry -> "Add the expired lots above."
                  true -> "Add the batches going back to the supplier above."
                end}
              </p>
            </div>
          </div>

          <div :if={@disposal.items != []} class="td-list-table" id="disposal-item-rows">
            <table class="td-rows is-static">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Batch</th>
                  <th>Expiry</th>
                  <th :if={@disposal.kind == :returned}>Supplier</th>
                  <th class="is-num">Available</th>
                  <th class="is-num">Units</th>
                  <th><span class="sr-only">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={item <- @disposal.items} id={"item-#{item.id}"}>
                  <% batch = item.batch %>
                  <td>
                    {product_name(@products_by_id, batch && batch.product_id)}
                    <span :if={batch && batch.gtin} class="td-sub td-mono td-s12">{batch.gtin}</span>
                    <button
                      :if={batch && batch.serials != []}
                      type="button"
                      class="td-link td-s12"
                      phx-click="toggle_batch_serials"
                      phx-value-batch={batch.id}
                      aria-expanded={to_string(MapSet.member?(@expanded_batches, to_string(batch.id)))}
                    >
                      {length(batch.serials)} {if length(batch.serials) == 1, do: "serial", else: "serials"}
                    </button>
                    <div :if={batch && batch.serials != [] and MapSet.member?(@expanded_batches, to_string(batch.id))}>
                      <span :for={serial <- batch.serials} class="td-chip td-mono">{serial}</span>
                    </div>
                  </td>
                  <td class="td-mono">{batch && batch.batch_no}</td>
                  <td>{batch && batch.expiry_date && ThamaniDawaWeb.TimeFormat.date(batch.expiry_date)}</td>
                  <td :if={@disposal.kind == :returned}>{supplier_name(item)}</td>
                  <td class="is-num">{item.available_quantity}</td>
                  <td class="is-num">{item.quantity}</td>
                  <td class="td-row-actions">
                    <button
                      :if={@disposal.status == :draft}
                      type="button"
                      class="td-icon-btn"
                      phx-click="remove_item"
                      phx-value-item_id={item.id}
                      aria-label="Remove"
                      title="Remove"
                    >
                      <.td_icon name="trash" class="size-4" />
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <.modal
          :if={@confirm_submit}
          id="confirm-submit-modal"
          show
          size="confirm"
          title={if @disposal.kind == :expiry, do: "Submit this write-off?", else: "Submit this return for approval?"}
          subtitle={
            if @disposal.kind == :expiry,
              do: "An admin will review this write-off. Once approved, the remaining quantity of each lot leaves stock.",
              else: "Your organisation admin reviews it. Once approved, the requested quantities leave stock."
          }
          on_cancel={JS.push("cancel_submit")}
        >
          <dl class="td-kv-list">
            <div><dt>Batches</dt><dd>{length(@disposal.items)}</dd></div>
            <div><dt>Units</dt><dd>{@disposal.items |> Enum.map(&(&1.quantity || 0)) |> Enum.sum()}</dd></div>
            <div :if={@disposal.kind == :returned}><dt>Supplier</dt><dd>{disposal_supplier(@disposal)}</dd></div>
          </dl>
          <:footer>
            <.td_button type="button" label="Cancel" phx-click="cancel_submit" />
            <.td_button id="confirm-submit" variant="primary" label="Submit for approval" phx-click="submit" phx-disable-with="Submitting…" />
          </:footer>
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
