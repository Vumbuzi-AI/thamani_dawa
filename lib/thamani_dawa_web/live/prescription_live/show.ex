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

    case Prescriptions.dispense_item(
           organization_id,
           String.to_integer(item_id),
           pharmacist_id,
           String.to_integer(quantity)
         ) do
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

      <.list>
        <:item title="Status">{Phoenix.Naming.humanize(@prescription.status)}</:item>
        <:item title="Prescriber">{@prescription.referring_doctor}</:item>
        <:item title="Total Amount">{@prescription.total_amount}</:item>
        <:item title="Payment type">{@prescription.payment_type}</:item>
        <:item title="Paid">{if @prescription.has_paid, do: "Yes", else: "No"}</:item>
        <:item title="Notes">{@prescription.notes}</:item>
      </.list>

      <div :for={item <- @items} class="border rounded-box border-base-300 p-3 mt-4">
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
        <p class="text-sm mt-1">
          {item.dosage_instructions} {item.frequency}
          {if item.route_of_administration, do: "- #{item.route_of_administration}"}
          {if item.duration_in_days, do: "(for #{item.duration_in_days} days)"}
        </p>

        <form
          :if={item.quantity_dispensed < item.quantity_prescribed}
          phx-submit="dispense"
          class="flex gap-2 items-end mt-3"
        >
          <input type="hidden" name="item_id" value={item.id} />
          <input type="number" name="quantity" placeholder="Quantity" class="input input-sm" required />
          <button class="btn btn-sm btn-primary">Dispense</button>
        </form>
      </div>
    </Layouts.pharmacy_shell>
    """
  end
end
