defmodule ThamaniDawaWeb.PrescriptionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Prescriptions.Prescription
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
    initial_attrs = if site_id, do: %{site_id: site_id, items: []}, else: %{items: []}

    products =
      if site_id do
        ThamaniDawa.Products.list_active_products_for_site(organization_id, site_id)
      else
        []
      end

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:products, products)
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:use_new_patient, false)
    |> assign(:editing_items, MapSet.new())
    |> assign(
      :header_form,
      to_form(Prescription.changeset(%Prescription{}, initial_attrs), as: :prescription)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_patient_mode", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("validate", params, socket) do
    header_attrs = params["prescription"] || %{}
    patient_attrs = params["patient"] || %{}

    header_changeset =
      %Prescription{}
      |> Prescription.changeset(header_attrs)
      |> Map.put(:action, :validate)

    patient_changeset =
      %Patient{}
      |> Patient.changeset(patient_attrs)
      |> Map.put(:action, :validate)

    socket =
      socket
      |> assign(:header_form, to_form(header_changeset, as: :prescription))
      |> assign(:patient_form, to_form(patient_changeset, as: :patient))

    {:noreply, socket}
  end

  def handle_event("add-item", _, socket) do
    changeset = socket.assigns.header_form.source
    items = socket.assigns.header_form[:items].value || []
    new_index = length(items)

    changeset =
      Ecto.Changeset.put_assoc(
        changeset,
        :items,
        items ++ [%ThamaniDawa.Prescriptions.PrescriptionItem{}]
      )

    editing_items = MapSet.put(socket.assigns.editing_items, new_index)

    {:noreply,
     assign(socket,
       header_form: to_form(changeset, as: :prescription),
       editing_items: editing_items
     )}
  end

  def handle_event("remove-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    changeset = socket.assigns.header_form.source
    items = socket.assigns.header_form[:items].value || []
    items = List.delete_at(items, index)
    changeset = Ecto.Changeset.put_assoc(changeset, :items, items)

    editing_items =
      socket.assigns.editing_items
      |> Enum.reject(&(&1 == index))
      |> Enum.map(fn i -> if i > index, do: i - 1, else: i end)
      |> MapSet.new()

    {:noreply,
     assign(socket,
       header_form: to_form(changeset, as: :prescription),
       editing_items: editing_items
     )}
  end

  def handle_event("edit-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    editing_items = MapSet.put(socket.assigns.editing_items, index)
    {:noreply, assign(socket, :editing_items, editing_items)}
  end

  def handle_event("collapse-item", %{"index" => index}, socket) do
    index = String.to_integer(index)
    editing_items = MapSet.delete(socket.assigns.editing_items, index)
    {:noreply, assign(socket, :editing_items, editing_items)}
  end

  def handle_event("save", params, socket) do
    %{"prescription" => header_attrs} = params
    site_id = header_attrs["site_id"] || socket.assigns.current_scope.site_id

    if is_nil(site_id) do
      {:noreply, put_flash(socket, :error, "Site is required.")}
    else
      socket.assigns.use_new_patient
      |> save_prescription(params, site_id, socket)
      |> handle_save_result(socket)
    end
  end

  defp save_prescription(true = _new_patient, params, site_id, socket) do
    %{"prescription" => header_attrs} = params
    patient_attrs = Map.get(params, "patient", %{})
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    Prescriptions.create_prescription_with_new_patient(
      organization_id,
      patient_attrs,
      site_id,
      user_id,
      header_attrs
    )
  end

  defp save_prescription(false = _new_patient, params, site_id, socket) do
    %{"prescription" => header_attrs} = params
    patient_id = header_attrs["patient_id"]
    organization_id = socket.assigns.current_scope.organization_id
    user_id = socket.assigns.current_scope.user.id

    if is_nil(patient_id) or patient_id == "" do
      changeset =
        %Prescription{}
        |> Prescription.changeset(header_attrs)
        |> Ecto.Changeset.add_error(:patient_id, "can't be blank")
        |> Map.put(:action, :insert)

      {:error, changeset}
    else
      Prescriptions.create_prescription_for_patient(
        organization_id,
        patient_id,
        site_id,
        user_id,
        header_attrs
      )
    end
  end

  defp handle_save_result({:ok, prescription}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Prescription created.")
     |> assign_prescriptions()
     |> push_navigate(to: ~p"/pharmacy/prescriptions/#{prescription.id}")}
  end

  defp handle_save_result({:error, %Ecto.Changeset{data: %Patient{}} = changeset}, socket) do
    {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}
  end

  defp handle_save_result({:error, changeset}, socket) do
    {:noreply, assign(socket, :header_form, to_form(changeset, as: :prescription))}
  end

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
          <.button variant="primary" patch={~p"/pharmacy/prescriptions/new"}>+ New prescription</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">New prescription</h2>

          <form id="prescription-form" phx-change="validate" phx-submit="save" class="space-y-6">
            <!-- Step 1: Patient Information -->
            <div class="border rounded-box border-base-300 overflow-hidden">
              <div class="bg-base-300/50 px-4 py-3 border-b border-base-300 flex justify-between items-center">
                <h3 class="font-semibold text-lg">1. Patient Information</h3>
                <div class="tabs tabs-boxed tabs-sm">
                  <a
                    class={["tab", not @use_new_patient && "tab-active"]}
                    phx-click="toggle_patient_mode"
                  >Existing Patient</a>
                  <a class={["tab", @use_new_patient && "tab-active"]} phx-click="toggle_patient_mode">New Patient</a>
                </div>
              </div>
              <div class="p-4 bg-base-100">
                <div :if={not @use_new_patient}>
                  <.input
                    field={@header_form[:patient_id]}
                    type="select"
                    label="Search and select patient"
                    options={Enum.map(@patients, &{patient_label(&1), &1.id})}
                    prompt="Select patient..."
                  />
                </div>

                <div :if={@use_new_patient} class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input field={@patient_form[:full_name]} label="Full Name" required />
                  <.input field={@patient_form[:gsrn]} type="text" label="GSRN (Identifier)" required />
                  <.input field={@patient_form[:age]} type="number" label="Age" />
                  <.input
                    field={@patient_form[:gender]}
                    type="select"
                    label="Gender"
                    options={["Male", "Female", "Other"]}
                    prompt="Select gender"
                  />
                  <.input field={@patient_form[:phone]} label="Phone" />
                  <.input field={@patient_form[:national_id]} label="National ID" />
                </div>
              </div>
            </div>

            <!-- Step 2: Prescription Items -->
            <div class="border rounded-box border-base-300 overflow-hidden">
              <div class="bg-base-300/50 px-4 py-3 border-b border-base-300 flex justify-between items-center">
                <h3 class="font-semibold text-lg">2. Prescription Items</h3>
                <.button type="button" phx-click="add-item" variant="ghost">+ Add Item</.button>
              </div>
              <div class="p-4 bg-base-100 space-y-4">
                <.inputs_for :let={item_form} field={@header_form[:items]}>
                  <% is_editing = MapSet.member?(@editing_items, item_form.index) %>
                  <div class={"border rounded-lg p-4 #{if is_editing, do: "border-base-300 bg-base-50", else: "border-base-200 bg-base-100"}"}>
                    <div class={"flex justify-between items-center #{if is_editing, do: "mb-4"}"}>
                      <h4 class="font-medium text-sm text-base-content/70">
                        Item {item_form.index + 1}
                      </h4>
                      <div class="flex items-center gap-2">
                        <%= if is_editing do %>
                          <% can_collapse =
                            not is_nil(Ecto.Changeset.get_field(item_form.source, :product_id)) and
                              not is_nil(
                                Ecto.Changeset.get_field(item_form.source, :quantity_prescribed)
                              ) %>
                          <.button
                            type="button"
                            phx-click="collapse-item"
                            phx-value-index={item_form.index}
                            variant="primary"
                            disabled={not can_collapse}
                          >
                            <.icon name="hero-check" class="w-4 h-4" /> Done
                          </.button>
                        <% else %>
                          <.button
                            type="button"
                            phx-click="edit-item"
                            phx-value-index={item_form.index}
                            variant="ghost-edit"
                          >
                            <.icon name="hero-pencil" class="w-4 h-4" /> Edit
                          </.button>
                        <% end %>
                        <.button
                          :if={
                            is_list(@header_form[:items].value) and
                              length(@header_form[:items].value) > 1
                          }
                          type="button"
                          phx-click="remove-item"
                          phx-value-index={item_form.index}
                          variant="ghost-delete"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" /> Remove
                        </.button>
                      </div>
                    </div>

                    <%= if is_editing do %>
                      <div class="grid grid-cols-1 md:grid-cols-6 gap-4">
                        <div class="md:col-span-2">
                          <.input
                            field={item_form[:product_id]}
                            type="select"
                            label="Product"
                            options={
                              Enum.map(
                                @products,
                                &{"#{&1.generic_name}#{if &1.brand_name, do: " (" <> &1.brand_name <> ")"}",
                                 &1.id}
                              )
                            }
                            prompt="Select product..."
                            required
                          />
                        </div>
                        <div class="md:col-span-1">
                          <.input
                            field={item_form[:quantity_prescribed]}
                            type="number"
                            label="Qty"
                            required
                            min="1"
                          />
                        </div>
                        <div class="md:col-span-1">
                          <.input
                            field={item_form[:frequency]}
                            type="text"
                            label="Frequency"
                            placeholder="e.g. 1x3"
                          />
                        </div>
                        <div class="md:col-span-1">
                          <.input
                            field={item_form[:duration_in_days]}
                            type="number"
                            label="Days"
                            min="1"
                          />
                        </div>
                        <div class="md:col-span-1">
                          <.input
                            field={item_form[:route_of_administration]}
                            type="text"
                            label="Route"
                            placeholder="e.g. Oral"
                          />
                        </div>
                        <div class="md:col-span-6">
                          <.input
                            field={item_form[:dosage_instructions]}
                            type="text"
                            label="Instructions"
                            placeholder="e.g. Take after meals"
                          />
                        </div>
                      </div>
                    <% else %>
                      <% product_id = Ecto.Changeset.get_field(item_form.source, :product_id) %>
                      <% product = Enum.find(@products, &(&1.id == product_id)) %>
                      <% qty = Ecto.Changeset.get_field(item_form.source, :quantity_prescribed) %>
                      <% freq = Ecto.Changeset.get_field(item_form.source, :frequency) %>
                      <% days = Ecto.Changeset.get_field(item_form.source, :duration_in_days) %>

                      <div class="hidden">
                        <.input field={item_form[:product_id]} type="hidden" />
                        <.input field={item_form[:quantity_prescribed]} type="hidden" />
                        <.input field={item_form[:frequency]} type="hidden" />
                        <.input field={item_form[:duration_in_days]} type="hidden" />
                        <.input field={item_form[:route_of_administration]} type="hidden" />
                        <.input field={item_form[:dosage_instructions]} type="hidden" />
                      </div>

                      <div class="mt-2 flex flex-col sm:flex-row gap-4 justify-between items-start sm:items-center">
                        <div class="flex-1">
                          <div class="font-semibold text-base-content">
                            <%= if product do %>
                              {product.generic_name} {if product.brand_name,
                                do: "(#{product.brand_name})"}
                            <% else %>
                              <span class="italic text-base-content/50">No product selected</span>
                            <% end %>
                          </div>
                          <div class="text-sm text-base-content/70 mt-1">
                            Qty: {qty || "-"} {if freq && freq != "", do: " | #{freq}"} {if days,
                              do: " | #{days} days"}
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </.inputs_for>
                <div
                  :if={
                    not is_list(@header_form[:items].value) or Enum.empty?(@header_form[:items].value)
                  }
                  class="text-center text-base-content/50 py-4"
                >
                  No items added. Click "+ Add Item" to prescribe medicine.
                </div>
              </div>
            </div>

            <!-- Step 3: Prescription Details -->
            <div class="border rounded-box border-base-300 overflow-hidden">
              <div class="bg-base-300/50 px-4 py-3 border-b border-base-300">
                <h3 class="font-semibold text-lg">3. Prescription Details</h3>
              </div>
              <div class="p-4 bg-base-100 space-y-4">
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

                <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <.input
                    field={@header_form[:referring_doctor]}
                    label="Prescriber (Doctor)"
                    required
                  />
                  <.input
                    field={@header_form[:payment_type]}
                    type="select"
                    label="Payment Method"
                    options={["Cash", "Mobile Money", "Insurance"]}
                    prompt="Select payment method"
                    required
                  />
                </div>

                <.input field={@header_form[:notes]} type="textarea" label="Additional Notes" />
              </div>
            </div>

            <div class="flex gap-2 justify-end">
              <.button type="button" patch={~p"/pharmacy/prescriptions"} variant="ghost">Cancel</.button>
              <.button type="submit" variant="primary">Create Prescription</.button>
            </div>
          </form>
        </div>
      </div>

      <.table
        :if={@live_action != :new}
        id="prescriptions"
        rows={@prescriptions}
        row_click={&JS.navigate(~p"/pharmacy/prescriptions/#{&1.id}")}
      >
        <:col :let={prescription} label="ID">#{prescription.id}</:col>
        <:col :let={prescription} label="Patient">
          <div class="font-semibold">{prescription.patient_name}</div>
          <div class="text-xs text-base-content/70">{prescription.patient_phone}</div>
        </:col>
        <:col :let={prescription} label="Status">{Phoenix.Naming.humanize(prescription.status)}</:col>
        <:col :let={prescription} label="Items">{prescription.items_count}</:col>
        <:col :let={prescription} label="Total">{prescription.total_amount}</:col>
        <:col :let={prescription} label="Prescriber">{prescription.referring_doctor}</:col>
        <:col :let={prescription} label="Created">
          {Calendar.strftime(prescription.inserted_at, "%b %d, %H:%M")}
        </:col>
      </.table>
    </Layouts.pharmacy_shell>
    """
  end

  defp patient_label(patient) do
    id = patient.national_id || patient.phone || "Unknown ID"
    "#{patient.full_name} (#{id})"
  end
end
