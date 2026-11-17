defmodule ThamaniDawaWeb.DistributorShipmentLive.Show do
  @moduledoc """
  The shipment review screen: origin/destination/order summary, the mobile
  user holding or submitting it, review warnings, scanned units grouped per
  shipper and product/batch, and — depending on status — approve/reject
  actions, per-unit removal, printable SSCC shipper labels, CSV export, and
  the shipment's activity log.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, SerialUsage}
  alias ThamaniDawa.Distributor.Reports
  alias ThamaniDawa.Products

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  def mount(%{"id" => id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    if connected?(socket), do: Distributor.subscribe(organization_id)

    {:ok,
     socket
     |> assign(:problems, [])
     |> assign(:expanded, MapSet.new())
     |> assign(:approving?, false)
     |> assign(:approval_confirming?, false)
     |> assign(:rejecting?, false)
     |> assign(:reject_form, to_form(%{"reason" => ""}, as: :reject))
     |> assign(:products, Products.list_products(organization_id))
     |> assign(
       :line_item_form,
       to_form(%{"product_id" => "", "quantity" => ""}, as: :line_item)
     )
     |> assign(:editing_line_items?, true)
     |> load(id)}
  end

  defp load(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    shipment = Distributor.get_shipment!(organization_id, id)
    usage = Billing.active_usage(organization_id)
    shipper_count = length(shipment.shippers)
    remaining_allowance = SerialUsage.serials_left(usage)

    socket
    |> assign(:shipment, shipment)
    |> assign(:page_title, "Shipment #{shipment.order_number}")
    |> assign(:warnings, Reports.shipment_warnings(shipment))
    |> assign(:item_groups, Reports.item_groups(shipment))
    |> assign(:labels, Reports.shipper_labels(shipment))
    |> assign(:unit_count, shipment.shippers |> Enum.map(&length(&1.items)) |> Enum.sum())
    |> assign(:serial_usage, usage)
    |> assign(:shipper_count, shipper_count)
    |> assign(:remaining_allowance, remaining_allowance)
    |> assign(
      :insufficient_allowance?,
      is_integer(remaining_allowance) and shipper_count > remaining_allowance
    )
    |> assign(
      :reserved_batches,
      Batches.list_reserved_batches_for_shipment(organization_id, shipment.id)
    )
    |> assign(:available_by_product_id, available_by_product_id(organization_id, shipment))
  end

  defp available_by_product_id(_organization_id, %{origin_site_id: nil}), do: %{}

  defp available_by_product_id(organization_id, shipment) do
    Map.new(shipment.line_items, fn line ->
      {line.product_id,
       Batches.available_to_pick(organization_id, shipment.origin_site_id, line.product_id)}
    end)
  end

  defp insufficient_stock?(line_items, available_by_product_id) do
    Enum.any?(line_items, fn line ->
      Map.get(available_by_product_id, line.product_id, 0) < line.quantity
    end)
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

  def handle_event("open_approve", _params, %{assigns: %{approving?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("open_approve", _params, socket),
    do: {:noreply, assign(socket, :approval_confirming?, true)}

  def handle_event("close_approve", _params, socket),
    do: {:noreply, assign(socket, :approval_confirming?, false)}

  def handle_event("approve", _params, %{assigns: %{approving?: true}} = socket),
    do: {:noreply, socket}

  def handle_event("approve", _params, socket) do
    socket = assign(socket, approving?: true, approval_confirming?: false)
    %{current_scope: scope, shipment: shipment} = socket.assigns

    {:noreply,
     start_async(socket, :approve_shipment, fn ->
       Distributor.approve_shipment(scope.organization_id, scope.user, shipment.id)
     end)}
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

  def handle_event("validate_line_item", %{"line_item" => attrs}, socket) do
    {:noreply, assign(socket, :line_item_form, to_form(attrs, as: :line_item))}
  end

  def handle_event("add_line_item", %{"line_item" => attrs}, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.add_line_item(scope.organization_id, shipment.id, attrs) do
      {:ok, _line_item} ->
        {:noreply,
         socket
         |> assign(
           :line_item_form,
           to_form(%{"product_id" => "", "quantity" => ""}, as: :line_item)
         )
         |> load(shipment.id)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :line_item_form, to_form(changeset, as: :line_item))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("remove_line_item", %{"id" => id}, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.remove_line_item(scope.organization_id, id) do
      {:ok, _} -> {:noreply, load(socket, shipment.id)}
      {:error, reason} -> {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("generate_pick_list", _params, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns

    case Distributor.generate_pick_list(scope.organization_id, shipment.id) do
      {:ok, _shipment} ->
        socket = load(socket, shipment.id)

        if socket.assigns.reserved_batches == [] do
          {:noreply,
           put_flash(
             socket,
             :error,
             "No available stock found at this site for these products — nothing was reserved."
           )}
        else
          {:noreply,
           socket
           |> put_flash(:info, "Pick list generated.")
           |> assign(:editing_line_items?, false)}
        end

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Couldn't generate a pick list. Check stock availability.")}
    end
  end

  def handle_event("edit_line_items", _params, socket) do
    {:noreply, assign(socket, :editing_line_items?, true)}
  end

  def handle_event("confirm_pick_list", _params, socket) do
    %{current_scope: scope, shipment: shipment} = socket.assigns
    :ok = Distributor.confirm_pick_list(scope.organization_id, shipment.id)

    {:noreply,
     socket
     |> put_flash(:info, "Pick confirmed — stock staged for dispatch.")
     |> load(shipment.id)}
  end

  def handle_async(:approve_shipment, result, socket) do
    socket = assign(socket, :approving?, false)
    shipment_id = socket.assigns.shipment.id

    case result do
      {:ok, {:ok, _shipment}} ->
        {:noreply,
         socket
         |> assign(:problems, [])
         |> put_flash(:info, "Shipment approved. SSCCs have been issued for every shipper.")
         |> load(shipment_id)}

      {:ok, {:already_approved, _shipment}} ->
        {:noreply,
         socket |> put_flash(:info, "This shipment is already approved.") |> load(shipment_id)}

      {:ok, {:error, {:invalid, problems}}} ->
        {:noreply,
         socket
         |> assign(:problems, problems)
         |> put_flash(:error, "This shipment can't be approved yet. See the problems below.")
         |> load(shipment_id)}

      {:ok, {:error, reason}} ->
        {:noreply, socket |> put_flash(:error, error_message(reason)) |> load(shipment_id)}

      {:exit, _reason} ->
        {:noreply, socket |> put_flash(:error, error_message(:unknown)) |> load(shipment_id)}
    end
  end

  @doc false
  def error_message(:missing_gs1_company_prefix),
    do: "Set your GS1 Company Prefix in Settings before approving. It's needed to issue SSCCs."

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
  defp event_label("approved"), do: "Approved · SSCCs issued"
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
              phx-click="open_approve"
              disabled={@approving?}
            >
              <.icon :if={!@approving?} name="hero-check-badge" class="size-4" />
              {if @approving?, do: "Approving…", else: "Approve & issue SSCCs"}
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

        <section :if={@shipment.status == "draft"} class="mt-6" id="distributor-pick-list">
          <div class="rounded-2xl ff-surface-card">
            <header class="flex flex-wrap items-start justify-between gap-3 border-b border-thamani-stone px-5 py-4 sm:px-6">
              <div>
                <h2 class="text-base font-semibold text-thamani-forest">Products to pick</h2>
                <p class="mt-1 text-xs leading-5 text-thamani-pewter">
                  Add the products and quantities required for this shipment.
                </p>
              </div>
              <div class="flex items-center gap-2">
                <span class="inline-flex min-h-7 items-center rounded-full bg-thamani-canvas px-3 text-xs font-semibold text-thamani-forest">
                  {length(@shipment.line_items)} {if length(@shipment.line_items) == 1,
                    do: "line",
                    else: "lines"}
                </span>
                <.button
                  :if={not @editing_line_items? and @shipment.line_items != []}
                  id="edit-shipment-line-items"
                  variant="ghost"
                  phx-click="edit_line_items"
                >
                  <.icon name="hero-pencil-square" class="size-4" /> Edit
                </.button>
              </div>
            </header>

            <div
              :if={not @editing_line_items? and @shipment.line_items != []}
              class="overflow-x-auto"
            >
              <table class="w-full text-left text-sm">
                <thead class="bg-thamani-canvas/70 text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                  <tr>
                    <th class="px-5 py-3 sm:px-6">Product</th>
                    <th class="w-40 px-5 py-3">Quantity</th>
                    <th class="w-40 px-5 py-3">Available</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-thamani-stone">
                  <tr :for={line <- @shipment.line_items} id={"shipment-line-item-#{line.id}"}>
                    <td class="px-5 py-4 font-medium text-thamani-forest sm:px-6">
                      {line.product && (line.product.generic_name || line.product.brand_name)}
                    </td>
                    <td class="px-5 py-4 tabular-nums text-thamani-ink">{line.quantity}</td>
                    <td class="px-5 py-4 tabular-nums">
                      <span class={
                        if Map.get(@available_by_product_id, line.product_id, 0) < line.quantity,
                          do: "font-semibold text-red-600",
                          else: "text-thamani-pewter"
                      }>
                        {Map.get(@available_by_product_id, line.product_id, 0)}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div :if={@editing_line_items?}>
              <div :if={@shipment.line_items == []} class="px-5 py-8 text-center sm:px-6">
                <span class="mx-auto flex size-11 items-center justify-center rounded-xl bg-thamani-canvas text-thamani-forest">
                  <.icon name="hero-clipboard-document-list" class="size-5" />
                </span>
                <p class="mt-3 text-sm font-semibold text-thamani-forest">No products added yet</p>
                <p class="mt-1 text-xs text-thamani-pewter">
                  Add the first product below to start building the pick list.
                </p>
              </div>

              <div :if={@shipment.line_items != []} class="overflow-x-auto">
                <table class="w-full text-left text-sm">
                  <thead class="bg-thamani-canvas/70 text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                    <tr>
                      <th class="px-5 py-3 sm:px-6">Product</th>
                      <th class="w-40 px-5 py-3">Quantity</th>
                      <th class="w-40 px-5 py-3">Available</th>
                      <th class="w-20 px-5 py-3 text-right"><span class="sr-only">Actions</span></th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-thamani-stone">
                    <tr :for={line <- @shipment.line_items} id={"shipment-line-item-#{line.id}"}>
                      <td class="px-5 py-4 font-medium text-thamani-forest sm:px-6">
                        {line.product && (line.product.generic_name || line.product.brand_name)}
                      </td>
                      <td class="px-5 py-4 tabular-nums text-thamani-ink">{line.quantity}</td>
                      <td class="px-5 py-4 tabular-nums">
                        <span class={
                          if Map.get(@available_by_product_id, line.product_id, 0) < line.quantity,
                            do: "font-semibold text-red-600",
                            else: "text-thamani-pewter"
                        }>
                          {Map.get(@available_by_product_id, line.product_id, 0)}
                        </span>
                      </td>
                      <td class="px-5 py-4 text-right">
                        <button
                          id={"remove-shipment-line-item-#{line.id}"}
                          type="button"
                          phx-click="remove_line_item"
                          phx-value-id={line.id}
                          aria-label={"Remove #{line.product && (line.product.generic_name || line.product.brand_name)}"}
                          class="inline-flex size-9 items-center justify-center rounded-lg text-thamani-error transition-colors hover:bg-red-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-300"
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div class="border-t border-thamani-stone bg-thamani-canvas/40 px-5 py-5 sm:px-6">
                <h3 class="text-sm font-semibold text-thamani-forest">Add a product</h3>
                <.form
                  for={@line_item_form}
                  id="distributor-add-line-item-form"
                  phx-change="validate_line_item"
                  phx-submit="add_line_item"
                  class="mt-3 grid items-end gap-3 sm:grid-cols-[minmax(0,1fr)_10rem_auto]"
                >
                  <.input
                    field={@line_item_form[:product_id]}
                    type="select"
                    label="Product"
                    prompt="Select product"
                    options={Enum.map(@products, &{&1.generic_name || &1.brand_name, &1.id})}
                  />
                  <.input
                    field={@line_item_form[:quantity]}
                    type="number"
                    label="Quantity"
                    min="1"
                    placeholder="0"
                  />
                  <.button id="add-shipment-line-item" variant="ghost" class="min-h-12 px-5">
                    <.icon name="hero-plus" class="size-4" /> Add product
                  </.button>
                </.form>
              </div>
            </div>

            <div
              :if={@shipment.line_items != []}
              class="flex flex-col gap-3 border-t border-thamani-stone px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6"
            >
              <p
                :if={insufficient_stock?(@shipment.line_items, @available_by_product_id)}
                class="inline-flex items-center gap-1.5 text-xs font-semibold leading-5 text-red-600"
              >
                <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
                Not enough stock at this site for one or more products — picking will reserve less than requested.
              </p>
              <p
                :if={not insufficient_stock?(@shipment.line_items, @available_by_product_id)}
                class="text-xs leading-5 text-thamani-pewter"
              >
                Reserve available batches using first-expiry-first-out allocation.
              </p>
              <div class="flex flex-wrap gap-2">
                <.button
                  id="generate-shipment-pick-list"
                  variant="primary"
                  phx-click="generate_pick_list"
                >
                  <.icon name="hero-clipboard-document-check" class="size-4" /> Generate pick list
                </.button>
                <.button
                  :if={Enum.any?(@reserved_batches, &(&1.zone == :picking))}
                  id="confirm-shipment-pick-list"
                  variant="primary"
                  phx-click="confirm_pick_list"
                >
                  <.icon name="hero-check" class="size-4" /> Confirm pick
                </.button>
              </div>
            </div>

            <div :if={@reserved_batches != []} class="border-t border-thamani-stone">
              <div class="px-5 py-3 sm:px-6">
                <h3 class="text-sm font-semibold text-thamani-forest">Reserved stock</h3>
              </div>
              <div class="overflow-x-auto">
                <table class="w-full text-left text-sm">
                  <thead class="bg-thamani-canvas text-xs font-semibold uppercase tracking-wide text-thamani-subtle">
                    <tr>
                      <th class="px-5 py-3 sm:px-6">Product</th>
                      <th class="px-5 py-3">Batch</th>
                      <th class="px-5 py-3">Qty</th>
                      <th class="px-5 py-3">Zone</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-thamani-stone">
                    <tr :for={batch <- @reserved_batches}>
                      <td class="px-5 py-3 sm:px-6">
                        {batch.product && (batch.product.generic_name || batch.product.brand_name)}
                      </td>
                      <td class="px-5 py-3 font-mono text-xs">{batch.batch_no}</td>
                      <td class="px-5 py-3 tabular-nums">{batch.remaining_quantity}</td>
                      <td class="px-5 py-3 capitalize">{batch.zone}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </section>

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
                  <p>Mixed · {label.unit_count} unit(s)</p>
                </div>
              <% else %>
                <div class="col-span-2">
                  <p class="font-semibold uppercase">Contents</p>
                  <p>{label.product_name || "Product"} · {label.unit_count} unit(s)</p>
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
            placeholder="e.g. Shipper 2 contains expired units, repack without them."
            required
          />
          <.button id="confirm-reject-shipment" variant="destructive" class="mt-2 w-full">
            Reject shipment
          </.button>
        </.form>
      </.modal>

      <.modal
        :if={@approval_confirming?}
        id="distributor-approve-modal"
        show
        on_cancel={JS.push("close_approve")}
      >
        <h2
          id="distributor-approve-modal-title"
          class="mb-1 text-2xl font-medium tracking-tight text-thamani-forest"
        >
          Approve shipment?
        </h2>
        <p id="distributor-approve-modal-description" class="mb-4 text-sm text-thamani-pewter">
          Review the serialisation usage before issuing SSCCs.
        </p>
        <dl class="grid grid-cols-2 gap-x-4 gap-y-3 rounded-xl bg-thamani-snow p-4 text-sm">
          <dt class="text-thamani-pewter">Shipment / order</dt>
          <dd id="approval-order-number" class="text-right font-semibold text-thamani-forest">
            {@shipment.order_number}
          </dd>
          <dt class="text-thamani-pewter">Shippers</dt>
          <dd id="approval-shipper-count" class="text-right font-semibold text-thamani-forest">
            {@shipper_count}
          </dd>
          <dt class="text-thamani-pewter">SSCCs to issue</dt>
          <dd id="approval-sscc-count" class="text-right font-semibold text-thamani-forest">
            {@shipper_count}
          </dd>
          <dt class="text-thamani-pewter">Credits to consume</dt>
          <dd id="approval-credit-count" class="text-right font-semibold text-thamani-forest">
            {@shipper_count}
          </dd>
          <dt class="text-thamani-pewter">Current allowance</dt>
          <dd id="approval-current-allowance" class="text-right font-semibold text-thamani-forest">
            {if is_integer(@remaining_allowance), do: @remaining_allowance, else: "Unlimited"}
          </dd>
          <dt class="text-thamani-pewter">Remaining after approval</dt>
          <dd id="approval-remaining-allowance" class="text-right font-semibold text-thamani-forest">
            {if is_integer(@remaining_allowance),
              do: max(@remaining_allowance - @shipper_count, 0),
              else: "Unlimited"}
          </dd>
        </dl>
        <div
          :if={@insufficient_allowance?}
          id="approval-insufficient-allowance"
          role="alert"
          class="mt-4 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900"
        >
          This shipment needs {@shipper_count} credits, but only {@remaining_allowance} remain in your allowance. Approval may fail if your available buffer cannot cover the difference.
        </div>
        <div class="mt-5 flex justify-end gap-3">
          <.button id="cancel-approve-shipment" type="button" phx-click="close_approve">
            Cancel
          </.button>
          <.button
            id="confirm-approve-shipment"
            variant="primary"
            phx-click="approve"
            phx-disable-with="Approving…"
            disabled={@approving?}
          >
            Approve &amp; issue SSCCs
          </.button>
        </div>
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
