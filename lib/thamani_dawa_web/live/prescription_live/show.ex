defmodule ThamaniDawaWeb.PrescriptionLive.Show do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Products
  alias ThamaniDawa.ScanEvents

  def mount(%{"id" => id}, _session, socket) do
    {:ok, load_prescription(socket, id)}
  end

  defp load_prescription(socket, id) do
    organization_id = socket.assigns.current_scope.organization_id
    prescription = Prescriptions.get_prescription!(organization_id, id)
    patient = Patients.get_patient!(organization_id, prescription.patient_id)
    items = Prescriptions.list_prescription_items(organization_id, prescription.id)
    products_by_id = organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    dispensed_by_item =
      Map.new(items, fn item ->
        {item.id, Prescriptions.list_dispensed_items(organization_id, item.id)}
      end)

    socket
    |> assign(:prescription, prescription)
    |> assign(:patient, patient)
    |> assign(:items, items)
    |> assign(:products_by_id, products_by_id)
    |> assign(:dispensed_by_item, dispensed_by_item)
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
      {:ok, _dispensed_item} ->
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

  def handle_event(
        "verify",
        %{"dispensed_item_id" => dispensed_item_id, "raw_gs1" => raw_gs1},
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    dispensed_item_id = String.to_integer(dispensed_item_id)

    case Prescriptions.verify_dispensed_item(organization_id, dispensed_item_id, raw_gs1) do
      {:ok, _dispensed_item} ->
        ScanEvents.log_scan_event(
          organization_id,
          :dispense,
          dispensed_item_id,
          socket.assigns.current_scope.user.id,
          raw_gs1
        )

        {:noreply,
         socket
         |> put_flash(:info, "Verified.")
         |> load_prescription(socket.assigns.prescription.id)}

      {:error, :mismatch} ->
        {:noreply, put_flash(socket, :error, "Scanned code doesn't match this batch.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't verify that scan: #{inspect(reason)}")}
    end
  end

  defp product_name(products_by_id, product_id) do
    case products_by_id[product_id] do
      nil -> "(unknown product)"
      product -> product.generic_name || product.name || "(unnamed)"
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Prescription for {@patient.full_name}
        <:actions>
          <.button navigate={~p"/pharmacy/prescriptions"}>Back</.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Status">{Phoenix.Naming.humanize(@prescription.status)}</:item>
        <:item title="Prescriber">{@prescription.prescriber_name}</:item>
        <:item title="Payment type">{@prescription.payment_type}</:item>
        <:item title="Paid">{if @prescription.has_paid, do: "Yes", else: "No"}</:item>
        <:item title="Notes">{@prescription.notes}</:item>
      </.list>

      <div :for={item <- @items} class="border rounded-box border-base-300 p-3 mt-4">
        <h3 class="font-semibold">{product_name(@products_by_id, item.product_id)}</h3>
        <p class="text-sm text-base-content/70">
          Prescribed {item.quantity_prescribed} · Dispensed {item.quantity_dispensed} · {item.dosage_instructions} {item.frequency}
        </p>

        <form
          :if={item.quantity_dispensed < item.quantity_prescribed}
          phx-submit="dispense"
          class="flex gap-2 items-end mt-2"
        >
          <input type="hidden" name="item_id" value={item.id} />
          <input type="number" name="quantity" placeholder="Quantity" class="input input-sm" required />
          <button class="btn btn-sm btn-primary">Dispense</button>
        </form>

        <div
          :for={dispensed_item <- @dispensed_by_item[item.id]}
          class="mt-2 pl-3 border-l border-base-300"
        >
          <p class="text-sm">
            Dispensed {dispensed_item.quantity} · {if dispensed_item.is_verified,
              do: "Verified",
              else: "Not verified"}
          </p>
          <form
            :if={not dispensed_item.is_verified}
            phx-submit="verify"
            class="flex gap-2 items-end mt-1"
          >
            <input type="hidden" name="dispensed_item_id" value={dispensed_item.id} />
            <input
              type="text"
              name="raw_gs1"
              placeholder="Scan/paste GS1 code"
              class="input input-sm"
              required
            />
            <button class="btn btn-sm">Verify</button>
          </form>
        </div>
      </div>
    </Layouts.app_shell>
    """
  end
end
