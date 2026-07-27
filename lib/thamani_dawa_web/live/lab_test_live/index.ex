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
     |> assign(:field_defs_rows, [])
     |> assign(:next_field_idx, 0)
     |> assign(:field_defs_error, nil)
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> refresh_categories(org_id)
     |> reload_lab_tests()}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    socket = socket |> assign(:page, page) |> reload_lab_tests()
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    rows = field_definitions_to_rows(%{})

    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_rows, rows)
    |> assign(:next_field_idx, length(rows))
    |> assign(:field_defs_error, nil)
    |> reset_preset()
    |> assign(:form, to_form(LabTests.change_lab_test(%LabTest{}, %{}), as: :lab_test))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    org_id = socket.assigns.current_scope.organization_id
    lab_test = LabTests.get_lab_test!(org_id, id)
    rows = field_definitions_to_rows(lab_test.field_definitions || %{})

    socket
    |> assign(:lab_test, lab_test)
    |> assign(:field_defs_rows, rows)
    |> assign(:next_field_idx, length(rows))
    |> assign(:field_defs_error, nil)
    |> reset_preset()
    |> assign(:form, to_form(LabTests.change_lab_test(lab_test, %{}), as: :lab_test))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_rows, [])
    |> assign(:next_field_idx, 0)
    |> assign(:field_defs_error, nil)
    |> assign(:form, nil)
    |> reset_preset()
  end

  defp reset_preset(socket) do
    socket
    |> assign(:selected_preset, "")
    |> assign(:applied_preset_defs, nil)
  end

  def handle_event("validate", %{"lab_test" => attrs} = params, socket) do
    rows = field_defs_rows_from_params(Map.get(params, "field_defs", %{}))
    {merged_attrs, field_defs_error} = merge_field_defs(attrs, rows)

    changeset =
      (socket.assigns.lab_test || %LabTest{})
      |> LabTests.change_lab_test(merged_attrs)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :lab_test))
     |> assign(:field_defs_rows, rows)
     |> assign(:field_defs_error, field_defs_error)}
  end

  def handle_event("save", %{"lab_test" => attrs} = params, socket) do
    rows = field_defs_rows_from_params(Map.get(params, "field_defs", %{}))

    case merge_field_defs(attrs, rows) do
      {merged_attrs, nil} ->
        save_lab_test(socket, socket.assigns.live_action, merged_attrs)

      {_attrs, error} ->
        {:noreply, socket |> assign(:field_defs_rows, rows) |> assign(:field_defs_error, error)}
    end
  end

  def handle_event("add_field_row", _params, socket) do
    idx = socket.assigns.next_field_idx
    new_row = %{"idx" => idx, "key" => "", "type" => "number", "unit" => "", "options" => ""}

    {:noreply,
     socket
     |> assign(:field_defs_rows, socket.assigns.field_defs_rows ++ [new_row])
     |> assign(:next_field_idx, idx + 1)}
  end

  def handle_event("remove_field_row", %{"idx" => idx}, socket) do
    idx = String.to_integer(idx)
    rows = Enum.reject(socket.assigns.field_defs_rows, &(&1["idx"] == idx))
    {:noreply, assign(socket, :field_defs_rows, rows)}
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
        {current_defs, _error} = build_field_definitions(socket.assigns.field_defs_rows)

        if current_defs in [%{}, socket.assigns.applied_preset_defs] do
          rows = field_definitions_to_rows(preset.field_definitions)

          {:noreply,
           socket
           |> assign(:field_defs_rows, rows)
           |> assign(:next_field_idx, length(rows))
           |> assign(:applied_preset_defs, preset.field_definitions)
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

  defp merge_field_defs(attrs, rows) do
    case build_field_definitions(rows) do
      {field_definitions, nil} -> {Map.put(attrs, "field_definitions", field_definitions), nil}
      {_field_definitions, error} -> {attrs, error}
    end
  end

  defp field_defs_rows_from_params(field_defs_params) do
    field_defs_params
    |> Enum.map(fn {idx, row} ->
      %{
        "idx" => String.to_integer(idx),
        "key" => Map.get(row, "key", ""),
        "type" => Map.get(row, "type", "number"),
        "unit" => Map.get(row, "unit", ""),
        "options" => Map.get(row, "options", "")
      }
    end)
    |> Enum.sort_by(& &1["idx"])
  end

  defp build_field_definitions(rows) do
    Enum.reduce_while(rows, {%{}, nil}, fn row, {defs, nil} ->
      key = String.trim(row["key"] || "")
      type = row["type"] || "number"
      unit = String.trim(row["unit"] || "")
      options_raw = row["options"] || ""

      cond do
        key == "" and unit == "" and String.trim(options_raw) == "" ->
          {:cont, {defs, nil}}

        key == "" ->
          {:halt, {defs, "Give every field a name."}}

        type == "select" ->
          options =
            options_raw
            |> String.split(",")
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          if options == [] do
            {:halt, {defs, "Give \"#{key}\" at least one choice (separate choices with commas)."}}
          else
            {:cont, {Map.put(defs, key, %{"type" => "select", "options" => options}), nil}}
          end

        true ->
          {:cont, {Map.put(defs, key, %{"type" => type, "unit" => unit}), nil}}
      end
    end)
  end

  defp field_definitions_to_rows(field_definitions) when map_size(field_definitions) == 0 do
    [%{"idx" => 0, "key" => "", "type" => "number", "unit" => "", "options" => ""}]
  end

  defp field_definitions_to_rows(field_definitions) do
    field_definitions
    |> Enum.with_index()
    |> Enum.map(fn {{key, def_}, idx} ->
      %{
        "idx" => idx,
        "key" => key,
        "type" => Map.get(def_, "type", "text"),
        "unit" => Map.get(def_, "unit", ""),
        "options" => def_ |> Map.get("options", []) |> Enum.join(", ")
      }
    end)
  end

  defp reload_lab_tests(socket) do
    org_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = LabTests.list_lab_tests_paginated(org_id, page)
    lab_tests = page_result.entries

    filtered =
      lab_tests
      |> filter_by_search(socket.assigns.search)
      |> filter_by_category(socket.assigns.filters.category)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> stream(:lab_tests, filtered, reset: true)
    |> assign(:page_info, page_result)
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

            <.input
              field={@form[:category_id]}
              type="select"
              label="Category"
              options={@categories}
              prompt="Choose a category"
              required
            />
          </div>

          <div class="grid grid-cols-2 gap-3 mb-3">
            <.input field={@form[:price]} type="number" label="Price" step="0.01" min="0" required />
            <div class="flex items-end pb-1">
              <.input field={@form[:is_active]} type="checkbox" label="Active" />
            </div>
          </div>

          <div class="mb-3">
            <label class="block text-sm font-medium mb-1">Test results</label>
            <p class="text-sm mb-2" style="color: var(--thamani-pewter);">
              Add one row for each result this test reports.
            </p>

            <div
              class="grid grid-cols-12 gap-2 px-1 mb-1 text-xs font-medium"
              style="color: var(--thamani-pewter);"
            >
              <div class="col-span-5">Field name</div>
              <div class="col-span-3">Type</div>
              <div class="col-span-3">Unit or choices</div>
            </div>

            <div class="divide-y divide-base-300 border-t border-b border-base-300">
              <div
                :for={row <- @field_defs_rows}
                class="grid grid-cols-12 gap-2 items-center py-2"
              >
                <div class="col-span-5">
                  <.input
                    type="text"
                    name={"field_defs[#{row["idx"]}][key]"}
                    value={row["key"]}
                    placeholder="e.g. Haemoglobin"
                    class="thamani-input"
                  />
                </div>
                <div class="col-span-3">
                  <.input
                    type="select"
                    name={"field_defs[#{row["idx"]}][type]"}
                    value={row["type"]}
                    options={[{"Number", "number"}, {"Text", "text"}, {"Multiple choice", "select"}]}
                  />
                </div>
                <div class="col-span-3">
                  <.input
                    :if={row["type"] != "select"}
                    type="text"
                    name={"field_defs[#{row["idx"]}][unit]"}
                    value={row["unit"]}
                    placeholder="e.g. g/dL"
                  />
                  <.input
                    :if={row["type"] == "select"}
                    type="text"
                    name={"field_defs[#{row["idx"]}][options]"}
                    value={row["options"]}
                    placeholder="e.g. Positive, Negative"
                  />
                </div>
                <div class="col-span-1 flex justify-end">
                  <button
                    type="button"
                    phx-click="remove_field_row"
                    phx-value-idx={row["idx"]}
                    aria-label="Remove field"
                    class="relative transition-[opacity,transform] hover:opacity-70 active:scale-[0.96] after:absolute after:inset-[-10px] after:content-['']"
                    style="color: var(--thamani-pewter);"
                  >
                    <.icon name="hero-x-mark" class="size-5" />
                  </button>
                </div>
              </div>
            </div>

            <.button type="button" phx-click="add_field_row" variant="ghost" class="mt-2">
              + Add field
            </.button>

            <p :if={@field_defs_error} class="mt-2 text-sm" style="color: #C21F17;">
              {@field_defs_error}
            </p>
            <p
              :if={!@field_defs_error && @form[:field_definitions].errors != []}
              class="mt-2 text-sm"
              style="color: #C21F17;"
            >
              Add at least one field.
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
          <.button
            variant="ghost-edit"
            patch={~p"/lab/tests/#{test.id}/edit"}
            class="gap-2"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.button>
        </:action>
        <:action :let={{_id, test}}>
          <.button
            type="button"
            phx-click="toggle_active"
            phx-value-id={test.id}
            class="gap-2"
            variant={if test.is_active, do: "ghost-delete", else: "ghost"}
          >
            <.icon
              name={if test.is_active, do: "hero-power", else: "hero-arrow-path"}
              class="size-4"
            />
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

      <.pagination page={@page_info} path={~p"/lab/tests"} />
    </Layouts.lab_shell>
    """
  end
end
