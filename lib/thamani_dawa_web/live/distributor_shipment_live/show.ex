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
     |> assign(:serial_shortage?, false)
     |> assign(:rejecting?, false)
     |> assign(:prompt_save_customer, false)
     |> assign(:saving_customer?, false)
     |> assign(:customer_form, nil)
     |> assign(:reject_form, to_form(%{"reason" => ""}, as: :reject))
     |> load(id)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, socket |> assign_return_to(params) |> maybe_prompt_save_customer(params)}
  end

  defp maybe_prompt_save_customer(socket, %{"prompt_save_customer" => _}) do
    organization_id = socket.assigns.current_scope.organization_id
    shipment = socket.assigns.shipment

    should_prompt =
      shipment.destination_gln &&
        !Customers.get_by_gln(organization_id, shipment.destination_gln)

    assign(socket, :prompt_save_customer, should_prompt)
  end

  defp maybe_prompt_save_customer(socket, _params), do: socket

  # Back link: `return_to` when given, else Orders for drafts, submitted
  # and rejected orders, Shipments once approved.
  defp assign_return_to(socket, params) do
    shipment = socket.assigns.shipment
    list = list_path(shipment)
    return_to = ThamaniDawaWeb.ReturnTo.path(params, list)

    return_query =
      if Map.has_key?(params, "return_to"), do: %{"return_to" => return_to}, else: %{}

    socket
    |> assign(:return_to, return_to)
    |> assign(:return_query, return_query)
    |> assign(
      :back_label,
      ThamaniDawaWeb.ReturnTo.label(
        return_to,
        if(list == "/distributor/orders", do: "Back to Orders", else: "Back to Shipments")
      )
    )
    |> assign(:self_path, "/distributor/shipments/#{shipment.id}")
  end

  defp list_path(%{status: "approved"}), do: "/distributor/shipments"
  defp list_path(_shipment), do: "/distributor/orders"

  defp load(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    shipment = Distributor.get_shipment!(organization_id, id)
    usage = Billing.active_usage(organization_id)
    shipper_count = length(shipment.shippers)
    remaining_allowance = SerialUsage.serials_left(usage)

    order? = shipment.status != "approved"

    socket
    |> assign(:shipment, shipment)
    |> assign(:order?, order?)
    |> assign(:nav_path, if(order?, do: "/distributor/orders", else: "/distributor/shipments"))
    |> assign(:crumb_parent, if(order?, do: "Orders", else: "Shipments"))
    |> assign(
      :page_title,
      if(order?, do: "Order #{shipment.order_number}", else: "Shipment #{shipment.reference}")
    )
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
    do: {:noreply, assign(socket, approval_confirming?: false, serial_shortage?: false)}

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
        socket = load(socket, shipment_id)

        {:noreply,
         socket
         |> assign(:problems, [])
         |> assign(
           :back_label,
           if(socket.assigns.return_to == "/distributor/orders",
             do: "Back to Orders",
             else: socket.assigns.back_label
           )
         )
         |> put_flash(
           :info,
           "Approved. #{count_phrase(socket.assigns.shipper_count, "SSCC")} issued."
         )}

      {:ok, {:error, {:billing, :insufficient_allowance}}} ->
        {:noreply, socket |> assign(:serial_shortage?, true) |> load(shipment_id)}

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

  defp shipment_badge(assigns) do
    {tone, label} =
      case assigns.status do
        "draft" -> {"neutral", "Draft"}
        "submitted" -> {"warning", "Submitted"}
        "approved" -> {"success", "Approved"}
        "rejected" -> {"danger", "Rejected"}
        other -> {"neutral", Phoenix.Naming.humanize(other)}
      end

    assigns = assign(assigns, tone: tone, label: label)

    ~H"""
    <.td_badge tone={@tone} label={@label} />
    """
  end

  defp header_sub(%{status: "approved"} = s),
    do:
      "Order #{s.order_number} · Approved by #{user_name(s.approved_by)} on #{date_time(s.approved_at)} EAT"

  defp header_sub(%{status: "rejected"} = s),
    do:
      "Shipment #{s.reference} · Rejected by #{user_name(s.rejected_by)} on #{date_time(s.rejected_at)} EAT"

  defp header_sub(%{status: "submitted"} = s),
    do:
      "Shipment #{s.reference} · Submitted by #{(s.submitted_by && s.submitted_by.name) || "the mobile team"} on #{date_time(s.submitted_at)} EAT"

  defp header_sub(s),
    do:
      "Shipment #{s.reference} · Created by #{user_name(s.created_by)} on #{date_time(s.inserted_at)} EAT"

  defp user_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_name(%{email: email}) when is_binary(email), do: email
  defp user_name(_user), do: "an administrator"

  defp packed_by(%{submitted_by: %{name: name}}), do: name
  defp packed_by(%{assigned_to: %{name: name}}), do: name
  defp packed_by(_shipment), do: "Not started"

  defp shipper_items_field(shipper, field) do
    shipper.items |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  defp shipper_product(shipper) do
    case shipper.product_name || List.first(shipper_items_field(shipper, :product_name)) do
      nil ->
        if shipper.items == [], do: "Empty", else: "Unverified product"

      name ->
        if length(shipper_items_field(shipper, :gtin)) > 1, do: "#{name} and more", else: name
    end
  end

  defp shipper_batch(shipper) do
    case shipper.batch || shipper_items_field(shipper, :batch) do
      batch when is_binary(batch) -> batch
      [] -> "—"
      [one] -> one
      many -> "#{length(many)} batches"
    end
  end

  defp shipper_gtin(shipper) do
    case shipper.gtin || shipper_items_field(shipper, :gtin) do
      gtin when is_binary(gtin) -> gtin
      [] -> "—"
      [one] -> one
      _many -> "Mixed"
    end
  end

  defp shipper_expiry(shipper) do
    shipper.expiry_date ||
      shipper.items
      |> Enum.map(& &1.expiry_date)
      |> Enum.reject(&is_nil/1)
      |> Enum.min(Date, fn -> nil end)
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
      current_path={@nav_path}
      crumb_parent={@crumb_parent}
      crumb={if @order?, do: @shipment.order_number, else: @shipment.reference}
    >
      <div class="no-print td-recipe td-list-page td-detail-page" id="distributor-shipment-detail">
        <.td_back_link id="shipment-back" to={@return_to} label={@back_label} />

        <header class="td-idh">
          <div class="td-idh-text">
            <h1 class="td-idh-title">
              <span>{if @order?,
                do: "Order #{@shipment.order_number}",
                else: "Shipment #{@shipment.reference}"}</span>
              <.shipment_badge status={@shipment.status} />
            </h1>
            <p class="td-idh-sub">{header_sub(@shipment)}</p>
          </div>
          <div class="td-idh-actions">
            <.td_button
              :if={@shipment.status == "draft"}
              id="edit-distributor-shipment"
              glyph="pencil-simple"
              label="Edit details"
              patch={~p"/distributor/shipments/#{@shipment.id}/edit-details?#{@return_query}"}
            />
            <.td_button
              :if={@unit_count > 0}
              id="export-distributor-shipment"
              glyph="download-simple"
              label="Export CSV"
              href={~p"/distributor/shipments/#{@shipment.id}/export"}
            />
            <.td_button
              :if={@labels != []}
              id="print-distributor-labels"
              type="button"
              glyph="printer"
              label="Print labels"
              phx-hook="PrintAllLabels"
            />
            <.td_button
              :if={@shipment.status == "approved"}
              id="packing-list"
              glyph="list-checks"
              label="Packing list"
              navigate={
                ~p"/distributor/shipments/#{@shipment.id}/packing-list?#{%{return_to: @self_path}}"
              }
            />
            <.td_button
              :if={@shipment.status == "approved"}
              id="delivery-note"
              variant="primary"
              glyph="file-text"
              label="Delivery note"
              navigate={
                ~p"/distributor/shipments/#{@shipment.id}/delivery-note?#{%{return_to: @self_path}}"
              }
            />
            <.td_button
              :if={@shipment.status == "submitted"}
              id="reject-distributor-shipment"
              variant="danger"
              label="Reject"
              phx-click="open_reject"
            />
            <.td_button
              :if={@shipment.status == "submitted"}
              id="approve-distributor-shipment"
              variant="primary"
              glyph={if !@approving?, do: "seal-check"}
              label={if @approving?, do: "Approving…", else: "Approve and issue SSCCs"}
              phx-click="open_approve"
              disabled={@approving?}
            />
          </div>
        </header>

        <div class="td-pad td-stack">
          <div :if={@shipment.status == "draft"} id="draft-banner" class="td-ban is-info">
            <.td_icon name="info" />
            <span>
              Your mobile team can pick this order up now. It moves to Submitted when the packer
              finishes on the mobile app, then you can approve it.
            </span>
          </div>

          <div :if={@shipment.status == "approved"} id="approved-banner" class="td-ban is-success">
            <.td_icon name="check-circle" />
            <span>
              {count_phrase(@shipper_count, "SSCC")} issued and the shipping event is queued for
              TNT. Print the labels, then the delivery note for the driver.
            </span>
          </div>

          <div
            :if={@shipment.status == "rejected"}
            id="distributor-rejection-reason"
            class="td-ban is-danger"
          >
            <.td_icon name="x-circle" />
            <span>
              <b>Reason sent to {(@shipment.submitted_by && @shipment.submitted_by.name) ||
                "the packer"}:</b>
              {@shipment.rejection_reason}
              <span class="td-note">The packer can reopen it as a draft on the mobile app, fix it, and submit it again.</span>
            </span>
          </div>

          <div :if={@problems != []} id="distributor-approval-problems" class="td-ban is-danger">
            <.td_icon name="warning-circle" />
            <span>
              <b>Can't approve yet</b>
              <span :for={problem <- @problems} class="block">{problem.message}</span>
            </span>
          </div>

          <div :if={@warnings != []} id="distributor-shipment-warnings" class="td-stack">
            <div :for={warning <- @warnings} id={"warning-#{warning.code}"} class="td-ban is-warning">
              <.td_icon name="warning" />
              <span><b>{warning.count}</b> {warning.message}</span>
            </div>
          </div>

          <div :if={@prompt_save_customer} id="save-customer-prompt" class="td-ban is-info">
            <.td_icon name="address-book" />
            <span class="flex-1">
              <b>{@shipment.destination_company}</b>
              <span class="block">Save this destination as a customer for faster ordering next time.</span>
            </span>
            <.td_button
              variant="primary"
              glyph="plus"
              label="Add customer"
              phx-click="open_save_customer"
            />
          </div>

          <div class="td-card">
            <dl class="td-kv-grid is-pad is-6">
              <div class="td-kv">
                <dt class="td-kv-label">Customer</dt>
                <dd class="td-kv-value">{@shipment.destination_company || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Ship to GLN</dt>
                <dd class="td-kv-value is-mono">{@shipment.destination_gln || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Ship from</dt>
                <dd class="td-kv-value">{@shipment.origin_company || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">From GLN</dt>
                <dd class="td-kv-value is-mono">{@shipment.origin_gln || "—"}</dd>
              </div>
              <div :if={@order?} class="td-kv">
                <dt class="td-kv-label">Packed by</dt>
                <dd class="td-kv-value">{packed_by(@shipment)}</dd>
              </div>
              <div :if={!@order?} class="td-kv">
                <dt class="td-kv-label">Order</dt>
                <dd class="td-kv-value">{@shipment.order_number}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">
                  {if @order?, do: "Shippers / units", else: "SSCCs / units"}
                </dt>
                <dd class="td-kv-value">{@shipper_count} / {@unit_count}</dd>
              </div>
            </dl>
          </div>

          <div class="td-detail-row">
            <div class="td-card" id="distributor-shippers">
              <.td_card_header
                title={if @order?, do: "Shippers", else: "Shippers and SSCCs"}
                subtitle={
                  if @order?,
                    do:
                      "#{count_phrase(@shipper_count, "shipper")} · #{count_phrase(@unit_count, "unit")} packed on the mobile app",
                    else: "Hover an SSCC to preview it. Labels print in this order."
                }
              />
              <div :if={@shipment.shippers == []} id="shippers-empty" class="td-empty-inline">
                <p class="td-empty-title">Nothing packed yet</p>
                <p class="td-note">
                  Shippers appear here as they are scanned on the mobile app. A mobile user finds this
                  order by {@shipment.order_number}.
                </p>
              </div>
              <table
                :if={@shipment.shippers != []}
                class="td-rows is-tight"
                id="shipment-shippers-table"
              >
                <thead>
                  <tr>
                    <th>{if @order?, do: "Shipper", else: "SSCC"}</th>
                    <th>Product</th>
                    <th>Batch</th>
                    <th class="is-num">Units</th>
                    <th>Expiry</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={shipper <- @shipment.shippers} id={"shipper-row-#{shipper.id}"}>
                    <td>
                      <%= if shipper.sscc do %>
                        <.td_pid id={"sscc-#{shipper.id}"} label={shipper.sscc} mono>
                          <:peek>
                            <.td_peek
                              kind="SSCC"
                              icon="package"
                              title={shipper.sscc}
                              mono
                              subtitle={shipper_product(shipper)}
                            >
                              <:row label="Batch" mono>{shipper_batch(shipper)}</:row>
                              <:row label="GTIN" mono>{shipper_gtin(shipper)}</:row>
                              <:row label="Expiry">{short_date(shipper_expiry(shipper))}</:row>
                              <:row label="Shipment">{@shipment.reference}</:row>
                              <:row label="Units">{length(shipper.items)}</:row>
                              <:row :if={shipper.sscc_assigned_at} label="Issued">
                                {date_time(shipper.sscc_assigned_at)} EAT
                              </:row>
                            </.td_peek>
                          </:peek>
                        </.td_pid>
                      <% else %>
                        {shipper.name || "Shipper #{shipper.sequence}"}
                      <% end %>
                    </td>
                    <td>{shipper_product(shipper)}</td>
                    <td><span class="td-mono">{shipper_batch(shipper)}</span></td>
                    <td class="is-num">{length(shipper.items)}</td>
                    <td>{short_date(shipper_expiry(shipper))}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="td-card" id="distributor-shipment-activity">
              <.td_card_header title="Activity" subtitle="Times in EAT" />
              <p :if={@shipment.events == []} class="td-empty-inline td-note">No activity yet.</p>
              <ol :if={@shipment.events != []} class="td-list">
                <li :for={event <- @shipment.events} class="td-li">
                  <.td_orb seed={actor(event)} size={24} />
                  <div class="td-li-g">
                    <b>{event_label(event.event)}</b>
                    <span>{actor(event)} · {date_time(event.inserted_at)}</span>
                    <span :if={event.details["reason"]} class="td-note">“{event.details["reason"]}”</span>
                  </div>
                </li>
              </ol>
            </div>
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

            <div class="space-y-4 rounded-xl border border-td-hairline bg-td-wash/50 p-3.5">
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

        <section :if={@item_groups != []} class="td-pad td-stack" id="distributor-units">
          <h2 class="td-sec">Units by shipper</h2>
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
                class="rounded-lg bg-td-accent-tint px-3 py-1 font-mono text-xs font-semibold text-thamani-forest"
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
                  class="relative flex gap-3 rounded-xl border border-thamani-stone bg-td-surface p-3"
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
              class="printable-sscc-label box-border flex h-[6in] w-[4in] flex-col overflow-hidden border-2 border-black bg-td-surface text-black"
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
        size="confirm"
        title={"Reject order #{@shipment.order_number}?"}
        subtitle={"The order goes back to #{packed_by(@shipment)} with your reason."}
        on_cancel={JS.push("close_reject")}
      >
        <.form
          for={@reject_form}
          id="distributor-reject-form"
          class="td-modal-form"
          phx-submit="reject"
        >
          <.input
            field={@reject_form[:reason]}
            type="textarea"
            label="Reason for the packer"
            placeholder="For example: Shipper 2 has the wrong batch. Repack without it."
            required
          />
          <p class="td-note">
            The packer sees this reason on the mobile app. All {count_phrase(@unit_count, "unit")} are
            released so they can be packed again.
          </p>
        </.form>
        <:footer>
          <.td_button type="button" label="Cancel" phx-click="close_reject" />
          <.td_button
            id="confirm-reject-shipment"
            type="submit"
            form="distributor-reject-form"
            variant="danger-confirm"
            label="Reject order"
          />
        </:footer>
      </.modal>

      <.modal
        :if={@approval_confirming? or @serial_shortage?}
        id="distributor-approve-modal"
        show
        title={"Approve order #{@shipment.order_number}?"}
        subtitle="Approving issues one SSCC per shipper and turns this order into a shipment."
        on_cancel={JS.push("close_approve")}
      >
        <dl class="td-kv-grid is-2">
          <div class="td-kv">
            <dt class="td-kv-label">Order</dt>
            <dd id="approval-order-number" class="td-kv-value">{@shipment.order_number}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Customer</dt>
            <dd class="td-kv-value">{@shipment.destination_company || "—"}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">SSCCs to issue</dt>
            <dd id="approval-sscc-count" class="td-kv-value">
              <span id="approval-shipper-count">{@shipper_count}</span>, one per shipper
            </dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Serials used</dt>
            <dd id="approval-credit-count" class="td-kv-value">{@shipper_count}</dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">Allowance now</dt>
            <dd id="approval-current-allowance" class="td-kv-value">
              {if is_integer(@remaining_allowance),
                do: count_phrase(@remaining_allowance, "serial"),
                else: "Unlimited"}
            </dd>
          </div>
          <div class="td-kv">
            <dt class="td-kv-label">After approval</dt>
            <dd id="approval-remaining-allowance" class="td-kv-value">
              {cond do
                @serial_shortage? ->
                  "Not enough"

                is_integer(@remaining_allowance) ->
                  count_phrase(max(@remaining_allowance - @shipper_count, 0), "serial")

                true ->
                  "Unlimited"
              end}
            </dd>
          </div>
        </dl>
        <div
          :if={@serial_shortage?}
          id="approval-not-enough-serials"
          role="alert"
          class="td-ban is-danger"
        >
          <.td_icon name="warning-circle" />
          <span>
            {if is_integer(@remaining_allowance),
              do:
                "You have #{count_phrase(@remaining_allowance, "serial")} left and this order needs #{@shipper_count}.",
              else: "There are not enough serials left for this order."} Buy more serials, then approve again.
          </span>
        </div>
        <div
          :if={@insufficient_allowance? and not @serial_shortage?}
          id="approval-insufficient-allowance"
          role="alert"
          class="td-ban is-warning"
        >
          <.td_icon name="warning" />
          <span>
            This order needs {@shipper_count} serials, but only {@remaining_allowance} remain in your
            allowance. Approval may fail if your available buffer cannot cover the difference.
          </span>
        </div>
        <p :if={not @serial_shortage?} class="td-note">
          SSCCs can't be withdrawn once issued. The stock is taken out of {@shipment.origin_company ||
            "the ship-from site"} and a shipping event is queued for TNT.
        </p>
        <:footer>
          <.td_button
            id="cancel-approve-shipment"
            type="button"
            label="Cancel"
            phx-click="close_approve"
          />
          <.td_button
            :if={@serial_shortage?}
            id="buy-serials"
            variant="primary"
            label="Buy serials"
            navigate={~p"/distributor/billing"}
          />
          <.td_button
            :if={not @serial_shortage?}
            id="confirm-approve-shipment"
            variant="primary"
            label="Approve and issue SSCCs"
            phx-click="approve"
            phx-disable-with="Approving…"
            disabled={@approving?}
          />
        </:footer>
      </.modal>

      <.live_component
        :if={@live_action == :edit and @shipment.status == "draft"}
        module={ThamaniDawaWeb.DistributorShipmentLive.OrderFormComponent}
        id="edit-order"
        action={:edit}
        shipment={@shipment}
        return_query={@return_query}
        current_scope={@current_scope}
        cancel={~p"/distributor/shipments/#{@shipment.id}?#{@return_query}"}
      />
    </Layouts.distributor_shell>
    """
  end
end
