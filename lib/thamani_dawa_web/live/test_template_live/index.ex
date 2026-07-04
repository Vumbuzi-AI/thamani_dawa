defmodule ThamaniDawaWeb.TestTemplateLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.LabTestTemplates.{FieldDefinition, LabTestTemplate}

  def mount(_params, _session, socket) do
    {:ok, assign_templates(socket)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    assign_form(socket, %LabTestTemplate{field_definitions: []}, %{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    organization_id = socket.assigns.current_scope.organization_id
    template = LabTestTemplates.get_lab_test_template!(organization_id, id)
    assign_form(socket, template, %{})
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, template: nil, form: nil)
  end

  defp assign_form(socket, template, attrs) do
    changeset = LabTestTemplate.changeset(template, attrs)
    assign(socket, template: template, form: to_form(changeset, as: :template))
  end

  def handle_event("validate", %{"template" => attrs}, socket) do
    changeset =
      socket.assigns.template
      |> LabTestTemplate.changeset(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :template))}
  end

  def handle_event("add_field", _params, socket) do
    field_defs = Ecto.Changeset.get_field(socket.assigns.form.source, :field_definitions, []) ++ [%FieldDefinition{}]
    changeset = Ecto.Changeset.put_embed(socket.assigns.form.source, :field_definitions, field_defs)
    {:noreply, assign(socket, :form, to_form(changeset, as: :template, action: :validate))}
  end

  def handle_event("remove_field", %{"index" => index}, socket) do
    index = String.to_integer(index)
    field_defs = List.delete_at(Ecto.Changeset.get_field(socket.assigns.form.source, :field_definitions, []), index)
    changeset = Ecto.Changeset.put_embed(socket.assigns.form.source, :field_definitions, field_defs)
    {:noreply, assign(socket, :form, to_form(changeset, as: :template, action: :validate))}
  end

  def handle_event("save", %{"template" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    save_template(socket, socket.assigns.live_action, organization_id, attrs)
  end

  defp save_template(socket, :new, organization_id, attrs) do
    case LabTestTemplates.create_lab_test_template(organization_id, attrs) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template created.")
         |> assign_templates()
         |> push_patch(to: ~p"/lab/test-templates")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :template))}
    end
  end

  defp save_template(socket, :edit, _organization_id, attrs) do
    case LabTestTemplates.update_lab_test_template(socket.assigns.template, attrs) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template updated.")
         |> assign_templates()
         |> push_patch(to: ~p"/lab/test-templates")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :template))}
    end
  end

  defp assign_templates(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    assign(socket, :templates, LabTestTemplates.list_lab_test_templates(organization_id))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Test templates
        <:actions>
          <.button variant="primary" navigate={~p"/lab/test-templates/new"}>+ Add template</.button>
        </:actions>
      </.header>

      <div :if={@live_action in [:new, :edit]} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">{if @live_action == :new, do: "Add a template", else: "Edit template"}</h2>
          <form phx-change="validate" phx-submit="save">
            <.input field={@form[:name]} label="Name" required />
            <.input field={@form[:short_name]} label="Short name" />
            <.input field={@form[:display_order]} type="number" label="Display order" />
            <.input field={@form[:is_active]} type="checkbox" label="Active" />

            <.header class="mt-4">Result fields</.header>
            <.inputs_for :let={fd_form} field={@form[:field_definitions]}>
              <div class="border rounded-box border-base-300 p-3 mb-2">
                <.input field={fd_form[:key]} label="Key" required />
                <.input field={fd_form[:label]} label="Label" required />
                <.input field={fd_form[:unit]} label="Unit" />
                <.input
                  field={fd_form[:data_type]}
                  type="select"
                  label="Data type"
                  options={Enum.map(FieldDefinition.data_types(), &{Phoenix.Naming.humanize(&1), &1})}
                />
                <.input field={fd_form[:low]} type="number" step="any" label="Low" />
                <.input field={fd_form[:high]} type="number" step="any" label="High" />
                <.button type="button" phx-click="remove_field" phx-value-index={fd_form.index} class="mt-2">
                  Remove field
                </.button>
              </div>
            </.inputs_for>
            <.button type="button" phx-click="add_field">+ Add field</.button>

            <div class="flex gap-2 mt-4">
              <.button variant="primary">Save</.button>
              <.button navigate={~p"/lab/test-templates"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table id="templates" rows={@templates}>
        <:col :let={template} label="Name">{template.name}</:col>
        <:col :let={template} label="Short name">{template.short_name}</:col>
        <:col :let={template} label="Fields">{length(template.field_definitions)}</:col>
        <:col :let={template} label="Active">{if template.is_active, do: "Yes", else: "No"}</:col>
        <:action :let={template}>
          <.link navigate={~p"/lab/test-templates/#{template.id}/edit"} class="link">Edit</.link>
        </:action>
      </.table>
    </Layouts.app_shell>
    """
  end
end
