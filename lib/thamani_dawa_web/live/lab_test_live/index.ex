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
    page = if p = Map.get(params, "page"), do: String.to_integer(p), else: socket.assigns.page
    search = Map.get(params, "search", socket.assigns.search)
    category = Map.get(params, "category", socket.assigns.filters.category)
    status = Map.get(params, "status", socket.assigns.filters.status)

    filters = %{
      category: category,
      status: status
    }

    socket =
      socket
      |> assign(:page, page)
      |> assign(:search, search)
      |> assign(:filters, filters)
      |> reload_lab_tests()

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

  def handle_event("validate", params, socket) do
    attrs = params["lab_test"] || %{}
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

  def handle_event("save", params, socket) do
    attrs = params["lab_test"] || %{}
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

    new_row = %{
      "idx" => idx,
      "key" => "",
      "type" => "number",
      "unit" => "",
      "options" => ["Option 1"]
    }

    {:noreply,
     socket
     |> assign(:field_defs_rows, socket.assigns.field_defs_rows ++ [new_row])
     |> assign(:next_field_idx, idx + 1)}
  end

  def handle_event("remove_field_row", %{"idx" => idx}, socket) do
    if length(socket.assigns.field_defs_rows) > 1 do
      idx = String.to_integer(idx)
      rows = Enum.reject(socket.assigns.field_defs_rows, &(&1["idx"] == idx))
      {:noreply, assign(socket, :field_defs_rows, rows)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_field_option", %{"field_idx" => f_idx}, socket) do
    f_idx = String.to_integer(f_idx)
    rows = Enum.map(socket.assigns.field_defs_rows, &update_row_add_option(&1, f_idx))
    {:noreply, assign(socket, :field_defs_rows, rows)}
  end

  def handle_event("remove_field_option", %{"field_idx" => f_idx, "opt_idx" => o_idx}, socket) do
    f_idx = String.to_integer(f_idx)
    o_idx = String.to_integer(o_idx)

    rows = Enum.map(socket.assigns.field_defs_rows, &update_row_remove_option(&1, f_idx, o_idx))
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
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload_lab_tests()}
  end

  def handle_event("apply_filters", %{"filters" => filter_params}, socket) do
    filters = %{
      category: Map.get(filter_params, "category", ""),
      status: Map.get(filter_params, "status", "")
    }

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload_lab_tests()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply,
     socket |> assign(:filters, @default_filters) |> assign(:page, 1) |> reload_lab_tests()}
  end

  def handle_event("clear_chip", %{"field" => "category"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | category: ""})
     |> assign(:page, 1)
     |> reload_lab_tests()}
  end

  def handle_event("clear_chip", %{"field" => "status"}, socket) do
    {:noreply,
     socket
     |> assign(:filters, %{socket.assigns.filters | status: ""})
     |> assign(:page, 1)
     |> reload_lab_tests()}
  end

  defp update_row_add_option(%{"idx" => idx} = row, target_idx) when idx == target_idx do
    opts = if is_list(row["options"]), do: row["options"], else: []
    Map.put(row, "options", opts ++ [""])
  end

  defp update_row_add_option(row, _target_idx), do: row

  defp update_row_remove_option(%{"idx" => idx} = row, target_idx, o_idx)
       when idx == target_idx do
    opts = if is_list(row["options"]), do: row["options"], else: []

    if length(opts) > 1 do
      Map.put(row, "options", List.delete_at(opts, o_idx))
    else
      row
    end
  end

  defp update_row_remove_option(row, _target_idx, _o_idx), do: row

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
    lab_test = socket.assigns.lab_test

    case LabTests.update_lab_test(org_id, lab_test, attrs) do
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

  defp field_defs_rows_from_params(field_defs_params) when is_map(field_defs_params) do
    field_defs_params
    |> Enum.reject(fn {k, _v} -> String.starts_with?(to_string(k), "_") end)
    |> Enum.filter(fn {k, _v} -> match?({_, ""}, Integer.parse(to_string(k))) end)
    |> Enum.map(fn {idx, row} ->
      raw_opts = if is_map(row), do: Map.get(row, "options", []), else: []
      opts_list = parse_options_param(raw_opts)
      type = if is_map(row), do: Map.get(row, "type", "number"), else: "number"

      opts_list =
        if type in ["select", "checkbox"] and opts_list == [] do
          ["Option 1"]
        else
          opts_list
        end

      %{
        "idx" => String.to_integer(to_string(idx)),
        "key" => if(is_map(row), do: Map.get(row, "key", ""), else: ""),
        "type" => type,
        "unit" => if(is_map(row), do: Map.get(row, "unit", ""), else: ""),
        "options" => opts_list
      }
    end)
    |> Enum.sort_by(& &1["idx"])
  end

  defp field_defs_rows_from_params(_), do: []

  defp parse_options_param(opts) when is_map(opts) do
    opts
    |> Enum.reject(fn {k, _v} -> String.starts_with?(to_string(k), "_") end)
    |> Enum.filter(fn {k, _v} -> match?({_, ""}, Integer.parse(to_string(k))) end)
    |> Enum.sort_by(fn {k, _v} -> String.to_integer(to_string(k)) end)
    |> Enum.map(fn {_k, v} -> to_string(v) end)
  end

  defp parse_options_param(opts) when is_list(opts), do: Enum.map(opts, &to_string/1)

  defp parse_options_param(_), do: []

  defp build_field_definitions(rows) do
    Enum.reduce_while(rows, {%{}, nil}, fn row, {defs, nil} ->
      case classify_row(row) do
        :skip -> {:cont, {defs, nil}}
        {:error, msg} -> {:halt, {defs, msg}}
        {:ok, key, field_def} -> {:cont, {Map.put(defs, key, field_def), nil}}
      end
    end)
  end

  defp classify_row(row) do
    {key, type, unit, options} = parse_row(row)

    cond do
      key == "" and unit == "" and clean_options(options) == [] -> :skip
      key == "" -> {:error, "Give every field a name."}
      type == "select" -> classify_select_row(key, options)
      true -> {:ok, key, %{"type" => type, "unit" => unit}}
    end
  end

  defp parse_row(row) do
    key = String.trim(row["key"] || "")
    type = row["type"] || "number"
    unit = String.trim(row["unit"] || "")
    options = row["options"] || []
    {key, type, unit, options}
  end

  defp classify_select_row(key, options) do
    cleaned = clean_options(options)

    if cleaned == [] do
      {:error, "Give \"#{key}\" at least one choice option."}
    else
      {:ok, key, %{"type" => "select", "options" => cleaned}}
    end
  end

  defp clean_options(opts) when is_list(opts) do
    opts |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp clean_options(opts) when is_binary(opts) do
    opts |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp clean_options(_), do: []

  defp field_definitions_to_rows(field_definitions) when map_size(field_definitions) == 0 do
    [%{"idx" => 0, "key" => "", "type" => "number", "unit" => "", "options" => ["Option 1"]}]
  end

  defp field_definitions_to_rows(field_definitions) do
    field_definitions
    |> Enum.with_index()
    |> Enum.map(fn {{key, def_}, idx} ->
      raw_opts = Map.get(def_, "options", [])

      opts_list =
        cond do
          is_list(raw_opts) and raw_opts != [] ->
            raw_opts

          is_binary(raw_opts) and raw_opts != "" ->
            raw_opts |> String.split(",") |> Enum.map(&String.trim/1)

          true ->
            ["Option 1"]
        end

      %{
        "idx" => idx,
        "key" => key,
        "type" => Map.get(def_, "type", "text"),
        "unit" => Map.get(def_, "unit", ""),
        "options" => opts_list
      }
    end)
  end

  defp pagination_path(search, filters) do
    search = String.trim(search || "")
    category = Map.get(filters, :category, "")
    status = Map.get(filters, :status, "")

    params =
      %{}
      |> then(fn m -> if search != "", do: Map.put(m, "search", search), else: m end)
      |> then(fn m -> if category != "", do: Map.put(m, "category", category), else: m end)
      |> then(fn m -> if status != "", do: Map.put(m, "status", status), else: m end)

    if map_size(params) > 0 do
      ~p"/lab/tests?#{params}"
    else
      ~p"/lab/tests"
    end
  end

  defp reload_lab_tests(socket) do
    org_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page
    search = socket.assigns.search
    filters = socket.assigns.filters

    page_result =
      LabTests.list_lab_tests_paginated(org_id, page,
        search: search,
        category: filters.category,
        status: filters.status
      )

    socket
    |> stream(:lab_tests, page_result.entries, reset: true)
    |> assign(:page_info, page_result)
  end

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
        class="max-w-3xl"
        on_cancel={JS.patch(~p"/lab/tests")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          {if @live_action == :new, do: "New test template", else: "Edit test template"}
        </h2>

        <form id="lab-test-preset-form" phx-change="select_preset" class="mb-5">
          <.input
            type="select"
            name="preset"
            value={@selected_preset}
            label="Preset template (optional)"
            options={FieldDefinitionPresets.options()}
            prompt="No preset — enter everything manually"
          />
        </form>

        <.form
          for={@form}
          id="lab-test-form"
          phx-submit="save"
          phx-change="validate"
          class="space-y-5"
        >
          <%!-- Step 1: Test Details --%>
          <.form_block title="1. Test details">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <.input
                field={@form[:price]}
                type="number"
                label="Price (KES)"
                step="0.01"
                min="0"
                required
              />
              <div class="flex items-center pt-6">
                <.input field={@form[:is_active]} type="checkbox" label="Active catalog entry" />
              </div>
            </div>
          </.form_block>

          <%!-- Step 2: Result Fields & Options --%>
          <.form_block title="2. Result fields & options">
            <:actions>
              <.button
                id="add-field-row-btn"
                type="button"
                phx-click="add_field_row"
                variant="ghost"
                class="text-xs py-1 px-2.5 h-auto min-h-0"
              >
                + Add Field
              </.button>
            </:actions>

            <p class="text-xs text-thamani-pewter mb-3">
              Configure each result field. Multiple choice fields let you define specific options below.
            </p>

            <div class="space-y-4">
              <%= for row <- @field_defs_rows do %>
                <% opts = if is_list(row["options"]), do: row["options"], else: ["Option 1"] %>
                <% opts = if opts == [], do: ["Option 1"], else: opts %>
                <div class="rounded-xl border border-thamani-stone bg-thamani-canvas p-4 space-y-3">
                  <div class="grid grid-cols-1 md:grid-cols-12 gap-3 items-start">
                    <div class={
                      if row["type"] == "select", do: "md:col-span-6", else: "md:col-span-5"
                    }>
                      <.input
                        type="text"
                        name={"field_defs[#{row["idx"]}][key]"}
                        value={row["key"]}
                        label="Field name"
                        placeholder="e.g. Haemoglobin, Result, Species"
                        required
                      />
                    </div>
                    <div class={
                      if row["type"] == "select", do: "md:col-span-5", else: "md:col-span-4"
                    }>
                      <.input
                        type="select"
                        name={"field_defs[#{row["idx"]}][type]"}
                        value={row["type"]}
                        label="Result type"
                        options={[
                          {"Number", "number"},
                          {"Text", "text"},
                          {"Multiple choice", "select"}
                        ]}
                      />
                    </div>
                    <div :if={row["type"] != "select"} class="md:col-span-2">
                      <.input
                        type="text"
                        name={"field_defs[#{row["idx"]}][unit]"}
                        value={row["unit"]}
                        label="Unit"
                        placeholder="e.g. g/dL"
                      />
                    </div>
                    <div class="md:col-span-1 flex justify-end pt-7">
                      <button
                        :if={length(@field_defs_rows) > 1}
                        type="button"
                        phx-click="remove_field_row"
                        phx-value-idx={row["idx"]}
                        class="flex size-7 items-center justify-center rounded-md text-thamani-error hover:bg-thamani-error/10 transition-colors"
                        aria-label="Remove field"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  <%!-- Choice options for Multiple choice (select) & Checkbox types --%>
                  <%= if row["type"] in ["select", "checkbox"] do %>
                    <div class="border-t border-thamani-stone/60 pt-3 mt-2">
                      <div class="flex items-center justify-between mb-2">
                        <span class="thamani-label" style="margin-bottom: 0;">
                          {if row["type"] == "checkbox",
                            do: "Checkbox options",
                            else: "Choice options"}
                        </span>
                        <.button
                          type="button"
                          phx-click="add_field_option"
                          phx-value-field_idx={row["idx"]}
                          variant="ghost"
                          class="text-xs py-1 px-2.5 h-auto min-h-0 text-thamani-accent font-medium hover:bg-thamani-accent/10"
                        >
                          + Add option
                        </.button>
                      </div>

                      <div class="space-y-2">
                        <%= for {opt_val, opt_idx} <- Enum.with_index(opts) do %>
                          <div class="flex items-center gap-2">
                            <div class="flex items-center gap-1 min-w-6 justify-end text-thamani-pewter">
                              <.icon
                                name={
                                  if row["type"] == "checkbox",
                                    do: "hero-check-square",
                                    else: "hero-check-circle"
                                }
                                class="w-3.5 h-3.5 opacity-60 text-thamani-accent"
                              />
                              <span class="text-xs font-mono">{opt_idx + 1}.</span>
                            </div>
                            <.input
                              type="text"
                              name={"field_defs[#{row["idx"]}][options][#{opt_idx}]"}
                              value={opt_val}
                              placeholder={"Option #{opt_idx + 1}"}
                              class="flex-1 py-1.5 px-3 text-xs h-9"
                            />
                            <button
                              :if={length(opts) > 1}
                              type="button"
                              phx-click="remove_field_option"
                              phx-value-field_idx={row["idx"]}
                              phx-value-opt_idx={opt_idx}
                              class="flex size-7 items-center justify-center rounded-md text-thamani-error hover:bg-thamani-error/10 transition-colors"
                              aria-label="Remove option"
                            >
                              <.icon name="hero-trash" class="w-4 h-4" />
                            </button>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>

            <p :if={@field_defs_error} class="mt-2 text-sm text-thamani-error font-medium">
              {@field_defs_error}
            </p>
            <p
              :if={!@field_defs_error && @form[:field_definitions].errors != []}
              class="mt-2 text-sm text-thamani-error font-medium"
            >
              Add at least one field definition.
            </p>
          </.form_block>

          <.button type="submit" variant="primary" class="w-full">
            Save Test
          </.button>
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
            class="px-3 py-1.5 text-xs"
            id={"btn-edit-test-#{test.id}"}
          >
            Edit
          </.button>
        </:action>
        <:action :let={{_id, test}}>
          <.button
            type="button"
            phx-click="toggle_active"
            phx-value-id={test.id}
            class="px-3 py-1.5 text-xs"
            variant={if test.is_active, do: "destructive", else: "ghost"}
            id={"btn-toggle-test-#{test.id}"}
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

      <.pagination page={@page_info} path={pagination_path(@search, @filters)} />
    </Layouts.lab_shell>
    """
  end
end
