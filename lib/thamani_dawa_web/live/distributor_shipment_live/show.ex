defmodule ThamaniDawaWeb.DistributorShipmentLive.Show do
  @moduledoc """
  The shipment review screen: origin/destination/order summary, the mobile
  user holding or submitting it, review warnings, scanned units grouped per
  shipper and product/batch, and — depending on status — approve/reject
  actions, per-unit removal, printable SSCC shipper labels, CSV export, and
  the shipment's activity log.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.Reports

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    if connected?(socket), do: Distributor.subscribe(organization_id)

    {:ok,
     socket
     |> assign(:problems, [])
     |> assign(:expanded, MapSet.new())
     |> assign(:rejecting?, false)
     |> assign(:reject_form, to_form(%{"reason" => ""}, as: :reject))
     |> load(id)}
  end

  defp load(socket, id) do
    shipment = Distributor.get_shipment!(socket.assigns.current_scope.organization_id, id)

    socket
    |> assign(:shipment, shipment)
    |> assign(:page_title, "Shipment #{shipment.order_number}")
    |> assign(:warnings, Reports.shipment_warnings(shipment))
    |> assign(:item_groups, Reports.item_groups(shipment))
    |> assign(:labels, Reports.shipper_labels(shipment))
    |> assign(:unit_count, shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum())
  end

  def handle_info({:distributor_shipment, _event, shipment_id}, socket) do
    if shipment_id == socket.assigns.shipment.id do
      {:noreply, load(socket, shipment_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_group", %{"group" => group_id}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, group_id),
        do: MapSet.delete(expanded, group_id),
        else: MapSet.put(expanded, group_id)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  def handle_event("approve", _params, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.approve_shipment(scope.organization_id, scope.user, shipment.id) do
      {:ok, _shipment} ->
        {:noreply,
         socket
         |> assign(:problems, [])
         |> put_flash(:info, "Shipment approved. SSCCs have been issued for every shipper.")
         |> load(shipment.id)}

      {:already_approved, _shipment} ->
        {:noreply,
         socket |> put_flash(:info, "This shipment is already approved.") |> load(shipment.id)}

      {:error, {:invalid, problems}} ->
        {:noreply,
         socket
         |> assign(:problems, problems)
         |> put_flash(:error, "This shipment can't be approved yet — see the problems below.")
         |> load(shipment.id)}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, error_message(reason)) |> load(shipment.id)}
    end
  end

  def handle_event("open_reject", _params, socket) do
    {:noreply,
     socket
     |> assign(:rejecting?, true)
     |> assign(:reject_form, to_form(%{"reason" => ""}, as: :reject))}
  end

  def handle_event("close_reject", _params, socket) do
    {:noreply, assign(socket, :rejecting?, false)}
  end

  def handle_event("reject", %{"reject" => %{"reason" => reason}}, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.reject_shipment(scope.organization_id, scope.user, shipment.id, reason) do
      {:ok, _shipment} ->
        {:noreply,
         socket
         |> assign(:rejecting?, false)
         |> put_flash(:info, "Shipment rejected. Its units are free to be packed again.")
         |> load(shipment.id)}

      {:error, :reason_required} ->
        form =
          to_form(%{"reason" => reason}, as: :reject, errors: [reason: {"Give a reason", []}])

        {:noreply, assign(socket, :reject_form, form)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:rejecting?, false)
         |> put_flash(:error, error_message(reason))
         |> load(shipment.id)}
    end
  end

  def handle_event("remove_item", %{"id" => item_id}, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.remove_item(scope.organization_id, scope.user, shipment.id, item_id) do
      {:ok, _shipment} ->
        {:noreply, socket |> put_flash(:info, "Unit removed.") |> load(shipment.id)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  @doc false
  def error_message(:missing_gs1_company_prefix),
    do: "Set your GS1 Company Prefix in Settings before approving — it's needed to issue SSCCs."

  def error_message({:billing, :no_active_plan}),
    do:
      "You have no active serialisation allowance. Buy a bundle on the Billing page to continue."

  def error_message({:billing, :insufficient_allowance}),
    do:
      "Not enough serials left in your bundle to issue SSCCs for every shipper. Top up on the Billing page."

  def error_message({:billing, :overdue}),
    do:
      "Your flex billing cycle is overdue. Settle it on the Billing page to keep approving shipments."

  def error_message(:reservation_missing),
    do:
      "Some scanned units no longer hold a reservation. Reject the shipment so it can be resubmitted."

  def error_message({:invalid_state, status}),
    do: "This shipment is #{status} and can't be changed."

  def error_message(:already_approved), do: "Approved shipments can't be changed."
  def error_message(:not_found), do: "That item no longer exists."
  def error_message(_reason), do: "Something went wrong. Please try again."

  defp gs1_text(item) do
    [
      "(01)",
      item.gtin,
      item.production_date && "(11)" <> Calendar.strftime(item.production_date, "%y%m%d"),
      item.expiry_date && "(17)" <> Calendar.strftime(item.expiry_date, "%y%m%d"),
      item.batch && "(10)" <> item.batch,
      "(21)",
      item.serial
    ]
    |> Enum.filter(& &1)
    |> Enum.join()
  end

  defp event_label("created"), do: "Created"
  defp event_label("updated"), do: "Updated"
  defp event_label("selected"), do: "Claimed on the mobile app"
  defp event_label("released"), do: "Released on the mobile app"
  defp event_label("submitted"), do: "Submitted for approval"
  defp event_label("approved"), do: "Approved — SSCCs issued"
  defp event_label("rejected"), do: "Rejected"
  defp event_label("reopened"), do: "Reopened as a draft"
  defp event_label("item_removed"), do: "Unit removed"
  defp event_label(event), do: Phoenix.Naming.humanize(event)

  defp actor(%{user: %{name: name}}), do: name
  defp actor(%{mobile_user: %{name: name}}), do: "#{name} (mobile)"
  defp actor(_event), do: "System"

  defp warning_icon(:serial_conflict), do: "hero-no-symbol"
  defp warning_icon(:expired), do: "hero-clock"
  defp warning_icon(_code), do: "hero-exclamation-triangle"

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/shipments"}
    >
      <div class="no-print">
        <.header icon="hero-truck" back={~p"/distributor/shipments"}>
          <span class="flex flex-wrap items-center gap-3">
            {@shipment.order_number}
            <.shipment_status_badge status={@shipment.status} />
          </span>
          <:subtitle>
            <span class="font-mono">{@shipment.reference}</span>
            · {length(@shipment.shippers)} shipper(s) · {@unit_count} unit(s)
          </:subtitle>
          <:actions>
            <.button
              :if={@shipment.status == "draft"}
              id="edit-distributor-shipment"
              navigate={~p"/distributor/shipments/#{@shipment.id}/edit"}
            >
              <.icon name="hero-pencil-square" class="size-4" /> Edit
            </.button>
            <.button
              :if={@unit_count > 0}
              id="export-distributor-shipment"
              href={~p"/distributor/shipments/#{@shipment.id}/export"}
            >
              <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
            </.button>
            <.button
              :if={@labels != []}
              id="print-distributor-labels"
              type="button"
              onclick="window.print()"
            >
              <.icon name="hero-printer" class="size-4" /> Print labels
            </.button>
            <.button
              :if={@shipment.status == "submitted"}
              id="reject-distributor-shipment"
              variant="destructive"
              phx-click="open_reject"
            >
              Reject
            </.button>
            <.button
              :if={@shipment.status == "submitted"}
              id="approve-distributor-shipment"
              variant="primary"
              phx-click="approve"
              phx-disable-with="Approving…"
              data-confirm={"Approve and issue #{length(@shipment.shippers)} SSCC(s)? This uses #{length(@shipment.shippers)} serial(s) from your allowance."}
            >
              <.icon name="hero-check-badge" class="size-4" /> Approve &amp; issue SSCCs
            </.button>
          </:actions>
        </.header>

        <div
          :if={@shipment.status == "rejected"}
          id="distributor-rejection-reason"
          class="mb-5 flex gap-3 rounded-2xl border border-rose-200 bg-rose-50 p-4"
        >
          <.icon name="hero-x-circle" class="mt-0.5 size-5 shrink-0 text-rose-700" />
          <div class="text-sm">
            <p class="font-semibold text-rose-900">
              Rejected by {(@shipment.rejected_by && @shipment.rejected_by.name) || "an administrator"} · {date_time(
                @shipment.rejected_at
              )}
            </p>
            <p class="mt-1 text-rose-800">{@shipment.rejection_reason}</p>
            <p class="mt-1 text-xs text-rose-700">
              The mobile user can reopen it as a draft, fix it, and resubmit.
            </p>
          </div>
        </div>

        <div
          :if={@problems != []}
          id="distributor-approval-problems"
          class="mb-5 rounded-2xl border border-rose-200 bg-white p-4"
        >
          <p class="flex items-center gap-2 text-sm font-semibold text-rose-800">
            <.icon name="hero-exclamation-circle" class="size-5" /> Can't approve yet
          </p>
          <ul class="mt-2 list-disc space-y-1 pl-6 text-sm text-rose-800">
            <li :for={problem <- @problems}>{problem.message}</li>
          </ul>
        </div>

        <div class="grid gap-4 md:grid-cols-3">
          <.party_card
            title="Ship from"
            icon="hero-building-office-2"
            company={@shipment.origin_company}
            address={@shipment.origin_address}
            po_box={@shipment.origin_po_box}
            gln={@shipment.origin_gln}
          />
          <.party_card
            title="Ship to"
            icon="hero-building-storefront"
            company={@shipment.destination_company}
            address={@shipment.destination_address}
            po_box={@shipment.destination_po_box}
            gln={@shipment.destination_gln}
          />
          <div class="rounded-2xl ff-surface-card p-4">
            <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
              <.icon name="hero-device-phone-mobile" class="size-4" /> Mobile team
            </div>
            <dl class="mt-2 space-y-1.5 text-sm">
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Held by</dt>
                <dd class="text-right font-medium text-thamani-forest">
                  {(@shipment.assigned_to && @shipment.assigned_to.name) || "Unclaimed"}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Submitted by</dt>
                <dd class="text-right font-medium text-thamani-forest">
                  {(@shipment.submitted_by && @shipment.submitted_by.name) || "—"}
                </dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Submitted</dt>
                <dd class="text-right">{date_time(@shipment.submitted_at)}</dd>
              </div>
              <div :if={@shipment.approved_at} class="flex justify-between gap-3">
                <dt class="text-thamani-pewter">Approved</dt>
                <dd class="text-right">
                  {date_time(@shipment.approved_at)}
                  <span :if={@shipment.approved_by} class="block text-xs text-thamani-pewter">
                    by {@shipment.approved_by.name}
                  </span>
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <div
          :if={@warnings != []}
          id="distributor-shipment-warnings"
          class="mt-5 grid gap-2 sm:grid-cols-2"
        >
          <div
            :for={warning <- @warnings}
            id={"warning-#{warning.code}"}
            class="flex items-start gap-3 rounded-xl border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900"
          >
            <.icon name={warning_icon(warning.code)} class="mt-0.5 size-4 shrink-0" />
            <span><span class="font-semibold">{warning.count}</span> {warning.message}</span>
          </div>
        </div>

        <section class="mt-6 space-y-4" id="distributor-shippers">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Shippers</h2>
          <div
            :if={@item_groups == []}
            class="rounded-2xl border border-dashed border-thamani-stone bg-thamani-canvas p-8 text-center text-sm text-thamani-pewter"
          >
            <.icon name="hero-device-phone-mobile" class="mx-auto mb-2 size-8 text-thamani-subtle" />
            Nothing packed yet. A mobile user finds this shipment by order
            <span class="font-semibold text-thamani-forest">{@shipment.order_number}</span>
            and scans units into shippers.
          </div>

          <article
            :for={%{shipper: shipper, groups: groups} <- @item_groups}
            id={"shipper-#{shipper.id}"}
            class="overflow-hidden rounded-2xl ff-surface-card"
          >
            <header class="flex flex-wrap items-center justify-between gap-3 border-b border-thamani-stone px-4 py-3 sm:px-5">
              <div class="flex items-center gap-3">
                <span class="flex size-8 items-center justify-center rounded-lg bg-thamani-canvas text-sm font-semibold text-thamani-forest">
                  {shipper.sequence}
                </span>
                <div>
                  <p class="font-medium text-thamani-forest">{shipper.name}</p>
                  <p class="text-xs text-thamani-pewter">{length(shipper.items)} unit(s)</p>
                </div>
              </div>
              <span
                :if={shipper.sscc}
                class="rounded-lg bg-thamani-lime px-3 py-1 font-mono text-xs font-semibold text-thamani-forest"
              >
                SSCC {shipper.sscc}
              </span>
            </header>

            <p :if={groups == []} class="px-5 py-4 text-sm text-thamani-pewter">
              No units scanned into this shipper.
            </p>

            <div
              :for={group <- groups}
              id={group.id}
              class="border-b border-thamani-stone last:border-b-0"
            >
              <button
                type="button"
                phx-click="toggle_group"
                phx-value-group={group.id}
                class="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 py-3 text-left transition-colors duration-150 hover:bg-thamani-canvas sm:grid-cols-[minmax(0,2fr)_repeat(3,minmax(0,1fr))_auto] sm:px-5"
                aria-expanded={to_string(MapSet.member?(@expanded, group.id))}
              >
                <span class="min-w-0">
                  <span class="block truncate text-sm font-medium text-thamani-ink">
                    {group.product_name || "Unverified product"}
                  </span>
                  <span class="block font-mono text-xs text-thamani-pewter">{group.gtin}</span>
                </span>
                <span class="hidden text-sm sm:block">
                  <span class="block text-xs text-thamani-pewter">Batch</span>{group.batch || "—"}
                </span>
                <span class="hidden text-sm sm:block">
                  <span class="block text-xs text-thamani-pewter">Expiry</span>{short_date(
                    group.expiry_date
                  )}
                </span>
                <span class="hidden text-sm sm:block">
                  <span class="block text-xs text-thamani-pewter">Units</span>{group.count}
                </span>
                <span class="flex items-center gap-1 text-xs font-semibold text-thamani-forest">
                  <span class="sm:hidden">{group.count} ·</span>
                  {if MapSet.member?(@expanded, group.id), do: "Hide units", else: "View units"}
                  <.icon
                    name="hero-chevron-down"
                    class={[
                      "size-4 transition-transform duration-200",
                      MapSet.member?(@expanded, group.id) && "rotate-180"
                    ]}
                  />
                </span>
              </button>

              <ul
                :if={MapSet.member?(@expanded, group.id)}
                id={"#{group.id}-units"}
                class="grid gap-3 bg-thamani-canvas/60 px-4 py-4 sm:grid-cols-2 sm:px-5 xl:grid-cols-3"
              >
                <li
                  :for={item <- group.items}
                  id={"shipment-item-#{item.id}"}
                  class="flex gap-3 rounded-xl border border-thamani-stone bg-white p-3"
                >
                  <canvas
                    id={"unit-datamatrix-#{item.id}"}
                    phx-hook="DataMatrix"
                    phx-update="ignore"
                    data-gs1-text={gs1_text(item)}
                    class="size-16 shrink-0"
                  ></canvas>
                  <div class="min-w-0 flex-1 text-xs">
                    <p class="truncate font-mono text-sm text-thamani-ink">{item.serial}</p>
                    <p class="text-thamani-pewter">
                      {(item.scanned_by && item.scanned_by.name) || "—"} · {date_time(item.scanned_at)}
                    </p>
                    <div class="mt-1.5 flex flex-wrap items-center gap-2">
                      <.validation_badge status={item.validation_status} />
                      <button
                        :if={@shipment.status != "approved"}
                        type="button"
                        id={"remove-item-#{item.id}"}
                        phx-click="remove_item"
                        phx-value-id={item.id}
                        data-confirm="Remove this unit from the shipment?"
                        class="font-semibold text-rose-700 hover:underline"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                </li>
              </ul>
            </div>
          </article>
        </section>

        <section
          :if={@shipment.events != []}
          class="mt-6 rounded-2xl ff-surface-card p-5"
          id="distributor-shipment-activity"
        >
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">Activity</h2>
          <ol class="mt-3 space-y-3 border-l border-thamani-stone pl-4">
            <li :for={event <- @shipment.events} class="relative text-sm">
              <span class="absolute -left-[21px] top-1.5 size-2.5 rounded-full bg-thamani-forest"></span>
              <p class="font-medium text-thamani-ink">{event_label(event.event)}</p>
              <p class="text-xs text-thamani-pewter">
                {actor(event)} · {date_time(event.inserted_at)}
              </p>
              <p :if={event.details["reason"]} class="mt-0.5 text-xs text-thamani-ink">
                “{event.details["reason"]}”
              </p>
            </li>
          </ol>
        </section>
      </div>

      <section :if={@labels != []} id="distributor-sscc-labels" class="mt-6">
        <h2 class="no-print mb-3 text-sm font-semibold uppercase tracking-wide text-thamani-pewter">
          SSCC shipper labels
        </h2>
        <div class="printable-sscc-labels grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          <div
            :for={label <- @labels}
            id={"sscc-label-#{label.id}"}
            class="printable-sscc-label rounded-2xl border-2 border-thamani-ink bg-white p-4 text-thamani-ink"
          >
            <div class="grid grid-cols-2 gap-3 border-b border-thamani-ink pb-3 text-xs">
              <div>
                <p class="font-semibold uppercase">From</p>
                <p class="font-medium">{label.ship_from.company}</p>
                <p>{label.ship_from.address}</p>
                <p class="font-mono">GLN {label.ship_from.gln}</p>
              </div>
              <div>
                <p class="font-semibold uppercase">To</p>
                <p class="font-medium">{label.ship_to.company}</p>
                <p>{label.ship_to.address}</p>
                <p :if={label.ship_to.po_box}>{label.ship_to.po_box}</p>
                <p class="font-mono">GLN {label.ship_to.gln}</p>
              </div>
            </div>
            <div class="grid grid-cols-2 gap-3 border-b border-thamani-ink py-3 text-xs">
              <div>
                <p class="font-semibold uppercase">Order</p>
                <p class="font-mono">{label.order_number}</p>
              </div>
              <div>
                <p class="font-semibold uppercase">Shipper</p>
                <p>{label.name} ({label.position})</p>
              </div>
              <%= if label.mixed do %>
                <div class="col-span-2">
                  <p class="font-semibold uppercase">Contents</p>
                  <p>Mixed — {label.unit_count} unit(s)</p>
                </div>
              <% else %>
                <div class="col-span-2">
                  <p class="font-semibold uppercase">Contents</p>
                  <p>{label.product_name || "Product"} — {label.unit_count} unit(s)</p>
                  <p class="font-mono">(02) {label.gtin}</p>
                </div>
                <div>
                  <p class="font-semibold uppercase">Batch</p>
                  <p class="font-mono">(10) {label.batch}</p>
                </div>
                <div>
                  <p class="font-semibold uppercase">Expiry</p>
                  <p class="font-mono">(17) {short_date(label.expiry_date)}</p>
                </div>
              <% end %>
            </div>
            <div class="pt-3 text-center">
              <p class="text-xs font-semibold uppercase">SSCC</p>
              <canvas
                id={"sscc-barcode-#{label.id}"}
                phx-hook="SsccBarcode"
                phx-update="ignore"
                data-sscc={label.sscc}
                class="mx-auto mt-1 h-auto w-full"
              ></canvas>
              <p class="mt-1 font-mono text-sm font-semibold tracking-wider">(00) {label.sscc}</p>
            </div>
          </div>
        </div>
      </section>

      <.modal
        :if={@rejecting?}
        id="distributor-reject-modal"
        show
        on_cancel={JS.push("close_reject")}
      >
        <h2 class="mb-1 text-2xl font-medium tracking-tight text-thamani-forest">Reject shipment</h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          The reason is shown to the mobile team. All {@unit_count} unit(s) are released so they can
          be packed again.
        </p>
        <.form for={@reject_form} id="distributor-reject-form" phx-submit="reject">
          <.input
            field={@reject_form[:reason]}
            type="textarea"
            label="Reason"
            placeholder="e.g. Shipper 2 contains expired units — repack without them."
            required
          />
          <.button id="confirm-reject-shipment" variant="destructive" class="mt-2 w-full">
            Reject shipment
          </.button>
        </.form>
      </.modal>
    </Layouts.distributor_shell>
    """
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :company, :string, default: nil
  attr :address, :string, default: nil
  attr :po_box, :string, default: nil
  attr :gln, :string, required: true

  defp party_card(assigns) do
    ~H"""
    <div class="rounded-2xl ff-surface-card p-4">
      <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
        <.icon name={@icon} class="size-4" /> {@title}
      </div>
      <p class="mt-2 font-medium text-thamani-forest">{@company || "—"}</p>
      <p :if={@address} class="text-sm text-thamani-ink">{@address}</p>
      <p :if={@po_box} class="text-sm text-thamani-ink">{@po_box}</p>
      <p class="mt-1 font-mono text-xs text-thamani-pewter">GLN {@gln}</p>
    </div>
    """
  end
end
