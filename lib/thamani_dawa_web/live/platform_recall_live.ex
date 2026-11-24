defmodule ThamaniDawaWeb.PlatformRecallLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Recalls

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:gtin, nil)
     |> assign(:batch_no, nil)
     |> assign(:trace, nil)
     |> assign(:reference, "")
     |> assign(:classification, "class_ii")
     |> assign(:reason, "")}
  end

  def handle_event("search", %{"gtin" => gtin, "batch_no" => batch_no}, socket) do
    gtin = String.trim(gtin)
    batch_no = String.trim(batch_no)

    if gtin == "" or batch_no == "" do
      {:noreply, put_flash(socket, :error, "Enter both a GTIN and a batch number.")}
    else
      {:noreply,
       socket
       |> assign(:gtin, gtin)
       |> assign(:batch_no, batch_no)
       |> assign(:trace, Recalls.trace(gtin, batch_no))}
    end
  end

  def handle_event(
        "validate_recall_form",
        %{"reference" => reference, "classification" => classification, "reason" => reason},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:reference, reference)
     |> assign(:classification, classification)
     |> assign(:reason, reason)}
  end

  def handle_event("initiate_recall", _params, socket) do
    reference = String.trim(socket.assigns.reference)
    reason = String.trim(socket.assigns.reason)

    if reference == "" do
      {:noreply,
       put_flash(socket, :error, "Enter an incident/recall reference before recalling.")}
    else
      user = socket.assigns.current_scope.user
      classification = String.to_existing_atom(socket.assigns.classification)
      reason = if reason == "", do: nil, else: reason

      case Recalls.initiate_recall(
             socket.assigns.gtin,
             socket.assigns.batch_no,
             reference,
             classification,
             reason,
             user
           ) do
        {:ok, _recall} ->
          {:noreply,
           socket
           |> put_flash(:info, "Recall issued and cascaded across the network.")
           |> assign(:trace, Recalls.trace(socket.assigns.gtin, socket.assigns.batch_no))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Recall failed — no batches were changed.")}
      end
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.platform_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/platform/recalls"}
    >
      <.td_list_page
        title="Recalls"
        subtitle="Trace a batch across every organization on the network, and cascade a recall to every holder at once."
      >

      <.form_block title="Find a batch">
        <form phx-submit="search" class="flex flex-wrap items-end gap-3">
          <div>
            <label class="text-xs font-semibold uppercase text-thamani-pewter">GTIN</label>
            <input
              type="text"
              name="gtin"
              value={@gtin}
              required
              class="mt-1 block rounded-lg border border-thamani-stone px-3 py-2 text-sm"
            />
          </div>
          <div>
            <label class="text-xs font-semibold uppercase text-thamani-pewter">Batch number</label>
            <input
              type="text"
              name="batch_no"
              value={@batch_no}
              required
              class="mt-1 block rounded-lg border border-thamani-stone px-3 py-2 text-sm"
            />
          </div>
          <.button variant="primary">Trace</.button>
        </form>
      </.form_block>

      <.form_block :if={@trace} title="Network trail">
        <p :if={@trace == []} class="text-sm text-thamani-pewter">
          No organization currently holds a batch matching that GTIN and batch number.
        </p>

        <div :if={@trace != []} class="space-y-4">
          <div
            :for={%{batch: batch, shipments: shipments} <- @trace}
            class="rounded-lg border border-thamani-stone p-4"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <p class="text-sm font-semibold text-thamani-forest">
                {batch.organization.name} — {batch.site && batch.site.name}
              </p>
              <span class="rounded-full bg-thamani-canvas px-2 py-0.5 text-xs font-semibold text-thamani-forest">
                {batch.status}
              </span>
            </div>
            <p class="mt-1 text-xs text-thamani-pewter">
              {batch.remaining_quantity} units remaining, zone {batch.zone}
            </p>
            <p :if={batch.goods_receipt} class="mt-1 text-xs text-thamani-pewter">
              Received from {batch.goods_receipt.origin_company || "unknown origin"} on {ThamaniDawaWeb.TimeFormat.date(batch.goods_receipt.received_at)}
            </p>
            <ul :if={shipments != []} class="mt-1 text-xs text-thamani-pewter">
              <li :for={%{shipment: shipment, unit_count: unit_count} <- shipments}>
                → {unit_count} unit(s) shipped to {shipment.destination_company ||
                  "unknown destination"} ({shipment.status})
              </li>
            </ul>
          </div>

          <form
            phx-change="validate_recall_form"
            phx-submit="initiate_recall"
            class="grid grid-cols-1 items-end gap-3 sm:grid-cols-2 xl:grid-cols-[minmax(0,1fr)_minmax(0,1.35fr)_minmax(0,1fr)_auto]"
          >
            <div>
              <label class="text-xs font-semibold uppercase text-thamani-pewter">
                Incident / recall reference
              </label>
              <input
                type="text"
                name="reference"
                value={@reference}
                required
                class="mt-1 block w-full rounded-lg border-2 border-td-hairline bg-thamani-surface px-3 py-[9px] text-sm text-thamani-forest transition-colors placeholder:text-thamani-pewter focus:border-thamani-forest focus:outline-none"
              />
            </div>
            <div>
              <label class="text-xs font-semibold uppercase text-thamani-pewter">
                Classification
              </label>
              <select
                id="recall-classification"
                name="classification"
                class="mt-1 block w-full appearance-none rounded-lg border-2 border-td-hairline bg-thamani-surface bg-[linear-gradient(45deg,transparent_50%,#38594b_50%),linear-gradient(135deg,#38594b_50%,transparent_50%)] bg-[position:calc(100%-18px)_calc(50%-2px),calc(100%-13px)_calc(50%-2px)] bg-[size:5px_5px,5px_5px] bg-no-repeat px-3 py-[9px] pr-9 text-sm text-thamani-forest transition-colors focus:border-thamani-forest focus:outline-none"
              >
                <option value="class_i" selected={@classification == "class_i"}>
                  Class I — serious risk
                </option>
                <option value="class_ii" selected={@classification == "class_ii"}>
                  Class II — temporary/reversible risk
                </option>
                <option value="class_iii" selected={@classification == "class_iii"}>
                  Class III — unlikely to cause harm
                </option>
              </select>
            </div>
            <div>
              <label class="text-xs font-semibold uppercase text-thamani-pewter">
                Reason (optional)
              </label>
              <input
                type="text"
                name="reason"
                value={@reason}
                class="mt-1 block w-full rounded-lg border-2 border-td-hairline bg-thamani-surface px-3 py-[9px] text-sm text-thamani-forest transition-colors placeholder:text-thamani-pewter focus:border-thamani-forest focus:outline-none"
              />
            </div>
            <.button variant="primary" class="w-full whitespace-nowrap xl:w-auto">
              Recall this batch everywhere
            </.button>
          </form>
        </div>
      </.form_block>
      </.td_list_page>
    </Layouts.platform_shell>
    """
  end
end
