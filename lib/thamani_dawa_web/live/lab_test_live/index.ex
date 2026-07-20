defmodule ThamaniDawaWeb.LabTestLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.LabTests
  alias ThamaniDawa.LabTests.LabTest

  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization_id

    {:ok,
     socket
     |> assign(:lab_test, nil)
     |> assign(:form, nil)
     |> assign(:field_defs_json, "{}")
     |> assign(:field_defs_error, nil)
     |> stream(:lab_tests, LabTests.list_lab_tests(org_id))}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_json, "{}")
    |> assign(:field_defs_error, nil)
    |> assign(:form, to_form(LabTests.change_lab_test(%LabTest{}, %{}), as: :lab_test))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    org_id = socket.assigns.current_scope.organization_id
    lab_test = LabTests.get_lab_test!(org_id, id)

    socket
    |> assign(:lab_test, lab_test)
    |> assign(:field_defs_json, Jason.encode!(lab_test.field_definitions || %{}, pretty: true))
    |> assign(:field_defs_error, nil)
    |> assign(:form, to_form(LabTests.change_lab_test(lab_test, %{}), as: :lab_test))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:lab_test, nil)
    |> assign(:field_defs_json, "{}")
    |> assign(:field_defs_error, nil)
    |> assign(:form, nil)
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

  def handle_event("save", %{"lab_test" => attrs, "field_defs_json" => json}, socket) do
    case decode_field_defs(attrs, json) do
      {merged_attrs, nil} -> save_lab_test(socket, socket.assigns.live_action, merged_attrs)
      {_attrs, error} -> {:noreply, assign(socket, :field_defs_error, error)}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    lab_test = LabTests.get_lab_test!(org_id, id)

    case LabTests.update_lab_test(org_id, lab_test, %{is_active: !lab_test.is_active}) do
      {:ok, updated} ->
        {:noreply, stream_insert(socket, :lab_tests, updated)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update test.")}
    end
  end

  defp save_lab_test(socket, :new, attrs) do
    org_id = socket.assigns.current_scope.organization_id

    case LabTests.create_lab_test(org_id, attrs) do
      {:ok, lab_test} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test created.")
         |> stream_insert(:lab_tests, lab_test)
         |> push_patch(to: ~p"/lab/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :lab_test))}
    end
  end

  defp save_lab_test(socket, :edit, attrs) do
    org_id = socket.assigns.current_scope.organization_id

    case LabTests.update_lab_test(org_id, socket.assigns.lab_test, attrs) do
      {:ok, lab_test} ->
        {:noreply,
         socket
         |> put_flash(:info, "Test updated.")
         |> stream_insert(:lab_tests, lab_test)
         |> push_patch(to: ~p"/lab/tests")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :lab_test))}
    end
  end

  defp decode_field_defs(attrs, json) do
    case Jason.decode(json) do
      {:ok, decoded} -> {Map.put(attrs, "field_definitions", decoded), nil}
      {:error, _} -> {attrs, "must be valid JSON (e.g. {\"result\": {\"type\": \"number\"}})"}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path={~p"/lab/tests"}>
      <.header>
        Test catalog
        <:actions>
          <.button variant="primary" patch={~p"/lab/tests/new"}>+ New test</.button>
        </:actions>
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

        <.form for={@form} id="lab-test-form" phx-submit="save" phx-change="validate">
          <div class="grid grid-cols-2 gap-3 mb-3">
            <.input field={@form[:name]} label="Test name" required />
            <.input field={@form[:category]} label="Category" required />
          </div>

          <div class="grid grid-cols-2 gap-3 mb-3">
            <.input field={@form[:price]} type="number" label="Price" step="0.01" min="0" />
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
        <:col :let={{_id, test}} label="Category">{test.category}</:col>
        <:col :let={{_id, test}} label="Price">{test.price && "KES #{test.price}"}</:col>
        <:col :let={{_id, test}} label="Status">
          <span
            class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium"
            style={
              if test.is_active,
                do: "background: #D1FAE5; color: #065F46;",
                else: "background: #e5e7eb; color: #6b7280;"
            }
          >
            {if test.is_active, do: "Active", else: "Inactive"}
          </span>
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
      </.table>
    </Layouts.lab_shell>
    """
  end
end
