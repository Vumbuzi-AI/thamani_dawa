defmodule ThamaniDawaWeb.LabTestLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabTests
  alias ThamaniDawa.LabTests.FieldDefinitionPresets
  alias ThamaniDawa.LabTests.LabTest
  alias ThamaniDawa.LabTests.LabTestCategory

  @default_filters %{category: "", status: ""}

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:lab_test, nil)
     |> assign(:form, nil)
     |> assign(:field_defs_json, "{}")
     |> assign(:field_defs_error, nil)
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> refresh_categories(org_id)
     |> reload_lab_tests()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_json, "{}")
    |> assign(:field_defs_error, nil)
    |> assign(:use_new_category, false)
    |> reset_preset()
    |> assign(
      :category_form,
      to_form(LabTestCategory.changeset(%LabTestCategory{}, %{}), as: :category)
    )
    |> assign(:form, to_form(LabTests.change_lab_test(%LabTest{}, %{}), as: :lab_test))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    org_id = socket.assigns.current_scope.organization_id
    lab_test = LabTests.get_lab_test!(org_id, id)

    socket
    |> assign(:lab_test, lab_test)
    |> assign(:field_defs_json, Jason.encode!(lab_test.field_definitions || %{}, pretty: true))
    |> assign(:field_defs_error, nil)
    |> assign(:use_new_category, false)
    |> reset_preset()
    |> assign(
      :category_form,
      to_form(LabTestCategory.changeset(%LabTestCategory{}, %{}), as: :category)
    )
    |> assign(:form, to_form(LabTests.change_lab_test(lab_test, %{}), as: :lab_test))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_json, "{}")
    |> assign(:field_defs_error, nil)
    |> assign(:form, nil)
    |> reset_preset()
  end

  defp reset_preset(socket) do
    socket
    |> assign(:selected_preset, "")
    |> assign(:applied_preset_json, nil)
  end

  def handle_event("toggle_new_category", _params, socket) do
    {:noreply, assign(socket, :use_new_category, not socket.assigns.use_new_category)}
  end

  def handle_event("validate", %{"lab_test" => attrs, "field_defs_json" => json}, socket) do
    {merged_attrs, json_error} = decode_field_defs(attrs, json)

    changeset =
      (socket.assigns.lab_test || %LabTest{})
      |> LabTests.change_lab_test(merged_attrs)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :lab_test))
     |> assign(:field_defs_json, json)
     |> assign(:field_defs_error, json_error)}
  end

  def handle_event("save", %{"lab_test" => attrs, "field_defs_json" => json} = params, socket) do
    case decode_field_defs(attrs, json) do
      {merged_attrs, nil} ->
        org_id = socket.assigns.current_scope.organization_id

        case resolve_category(socket, org_id, merged_attrs, params) do
          {:ok, attrs} ->
            save_lab_test(socket, socket.assigns.live_action, attrs)

          {:error, changeset} ->
            {:noreply, assign(socket, :category_form, to_form(changeset, as: :category))}
        end

      {_attrs, error} ->
        {:noreply, assign(socket, :field_defs_error, error)}
    end
  end

  def handle_event("select_preset", %{"preset" => ""}, socket) do
    {:noreply, assign(socket, :selected_preset, "")}
  end

  def handle_event("select_preset", %{"preset" => name}, socket) do
    case FieldDefinitionPresets.get(name) do
      nil ->
        {:noreply, socket}

      preset ->
        apply_preset(socket, preset)
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    lab_test = LabTests.get_lab_test!(org_id, id)

    case LabTests.update_lab_test(org_id, lab_test, %{is_active: !lab_test.is_active}) do
      {:ok, _updated} ->
        {:noreply, reload_lab_tests(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update test.")}
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_lab_tests()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      category: Map.get(filter_params, "category", ""),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> reload_lab_tests()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_lab_tests()}
  end

  def handle_event("clear_chip", %{"field" => "category"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | category: ""}) |> reload_lab_tests()}
  end

  def handle_event("clear_chip", %{"field" => "status"}, socket) do
    {:noreply,
     socket |> assign(:filters, %{socket.assigns.filters | status: ""}) |> reload_lab_tests()}
  end

  defp resolve_category(%{assigns: %{use_new_category: true}}, organization_id, attrs, %{
         "category" => category_attrs
       }) do
    case LabTests.create_lab_test_category(organization_id, category_attrs) do
      {:ok, category} -> {:ok, Map.put(attrs, "category_id", category.id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp resolve_category(_socket, _organization_id, attrs, _params), do: {:ok, attrs}

  defp apply_preset(socket, preset) do
    org_id = socket.assigns.current_scope.organization_id

    case find_or_create_category(socket, org_id, preset.category_name) do
      {:ok, category} ->
        socket =
          socket
          |> refresh_categories(org_id)
          |> assign(:selected_preset, preset.name)

        changeset =
          socket.assigns.form.source
          |> LabTests.change_lab_test(%{"name" => preset.name, "category_id" => category.id})

        socket = assign(socket, :form, to_form(changeset, as: :lab_test))
        new_json = Jason.encode!(preset.field_definitions, pretty: true)

        if socket.assigns.field_defs_json in ["{}", socket.assigns.applied_preset_json] do
          {:noreply,
           socket
           |> assign(:field_defs_json, new_json)
           |> assign(:applied_preset_json, new_json)
           |> assign(:field_defs_error, nil)}
        else
          {:noreply,
           put_flash(
             socket,
             :info,
             "Applied #{preset.name}'s name and category. Field definitions were already edited, so they were left as-is."
           )}
        end

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't apply that preset's category.")}
    end
  end

  defp find_or_create_category(socket, org_id, category_name) do
    case Enum.find(socket.assigns.categories_by_id, fn {_id, category} ->
           category.name == category_name
         end) do
      {_id, category} -> {:ok, category}
      nil -> LabTests.create_lab_test_category(org_id, %{name: category_name})
    end
  end

  defp save_lab_test(socket, :new, attrs) do
    org_id = socket.assigns.current_scope.organization_id

    case LabTests.create_lab_test(org_id, attrs) do
      {:ok, lab_test} ->
        socket = refresh_categories(socket, org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Test created.")
         |> stream_insert(:lab_tests, with_category(socket, lab_test))
         |> push_patch(to: ~p"/lab/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :lab_test))}
    end
  end

  defp save_lab_test(socket, :edit, attrs) do
    org_id = socket.assigns.current_scope.organization_id

    case LabTests.update_lab_test(org_id, socket.assigns.lab_test, attrs) do
      {:ok, lab_test} ->
        socket = refresh_categories(socket, org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Test updated.")
         |> stream_insert(:lab_tests, with_category(socket, lab_test))
         |> push_patch(to: ~p"/lab/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :lab_test))}
    end
  end

  defp with_category(socket, lab_test) do
    %{lab_test | category: socket.assigns.categories_by_id[lab_test.category_id]}
  end

  defp refresh_categories(socket, org_id) do
    categories = LabTests.list_lab_test_categories(org_id)

    socket
    |> assign(:categories, Enum.map(categories, &{&1.name, &1.id}))
    |> assign(:category_filter_options, Enum.map(categories, & &1.name))
    |> assign(:categories_by_id, Map.new(categories, &{&1.id, &1}))
  end

  defp decode_field_defs(attrs, json) do
    case Jason.decode(json) do
      {:ok, decoded} -> {Map.put(attrs, "field_definitions", decoded), nil}
      {:error, _} -> {attrs, "must be valid JSON (e.g. {\"result\": {\"type\": \"number\"}})"}
    end
  end

  defp reload_lab_tests(socket) do
    org_id = socket.assigns.current_scope.organization_id
    lab_tests = LabTests.list_lab_tests(org_id)

    filtered =
      lab_tests
      |> filter_by_search(socket.assigns.search)
      |> filter_by_category(socket.assigns.filters.category)
      |> filter_by_status(socket.assigns.filters.status)

    stream(socket, :lab_tests, filtered, reset: true)
  end

  defp filter_by_search(lab_tests, ""), do: lab_tests

  defp filter_by_search(lab_tests, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(lab_tests, fn test ->
      [test.name, category_name(test)]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_category(lab_tests, ""), do: lab_tests

  defp filter_by_category(lab_tests, category),
    do: Enum.filter(lab_tests, &(category_name(&1) == category))

  defp filter_by_status(lab_tests, ""), do: lab_tests
  defp filter_by_status(lab_tests, "active"), do: Enum.filter(lab_tests, & &1.is_active)
  defp filter_by_status(lab_tests, "inactive"), do: Enum.filter(lab_tests, &(!&1.is_active))

  defp active_filter_count(filters) do
    Enum.count([filters.category != "", filters.status != ""], & &1)
  end

  defp filter_chips(filters) do
    [
      filters.category != "" && %{label: "Category: #{filters.category}", field: "category"},
      filters.status != "" &&
        %{
          label: "Status: #{Phoenix.Naming.humanize(filters.status)}",
          field: "status"
        }
    ]
    |> Enum.filter(& &1)
  end

  defp category_name(%{category: nil}), do: "(unknown category)"
  defp category_name(%{category: %LabTestCategory{name: name}}), do: name

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/tests"}>
      <.header icon="hero-beaker">
        Test catalog
        <:subtitle>Search, filter, and manage your lab test catalog.</:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/lab/tests/new"}>+ New test</.button>
        </:actions>
        <:toolbar>
          <form phx-change="search" class="flex-1" id="search-form">
            <.search_input name="search" value={@search} placeholder="Search by name or category" />
          </form>

          <.filter_drawer
            id="lab-tests-filters"
            title="Filter tests"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Category">
              <.input
                type="select"
                name="filters[category]"
                value={@filters.category}
                options={@category_filter_options}
                prompt="All categories"
              />
            </:group>
            <:group label="Status">
              <.input
                type="select"
                name="filters[status]"
                value={@filters.status}
                options={[{"Active", "active"}, {"Inactive", "inactive"}]}
                prompt="All statuses"
              />
            </:group>
            <:chip
              :for={chip <- filter_chips(@filters)}
              label={chip.label}
              clear={JS.push("clear_chip", value: %{"field" => chip.field})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="lab-test-modal"
        show
        on_cancel={JS.patch(~p"/lab/tests")}
      >
        <h2 class="text-base font-semibold mb-4" style="color: #373896;">
          {if @live_action == :new, do: "New test", else: "Edit test"}
        </h2>

        <form id="lab-test-preset-form" phx-change="select_preset" class="mb-3">
          <.input
            type="select"
            name="preset"
            value={@selected_preset}
            label="Preset (optional)"
            options={FieldDefinitionPresets.options()}
            prompt="No preset — enter everything manually"
          />
        </form>

        <.form for={@form} id="lab-test-form" phx-submit="save" phx-change="validate">
          <div class="grid grid-cols-2 gap-3 mb-3">
            <.input field={@form[:name]} label="Test name" required />

            <div class="flex items-end gap-2">
              <div class="flex-1">
                <.input
                  :if={not @use_new_category}
                  field={@form[:category_id]}
                  type="select"
                  label="Category"
                  options={@categories}
                  prompt="Choose a category"
                  required
                />
                <.input
                  :if={@use_new_category}
                  field={@category_form[:name]}
                  label="New category name"
                  required
                />
              </div>
              <.button type="button" phx-click="toggle_new_category" class="mb-1">
                {if @use_new_category, do: "Choose existing", else: "+ New category"}
              </.button>
            </div>
          </div>

          <div class="grid grid-cols-2 gap-3 mb-3">
            <.input field={@form[:price]} type="number" label="Price" step="0.01" min="0" required />
            <div class="flex items-end pb-1">
              <.input field={@form[:is_active]} type="checkbox" label="Active" />
            </div>
          </div>

          <div class="mb-3">
            <label class="block text-sm font-medium mb-1">Field definitions (JSON)</label>
            <textarea
              name="field_defs_json"
              rows="6"
              class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-2 font-mono text-xs"
              phx-debounce="blur"
            >{@field_defs_json}</textarea>
            <p :if={@field_defs_error} class="mt-1 text-sm" style="color: #C21F17;">
              {@field_defs_error}
            </p>
            <p
              :if={!@field_defs_error && @form[:field_definitions].errors != []}
              class="mt-1 text-sm"
              style="color: #C21F17;"
            >
              can't be blank
            </p>
          </div>

          <div class="flex gap-2">
            <.button variant="primary">Save</.button>
            <.button patch={~p"/lab/tests"}>Cancel</.button>
          </div>
        </.form>
      </.modal>

      <.table id="lab-tests" rows={@streams.lab_tests}>
        <:col :let={{_id, test}} label="Name">{test.name}</:col>
        <:col :let={{_id, test}} label="Category">{category_name(test)}</:col>
        <:col :let={{_id, test}} label="Price">{test.price && "KES #{test.price}"}</:col>
        <:col :let={{_id, test}} label="Status">
          <.status_badge status={if test.is_active, do: :active, else: :inactive} />
        </:col>
        <:action :let={{_id, test}}>
          <.link patch={~p"/lab/tests/#{test.id}/edit"} class="link">Edit</.link>
        </:action>
        <:action :let={{_id, test}}>
          <.button
            type="button"
            phx-click="toggle_active"
            phx-value-id={test.id}
          >
            {if test.is_active, do: "Deactivate", else: "Reactivate"}
          </.button>
        </:action>
        <:empty_state>
          <.blank_state
            icon="hero-beaker"
            title={
              if @search != "" or active_filter_count(@filters) > 0,
                do: "No tests match your search or filters",
                else: "No tests yet"
            }
          >
            {if @search != "" or active_filter_count(@filters) > 0,
              do: "Try a different search term, or clear the applied filters.",
              else: "Tests you add to the catalog will appear here."}
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
