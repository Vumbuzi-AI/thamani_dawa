defmodule ThamaniDawaWeb.TestCategoryLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.LabTestTemplates.LabTestCategory

  def mount(_params, _session, socket) do
    {:ok, assign_categories(socket)}
  end

  def handle_params(_params, _url, socket) do
    form =
      if socket.assigns.live_action == :new do
        to_form(LabTestCategory.changeset(%LabTestCategory{}, %{}), as: :category)
      end

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"category" => attrs}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case LabTestTemplates.create_lab_test_category(organization_id, attrs) do
      {:ok, _category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created.")
         |> assign_categories()
         |> push_patch(to: ~p"/lab/test-categories")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :category))}
    end
  end

  defp assign_categories(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    assign(socket, :categories, LabTestTemplates.list_lab_test_categories(organization_id))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>
        Test categories
        <:actions>
          <.button variant="primary" navigate={~p"/lab/test-categories/new"}>+ Add category</.button>
        </:actions>
      </.header>

      <div :if={@live_action == :new} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Add a category</h2>
          <form phx-submit="save">
            <.input field={@form[:name]} label="Name" required />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <.input field={@form[:display_order]} type="number" label="Display order" />
            <div class="flex gap-2 mt-2">
              <.button variant="primary">Save</.button>
              <.button navigate={~p"/lab/test-categories"}>Cancel</.button>
            </div>
          </form>
        </div>
      </div>

      <.table id="categories" rows={@categories}>
        <:col :let={category} label="Name">{category.name}</:col>
        <:col :let={category} label="Description">{category.description}</:col>
        <:col :let={category} label="Display order">{category.display_order}</:col>
      </.table>
    </Layouts.app_shell>
    """
  end
end
