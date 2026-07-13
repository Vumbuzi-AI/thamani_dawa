defmodule ThamaniDawaWeb.PrescriptionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    {:ok, assign_prescriptions(socket)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)
    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    products =
      organization_id
      |> Products.list_products()
      |> SiteScoping.for_current_site(scope)

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:products, products)
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:use_new_patient, false)
    |> assign(
      :header_form,
      to_form(Prescription.changeset(%Prescription{}, initial_attrs), as: :prescription)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
    |> assign(:item_ids, [0])
    |> assign(:next_item_id, 1)
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_new_patient", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("add_item", _params, socket) do
    {:noreply,
     socket
     |> update(:item_ids, &(&1 ++ [socket.assigns.next_item_id]))
     |> update(:next_item_id, &(&1 + 1))}
  end

  def handle_event("remove_item", %{"id" => id}, socket) do
    id = String.to_integer(id)
    item_ids = List.delete(socket.assigns.item_ids, id)
    item_ids = if item_ids == [], do: socket.assigns.item_ids, else: item_ids
    {:noreply, assign(socket, :item_ids, item_ids)}
  end

  def handle_event("save", params, socket) do
    %{"prescription" => header_attrs} = params
    items_attrs = Map.get(params, "items", [])

    if items_attrs == [] do
      {:noreply, put_flash(socket, :error, "Add at least one item to the prescription.")}
    else
      organization_id = socket.assigns.current_scope.organization_id
      header_attrs = Map.put(header_attrs, "entered_by_id", socket.assigns.current_scope.user.id)

      with {:ok, header_attrs} <- resolve_patient(socket, organization_id, header_attrs, params),
           {:ok, _result} <-
             Prescriptions.create_prescription_with_items(
               organization_id,
               header_attrs,
               items_attrs
             ) do
        {:noreply,
         socket
         |> put_flash(:info, "Prescription created.")
         |> assign_prescriptions()
         |> push_patch(to: ~p"/pharmacy/prescriptions")}
      else
        {:error, %Ecto.Changeset{data: %Patient{}} = changeset} ->
          {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}

        {:error, changeset} ->
          {:noreply, assign(socket, :header_form, to_form(changeset, as: :prescription))}
      end
    end
  end

  defp resolve_patient(%{assigns: %{use_new_patient: true}}, organization_id, header_attrs, %{
         "patient" => patient_attrs
       }) do
    case Patients.create_patient(organization_id, patient_attrs) do
      {:ok, patient} -> {:ok, Map.put(header_attrs, "patient_id", patient.id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp resolve_patient(_socket, _organization_id, header_attrs, _params), do: {:ok, header_attrs}

  defp assign_prescriptions(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    prescriptions =
      organization_id
      |> Prescriptions.list_prescriptions()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)

    assign(socket, :prescriptions, prescriptions)
  end

  def render(assigns) do
    ~H"""
    <Layouts.pharmacy_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/pharmacy/prescriptions"
    >
      <.header>
        Prescriptions
        <:actions>
          <.button variant="primary" navigate={~p"/pharmacy/prescriptions/new"}>+ New prescription</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">New prescription</h2>

          <form phx-submit="save">
            <div class="flex items-center gap-2 mb-2">
              <.input
                :if={not @use_new_patient}
                field={@header_form[:patient_id]}
                type="select"
                label="Patient"
                options={Enum.map(@patients, &{&1.full_name, &1.id})}
                prompt="Choose a patient"
              />
              <.button type="button" phx-click="toggle_new_patient">
                {if @use_new_patient, do: "Choose existing patient", else: "+ New patient"}
              </.button>
            </div>

            <div :if={@use_new_patient} class="border rounded-box border-base-300 p-3 mb-2">
              <.input field={@patient_form[:full_name]} label="Full name" required />
              <.input field={@patient_form[:date_of_birth]} type="date" label="Date of birth" />
              <.input field={@patient_form[:age]} type="number" label="Age" />
              <.input field={@patient_form[:gender]} label="Gender" />
              <.input field={@patient_form[:phone]} label="Phone" />
              <.input field={@patient_form[:national_id]} label="National ID" />
            </div>

            <.input
              :if={@site_locked}
              field={@header_form[:site_id]}
              type="hidden"
            />
            <.input
              :if={not @site_locked}
              field={@header_form[:site_id]}
              type="select"
              label="Site"
              options={Enum.map(@sites, &{&1.name, &1.id})}
              prompt="Choose a site"
              required
            />

            <.input field={@header_form[:prescriber_name]} label="Prescriber name" />
            <.input field={@header_form[:prescriber_reg_no]} label="Prescriber reg. no." />
            <.input field={@header_form[:payment_type]} label="Payment type" />
            <.input field={@header_form[:has_paid]} type="checkbox" label="Paid" />
            <.input field={@header_form[:notes]} type="textarea" label="Notes" />

            <.header class="mt-4">Items</.header>
            <div :for={id <- @item_ids} class="border rounded-box border-base-300 p-3 mb-2">
              <.input
                type="select"
                name="items[][product_id]"
                label="Product"
                options={Enum.map(@products, &{product_label(&1), &1.id})}
                prompt="Choose a product"
              />
              <.input type="number" name="items[][quantity_prescribed]" label="Quantity prescribed" />
              <.input name="items[][dosage_instructions]" label="Dosage instructions" />
              <.input name="items[][frequency]" label="Frequency" />
              <.input type="number" name="items[][duration_in_days]" label="Duration (days)" />
              <.input name="items[][route_of_administration]" label="Route of administration" />
              <.button type="button" phx-click="remove_item" phx-value-id={id} class="mt-2">
                Remove item
              </.button>
            </div>
            <.button type="button" phx-click="add_item">+ Add item</.button>

            <div class="flex gap-2 mt-4">
              <.button variant="primary">Create prescription</.button>
              <.button navigate={~p"/pharmacy/prescriptions"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table
        id="prescriptions"
        rows={@prescriptions}
        row_click={&~p"/pharmacy/prescriptions/#{&1.id}"}
      >
        <:col :let={prescription} label="Status">{Phoenix.Naming.humanize(prescription.status)}</:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Paid">
          {if prescription.has_paid, do: "Yes", else: "No"}
        </:col>
        <:col :let={prescription} label="Created">{prescription.inserted_at}</:col>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end

  defp product_label(product) do
    name = product.generic_name || product.brand_name || "(unnamed)"
    if product.brand_name, do: "#{name} (#{product.brand_name})", else: name
  end
end
