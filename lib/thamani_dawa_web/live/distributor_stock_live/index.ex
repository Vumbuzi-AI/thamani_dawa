defmodule ThamaniDawaWeb.DistributorStockLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Batches.Batch
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    site_id = SiteScoping.default_site_id(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:site_id, site_id)
     |> assign(:zone_filter, "all")
     |> assign(:location_batch, nil)
     |> assign(:location_form, nil)
     |> assign(:status_batch, nil)
     |> assign(:status_target, nil)
     |> assign(:status_form, nil)
     |> reload_batches()}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:zone_filter, Map.get(params, "zone", "all"))
     |> reload_batches()}
  end

  def handle_event("filter_zone", %{"zone" => zone}, socket) do
    {:noreply, push_patch(socket, to: ~p"/distributor/stock?zone=#{zone}")}
  end

  def handle_event("open_putaway", %{"id" => id}, socket) do
    batch = Enum.find(socket.assigns.batches, &(&1.id == String.to_integer(id)))

    {:noreply,
     socket
     |> assign(:location_batch, batch)
     |> assign(
       :location_form,
       to_form(Batch.location_changeset(batch, %{}), as: :location)
     )}
  end

  def handle_event("close_putaway", _params, socket) do
    {:noreply, socket |> assign(:location_batch, nil) |> assign(:location_form, nil)}
  end

  def handle_event("validate_putaway", %{"location" => attrs}, socket) do
    changeset =
      socket.assigns.location_batch
      |> Batch.location_changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :location_form, to_form(changeset, as: :location))}
  end

  def handle_event("save_putaway", %{"location" => attrs}, socket) do
    case Batches.putaway(socket.assigns.location_batch, attrs) do
      {:ok, _batch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Stock moved.")
         |> assign(:location_batch, nil)
         |> assign(:location_form, nil)
         |> reload_batches()}

      {:error, changeset} ->
        {:noreply, assign(socket, :location_form, to_form(changeset, as: :location))}
    end
  end

  def handle_event("open_status", %{"id" => id, "target" => target}, socket) do
    batch = Enum.find(socket.assigns.batches, &(&1.id == String.to_integer(id)))
    target = String.to_existing_atom(target)

    {:noreply,
     socket
     |> assign(:status_batch, batch)
     |> assign(:status_target, target)
     |> assign(:status_form, to_form(%{"reference" => ""}, as: :status))}
  end

  def handle_event("close_status", _params, socket) do
    {:noreply,
     socket
     |> assign(:status_batch, nil)
     |> assign(:status_target, nil)
     |> assign(:status_form, nil)}
  end

  def handle_event("validate_status_reference", %{"status" => attrs}, socket) do
    {:noreply, assign(socket, :status_form, to_form(attrs, as: :status))}
  end

  def handle_event("save_status", %{"status" => attrs}, socket) do
    user = socket.assigns.current_scope.user
    reference = String.trim(Map.get(attrs, "reference", ""))

    if socket.assigns.status_target != :expired and reference == "" do
      {:noreply,
       put_flash(socket, :error, "Enter a reference before confirming this status change.")}
    else
      case apply_status_transition(
             socket.assigns.status_batch,
             socket.assigns.status_target,
             reference,
             user
           ) do
        {:ok, _batch} ->
          {:noreply,
           socket
           |> put_flash(:info, "Status updated.")
           |> assign(:status_batch, nil)
           |> assign(:status_target, nil)
           |> assign(:status_form, nil)
           |> reload_batches()}

        {:error, _changeset} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "That status change isn't allowed from the batch's current state."
           )}
      end
    end
  end

  defp apply_status_transition(batch, :damaged, reference, user),
    do: Batches.mark_damaged(batch, reference, user)

  defp apply_status_transition(batch, :expired, _reference, user),
    do: Batches.mark_expired(batch, user)

  defp apply_status_transition(batch, :stolen, reference, user),
    do: Batches.mark_stolen(batch, reference, user)

  defp apply_status_transition(batch, :inactive, reference, user),
    do: Batches.mark_lost(batch, reference, user)

  defp apply_status_transition(batch, :non_sellable_other, reference, user),
    do: Batches.mark_exported(batch, reference, user)

  defp apply_status_transition(batch, :recalled, reference, user),
    do: Batches.mark_recalled(batch, reference, user)

  defp apply_status_transition(batch, :destroyed, reference, user),
    do: Batches.mark_destroyed(batch, reference, user)

  defp reload_batches(socket) do
    batches =
      if socket.assigns.site_id do
        socket.assigns.current_scope.organization_id
        |> Batches.list_batches_for_site(socket.assigns.site_id)
        |> Enum.filter(&(&1.remaining_quantity > 0))
      else
        []
      end

    filtered =
      case socket.assigns.zone_filter do
        "all" -> batches
        zone -> Enum.filter(batches, &(Atom.to_string(&1.zone) == zone))
      end

    socket
    |> assign(:batches, batches)
    |> assign(:grouped, Enum.group_by(filtered, & &1.zone))
  end

  defp valid_status_targets(:active),
    do: [:damaged, :expired, :stolen, :inactive, :non_sellable_other, :recalled]

  defp valid_status_targets(:quarantined), do: [:damaged, :recalled]

  defp valid_status_targets(status) when status in [:damaged, :expired],
    do: [:destroyed, :recalled]

  defp valid_status_targets(:recalled), do: [:destroyed]
  defp valid_status_targets(_status), do: []

  defp status_label(:damaged), do: "Damaged"
  defp status_label(:expired), do: "Expired"
  defp status_label(:stolen), do: "Stolen"
  defp status_label(:inactive), do: "Lost"
  defp status_label(:non_sellable_other), do: "Exported"
  defp status_label(:recalled), do: "Recalled"
  defp status_label(:destroyed), do: "Destroyed"
  defp status_label(:active), do: "Active"
  defp status_label(:quarantined), do: "Quarantined"
  defp status_label(:returned), do: "Returned"

  defp zone_label(:receiving), do: "Receiving"
  defp zone_label(:storage), do: "Storage"
  defp zone_label(:quarantine), do: "Quarantine"
  defp zone_label(:picking), do: "Picking"
  defp zone_label(:staging), do: "Staging"
  defp zone_label(:dispatch), do: "Dispatch"

  defp zones_with_batches(grouped) do
    Batch.zones()
    |> Enum.map(&{&1, Map.get(grouped, &1, [])})
    |> Enum.reject(fn {_zone, batches} -> batches == [] end)
  end

  defp product_name(product), do: product.generic_name || product.brand_name || "Unknown product"

  defp status_badge_class(:active),
    do: "bg-emerald-100 text-emerald-800 ring-1 ring-emerald-600/20"

  defp status_badge_class(status) when status in [:damaged, :expired, :recalled],
    do: "bg-amber-100 text-amber-800 ring-1 ring-amber-600/20"

  defp status_badge_class(status)
       when status in [:stolen, :inactive, :non_sellable_other, :destroyed],
       do: "bg-red-100 text-red-700 ring-1 ring-red-600/20"

  defp status_badge_class(_status),
    do: "bg-thamani-canvas text-thamani-pewter ring-1 ring-thamani-stone"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/stock"}
    >
      <.header icon="hero-cube">
        Stock
        <:subtitle>What's actually in the warehouse — by zone, bin, and status.</:subtitle>
      </.header>

      <div :if={is_nil(@site_id)} class="rounded-2xl ff-surface-card p-10 text-center">
        <.blank_state icon="hero-building-office-2" title="Pick a warehouse">
          Choose a warehouse from the site switcher in the sidebar to see its stock.
        </.blank_state>
      </div>

      <div :if={@site_id} class="mb-4 flex flex-wrap items-center gap-3">
        <div class="flex items-center gap-1 rounded-lg border border-thamani-stone bg-white p-1">
          <button
            type="button"
            phx-click="filter_zone"
            phx-value-zone="all"
            class={[
              "rounded-md px-3 py-1.5 text-xs font-semibold",
              if(@zone_filter == "all",
                do: "bg-thamani-forest text-white",
                else: "text-thamani-pewter"
              )
            ]}
          >
            All
          </button>
          <button
            :for={zone <- Batch.zones()}
            type="button"
            phx-click="filter_zone"
            phx-value-zone={zone}
            class={[
              "rounded-md px-3 py-1.5 text-xs font-semibold",
              if(@zone_filter == to_string(zone),
                do: "bg-thamani-forest text-white",
                else: "text-thamani-pewter"
              )
            ]}
          >
            {zone_label(zone)}
          </button>
        </div>
      </div>

      <div :if={@site_id && @grouped == %{}} class="rounded-2xl ff-surface-card p-10 text-center">
        <.blank_state icon="hero-cube" title="No stock here">
          Nothing is currently located in this zone at this warehouse.
        </.blank_state>
      </div>

      <div :for={{zone, batches} <- zones_with_batches(@grouped)} class="mb-6">
        <h3 class="mb-2 text-sm font-semibold text-thamani-forest">{zone_label(zone)}</h3>
        <div class="rounded-lg border border-thamani-stone bg-white">
          <table class="w-full text-left text-sm">
            <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
              <tr>
                <th class="px-3 py-2">Product</th>
                <th class="px-3 py-2">Batch</th>
                <th class="px-3 py-2">Bin</th>
                <th class="px-3 py-2">Expiry</th>
                <th class="px-3 py-2">Qty</th>
                <th class="px-3 py-2">Status</th>
                <th class="px-3 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-thamani-stone">
              <tr :for={batch <- batches} id={"stock-batch-#{batch.id}"}>
                <td class="px-3 py-2 font-medium text-thamani-forest">
                  {product_name(batch.product)}
                </td>
                <td class="px-3 py-2 font-mono text-xs">{batch.batch_no}</td>
                <td class="px-3 py-2 text-thamani-pewter">{batch.bin || "—"}</td>
                <td class="px-3 py-2 text-thamani-pewter">
                  {Calendar.strftime(batch.expiry_date, "%b %Y")}
                </td>
                <td class="px-3 py-2">{batch.remaining_quantity}</td>
                <td class="px-3 py-2">
                  <span class={[
                    "rounded-full px-2 py-0.5 text-xs font-semibold",
                    status_badge_class(batch.status)
                  ]}>
                    {status_label(batch.status)}
                  </span>
                </td>
                <td class="px-3 py-2 text-right">
                  <div class="flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="open_putaway"
                      phx-value-id={batch.id}
                      class="text-xs font-medium text-thamani-forest underline decoration-thamani-forest/40 underline-offset-2 hover:decoration-thamani-forest"
                    >
                      Move
                    </button>
                    <div :if={valid_status_targets(batch.status) != []} class="relative inline-block">
                      <details class="group">
                        <summary class="cursor-pointer list-none text-xs font-medium text-thamani-forest underline decoration-thamani-forest/40 underline-offset-2 hover:decoration-thamani-forest">
                          Change status
                        </summary>
                        <div class="absolute right-0 z-50 mt-1 w-40 rounded-lg border border-thamani-stone bg-white p-1 shadow-lg">
                          <button
                            :for={target <- valid_status_targets(batch.status)}
                            type="button"
                            phx-click="open_status"
                            phx-value-id={batch.id}
                            phx-value-target={target}
                            class="block w-full rounded-md px-2 py-1.5 text-left text-xs text-thamani-ink hover:bg-thamani-canvas"
                          >
                            {status_label(target)}
                          </button>
                        </div>
                      </details>
                    </div>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <.modal :if={@location_batch} id="putaway-modal" show on_cancel={JS.push("close_putaway")}>
        <h2 class="text-xl font-medium text-thamani-forest">Move stock</h2>
        <p class="mt-1 text-sm text-thamani-pewter">{@location_batch.batch_no}</p>
        <.form
          for={@location_form}
          id="putaway-form"
          phx-change="validate_putaway"
          phx-submit="save_putaway"
          class="mt-4"
        >
          <.input
            field={@location_form[:zone]}
            type="select"
            label="Zone"
            options={Enum.map(Batch.zones(), &{zone_label(&1), &1})}
            required
          />
          <.input field={@location_form[:bin]} label="Bin (optional)" placeholder="e.g. A-12-3" />
          <.button class="mt-3 w-full" variant="primary">Move</.button>
        </.form>
      </.modal>

      <.modal :if={@status_batch} id="status-modal" show on_cancel={JS.push("close_status")}>
        <h2 class="text-xl font-medium text-thamani-forest">
          Mark as {status_label(@status_target)}
        </h2>
        <p class="mt-1 text-sm text-thamani-pewter">{@status_batch.batch_no}</p>
        <.form
          for={@status_form}
          id="status-form"
          phx-change="validate_status_reference"
          phx-submit="save_status"
          class="mt-4"
        >
          <.input
            :if={@status_target != :expired}
            field={@status_form[:reference]}
            label="Reference (incident/recall number)"
            required
          />
          <.button class="mt-3 w-full" variant="primary">Confirm</.button>
        </.form>
      </.modal>
    </Layouts.distributor_shell>
    """
  end
end
