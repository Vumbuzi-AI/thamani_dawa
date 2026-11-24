defmodule ThamaniDawaWeb.SupplierLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Suppliers
  alias ThamaniDawa.Suppliers.Supplier

  @default_filters %{status: ""}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search, "")
     |> assign(:filters, @default_filters)
     |> assign(:page, 1)
     |> assign(:page_info, %{page_number: 1, total_pages: 1, total_entries: 0})
     |> assign(:show_onboarding_supplier_form?, false)}
  end

  def handle_params(params, _url, socket) do
    page = String.to_integer(Map.get(params, "page", "1"))
    socket = socket |> assign(:page, page) |> reload_suppliers()
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)

    assign(socket,
      form: to_form(Suppliers.change_supplier(%Supplier{}, %{}), as: :supplier),
      supplier: nil,
      back_path: back_path(params),
      onboarding_suppliers: Suppliers.list_suppliers(organization_id),
      onboarding_progress: Organizations.onboarding_progress(organization)
    )
  end

  defp apply_action(socket, :edit, %{"id" => id} = params) do
    organization_id = socket.assigns.current_scope.organization_id
    supplier = Suppliers.get_supplier!(organization_id, id)

    assign(socket,
      form: to_form(Suppliers.change_supplier(supplier, %{}), as: :supplier),
      supplier: supplier,
      back_path: back_path(params)
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, form: nil, supplier: nil, back_path: ~p"/org/suppliers")
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> reload_suppliers()}
  end

  def handle_event("set_filter", %{"field" => "status", "value" => value}, socket) do
    {:noreply, socket |> assign(:filters, %{status: value}) |> reload_suppliers()}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, socket |> assign(:filters, @default_filters) |> reload_suppliers()}
  end

  def handle_event("validate", %{"supplier" => attrs}, socket) do
    changeset =
      socket.assigns.supplier
      |> Kernel.||(%Supplier{})
      |> Suppliers.change_supplier(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: :supplier))}
  end

  def handle_event("save", %{"supplier" => attrs}, socket) do
    save_supplier(socket, socket.assigns.live_action, attrs)
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    org_id = socket.assigns.current_scope.organization_id
    supplier = Suppliers.get_supplier!(org_id, id)

    case Suppliers.update_supplier(supplier, %{is_active: !supplier.is_active}) do
      {:ok, _updated} ->
        {:noreply, reload_suppliers(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update supplier.")}
    end
  end

  def handle_event("open_onboarding_supplier", _params, socket) do
    {:noreply, assign(socket, :show_onboarding_supplier_form?, true)}
  end

  def handle_event("close_onboarding_supplier", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_onboarding_supplier_form?, false)
     |> assign(:form, to_form(Suppliers.change_supplier(%Supplier{}, %{}), as: :supplier))}
  end

  def handle_event("continue_onboarding", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/onboarding")}
  end

  defp save_supplier(socket, :new, attrs) do
    organization_id = socket.assigns.current_scope.organization_id

    case Suppliers.create_supplier(organization_id, attrs) do
      {:ok, supplier} ->
        socket =
          socket
          |> put_flash(:info, "Supplier created.")
          |> stream_insert(:suppliers, supplier)

        if socket.assigns.back_path == ~p"/onboarding" do
          {:noreply,
           socket
           |> assign(:onboarding_suppliers, socket.assigns.onboarding_suppliers ++ [supplier])
           |> assign(:show_onboarding_supplier_form?, false)
           |> assign(:form, to_form(Suppliers.change_supplier(%Supplier{}, %{}), as: :supplier))}
        else
          {:noreply, push_patch(socket, to: ~p"/org/suppliers")}
        end

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp save_supplier(socket, :edit, attrs) do
    case Suppliers.update_supplier(socket.assigns.supplier, attrs) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> put_flash(:info, "Supplier updated.")
         |> stream_insert(:suppliers, supplier)
         |> push_patch(to: ~p"/org/suppliers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :supplier))}
    end
  end

  defp back_path(%{"return_to" => "onboarding"}), do: ~p"/onboarding"
  defp back_path(_params), do: ~p"/org/suppliers"

  defp reload_suppliers(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    page = socket.assigns.page

    page_result = Suppliers.list_suppliers_paginated(organization_id, page)
    suppliers = page_result.entries

    filtered =
      suppliers
      |> filter_by_search(socket.assigns.search)
      |> filter_by_status(socket.assigns.filters.status)

    socket
    |> stream(:suppliers, filtered, reset: true)
    |> assign(:page_info, page_result)
  end

  defp filter_by_search(suppliers, ""), do: suppliers

  defp filter_by_search(suppliers, search) do
    search = String.downcase(String.trim(search))

    Enum.filter(suppliers, fn supplier ->
      [supplier.name, supplier.contact, supplier.email, supplier.gln]
      |> Enum.filter(& &1)
      |> Enum.any?(&String.contains?(String.downcase(&1), search))
    end)
  end

  defp filter_by_status(suppliers, ""), do: suppliers
  defp filter_by_status(suppliers, "active"), do: Enum.filter(suppliers, & &1.is_active)
  defp filter_by_status(suppliers, "inactive"), do: Enum.filter(suppliers, &(!&1.is_active))

  defp active_filter_count(filters) do
    Enum.count([filters.status != ""], & &1)
  end

  attr :form, :map, required: true

  defp supplier_form(assigns) do
    ~H"""
    <.form for={@form} id="supplier-form" phx-submit="save" phx-change="validate">
      <.input field={@form[:name]} label="Name" required />
      <div class="grid grid-cols-2 gap-x-4">
        <.input field={@form[:contact]} label="Contact person" />
        <.input field={@form[:phone]} label="Phone" required />
      </div>
      <.input field={@form[:email]} type="email" label="Email" required />
      <div class="flex items-center justify-between rounded-xl border border-thamani-stone bg-thamani-canvas px-4 py-3 mb-3">
        <div>
          <p class="text-sm font-medium text-thamani-forest">Active</p>
          <p class="text-xs text-thamani-pewter">Enable this supplier for orders</p>
        </div>
        <.input
          field={@form[:is_active]}
          type="checkbox"
          label=""
          class="size-5 rounded accent-thamani-forest cursor-pointer"
        />
      </div>
      <.input id="supplier-location" field={@form[:location]} label="Location" />
      <div class="grid grid-cols-2 gap-x-4">
        <.input id="supplier-lat" field={@form[:lat]} label="Latitude" type="number" step="any" />
        <.input id="supplier-long" field={@form[:long]} label="Longitude" type="number" step="any" />
      </div>
      <div
        id="supplier-map"
        phx-hook="GoogleMaps"
        phx-update="ignore"
        data-lat-input="supplier-lat"
        data-lng-input="supplier-long"
        data-address-input="supplier-location"
        data-lat={@form[:lat].value}
        data-lng={@form[:long].value}
        class="w-full h-40 rounded-xl mt-1 overflow-hidden border border-thamani-stone bg-thamani-canvas"
      >
      </div>
      <div class="mt-3">
        <.button variant="primary" class="w-full">Save</.button>
      </div>
    </.form>
    """
  end

  def render(assigns) do
    if assigns.live_action == :new and assigns.back_path == ~p"/onboarding" do
      render_onboarding(assigns)
    else
      render_index(assigns)
    end
  end

  defp render_onboarding(assigns) do
    ~H"""
    <.onboarding_task_shell
      flash={@flash}
      current_scope={@current_scope}
      icon="hero-truck"
      title="Add a supplier"
      description="Record who you receive stock from so receiving can reference them."
      progress_current={elem(@onboarding_progress, 0)}
      progress_total={elem(@onboarding_progress, 1)}
    >
      <:right>
        <div class="flex items-start justify-between gap-5">
          <div>
            <h2 class="text-2xl font-medium tracking-tight text-thamani-forest">Suppliers</h2>
            <p class="mt-2 text-sm leading-6 text-thamani-pewter">
              Suppliers recorded for this organization so far.
            </p>
          </div>
          <button
            id="onboarding-open-supplier"
            type="button"
            phx-click="open_onboarding_supplier"
            class="inline-flex min-h-11 shrink-0 items-center justify-center rounded-full bg-thamani-forest px-5 py-2.5 text-sm font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-md"
          >
            <.icon name="hero-plus" class="mr-2 size-4" /> Add a supplier
          </button>
        </div>

        <div
          :if={@onboarding_suppliers == []}
          id="onboarding-suppliers-empty"
          class="mt-8 flex min-h-52 flex-col items-center justify-center rounded-2xl border border-dashed border-[var(--thamani-stone)] bg-transparent px-6 text-center"
        >
          <span class="flex size-12 items-center justify-center rounded-2xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
            <.icon name="hero-truck" class="size-6" />
          </span>
          <h3 class="mt-4 text-base font-semibold text-thamani-forest">No suppliers yet</h3>
          <p class="mt-1 max-w-xs text-sm leading-6 text-thamani-pewter">
            Record the first supplier you receive stock from.
          </p>
        </div>

        <div :if={@onboarding_suppliers != []} id="onboarding-suppliers-list" class="mt-8">
          <h3 class="mb-3 text-sm font-semibold text-thamani-forest">
            Suppliers ({length(@onboarding_suppliers)})
          </h3>

          <div class="overflow-hidden rounded-2xl border border-[var(--thamani-stone)]">
            <div class="grid grid-cols-[1fr_auto_auto] gap-4 bg-[color-mix(in_srgb,var(--thamani-stone)_35%,white)] px-4 py-2.5 text-xs font-medium text-thamani-pewter">
              <span>Name</span>
              <span class="w-40">Contact</span>
              <span class="w-20 text-right">Status</span>
            </div>

            <div class="divide-y divide-[var(--thamani-stone)]">
              <div
                :for={supplier <- @onboarding_suppliers}
                id={"onboarding-supplier-#{supplier.id}"}
                class="grid grid-cols-[1fr_auto_auto] items-center gap-4 px-4 py-3"
              >
                <span class="min-w-0 truncate text-sm text-thamani-forest">{supplier.name}</span>
                <span class="w-40 truncate text-sm text-thamani-pewter">{supplier.contact}</span>
                <span class="flex w-20 justify-end">
                  <.status_badge status={if supplier.is_active, do: :active, else: :inactive} />
                </span>
              </div>
            </div>
          </div>
        </div>
      </:right>

      <:footer>
        <div class="flex items-center gap-4">
          <.link
            id="onboarding-supplier-back"
            navigate={~p"/onboarding"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
          >
            <.icon name="hero-arrow-left" class="mr-2 size-4" /> Back
          </.link>
          <.link
            id="onboarding-supplier-skip"
            navigate={~p"/onboarding?skip=first_supplier"}
            class="inline-flex min-h-11 items-center rounded-full px-2 text-sm font-medium text-[var(--thamani-pewter)] underline decoration-[color-mix(in_srgb,var(--thamani-pewter)_45%,transparent)] underline-offset-4 transition-colors hover:text-[var(--thamani-forest)]"
          >
            Skip this step
          </.link>
        </div>
        <button
          id="onboarding-supplier-continue"
          type="button"
          phx-click="continue_onboarding"
          class="inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg"
        >
          Continue <.icon name="hero-arrow-right" class="ml-3 size-4" />
        </button>
      </:footer>
    </.onboarding_task_shell>

    <.modal
      :if={@show_onboarding_supplier_form?}
      id="onboarding-supplier-modal"
      show
      on_cancel={JS.push("close_onboarding_supplier")}
    >
      <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">Add a supplier</h2>
      <.supplier_form form={@form} />
    </.modal>
    """
  end

  defp render_index(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path={~p"/org/suppliers"}>
      <:search>
        <form phx-change="search" id="search-form" onsubmit="return false">
          <.td_search
            name="search"
            value={@search}
            placeholder="Search by name, contact, email, or GLN"
            shortcut="⌘K"
            phx-debounce="200"
          />
        </form>
      </:search>
      <.td_list_page
        title="Suppliers"
        subtitle="Search, filter, and manage your organization's suppliers."
      >
        <:actions>
          <.td_button
            id="supplier-new-button"
            variant="primary"
            label="Add supplier"
            glyph="plus"
            patch={~p"/org/suppliers/new"}
          />
        </:actions>
        <:filters>
          <.td_filter_menu
            id="suppliers"
            field="status"
            label="Status"
            value={@filters.status}
            options={[{"", "Any"}, {"active", "Active"}, {"inactive", "Inactive"}]}
          />
        </:filters>

        <.modal
          :if={@live_action in [:new, :edit]}
          id="supplier-modal"
          show
          on_cancel={
            if @back_path == ~p"/onboarding",
              do: JS.navigate(@back_path),
              else: JS.patch(~p"/org/suppliers")
          }
        >
          <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
            {if @live_action == :new, do: "Add a supplier", else: "Edit supplier"}
          </h2>
          <.supplier_form form={@form} />
        </.modal>

        <.table id="suppliers" rows={@streams.suppliers}>
          <:col :let={{_id, supplier}} label="Name">{supplier.name}</:col>
          <:col :let={{_id, supplier}} label="Contact">
            <span class="block">
              <span class="block">{supplier.contact}</span>
              <span class="mt-0.5 block text-xs font-normal text-thamani-pewter sm:hidden">
                {supplier.phone}
              </span>
            </span>
          </:col>
          <:col :let={{_id, supplier}} label="Phone" mobile="hidden">{supplier.phone}</:col>
          <:col :let={{_id, supplier}} label="Email" mobile="hidden">{supplier.email}</:col>
          <:col :let={{_id, supplier}} label="GLN" mobile="hidden">{supplier.gln}</:col>
          <:col :let={{_id, supplier}} label="Status" mobile="aside">
            <.status_badge status={if supplier.is_active, do: :active, else: :inactive} />
          </:col>
          <:action :let={{_id, supplier}}>
            <.button
              variant="ghost-edit"
              patch={~p"/org/suppliers/#{supplier.id}/edit"}
              class="px-3 py-1.5 text-xs"
              id={"btn-edit-supplier-#{supplier.id}"}
            >
              Edit
            </.button>
          </:action>
          <:action :let={{_id, supplier}}>
            <.button
              type="button"
              phx-click="toggle_active"
              phx-value-id={supplier.id}
              class="px-3 py-1.5 text-xs"
              variant={if supplier.is_active, do: "destructive", else: "ghost"}
              id={"btn-toggle-supplier-#{supplier.id}"}
            >
              {if supplier.is_active, do: "Deactivate", else: "Reactivate"}
            </.button>
          </:action>
          <:empty_state>
            <.blank_state
              icon="hero-truck"
              title={
                if @search != "" or active_filter_count(@filters) > 0,
                  do: "No suppliers match your search or filters",
                  else: "No suppliers yet"
              }
            >
              {if @search != "" or active_filter_count(@filters) > 0,
                do: "Try a different search term, or clear the applied filters.",
                else: "Suppliers you add will appear here."}
            </.blank_state>
          </:empty_state>
        </.table>

        <.pagination page={@page_info} path={~p"/org/suppliers"} />
      </.td_list_page>
    </Layouts.org_shell>
    """
  end
end
