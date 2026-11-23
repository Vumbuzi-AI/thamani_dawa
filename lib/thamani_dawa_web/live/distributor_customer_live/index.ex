defmodule ThamaniDawaWeb.DistributorCustomerLive.Index do
  @moduledoc """
  Manages the distributor's customers: add/edit, look up a GLN to prefill
  name/address, and store contact details.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Customers
  alias ThamaniDawa.Customers.Customer

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Customers")
     |> assign(:gln_check, :idle)
     |> load_customers()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    customer = %Customer{}

    attrs =
      %{}
      |> maybe_put_param(params, "gln", :gln)
      |> maybe_put_param(params, "name", :name)
      |> maybe_put_param(params, "address", :address)

    gln_check =
      if Map.has_key?(attrs, "name") do
        {:matched, Map.get(attrs, "name"), Map.get(attrs, "address")}
      else
        :idle
      end

    socket
    |> assign(:customer, customer)
    |> assign(:gln_check, gln_check)
    |> assign(:form, to_form(Customers.change_customer(customer, attrs), as: :customer))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    customer = Customers.get_customer!(socket.assigns.current_scope.organization_id, id)

    socket
    |> assign(:customer, customer)
    |> assign(:gln_check, :idle)
    |> assign(:form, to_form(Customers.change_customer(customer), as: :customer))
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :customer, nil)

  defp maybe_put_param(attrs, params, key, field) do
    case Map.get(params, key) do
      value when is_binary(value) and byte_size(value) > 0 ->
        Map.put(attrs, Atom.to_string(field), value)

      _ ->
        attrs
    end
  end

  def handle_event("validate", %{"customer" => params} = form_params, socket) do
    changeset =
      socket.assigns.customer
      |> Customers.change_customer(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :customer))
     |> maybe_check_gln(form_params, params)}
  end

  def handle_event("skip_gln", _params, socket) do
    {:noreply, assign(socket, :gln_check, :skipped)}
  end

  def handle_event("save", %{"customer" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    result =
      case socket.assigns.live_action do
        :new -> Customers.create_customer(organization_id, params)
        :edit -> Customers.update_customer(socket.assigns.customer, params)
      end

    case result do
      {:ok, customer} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{customer.name} saved.")
         |> load_customers()
         |> push_patch(to: ~p"/distributor/customers")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
    end
  end

  defp maybe_check_gln(socket, params, customer_params) do
    if Map.get(params, "_target") == ["customer", "gln"] do
      check_gln(socket, customer_params)
    else
      socket
    end
  end

  defp check_gln(socket, customer_params) do
    gln = customer_params |> Map.get("gln", "") |> to_string() |> String.trim()

    if Regex.match?(~r/^\d{13}$/, gln) do
      socket
      |> assign(:gln_check, :checking)
      |> start_async(:gln_lookup, fn -> Customers.lookup_gln(gln) end)
    else
      assign(socket, :gln_check, :idle)
    end
  end

  def handle_async(:gln_lookup, {:ok, {:ok, resolved}}, socket) do
    changeset =
      Customers.change_customer(socket.assigns.customer, %{
        "gln" => socket.assigns.form[:gln].value,
        "name" => resolved.company,
        "address" => resolved.address
      })

    {:noreply,
     socket
     |> assign(:gln_check, {:matched, resolved.company, resolved.address})
     |> assign(:form, to_form(changeset, as: :customer))}
  end

  def handle_async(:gln_lookup, {:ok, {:error, :not_found}}, socket) do
    {:noreply, assign(socket, :gln_check, :not_found)}
  end

  def handle_async(:gln_lookup, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :gln_check, :unavailable)}
  end

  defp gln_resolved?({:matched, _company, _address}), do: true
  defp gln_resolved?(status) when status in [:not_found, :unavailable, :skipped], do: true
  defp gln_resolved?(_status), do: false

  defp show_customer_fields?(:edit, _gln_check), do: true
  defp show_customer_fields?(:new, gln_check), do: gln_resolved?(gln_check)

  defp show_organization_badge?(:new, {:matched, _company, _address}), do: true
  defp show_organization_badge?(_live_action, _gln_check), do: false

  defp customer_type_icon(:pharmacy), do: "hero-building-storefront"
  defp customer_type_icon(:wholesaler), do: "hero-truck"
  defp customer_type_icon(:hospital), do: "hero-building-office-2"
  defp customer_type_icon(:other), do: "hero-tag"

  defp customer_type_description(:pharmacy), do: "Retail or chain pharmacy"
  defp customer_type_description(:wholesaler), do: "Buys in bulk to resell to others"
  defp customer_type_description(:hospital), do: "Hospital, clinic, lab, or health center"
  defp customer_type_description(:other), do: "Another type of customer"

  defp load_customers(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    stream(socket, :customers, Customers.list_customers(organization_id), reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/customers"}
    >
      <.header icon="hero-user-group">
        Customers
        <:subtitle>
          Who you sell to — keep a record of customers so you don't have to re-enter GLN details each time.
        </:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/distributor/customers/new"}>
            <.icon name="hero-plus" class="size-4" /> Add customer
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-customer-modal"
        show
        on_cancel={JS.patch(~p"/distributor/customers")}
      >
        <h2 class="mb-4 text-2xl font-medium tracking-tight text-thamani-forest">
          {if @live_action == :new, do: "Add customer", else: "Edit customer"}
        </h2>
        <.form for={@form} id="distributor-customer-form" phx-change="validate" phx-submit="save">
          <div class="mb-6">
            <.input
              field={@form[:gln]}
              label="GLN"
              placeholder="13-digit GLN"
              phx-debounce="500"
              readonly={show_organization_badge?(@live_action, @gln_check)}
              class={
                show_organization_badge?(@live_action, @gln_check) &&
                  "bg-td-wash text-thamani-pewter"
              }
            />
            <%= case @gln_check do %>
              <% :checking -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-thamani-pewter">
                  <.icon name="hero-arrow-path" class="size-3.5 animate-spin" />
                  Looking up this GLN&hellip;
                </p>
              <% {:matched, company, address} -> %>
                <div class="mt-2 flex items-start gap-3 rounded-lg bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] px-3 py-2.5 text-xs font-semibold text-thamani-forest">
                  <.icon name="hero-check-circle" class="mt-0.5 size-4 flex-none" />
                  <div class="min-w-0">
                    <p>{company}</p>
                    <p
                      :if={address not in [nil, ""]}
                      class="mt-0.5 font-normal text-thamani-forest/80"
                    >
                      {address}
                    </p>
                  </div>
                </div>
              <% :not_found -> %>
                <p class="mt-2 inline-flex items-center gap-1.5 rounded-lg bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-800">
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                  We couldn't find this GLN. Enter the customer's details manually below.
                </p>
              <% :unavailable -> %>
                <p class="mt-2 text-xs leading-5 text-thamani-pewter">
                  We couldn't verify this GLN right now. Enter the customer's details manually below.
                </p>
              <% :skipped -> %>
                <p class="mt-2 text-xs leading-5 text-thamani-pewter">
                  Enter the customer's details manually below.
                </p>
              <% :idle -> %>
                <p class="mt-2 text-xs leading-5 text-thamani-pewter">
                  Enter the customer's GLN and we'll look up their name and address for you.
                </p>
            <% end %>
            <button
              :if={@live_action == :new and !show_customer_fields?(@live_action, @gln_check)}
              type="button"
              phx-click="skip_gln"
              class="mt-2 text-xs font-medium text-thamani-forest hover:underline"
            >
              I don't have a GLN — enter details manually
            </button>
          </div>

          <div :if={show_customer_fields?(@live_action, @gln_check)}>
            <fieldset class="mb-6">
              <legend class="mb-2 text-xs font-semibold text-thamani-forest">
                Customer type <span class="text-red-600">*</span>
              </legend>
              <div class="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
                <.activity_card
                  :for={type <- Customer.customer_types()}
                  type="radio"
                  name="customer[customer_type]"
                  value={to_string(type)}
                  label={Phoenix.Naming.humanize(type)}
                  description={customer_type_description(type)}
                  icon={customer_type_icon(type)}
                  selected={to_string(@form[:customer_type].value) == to_string(type)}
                  compact
                />
              </div>
              <p :for={error <- @form[:customer_type].errors} class="mt-2 text-xs text-red-700">
                {translate_error(error)}
              </p>
            </fieldset>

            <div
              :if={!show_organization_badge?(@live_action, @gln_check)}
              class="mb-6 space-y-4 rounded-xl border border-td-hairline bg-td-wash/50 p-3.5"
            >
              <p class="flex items-center gap-2 text-xs font-semibold text-thamani-forest">
                <.icon name="hero-building-office-2" class="size-4" /> Organization details
              </p>
              <.input field={@form[:name]} label="Name" required />
              <.input field={@form[:address]} label="Address" />
            </div>
            <.input
              :if={show_organization_badge?(@live_action, @gln_check)}
              field={@form[:name]}
              type="hidden"
            />
            <.input
              :if={show_organization_badge?(@live_action, @gln_check)}
              field={@form[:address]}
              type="hidden"
            />

            <div class="mb-2 space-y-4 rounded-xl border border-td-hairline bg-td-wash/50 p-3.5">
              <p class="flex items-center gap-2 text-xs font-semibold text-thamani-forest">
                <.icon name="hero-user" class="size-4" /> Contact details
              </p>
              <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <.input field={@form[:contact_name]} label="Contact person" />
                <.input field={@form[:contact_email]} label="Contact email" />
              </div>
              <.input field={@form[:contact_phone]} label="Contact phone" />
            </div>

            <div class="mt-6 flex items-center justify-end gap-3">
              <.button type="button" phx-click={JS.patch(~p"/distributor/customers")}>
                Cancel
              </.button>
              <.button variant="primary">Save customer</.button>
            </div>
          </div>
        </.form>
      </.modal>

      <.table id="distributor-customers" rows={@streams.customers}>
        <:col :let={{_id, customer}} label="Name">{customer.name}</:col>
        <:col :let={{_id, customer}} label="Type">
          {customer.customer_type && Phoenix.Naming.humanize(customer.customer_type)}
        </:col>
        <:col :let={{_id, customer}} label="GLN">{customer.gln || "—"}</:col>
        <:col :let={{_id, customer}} label="Contact">
          <span>{customer.contact_name || "—"}</span>
          <span :if={customer.contact_phone} class="mt-0.5 block text-xs text-thamani-pewter">
            {customer.contact_phone}
          </span>
        </:col>
        <:action :let={{_id, customer}}>
          <div class="flex flex-wrap justify-end gap-2">
            <.button variant="ghost-edit" patch={~p"/distributor/customers/#{customer.id}/edit"}>
              Edit
            </.button>
          </div>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-user-group" title="No customers yet">
            Add the businesses you sell to so you can start sales orders.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.distributor_shell>
    """
  end
end
