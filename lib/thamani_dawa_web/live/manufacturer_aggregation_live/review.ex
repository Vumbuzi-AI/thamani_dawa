defmodule ThamaniDawaWeb.ManufacturerAggregationLive.Review do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Manufacturing

  def mount(%{"id" => id}, _session, socket) do
    aggregation =
      Manufacturing.get_aggregation!(socket.assigns.current_scope.organization_id, id)

    {:ok,
     socket
     |> assign(:page_title, aggregation.reference)
     |> assign(:rejecting, false)
     |> assign_aggregation(aggregation)}
  end

  def handle_event("approve", _params, socket) do
    scope = socket.assigns.current_scope

    case Manufacturing.approve_aggregation(
           scope.organization_id,
           scope.user,
           socket.assigns.aggregation.id
         ) do
      {:ok, aggregation} ->
        aggregation =
          Manufacturing.get_aggregation!(scope.organization_id, aggregation.id)

        {:noreply,
         socket
         |> assign_aggregation(aggregation)
         |> put_flash(:info, "Aggregation approved and manufacturer EPCIS packing event queued.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This aggregation is already approved.")}

      {:error, {:invalid_state, _status}} ->
        {:noreply, put_flash(socket, :error, "This aggregation can no longer be approved.")}

      {:error, {:invalid, _items}} ->
        {:noreply,
         put_flash(socket, :error, "Some serials are no longer valid. Review them before approving.")}

      {:error, {:over_capacity, _details}} ->
        {:noreply, put_flash(socket, :error, "This aggregation exceeds the target SSCC capacity.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Aggregation could not be approved.")}
    end
  end

  def handle_event("open_reject", _params, socket),
    do: {:noreply, assign(socket, :rejecting, true)}

  def handle_event("cancel_reject", _params, socket),
    do: {:noreply, assign(socket, :rejecting, false)}

  def handle_event("reject", %{"reason" => reason}, socket) do
    scope = socket.assigns.current_scope

    case Manufacturing.reject_aggregation(
           scope.organization_id,
           scope.user,
           socket.assigns.aggregation.id,
           reason
         ) do
      {:ok, aggregation} ->
        aggregation =
          Manufacturing.get_aggregation!(scope.organization_id, aggregation.id)

        {:noreply,
         socket
         |> assign(:rejecting, false)
         |> assign_aggregation(aggregation)
         |> put_flash(:info, "Aggregation rejected.")}

      {:error, {:invalid_state, "approved"}} ->
        {:noreply, put_flash(socket, :info, "This aggregation is already approved.")}

      {:error, {:invalid_state, _status}} ->
        {:noreply, put_flash(socket, :error, "This aggregation can no longer be rejected.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Aggregation could not be rejected.")}
    end
  end

  defp assign_aggregation(socket, aggregation) do
    socket
    |> assign(:aggregation, aggregation)
    |> assign(
      :approveable?,
      aggregation.status == "submitted" and
        Enum.all?(aggregation.items, &(&1.validation_status == "ok"))
    )
  end

  defp batch_label(%{batches: batches}) do
    case Enum.map(batches, & &1.batch_no) do
      [] -> "—"
      batch_numbers -> Enum.join(batch_numbers, ", ")
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/aggregations"}
    >
      <div class="no-print">
        <.header icon="hero-qr-code" back={~p"/manufacturer/aggregations"}>
          <span class="flex flex-wrap items-center gap-3">{@aggregation.reference}<.aggregation_status_badge status={
            @aggregation.status
          } /></span>
          <:subtitle>
            <span class="tracking-tight tabular-nums">{@aggregation.shipper_sscc.code}</span>
            · {length(@aggregation.items)} serial(s)
          </:subtitle>
          <:actions>
            <div class="flex w-full flex-col gap-2 sm:flex-row sm:flex-wrap md:w-auto md:justify-end md:[&>*]:w-auto">
              <.button
                :if={@aggregation.status == "submitted"}
                id="reject-manufacturer-aggregation"
                phx-click="open_reject"
              ><.icon name="hero-x-circle" class="size-4" /> Reject</.button>
              <.button
                :if={@approveable?}
                id="approve-manufacturer-aggregation"
                variant="primary"
                phx-click="approve"
              ><.icon name="hero-check-badge" class="size-4" /> Approve aggregation</.button>
            </div>
          </:actions>
        </.header>

        <div class="grid gap-4 md:grid-cols-2">
          <div class="rounded-2xl ff-surface-card p-4">
            <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              <.icon name="hero-qr-code" class="size-4" /> Target SSCC
            </div>
            <p class="mt-2 font-mono text-sm font-semibold text-thamani-forest">
              {@aggregation.shipper_sscc.code}
            </p>
            <dl class="mt-2 space-y-1.5 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">GTIN</dt>
                <dd class="text-right font-mono text-xs">{@aggregation.shipper_sscc.gtin || "—"}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Batch</dt>
                <dd class="text-right">{batch_label(@aggregation.shipper_sscc)}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Capacity</dt>
                <dd class="text-right">
                  {@aggregation.shipper_sscc.count_of_trade_items || 0} trade items
                </dd>
              </div>
            </dl>
          </div>

          <div class="rounded-2xl ff-surface-card p-4">
            <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              <.icon name="hero-user-group" class="size-4" /> Manufacturing team
            </div>
            <dl class="mt-2 space-y-1.5 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Created by</dt>
                <dd class="text-right font-medium text-thamani-forest">
                  {(@aggregation.created_by && @aggregation.created_by.name) || "—"}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Created</dt>
                <dd class="text-right">{date_time(@aggregation.inserted_at)}</dd>
              </div>
              <div :if={@aggregation.approved_at} class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Approved</dt>
                <dd class="text-right">
                  {date_time(@aggregation.approved_at)}<span
                    :if={@aggregation.approved_by}
                    class="block text-xs text-thamani-pewter"
                  >by {@aggregation.approved_by.name}</span>
                </dd>
              </div>
              <div :if={@aggregation.rejected_at} class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Rejected</dt>
                <dd class="text-right">
                  {date_time(@aggregation.rejected_at)}<span
                    :if={@aggregation.rejected_by}
                    class="block text-xs text-thamani-pewter"
                  >by {@aggregation.rejected_by.name}</span>
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <section class="mt-6 space-y-4" id="manufacturer-aggregation-items">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">
            Scanned serials
          </h2>
          <div
            :if={@aggregation.items == []}
            class="rounded-2xl border border-dashed border-thamani-stone bg-thamani-canvas p-8 text-center text-sm text-thamani-pewter"
          >
            <.icon name="hero-device-phone-mobile" class="mx-auto mb-2 size-8 text-thamani-subtle" />
            Nothing scanned yet. Add serials from the new aggregation form or the mobile app.
          </div>
          <ul class="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            <li
              :for={item <- @aggregation.items}
              id={"aggregation-item-#{item.id}"}
              class="rounded-xl border border-thamani-stone bg-white p-3 text-sm"
            >
              <div class="flex items-start justify-between gap-2">
                <div class="min-w-0">
                  <p class="font-medium">Serial</p>
                  <p class="font-mono text-xs text-thamani-pewter">{item.serial}</p>
                </div>
                <.aggregation_validation_badge status={item.validation_status} />
              </div>
              <p class="mt-1 font-mono text-xs text-thamani-pewter">{item.gtin || "—"}</p>
            </li>
          </ul>
        </section>

        <section class="mt-6 rounded-2xl ff-surface-card p-5" id="manufacturer-aggregation-activity">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Activity</h2>
          <ol class="mt-4 border-l border-thamani-stone pl-5">
            <li class="relative pb-5">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span>
              <p class="font-medium">Created</p>
              <p class="text-xs text-thamani-pewter">
                {(@aggregation.created_by && @aggregation.created_by.name) || "System"} · {date_time(
                  @aggregation.inserted_at
                )}
              </p>
            </li>
            <li
              :if={@aggregation.status in ["submitted", "approved", "rejected"]}
              class="relative pb-5"
            >
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span>
              <p class="font-medium">Submitted for approval</p>
              <p class="text-xs text-thamani-pewter">
                {date_time(@aggregation.submitted_at)}
              </p>
            </li>
            <li :if={@aggregation.status == "approved"} class="relative pb-5">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span>
              <p class="font-medium">Approved · EPCIS packing event queued</p>
              <p class="text-xs text-thamani-pewter">
                {(@aggregation.approved_by && @aggregation.approved_by.name) || "System"} · {date_time(
                  @aggregation.approved_at
                )}
              </p>
            </li>
            <li :if={@aggregation.status == "rejected"} class="relative">
              <span class="absolute -left-[1.55rem] top-1.5 size-3 rounded-full bg-thamani-forest"></span>
              <p class="font-medium">Rejected</p>
              <p class="text-xs text-thamani-pewter">
                {(@aggregation.rejected_by && @aggregation.rejected_by.name) || "System"} · {date_time(
                  @aggregation.rejected_at
                )}
              </p>
              <p :if={@aggregation.rejection_reason not in [nil, ""]} class="mt-1 text-xs">
                {@aggregation.rejection_reason}
              </p>
            </li>
          </ol>
        </section>
      </div>

      <.modal
        :if={@rejecting}
        id="reject-aggregation-modal"
        show
        close_on_click_away={false}
        on_cancel={JS.push("cancel_reject")}
      >
        <.header icon="hero-x-circle">
          Reject aggregation
          <:subtitle>Give the manufacturing team a reason for rejecting this pack.</:subtitle>
        </.header>
        <form id="reject-aggregation-form" phx-submit="reject" class="mt-4 space-y-4">
          <.input
            name="reason"
            label="Rejection reason"
            placeholder="e.g. Wrong batch or over capacity"
            required
          />
          <div class="flex flex-col-reverse gap-3 sm:flex-row sm:justify-end">
            <.button type="button" phx-click="cancel_reject" variant="ghost">Cancel</.button>
            <.button id="confirm-reject-aggregation" variant="destructive">
              Reject aggregation
            </.button>
          </div>
        </form>
      </.modal>
    </Layouts.manufacturer_shell>
    """
  end
end
