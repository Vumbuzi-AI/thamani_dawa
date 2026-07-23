defmodule ThamaniDawaWeb.PrescriptionLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Prescriptions

  def mount(%{"id" => id}, _session, socket) do
    {:ok, load_prescription(socket, id)}
  end

  defp load_prescription(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    prescription = Prescriptions.get_prescription!(organization_id, id)

    visit =
      ThamaniDawa.PatientVisits.get_patient_visit!(organization_id, prescription.patient_visit_id)

    patient = Patients.get_patient!(organization_id, visit.patient_id)
    items = Prescriptions.list_prescription_items(organization_id, prescription.id)

    stock_by_product_id =
      items
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()
      |> Map.new(fn product_id ->
        {product_id,
         ThamaniDawa.Batches.total_available_stock(organization_id, visit.site_id, product_id)}
      end)

    socket
    |> assign(:prescription, prescription)
    |> assign(:patient, patient)
    |> assign(:items, items)
    |> assign(:stock_by_product_id, stock_by_product_id)
  end

  def handle_event("dispense", %{"item_id" => item_id, "quantity" => quantity}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    pharmacist_id = socket.assigns.current_scope.user.id

    with {item_id, ""} <- Integer.parse(item_id),
         {quantity, ""} <- Integer.parse(quantity),
         true <- quantity > 0 do
      do_dispense(socket, organization_id, item_id, pharmacist_id, quantity)
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter a valid quantity.")}
    end
  end

  def handle_event("verify_item", %{"item_id" => item_id, "gtin" => gtin}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Integer.parse(item_id) do
      {item_id, ""} -> do_verify(socket, organization_id, item_id, gtin)
      _ -> {:noreply, put_flash(socket, :error, "Couldn't verify that item.")}
    end
  end

  defp do_dispense(socket, organization_id, item_id, pharmacist_id, quantity) do
    case Prescriptions.dispense_item(organization_id, item_id, pharmacist_id, quantity) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item dispensed.")
         |> load_prescription(socket.assigns.prescription.id)}

      {:error, :out_of_stock} ->
        {:noreply, put_flash(socket, :error, "No stock available at this site for this product.")}

      {:error, :over_dispensed} ->
        {:noreply, put_flash(socket, :error, "That would dispense more than was prescribed.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't dispense that item.")}
    end
  end

  defp do_verify(socket, organization_id, item_id, gtin) do
    case Prescriptions.verify_dispensed_item(organization_id, item_id, gtin) do
      {:ok, _item} ->
        {:noreply,
         socket
         |> put_flash(:info, "Item verified successfully.")
         |> load_prescription(socket.assigns.prescription.id)}

      {:error, :gtin_mismatch} ->
        {:noreply, put_flash(socket, :error, "GTIN mismatch. This is the wrong product.")}

      {:error, :invalid_gtin} ->
        {:noreply, put_flash(socket, :error, "Invalid GTIN barcode scanned.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't verify that item.")}
    end
  end

  defp product_name(%{product: nil}), do: "(unknown product)"

  defp product_name(%{product: product}),
    do: product.generic_name || product.brand_name || "(unnamed)"

  defp item_state(item, stock) do
    cond do
      item.is_verified -> :verified
      item.quantity_dispensed >= item.quantity_prescribed -> :awaiting_verification
      item.quantity_dispensed > 0 -> :partially_dispensed
      stock <= 0 -> :out_of_stock
      true -> :ready
    end
  end

  defp item_state_label(:verified), do: "Verified"
  defp item_state_label(:awaiting_verification), do: "Awaiting verification"
  defp item_state_label(:partially_dispensed), do: "Partially dispensed"
  defp item_state_label(:out_of_stock), do: "Out of stock"
  defp item_state_label(:ready), do: "Ready to dispense"

  defp item_state_classes(:verified), do: "bg-emerald-50 text-emerald-700 ring-emerald-200"
  defp item_state_classes(:awaiting_verification), do: "bg-amber-50 text-amber-700 ring-amber-200"
  defp item_state_classes(:partially_dispensed), do: "bg-sky-50 text-sky-700 ring-sky-200"
  defp item_state_classes(:out_of_stock), do: "bg-rose-50 text-rose-700 ring-rose-200"
  defp item_state_classes(:ready), do: "bg-indigo-50 text-thamani-forest ring-indigo-200"

  defp outstanding_quantity(item),
    do: max(item.quantity_prescribed - item.quantity_dispensed, 0)

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/prescriptions"
    >
      <div id="prescription-show" class="space-y-5">
        <section
          id="prescription-overview"
          class="overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow shadow-sm"
        >
          <div class="flex flex-col gap-5 p-5 sm:p-6 lg:flex-row lg:items-start lg:justify-between">
            <div class="flex min-w-0 items-start gap-4">
              <div class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-thamani-lime text-thamani-forest sm:size-12">
                <.icon name="hero-user" class="size-5" />
              </div>
              <div class="min-w-0">
                <p class="text-xs font-medium uppercase tracking-[0.12em] text-thamani-subtle">
                  Prescription for
                </p>
                <div class="mt-1 flex flex-wrap items-center gap-2.5">
                  <h1 class="text-xl font-semibold tracking-tight text-slate-900 sm:text-2xl">
                    {@patient.full_name}
                  </h1>
                  <.status_badge status={@prescription.status} />
                </div>
                <div class="mt-2 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm text-thamani-pewter">
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-calendar-days" class="size-4 text-thamani-subtle" />
                    {if age = Patient.age(@patient), do: "#{age} years", else: "Age not recorded"}
                  </span>
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-identification" class="size-4 text-thamani-subtle" />
                    {@patient.gender || "Gender not recorded"}
                  </span>
                  <span class="inline-flex items-center gap-1.5">
                    <.icon name="hero-phone" class="size-4 text-thamani-subtle" />
                    {@patient.phone || "No phone number"}
                  </span>
                </div>
              </div>
            </div>

            <.button
              navigate={~p"/pharmacy/prescriptions"}
              class="self-start gap-2 whitespace-nowrap"
            >
              <.icon name="hero-arrow-left" class="size-4" /> Back to prescriptions
            </.button>
          </div>

          <dl class="grid grid-cols-2 border-t border-thamani-stone bg-thamani-canvas/70 lg:grid-cols-4">
            <div class="border-b border-r border-thamani-stone px-5 py-4 lg:border-b-0">
              <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                Payment
              </dt>
              <dd class="mt-1.5 flex flex-wrap items-center gap-2 text-sm font-medium text-slate-900">
                {@prescription.payment_type || "Not recorded"}
                <span class={[
                  "inline-flex rounded-full px-2 py-0.5 text-[11px] font-medium ring-1 ring-inset",
                  @prescription.has_paid && "bg-emerald-50 text-emerald-700 ring-emerald-200",
                  !@prescription.has_paid && "bg-rose-50 text-rose-700 ring-rose-200"
                ]}>
                  {if @prescription.has_paid, do: "Paid", else: "Unpaid"}
                </span>
              </dd>
            </div>
            <div class="border-b border-thamani-stone px-5 py-4 lg:border-b-0 lg:border-r">
              <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                Total amount
              </dt>
              <dd class="mt-1.5 text-sm font-semibold text-slate-900">
                KES {@prescription.total_amount || "—"}
              </dd>
            </div>
            <div class="border-r border-thamani-stone px-5 py-4">
              <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                Prescriber
              </dt>
              <dd class="mt-1.5 text-sm font-medium text-slate-900">
                {@prescription.referring_doctor || "Not recorded"}
              </dd>
            </div>
            <div class="px-5 py-4">
              <dt class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                Medication items
              </dt>
              <dd class="mt-1.5 text-sm font-medium text-slate-900">
                {length(@items)} {if length(@items) == 1, do: "item", else: "items"}
              </dd>
            </div>
          </dl>
        </section>

        <aside
          id="prescription-notes"
          class="flex items-start gap-3 rounded-xl border border-indigo-100 bg-indigo-50/60 px-4 py-3.5"
        >
          <div class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-lg bg-white text-thamani-forest ring-1 ring-indigo-100">
            <.icon name="hero-clipboard-document-check" class="size-4" />
          </div>
          <div class="min-w-0">
            <p class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
              Clinical notes
            </p>
            <p class={[
              "mt-1 text-sm leading-6 text-slate-700",
              !@prescription.notes && "italic text-thamani-subtle"
            ]}>
              {@prescription.notes || "No clinical notes were added to this prescription."}
            </p>
          </div>
        </aside>

        <section id="medication-fulfillment" class="pt-2">
          <div class="mb-3 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
            <div>
              <h2 class="text-lg font-semibold text-slate-900">Medication fulfillment</h2>
              <p class="mt-1 text-sm text-thamani-pewter">
                Dispense the prescribed quantity, then scan the product barcode to verify it.
              </p>
            </div>
            <span class="self-start rounded-full bg-thamani-lime px-3 py-1 text-xs font-medium text-thamani-forest">
              {Enum.count(@items, & &1.is_verified)} of {length(@items)} verified
            </span>
          </div>

          <div id="prescription-items" class="space-y-4">
            <.blank_state :if={@items == []} title="No medication items">
              This prescription does not have any medication items.
            </.blank_state>

            <%= for {item, index} <- Enum.with_index(@items, 1) do %>
              <% stock = Map.get(@stock_by_product_id, item.product_id, 0) %>
              <% state = item_state(item, stock) %>
              <article
                id={"prescription-item-#{item.id}"}
                class="overflow-hidden rounded-2xl border border-thamani-stone bg-thamani-snow shadow-sm transition-shadow hover:shadow-md"
              >
                <div class="p-5 sm:p-6">
                  <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                    <div class="flex min-w-0 items-start gap-3.5">
                      <div class="flex size-9 shrink-0 items-center justify-center rounded-lg bg-thamani-canvas text-sm font-semibold text-thamani-forest ring-1 ring-thamani-stone">
                        {index}
                      </div>
                      <div class="min-w-0">
                        <h3 class="text-lg font-semibold text-slate-900">{product_name(item)}</h3>
                        <p
                          :if={
                            item.product && item.product.brand_name &&
                              item.product.brand_name != product_name(item)
                          }
                          class="mt-0.5 text-sm text-thamani-pewter"
                        >
                          {item.product.brand_name}
                        </p>
                      </div>
                    </div>
                    <span class={[
                      "inline-flex self-start items-center gap-1.5 rounded-full px-3 py-1 text-xs font-medium ring-1 ring-inset",
                      item_state_classes(state)
                    ]}>
                      <span class="size-1.5 rounded-full bg-current"></span>
                      {item_state_label(state)}
                    </span>
                  </div>

                  <dl class="mt-5 grid grid-cols-3 overflow-hidden rounded-xl border border-thamani-stone bg-thamani-canvas/60">
                    <div class="border-r border-thamani-stone px-3 py-3.5 sm:px-4">
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Prescribed
                      </dt>
                      <dd class="mt-1 text-lg font-semibold text-slate-900">
                        {item.quantity_prescribed}
                      </dd>
                    </div>
                    <div class="border-r border-thamani-stone px-3 py-3.5 sm:px-4">
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Dispensed
                      </dt>
                      <dd
                        id={"dispensed-quantity-#{item.id}"}
                        class="mt-1 text-lg font-semibold text-slate-900"
                      >
                        {item.quantity_dispensed}
                      </dd>
                    </div>
                    <div class="px-3 py-3.5 sm:px-4">
                      <dt class="text-[11px] font-medium uppercase tracking-wide text-thamani-subtle">
                        Available
                      </dt>
                      <dd class={[
                        "mt-1 text-lg font-semibold",
                        stock < outstanding_quantity(item) && "text-rose-600",
                        stock >= outstanding_quantity(item) && "text-emerald-600"
                      ]}>
                        {stock}
                      </dd>
                    </div>
                  </dl>

                  <div class="mt-4 flex items-start gap-3 rounded-xl bg-indigo-50/60 px-4 py-3.5">
                    <.icon
                      name="hero-information-circle"
                      class="mt-0.5 size-5 shrink-0 text-thamani-forest"
                    />
                    <div>
                      <p class="text-xs font-medium uppercase tracking-wide text-thamani-subtle">
                        Directions
                      </p>
                      <p class="mt-1 text-sm leading-6 text-slate-700">
                        {item.dosage_instructions} {item.frequency}
                        {if item.route_of_administration,
                          do: " · #{item.route_of_administration}"}
                        {if item.duration_in_days, do: " · #{item.duration_in_days} days"}
                      </p>
                    </div>
                  </div>
                </div>

                <div
                  :if={item.quantity_dispensed < item.quantity_prescribed}
                  class="border-t border-thamani-stone bg-thamani-canvas/50 px-5 py-4 sm:px-6"
                >
                  <form
                    id={"dispense-form-#{item.id}"}
                    phx-submit="dispense"
                    class="flex flex-col gap-3 sm:flex-row sm:items-end"
                  >
                    <.input type="hidden" name="item_id" value={item.id} />
                    <div class="w-full sm:max-w-48">
                      <.input
                        id={"dispense-quantity-#{item.id}"}
                        type="number"
                        name="quantity"
                        value={outstanding_quantity(item)}
                        label="Quantity to dispense"
                        required
                        min="1"
                        max={outstanding_quantity(item)}
                        class="h-11 w-full rounded-lg border border-thamani-stone bg-white px-3 text-sm text-slate-900 outline-none transition focus:border-thamani-accent focus:ring-3 focus:ring-indigo-100"
                      />
                    </div>
                    <.button
                      type="submit"
                      variant="primary"
                      disabled={stock <= 0}
                      class="h-11 gap-2 whitespace-nowrap disabled:cursor-not-allowed disabled:opacity-40"
                      phx-disable-with="Dispensing..."
                    >
                      <.icon name="hero-check" class="size-4" /> Dispense medication
                    </.button>
                    <p :if={stock <= 0} class="self-center text-sm font-medium text-rose-600">
                      No stock is available at this site.
                    </p>
                  </form>
                </div>

                <div
                  :if={item.quantity_dispensed > 0}
                  class={[
                    "border-t px-5 py-4 sm:px-6",
                    item.is_verified && "border-emerald-100 bg-emerald-50/60",
                    !item.is_verified && "border-thamani-stone bg-thamani-canvas/50"
                  ]}
                >
                  <%= if item.is_verified do %>
                    <div class="flex items-center gap-3 text-emerald-700">
                      <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-white ring-1 ring-emerald-200">
                        <.icon name="hero-check" class="size-5" />
                      </div>
                      <div>
                        <p class="text-sm font-semibold">Product verified</p>
                        <p class="text-xs text-emerald-700/75">
                          The scanned barcode matched this medication.
                        </p>
                      </div>
                    </div>
                  <% else %>
                    <form
                      id={"verify-form-#{item.id}"}
                      phx-submit="verify_item"
                      class="flex flex-col gap-3 sm:flex-row sm:items-end"
                    >
                      <.input type="hidden" name="item_id" value={item.id} />
                      <div class="w-full sm:max-w-md">
                        <.input
                          id={"verify-gtin-#{item.id}"}
                          type="text"
                          name="gtin"
                          label="Scan product barcode"
                          placeholder="Scan or enter GTIN"
                          required
                          class="h-11 w-full rounded-lg border border-thamani-stone bg-white px-3 font-mono text-sm text-slate-900 outline-none transition placeholder:font-sans focus:border-thamani-accent focus:ring-3 focus:ring-indigo-100"
                        />
                      </div>
                      <.button
                        type="submit"
                        variant="primary"
                        class="h-11 gap-2 whitespace-nowrap"
                        phx-disable-with="Verifying..."
                      >
                        <.icon name="hero-qr-code" class="size-4" /> Verify product
                      </.button>
                    </form>
                  <% end %>
                </div>
              </article>
            <% end %>
          </div>
        </section>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
