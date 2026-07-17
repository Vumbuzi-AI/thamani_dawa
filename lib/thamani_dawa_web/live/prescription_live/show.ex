defmodule ThamaniDawaWeb.PrescriptionLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products

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
    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

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
    |> assign(:products_by_id, products_by_id)
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

  defp product_name(products_by_id, product_id) do
    case products_by_id[product_id] do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/prescriptions"
    >
      <.header>
        Prescription for {@patient.full_name}
        <:subtitle>
          {if @patient.age, do: "#{@patient.age} yrs", else: "Age N/A"} | {if @patient.gender,
            do: @patient.gender,
            else: "Gender N/A"} | {@patient.phone || "No phone"}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/pharmacy/prescriptions"}>Back</.button>
        </:actions>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-10 mt-6">
        <div class="border rounded-box border-base-300 p-4 sm:p-6 bg-transparent">
          <h3 class="font-semibold text-base-content/50 uppercase tracking-widest text-xs mb-4">
            Status & Payment
          </h3>
          <div class="space-y-3 text-sm">
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Status</span>
              <span class={[
                "font-medium",
                @prescription.status == :pending && "text-orange-600",
                @prescription.status == :completed && "text-green-600"
              ]}>
                {Phoenix.Naming.humanize(@prescription.status)}
              </span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Payment type</span>
              <span class="font-medium text-base-content">{@prescription.payment_type || "-"}</span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-base-content/70">Paid</span>
              <span class={[
                "font-medium",
                @prescription.has_paid && "text-success",
                !@prescription.has_paid && "text-error"
              ]}>
                {if @prescription.has_paid, do: "Yes", else: "No"}
              </span>
            </div>
            <div class="flex justify-between items-center pt-3 border-t border-base-200">
              <span class="text-base-content/70">Total Amount</span>
              <span class="font-bold text-base-content">{@prescription.total_amount || "-"}</span>
            </div>
          </div>
        </div>

        <div class="border rounded-box border-base-300 p-4 sm:p-6 bg-transparent flex flex-col">
          <h3 class="font-semibold text-base-content/50 uppercase tracking-widest text-xs mb-4">
            Prescriber & Notes
          </h3>
          <div class="space-y-4 text-sm flex-1">
            <div class="flex flex-col">
              <span class="text-base-content/70 mb-1">Prescriber</span>
              <span class="font-medium text-base-content">{@prescription.referring_doctor || "Unknown"}</span>
            </div>
            <div class="flex flex-col pt-3 border-t border-base-200">
              <span class="text-base-content/70 mb-1">Notes</span>
              <span class={["font-medium", !@prescription.notes && "italic text-base-content/40"]}>
                {@prescription.notes || "No notes provided"}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div :for={item <- @items} class="border rounded-box border-base-300 p-4 mt-4 bg-transparent">
        <h3 class="font-semibold text-lg">{product_name(@products_by_id, item.product_id)}</h3>
        <p class="text-sm text-base-content/70 mt-1">
          <strong>Prescribed:</strong> {item.quantity_prescribed} &nbsp;&middot;&nbsp;
          <strong>Dispensed:</strong> {item.quantity_dispensed} &nbsp;&middot;&nbsp;
          <span class={
            if (@stock_by_product_id[item.product_id] || 0) < item.quantity_prescribed,
              do: "text-error font-semibold",
              else: "text-success font-semibold"
          }>
            In Stock: {@stock_by_product_id[item.product_id] || 0}
          </span>
        </p>
        <p class="text-sm mt-1 text-base-content/90">
          {item.dosage_instructions} {item.frequency}
          {if item.route_of_administration, do: "- #{item.route_of_administration}"}
          {if item.duration_in_days, do: "(for #{item.duration_in_days} days)"}
        </p>

        <form
          :if={item.quantity_dispensed < item.quantity_prescribed}
          phx-submit="dispense"
          class="flex gap-3 items-end mt-4 pt-4 border-t border-base-200"
        >
          <input type="hidden" name="item_id" value={item.id} />
          <input
            type="number"
            name="quantity"
            placeholder="Quantity"
            class="input input-sm input-bordered bg-transparent"
            required
            min="1"
            max={item.quantity_prescribed - item.quantity_dispensed}
          />
          <.button type="submit" variant="primary" phx-disable-with="Dispensing...">Dispense</.button>
        </form>

        <div
          :if={item.quantity_dispensed > 0}
          class="mt-4 pt-4 border-t border-base-200 flex items-center gap-3"
        >
          <%= if item.is_verified do %>
            <span class="text-success font-semibold flex items-center gap-1">
              <.icon name="hero-check-circle" class="w-5 h-5" /> Verified
            </span>
          <% else %>
            <form phx-submit="verify_item" class="flex gap-3 items-end w-full">
              <input type="hidden" name="item_id" value={item.id} />
              <div class="flex-1 max-w-xs">
                <input
                  type="text"
                  name="gtin"
                  placeholder="Scan GTIN to verify..."
                  class="input input-sm input-bordered bg-transparent w-full"
                  required
                  autofocus
                />
              </div>
              <.button type="submit" variant="ghost">Verify</.button>
            </form>
          <% end %>
        </div>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
