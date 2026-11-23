defmodule ThamaniDawaWeb.DistributorShipmentLive.Show do
  @moduledoc """
  The shipment review screen: origin/destination/order summary, the mobile
  user holding or submitting it, review warnings, scanned units grouped per
  shipper and product/batch, and — depending on status — approve/reject
  actions, per-unit removal, printable SSCC shipper labels, CSV export, and
  the shipment's activity log.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Customers
  alias ThamaniDawa.Customers.Customer
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.{Billing, SerialUsage}
  alias ThamaniDawa.Distributor.Reports

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
     |> assign(:prompt_save_customer, false)
     |> assign(:saving_customer?, false)
     |> assign(:customer_form, nil)
     |> assign(:reject_form, to_form(%{"reason" => ""}, as: :reject))
     |> load(id)}
  end

  def handle_params(%{"prompt_save_customer" => _}, _url, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    shipment = socket.assigns.shipment

    should_prompt =
      shipment.destination_gln &&
        !Customers.get_by_gln(organization_id, shipment.destination_gln)

    {:noreply, assign(socket, :prompt_save_customer, should_prompt)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
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

  def handle_event("open_save_customer", _params, socket) do
    shipment = socket.assigns.shipment

    attrs = %{
      "gln" => shipment.destination_gln,
      "name" => shipment.destination_company,
      "address" => shipment.destination_address
    }

    {:noreply,
     socket
     |> assign(:saving_customer?, true)
     |> assign(
       :customer_form,
       to_form(Customers.change_customer(%Customer{}, attrs), as: :customer)
     )}
  end

  def handle_event("close_save_customer", _params, socket) do
    {:noreply, assign(socket, :saving_customer?, false)}
  end

  def handle_event("validate_customer", %{"customer" => params}, socket) do
    changeset =
      %Customer{}
      |> Customers.change_customer(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :customer_form, to_form(changeset, as: :customer))}
  end

  def handle_event("save_customer", %{"customer" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Customers.create_customer(organization_id, params) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> assign(:saving_customer?, false)
         |> assign(:prompt_save_customer, false)
         |> put_flash(:info, "#{customer.name} saved as a customer.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :customer_form, to_form(changeset, as: :customer))}
    end
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

  def error_message({:gs1, :unconfigured}),
    do: "SSCC issuing is not configured. Contact your platform administrator."

  def error_message({:gs1, :unauthorized}),
    do: "GS1 rejected the API credentials. Contact your platform administrator."

  def error_message({:gs1, :forbidden}),
    do: "This account is not allowed to issue SSCCs at GS1."

  def error_message({:gs1, :unavailable}),
    do: "GS1 could not issue an SSCC just now. Try again in a moment."

  def error_message({:gs1, {:invalid, message}}) when is_binary(message),
    do: "GS1 rejected the SSCC: #{message}"

  def error_message({:gs1, _reason}),
    do: "GS1 could not issue an SSCC just now. Try again in a moment."

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

  def error_message(:unknown_unit),
    do: "Every scanned unit must match a received batch before this shipment can be approved."

  def error_message(:insufficient_stock),
    do:
      "A scanned unit's batch no longer has enough remaining stock. Reject the shipment so it can be packed again."

  def error_message({:invalid_state, status}),
    do: "This shipment is #{status} and can't be changed."

  def error_message(:already_approved), do: "Approved shipments can't be changed."
  def error_message(:not_found), do: "That item no longer exists."
  def error_message(_reason), do: "Something went wrong. Please try again."

  attr :caption, :string, required: true
  attr :value, :any, required: true
  attr :align, :string, default: "left"

  defp label_field(assigns) do
    ~H"""
    <div class={[@align == "right" && "text-right"]}>
      <p class="text-[11px] font-normal leading-none">{@caption}</p>
      <p class="mt-1 text-[15px] font-bold leading-tight [overflow-wrap:anywhere]">{@value}</p>
    </div>
    """
  end

  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(count, word), do: "#{count} #{word}s"

  defp label_gs1_date(nil), do: "—"
  defp label_gs1_date(%Date{} = date), do: Calendar.strftime(date, "%y%m%d")

  defp label_ai_pairs(label) do
    [
      {"00", label.sscc},
      {"02", not label.mixed && label.gtin},
      {"10", not label.mixed && label.batch},
      {"17",
       not label.mixed && label.expiry_date && Calendar.strftime(label.expiry_date, "%y%m%d")},
      {"11",
       not label.mixed && label.production_date &&
         Calendar.strftime(label.production_date, "%y%m%d")},
      {"37", not label.mixed && label.unit_count},
      {"400", label.order_number}
    ]
    |> Enum.filter(fn {_ai, value} -> value not in [nil, false, ""] end)
  end

  defp label_gs1_text(label) do
    label |> label_ai_pairs() |> Enum.map_join(fn {ai, value} -> "(#{ai})#{value}" end)
  end

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

  defp customer_type_icon(:pharmacy), do: "hero-building-storefront"
  defp customer_type_icon(:wholesaler), do: "hero-truck"
  defp customer_type_icon(:hospital), do: "hero-building-office-2"
  defp customer_type_icon(:other), do: "hero-tag"

  defp customer_type_description(:pharmacy), do: "Retail or chain pharmacy"
  defp customer_type_description(:wholesaler), do: "Buys in bulk to resell to others"
  defp customer_type_description(:hospital), do: "Hospital, clinic, lab, or health center"
  defp customer_type_description(:other), do: "Another type of customer"

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
            <span class="tracking-tight tabular-nums">{@shipment.reference}</span>
            · {count_phrase(length(@shipment.shippers), "shipper")} · {count_phrase(
              @unit_count,
              "unit"
            )}
          </:subtitle>
          <:actions>
            <div class="flex w-full flex-col gap-2 sm:flex-row sm:flex-wrap md:w-auto md:justify-end md:[&>*]:w-auto">
              <.button
                :if={@shipment.status == "draft"}
                id="edit-distributor-shipment"
                navigate={~p"/distributor/shipments/#{@shipment.id}/edit"}
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
              <.button
                :if={@shipment.status == "approved"}
                id="delivery-note"
                variant="primary"
                navigate={~p"/distributor/shipments/#{@shipment.id}/delivery-note"}
              >
                <.icon name="hero-document-text" class="size-4" /> View delivery note
              </.button>
              <.button
                :if={@shipment.status == "approved"}
                id="packing-list"
                navigate={~p"/distributor/shipments/#{@shipment.id}/packing-list"}
              >
                <.icon name="hero-queue-list" class="size-4" /> View packing list
              </.button>
              <.button
                :if={@unit_count > 0}
                id="export-distributor-shipment"
                href={~p"/distributor/shipments/#{@shipment.id}/export"}
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> Export units CSV
              </.button>
              <.button
                :if={@labels != []}
                id="print-distributor-labels"
                type="button"
                phx-hook="PrintAllLabels"
              >
                <.icon name="hero-printer" class="size-4" /> Print case labels
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
            </div>
          </:actions>
        </.header>

        <div
          :if={@prompt_save_customer}
          id="save-customer-prompt"
          class="mb-5 flex gap-3 rounded-2xl border border-thamani-lime/50 bg-thamani-lime/20 p-4"
        >
          <.icon name="hero-star" class="mt-0.5 size-5 shrink-0 text-thamani-forest" />
          <div class="flex flex-1 flex-col gap-2 text-sm sm:flex-row sm:items-center">
            <div class="flex-1 text-thamani-forest">
              <p class="font-semibold">{@shipment.destination_company}</p>
              <p class="text-xs text-thamani-pewter">
                Save this destination as a customer for faster ordering next time.
              </p>
            </div>
            <.button class="shrink-0" variant="primary" phx-click="open_save_customer">
              <.icon name="hero-plus" class="size-4" /> Add customer
            </.button>
          </div>
        </div>

        <.modal
          :if={@saving_customer?}
          id="save-customer-modal"
          show
          on_cancel={JS.push("close_save_customer")}
        >
          <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">
            Add customer
          </h2>
          <.form
            for={@customer_form}
            id="save-customer-form"
            phx-change="validate_customer"
            phx-submit="save_customer"
          >
            <input type="hidden" name="customer[gln]" value={@customer_form[:gln].value} />
            <div class="mb-6 space-y-4">
              <.input field={@customer_form[:name]} label="Name" required />
              <.input field={@customer_form[:address]} label="Address" />
              <p :if={@customer_form[:gln].value not in [nil, ""]} class="text-xs text-thamani-pewter">
                GLN {@customer_form[:gln].value}
              </p>
            </div>

            <fieldset class="mb-6">
              <legend class="mb-2 text-xs font-semibold text-thamani-forest">
                Customer type <span class="text-red-600">*</span>
              </legend>
              <div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
                <.activity_card
                  :for={type <- Customer.customer_types()}
                  type="radio"
                  name="customer[customer_type]"
                  value={to_string(type)}
                  label={Phoenix.Naming.humanize(type)}
                  description={customer_type_description(type)}
                  icon={customer_type_icon(type)}
                  selected={to_string(@customer_form[:customer_type].value) == to_string(type)}
                  compact
                />
              </div>
              <p
                :for={error <- @customer_form[:customer_type].errors}
                class="mt-2 text-xs text-red-700"
              >
                {translate_error(error)}
              </p>
            </fieldset>

            <div class="space-y-4 rounded-xl border border-slate-200 bg-slate-50/50 p-3.5">
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@customer_form[:contact_name]} label="Contact person" />
                <.input field={@customer_form[:contact_email]} label="Contact email" />
              </div>
              <.input field={@customer_form[:contact_phone]} label="Contact phone" />
            </div>

            <div class="mt-6 flex items-center justify-end gap-3">
              <.button type="button" phx-click="close_save_customer">Cancel</.button>
              <.button variant="primary">Save customer</.button>
            </div>
          </.form>
        </.modal>

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
                  class="relative flex gap-3 rounded-xl border border-thamani-stone bg-white p-3"
                >
                  <canvas
                    id={"unit-datamatrix-#{item.id}"}
                    phx-hook="DataMatrix"
                    phx-update="ignore"
                    data-gs1-text={gs1_text(item)}
                    class="size-16 shrink-0"
                  ></canvas>
                  <div class="min-w-0 flex-1 pr-6 text-xs">
                    <p class="truncate font-mono text-sm text-thamani-ink">{item.serial}</p>
                    <p class="text-thamani-pewter">
                      {(item.scanned_by && item.scanned_by.name) || "—"} · {date_time(item.scanned_at)}
                    </p>
                    <div :if={item.validation_status != "ok"} class="mt-1.5">
                      <.validation_badge status={item.validation_status} />
                    </div>
                  </div>
                  <button
                    :if={@shipment.status != "approved"}
                    type="button"
                    id={"remove-item-#{item.id}"}
                    phx-click="remove_item"
                    phx-value-id={item.id}
                    data-confirm="Remove this unit from the shipment?"
                    aria-label={"Remove unit #{item.serial}"}
                    class="absolute right-2 top-2 inline-flex size-6 items-center justify-center rounded-md text-rose-600 transition-colors hover:bg-rose-50 hover:text-rose-700"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
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
        <div class="no-print mb-3 flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-wide text-thamani-pewter">
            SSCC labels · one label per shipper
          </h2>
          <.button
            id="download-all-distributor-labels-svg"
            type="button"
            variant="primary"
            phx-hook="DownloadAllLabelsSvg"
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Download all as SVG
          </.button>
        </div>
        <div class="printable-sscc-labels flex flex-wrap justify-center gap-6">
          <div
            :for={label <- @labels}
            id={"sscc-label-#{label.id}"}
            class="flex w-[4in] shrink-0 flex-col gap-3"
          >
            <div
              id={"sscc-label-content-#{label.id}"}
              class="printable-sscc-label box-border flex h-[6in] w-[4in] flex-col overflow-hidden border-2 border-black bg-white text-black"
              style="font-family: Arial, Helvetica, sans-serif"
            >
              <div class="grid grid-cols-2 border-b-2 border-black">
                <div class="border-r-2 border-black px-2.5 py-2.5">
                  <p class="text-[15px] font-bold leading-tight">From Address</p>
                  <p class="mt-1 text-[13px] leading-snug">{label.ship_from.company}</p>
                  <p class="text-[13px] leading-snug">{label.ship_from.address}</p>
                  <p :if={label.ship_from.gln} class="text-[13px] leading-snug">
                    GLN {label.ship_from.gln}
                  </p>
                </div>
                <div class="px-2.5 py-2.5">
                  <p class="text-[15px] font-bold leading-tight">To Address</p>
                  <p class="mt-1 text-[13px] leading-snug">{label.ship_to.company}</p>
                  <p class="text-[13px] leading-snug">{label.ship_to.address}</p>
                  <p :if={label.ship_to.po_box} class="text-[13px] leading-snug">
                    {label.ship_to.po_box}
                  </p>
                  <p :if={label.ship_to.gln} class="text-[13px] leading-snug">
                    GLN {label.ship_to.gln}
                  </p>
                </div>
              </div>

              <div class="flex min-h-0 flex-1 flex-col px-2.5 py-3">
                <div class="grid grid-cols-2 gap-x-4 gap-y-3.5">
                  <.label_field caption="SSCC" value={label.sscc} />
                  <.label_field caption="QUANTITY" value={label.unit_count} align="right" />
                  <.label_field
                    caption="CONTENT"
                    value={if(label.mixed, do: "Mixed", else: label.gtin)}
                  />
                  <.label_field
                    caption="EXPIRY"
                    value={if(label.mixed, do: "—", else: label_gs1_date(label.expiry_date))}
                    align="right"
                  />
                  <.label_field
                    caption="BATCH/LOT"
                    value={if(label.mixed, do: "—", else: label.batch)}
                  />
                  <.label_field
                    caption="PROD DATE"
                    value={if(label.mixed, do: "—", else: label_gs1_date(label.production_date))}
                    align="right"
                  />
                  <.label_field
                    caption="MATERIAL DESCRIPTION"
                    value={label.material_description || label.product_name || "—"}
                  />
                  <.label_field caption="ORDER NUMBER" value={label.order_number} align="right" />
                </div>

                <div class="mt-auto border-t-2 border-black pt-3">
                  <div class="flex items-start gap-3">
                    <canvas
                      id={"sscc-barcode-#{label.id}"}
                      phx-hook="DataMatrix"
                      phx-update="ignore"
                      data-gs1-text={label_gs1_text(label)}
                      class="size-[1.35in] shrink-0"
                    ></canvas>
                    <p class="pt-0.5 text-[11px] leading-[1.45] text-black">
                      <span :for={{ai, value} <- label_ai_pairs(label)} class="block">
                        ({ai}) {value}
                      </span>
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div class="no-print rounded-2xl ff-surface-card p-4">
              <div class="flex items-center justify-between gap-3">
                <p class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
                  Serials in this shipper
                </p>
                <span class="text-xs text-thamani-pewter">{length(label.serials)} unit(s)</span>
              </div>
              <div class="mt-2 grid grid-cols-2 gap-1.5 font-mono text-xs text-thamani-ink">
                <span
                  :for={serial <- label.serials}
                  class="truncate rounded bg-thamani-canvas px-2 py-1"
                >
                  {serial}
                </span>
              </div>
              <div class="mt-3 flex flex-wrap gap-2">
                <.button
                  id={"print-distributor-label-#{label.id}"}
                  type="button"
                  class="text-xs"
                  phx-hook="LabelPrint"
                  data-print-target={"#sscc-label-content-#{label.id}"}
                >
                  <.icon name="hero-printer" class="size-4" /> Print
                </.button>
                <.button
                  id={"download-svg-distributor-label-#{label.id}"}
                  type="button"
                  class="text-xs"
                  phx-hook="LabelSvgDownload"
                  data-role="download-label-svg"
                  data-sscc={label.sscc}
                  data-gs1-text={label_gs1_text(label)}
                  data-quantity={label.unit_count}
                  data-gtin={if label.mixed, do: "Mixed", else: label.gtin}
                  data-expiry={if label.mixed, do: nil, else: short_date(label.expiry_date)}
                  data-batch={if label.mixed, do: nil, else: label.batch}
                  data-production={if label.mixed, do: nil, else: short_date(label.production_date)}
                  data-material-description={label.material_description || label.product_name}
                  data-order-number={label.order_number}
                  data-from-company={label.ship_from.company}
                  data-from-address={label.ship_from.address}
                  data-to-company={label.ship_to.company}
                  data-to-address={label.ship_to.address}
                  data-to-po-box={label.ship_to.po_box}
                >
                  <.icon name="hero-code-bracket" class="size-4" /> Download as SVG
                </.button>
              </div>
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
