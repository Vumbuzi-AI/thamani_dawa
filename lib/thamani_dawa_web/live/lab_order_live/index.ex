defmodule ThamaniDawaWeb.LabOrderLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabOrders
  alias ThamaniDawa.LabOrders.LabOrder
  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.LabTests
  alias ThamaniDawa.Patients
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  @urgencies ~w(routine urgent stat)

  def mount(_params, _session, socket) do
    {:ok, assign_lab_orders(socket)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id
    site_id = SiteScoping.default_site_id(scope)
    initial_attrs = if site_id, do: %{site_id: site_id}, else: %{}

    socket
    |> assign(:patients, Patients.list_patients(organization_id))
    |> assign(:lab_tests, LabTests.list_lab_tests(organization_id))
    |> assign(:templates, LabTestTemplates.list_lab_test_templates(organization_id))
    |> assign(:sites, Sites.list_sites(organization_id))
    |> assign(:site_locked, not is_nil(site_id))
    |> assign(:urgencies, @urgencies)
    |> assign(:use_new_patient, false)
    |> assign(
      :header_form,
      to_form(LabOrder.changeset(%LabOrder{}, initial_attrs), as: :lab_order)
    )
    |> assign(:patient_form, to_form(Patient.changeset(%Patient{}, %{}), as: :patient))
    |> assign(:test_ids, [0])
    |> assign(:next_test_id, 1)
  end

  defp apply_action(socket, :index), do: socket

  def handle_event("toggle_new_patient", _params, socket) do
    {:noreply, assign(socket, :use_new_patient, not socket.assigns.use_new_patient)}
  end

  def handle_event("add_test", _params, socket) do
    {:noreply,
     socket
     |> update(:test_ids, &(&1 ++ [socket.assigns.next_test_id]))
     |> update(:next_test_id, &(&1 + 1))}
  end

  def handle_event("remove_test", %{"id" => id}, socket) do
    id = String.to_integer(id)
    test_ids = List.delete(socket.assigns.test_ids, id)
    test_ids = if test_ids == [], do: socket.assigns.test_ids, else: test_ids
    {:noreply, assign(socket, :test_ids, test_ids)}
  end

  def handle_event("save", params, socket) do
    %{"lab_order" => header_attrs} = params
    tests_attrs = params |> Map.get("tests", []) |> Enum.map(&sanitize_test_attrs/1)

    if tests_attrs == [] do
      {:noreply, put_flash(socket, :error, "Add at least one test to the order.")}
    else
      organization_id = socket.assigns.current_scope.organization_id
      header_attrs = Map.put(header_attrs, "ordered_by_id", socket.assigns.current_scope.user.id)

      with {:ok, header_attrs} <- resolve_patient(socket, organization_id, header_attrs, params),
           {:ok, _result} <-
             LabOrders.create_lab_order_with_tests(organization_id, header_attrs, tests_attrs) do
        {:noreply,
         socket
         |> put_flash(:info, "Lab order created.")
         |> assign_lab_orders()
         |> push_patch(to: ~p"/lab/orders")}
      else
        {:error, %Ecto.Changeset{data: %Patient{}} = changeset} ->
          {:noreply, assign(socket, :patient_form, to_form(changeset, as: :patient))}

        {:error, changeset} ->
          {:noreply, assign(socket, :header_form, to_form(changeset, as: :lab_order))}
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

  defp sanitize_test_attrs(test_attrs) do
    Map.update(test_attrs, "template_id", nil, fn value ->
      if value == "", do: nil, else: value
    end)
  end

  defp assign_lab_orders(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    lab_orders =
      organization_id
      |> LabOrders.list_lab_orders()
      |> SiteScoping.for_current_site(socket.assigns.current_scope)

    assign(socket, :lab_orders, lab_orders)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Lab orders
        <:actions>
          <.button variant="primary" navigate={~p"/lab/orders/new"}>+ New order</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">New lab order</h2>

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

            <.input :if={@site_locked} field={@header_form[:site_id]} type="hidden" />
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
            <.input
              field={@header_form[:urgency]}
              type="select"
              label="Urgency"
              options={Enum.map(@urgencies, &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose urgency"
            />
            <.input field={@header_form[:payment_type]} label="Payment type" />
            <.input field={@header_form[:has_paid]} type="checkbox" label="Paid" />
            <.input
              field={@header_form[:sample_collection_date]}
              type="date"
              label="Sample collection date"
            />
            <.input
              field={@header_form[:sample_collection_description]}
              label="Sample collection description"
            />

            <.header class="mt-4">Tests</.header>
            <div :for={id <- @test_ids} class="border rounded-box border-base-300 p-3 mb-2">
              <.input
                type="select"
                name="tests[][lab_test_id]"
                label="Test"
                options={Enum.map(@lab_tests, &{&1.name, &1.id})}
                prompt="Choose a test"
              />
              <.input
                type="select"
                name="tests[][template_id]"
                label="Result template"
                options={Enum.map(@templates, &{&1.name, &1.id})}
                prompt="No template"
              />
              <.button type="button" phx-click="remove_test" phx-value-id={id} class="mt-2">
                Remove test
              </.button>
            </div>
            <.button type="button" phx-click="add_test">+ Add test</.button>

            <div class="flex gap-2 mt-4">
              <.button variant="primary">Create order</.button>
              <.button navigate={~p"/lab/orders"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table id="lab-orders" rows={@lab_orders} row_click={&~p"/lab/orders/#{&1.id}"}>
        <:col :let={lab_order} label="Status">{Phoenix.Naming.humanize(lab_order.status)}</:col>
        <:col :let={lab_order} label="Urgency">{lab_order.urgency}</:col>
        <:col :let={lab_order} label="Paid">{if lab_order.has_paid, do: "Yes", else: "No"}</:col>
        <:col :let={lab_order} label="Created">{lab_order.inserted_at}</:col>
      </.table>
    </Layouts.app_shell>
    """
  end
end
