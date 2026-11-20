defmodule ThamaniDawaWeb.LabDisposalLive.Show do
  @moduledoc """
  Editing workspace for a lab disposal request. The requester adds
  batches with the quantity to dispose, then submits for admin approval —
  which decrements each batch's `remaining_quantity` and, if that fully
  empties an active batch, transitions its status.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites

  @base_path "/lab/disposals"

  def mount(%{"id" => id}, _session, socket) do
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
     |> assign(:confirm_submit, false)}
  end

  defp addable_batches(org_id, disposal) do
    already_added_ids = MapSet.new(disposal.items, & &1.batch_id)

    org_id
    |> Batches.list_active_batches_for_site_by_inventory_type(
      disposal.site_id,
      disposal.inventory_type
    )
    |> Enum.reject(&MapSet.member?(already_added_ids, &1.id))
  end

  def handle_event(
        "add_batch",
        %{"batch_id" => batch_id_str, "quantity" => quantity_str},
        socket
      )
      when batch_id_str != "" do
    scope = socket.assigns.current_scope
    org_id = scope.organization_id
    disposal = socket.assigns.disposal

    with {batch_id, ""} <- Integer.parse(batch_id_str),
         {quantity, ""} <- Integer.parse(quantity_str),
         true <- quantity > 0 do
      batch = Batches.get_batch!(org_id, batch_id)

      case InventoryDisposals.add_item(disposal, batch, quantity) do
        {:ok, _item} ->
          {:noreply, socket |> put_flash(:info, "Batch added.") |> reload(org_id)}

        {:error, :not_draft} ->
          {:noreply, put_flash(socket, :error, "This disposal is no longer a draft.")}

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

  defp reload(socket, org_id) do
    disposal = InventoryDisposals.get_disposal!(org_id, socket.assigns.disposal.id)

    assign(socket,
      disposal: disposal,
      addable_batches: addable_batches(org_id, disposal)
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

  defp supplier_name(%{batch: %{supplier: %{name: name}}}), do: name
  defp supplier_name(_item), do: "—"

  defp format_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  defp kind_label(:expiry), do: "Expiry write-off"
  defp kind_label(:returned), do: "Supplier return"

  def render(assigns) do
    assigns = assign(assigns, :base_path, @base_path)

    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={@base_path}>
      <div class="space-y-6">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 class="text-2xl font-semibold tracking-tight text-slate-900">
              {kind_label(@disposal.kind)} — {@site.name}
            </h1>
            <p class="mt-1 text-sm text-thamani-pewter">{status_message(@disposal.status)}</p>
          </div>
          <.status_badge status={@disposal.status} />
        </div>

        <section
          :if={@disposal.status == :draft}
          id="add-batch-panel"
          class="rounded-xl ff-surface-card p-4 sm:p-5"
        >
          <h2 class="mb-3 text-sm font-semibold text-slate-700">Add a batch to dispose</h2>
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
                prompt="Choose a batch"
              />
            </div>
            <div class="[&>div]:mb-0">
              <.input type="number" name="quantity" label="Quantity" min="1" required />
            </div>
            <.button variant="primary" phx-disable-with="Adding…">
              Add batch
            </.button>
          </form>
          <p :if={@addable_batches == []} class="mt-2 text-sm text-thamani-pewter">
            All active batches at this site have been added to this disposal.
          </p>
        </section>

        <section id="disposal-items">
          <h2 class="mb-3 text-sm font-semibold text-slate-700">
            Batches to dispose
            <span class="ml-1 rounded-full bg-thamani-stone px-2 py-0.5 text-xs font-normal text-thamani-pewter">
              {length(@disposal.items)}
            </span>
          </h2>

          <.blank_state
            :if={@disposal.items == []}
            icon="hero-trash"
            title="No batches added yet"
          >
            Add batches above to build this disposal request.
          </.blank_state>

          <div id="disposal-item-rows" class="space-y-3">
            <%= for item <- @disposal.items do %>
              <% batch = item.batch %>
              <article id={"item-#{item.id}"} class="overflow-hidden rounded-xl ff-surface-card">
                <div class="flex flex-col gap-4 p-4 sm:flex-row sm:items-center sm:justify-between">
                  <div class="min-w-0">
                    <p class="font-medium text-slate-900">
                      {product_name(@products_by_id, batch && batch.product_id)}
                    </p>
                    <p class="mt-0.5 font-mono text-xs text-thamani-subtle">
                      {batch && batch.batch_no} · {batch && batch.gtin}
                    </p>
                    <p :if={@disposal.kind == :returned} class="mt-0.5 text-xs text-thamani-subtle">
                      Supplier: {supplier_name(item)}
                    </p>
                  </div>

                  <dl class="grid grid-cols-2 gap-x-6 text-center text-sm">
                    <div>
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Available
                      </dt>
                      <dd class="mt-0.5 font-semibold tabular-nums text-slate-900">
                        {item.available_quantity}
                      </dd>
                    </div>
                    <div>
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Requested
                      </dt>
                      <dd class="mt-0.5 font-semibold tabular-nums text-slate-900">
                        {item.quantity}
                      </dd>
                    </div>
                  </dl>

                  <.button
                    :if={@disposal.status == :draft}
                    variant="ghost"
                    phx-click="remove_item"
                    phx-value-item_id={item.id}
                    class="!py-2"
                  >
                    Remove
                  </.button>
                </div>
              </article>
            <% end %>
          </div>
        </section>

        <div :if={@disposal.status == :draft} class="flex justify-end pt-2">
          <.button variant="primary" phx-click="confirm_submit">
            <.icon name="hero-paper-airplane" class="size-4" /> Submit for approval
          </.button>
        </div>

        <div :if={@disposal.status == :pending} class="flex justify-end pt-2">
          <.button variant="ghost" phx-click="reopen">
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
            An organization admin will review this disposal and, if approved, the batches' quantities will be reduced accordingly. Continue?
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
          class="flex items-start gap-3 rounded-xl border border-emerald-100 bg-emerald-50/60 px-4 py-3.5"
        >
          <.icon name="hero-check-circle" class="mt-0.5 size-5 shrink-0 text-emerald-600" />
          <div>
            <p class="text-sm font-semibold text-emerald-800">Disposal approved</p>
            <p class="mt-0.5 text-sm text-emerald-700">
              Batch quantities were reduced to match the disposal recorded above. {if @disposal.approved_at,
                do: "Approved on #{Calendar.strftime(@disposal.approved_at, "%d %b %Y at %H:%M")}.",
                else: ""}
            </p>
          </div>
        </aside>

        <aside
          :if={@disposal.status == :rejected}
          class="flex items-start gap-3 rounded-xl border border-rose-100 bg-rose-50/60 px-4 py-3.5"
        >
          <.icon name="hero-x-circle" class="mt-0.5 size-5 shrink-0 text-rose-600" />
          <div>
            <p class="text-sm font-semibold text-rose-800">Disposal rejected</p>
            <p class="mt-0.5 text-sm text-rose-700">
              {@disposal.rejection_reason}
            </p>
          </div>
        </aside>
      </div>
    </Layouts.lab_shell>
    """
  end

  defp status_message(:draft), do: "Add batches and quantities, then submit for admin approval."
  defp status_message(:pending), do: "Awaiting admin review. You can reopen to keep editing."
  defp status_message(:approved), do: "Approved. Batch quantities were reduced."
  defp status_message(:rejected), do: "Rejected. See the reason below."
end
