defmodule ThamaniDawaWeb.DistributorCustomerLive.Index do
  @moduledoc """
  Manages the distributor's customers: add/edit, look up a GLN to prefill
  name/address, and store contact details.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Customers
  alias ThamaniDawa.Customers.Customer
  alias ThamaniDawa.Distributor
  alias ThamaniDawaWeb.TimeFormat

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Customers")
     |> assign(:gln_check, :idle)
     |> assign(:search, "")
     |> assign(:selected, nil)
     |> assign(:recent_orders, [])
     |> load_customers()}
  end

  def handle_params(params, _url, socket) do
    {:noreply,
     socket
     |> assign(:search, params["search"] || "")
     |> load_customers()
     |> select_customer(params["customer"])
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp select_customer(socket, id) when is_binary(id) and id != "" do
    org_id = socket.assigns.current_scope.organization_id

    case Enum.find(socket.assigns.all_customers, &(Integer.to_string(&1.id) == id)) do
      nil ->
        socket |> assign(:selected, nil) |> assign(:recent_orders, [])

      customer ->
        orders = if customer.gln, do: Distributor.list_shipments_to(org_id, customer.gln, 5), else: []
        socket |> assign(:selected, customer) |> assign(:recent_orders, orders)
    end
  end

  defp select_customer(socket, _id), do: socket |> assign(:selected, nil) |> assign(:recent_orders, [])

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

  def handle_event("search", %{"search" => search}, socket) do
    query = if String.trim(search) == "", do: %{}, else: %{"search" => search}
    {:noreply, push_patch(socket, to: ~p"/distributor/customers?#{query}")}
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

  def handle_info({:gln_selected, "customer-gln", nil}, socket),
    do: {:noreply, assign(socket, :gln_check, :idle)}

  def handle_info({:gln_selected, "customer-gln", party}, socket) do
    changeset =
      Customers.change_customer(socket.assigns.customer, %{
        "gln" => party.gln,
        "name" => party.company,
        "address" => party.address
      })

    {:noreply,
     socket
     |> assign(:gln_check, {:matched, party.company, party.address})
     |> assign(:form, to_form(changeset, as: :customer))}
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
    all = Customers.list_customers(organization_id)
    query = (socket.assigns[:search] || "") |> String.trim() |> String.downcase()

    shown =
      if query == "",
        do: all,
        else:
          Enum.filter(all, fn c ->
            Enum.any?([c.name, c.gln, c.address], &(is_binary(&1) and String.contains?(String.downcase(&1), query)))
          end)

    socket
    |> assign(:all_customers, all)
    |> assign(:shown_count, length(shown))
    |> assign(:summaries, Distributor.destination_summaries(organization_id, Enum.map(all, & &1.gln)))
    |> stream(:customers, shown, reset: true)
  end

  defp panel_path(customer, search) do
    query = %{"customer" => customer.id}
    query = if search in [nil, ""], do: query, else: Map.put(query, "search", search)
    ~p"/distributor/customers?#{query}"
  end

  defp summary_for(summaries, %{gln: gln}) when is_binary(gln),
    do: Map.get(summaries, gln, %{open_orders: 0, order_count: 0, last_order_at: nil, last_shipment: nil})

  defp summary_for(_summaries, _customer), do: %{open_orders: 0, order_count: 0, last_order_at: nil, last_shipment: nil}

  defp type_label(nil), do: nil
  defp type_label(type), do: Phoenix.Naming.humanize(type)

  defp order_tone("submitted"), do: "warning"
  defp order_tone("approved"), do: "success"
  defp order_tone("rejected"), do: "danger"
  defp order_tone(_), do: "neutral"

  defp order_path(shipment, customer),
    do: ThamaniDawaWeb.ReturnTo.with_query(~p"/distributor/shipments/#{shipment.id}", "/distributor/customers?customer=#{customer.id}")

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/customers"}
    >
      <div class="td-recipe td-list-page">
        <.td_page_header
          title="Customers"
          subtitle="Pharmacies, hospitals and labs you ship to. A verified GLN lets you pick them quickly on new orders."
        >
          <:actions>
            <.td_button id="add-customer" variant="primary" glyph="plus" patch={~p"/distributor/customers/new"} label="Add customer" />
          </:actions>
        </.td_page_header>
      </div>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-customer-modal"
        show
        on_cancel={JS.patch(~p"/distributor/customers")}
        title={if @live_action == :new, do: "Add customer", else: "Edit customer"}
        subtitle={if @live_action == :new, do: "Look up the GLN in GS1. Verified customers are quicker to pick on orders.", else: nil}
      >
        <.form for={@form} id="distributor-customer-form" phx-change="validate" phx-submit="save">
          <div :if={@live_action == :new and @gln_check != :skipped} class="mb-6">
            <.live_component
              module={ThamaniDawaWeb.GlnField}
              id="customer-gln"
              name="customer[gln]"
              label="GLN"
              placeholder="Search GS1 by name or GLN"
              hint="Name and address are filled from GS1."
              organization_id={@current_scope.organization_id}
              api_token={ThamaniDawa.Organizations.gs1_api_key(@current_scope.organization_id)}
              scope={:gs1}
            />
            <button
              :if={!show_customer_fields?(@live_action, @gln_check)}
              type="button"
              id="customer-no-gln"
              phx-click="skip_gln"
              class="td-link td-s12 mt-2"
            >
              This customer has no GLN yet
            </button>
          </div>
          <div :if={@live_action == :edit or @gln_check == :skipped} class="mb-6">
            <.input
              :if={@live_action == :edit}
              field={@form[:gln]}
              label="GLN"
              placeholder="13-digit GLN"
              phx-debounce="500"
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


          </div>
        </.form>
        <:footer>
          <.td_button type="button" variant="secondary" label="Cancel" phx-click={JS.patch(~p"/distributor/customers")} />
          <.td_button
            id="save-customer"
            type="submit"
            form="distributor-customer-form"
            variant="primary"
            disabled={!show_customer_fields?(@live_action, @gln_check)}
            label={if @live_action == :new, do: "Add customer", else: "Save changes"}
          />
        </:footer>
      </.modal>

      <div class={["td-list-page", @selected && "td-detail-row"]} id="customers-page">
        <div class="min-w-0">
          <div class="td-toolbar">
            <form id="customer-search" phx-change="search" phx-submit="search" onsubmit="return false">
              <label class="td-search">
                <.td_icon name="magnifying-glass" />
                <input
                  type="search"
                  name="search"
                  value={@search}
                  placeholder="Search customer name or GLN"
                  phx-debounce="250"
                  autocomplete="off"
                />
                <kbd>/</kbd>
              </label>
            </form>
            <span class="flex-1"></span>
          </div>

          <div :if={@shown_count == 0} id="customers-empty" class="td-pad td-empty-wrap">
            <div class="td-card td-empty-card">
              <%= if @all_customers == [] do %>
                <p class="td-empty-title">No customers yet</p>
                <p class="td-note">Add the pharmacies, hospitals and labs you ship to, so you can pick them quickly on new orders.</p>
                <.td_button id="customers-empty-add" variant="primary" patch={~p"/distributor/customers/new"} label="Add customer" />
              <% else %>
                <p class="td-empty-title">Nothing matches</p>
                <p class="td-note">Try a different name or GLN.</p>
                <.td_button id="customers-clear-search" patch={~p"/distributor/customers"} label="Clear search" />
              <% end %>
            </div>
          </div>

          <div class="td-list-table" hidden={@shown_count == 0}>
            <table class="td-rows">
              <thead>
                <tr>
                  <th>Customer</th>
                  <th>GLN</th>
                  <th :if={!@selected}>Location</th>
                  <th class="is-num">Orders</th>
                  <th>Last order</th>
                </tr>
              </thead>
              <tbody id="distributor-customers" phx-update="stream">
                <tr
                  :for={{dom_id, customer} <- @streams.customers}
                  id={dom_id}
                  class={["is-link", @selected && @selected.id == customer.id && "is-selected"]}
                  phx-click={JS.patch(panel_path(customer, @search))}
                >
                  <td>
                    <b>{customer.name}</b>
                    <span :if={customer.customer_type} class="td-sub td-s12">{type_label(customer.customer_type)}</span>
                  </td>
                  <td>
                    <.td_pid :if={customer.gln} id={"#{dom_id}-gln"} label={customer.gln} mono>
                      <:peek>
                        <.td_peek kind="GLN" title={customer.gln} subtitle={customer.name} mono>
                          <:row label="Address">{customer.address || "—"}</:row>
                          <:row label="Party type">{type_label(customer.customer_type) || "—"}</:row>
                          <:row label="Saved as">Customer</:row>
                          <:row label="Used on">{summary_for(@summaries, customer).order_count} orders</:row>
                          <:row label="Open orders">{summary_for(@summaries, customer).open_orders}</:row>
                          <:action>
                            <.td_button patch={panel_path(customer, @search)} label="Open customer" />
                          </:action>
                        </.td_peek>
                      </:peek>
                    </.td_pid>
                    <span :if={!customer.gln} class="td-sub">No GLN</span>
                  </td>
                  <td :if={!@selected}>{customer.address || "—"}</td>
                  <td class="is-num">{summary_for(@summaries, customer).order_count}</td>
                  <td>{TimeFormat.date(summary_for(@summaries, customer).last_order_at)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <aside :if={@selected} class="td-card" id="customer-panel">
          <div class="td-pad">
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <h2 class="td-idh-title"><span>{@selected.name}</span></h2>
                <p :if={@selected.customer_type} class="td-idh-sub">{type_label(@selected.customer_type)}</p>
              </div>
              <.link patch={~p"/distributor/customers?#{if @search == "", do: %{}, else: %{"search" => @search}}"} class="td-icon-btn" aria-label="Close" id="customer-panel-close">
                <.td_icon name="x" class="size-4" />
              </.link>
            </div>
            <dl class="td-kv-list mt-3" id="customer-panel-details">
              <div><dt>GLN</dt><dd class="td-mono">{@selected.gln || "—"}</dd></div>
              <div><dt>Address</dt><dd>{@selected.address || "—"}</dd></div>
              <div><dt>Contact</dt><dd>{@selected.contact_name || "—"}</dd></div>
              <div><dt>Phone</dt><dd>{@selected.contact_phone || "—"}</dd></div>
            </dl>
            <dl class="td-kv-grid is-2 mt-4" id="customer-stats">
              <div class="td-kv">
                <dt class="td-kv-label">Open orders</dt>
                <dd class="td-kv-value">{summary_for(@summaries, @selected).open_orders}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">All orders</dt>
                <dd class="td-kv-value">{summary_for(@summaries, @selected).order_count}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Last order (EAT)</dt>
                <dd class="td-kv-value">{TimeFormat.datetime(summary_for(@summaries, @selected).last_order_at)}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Last shipment</dt>
                <dd class="td-kv-value">
                  {(summary_for(@summaries, @selected).last_shipment || %{reference: "—"}).reference}
                </dd>
              </div>
            </dl>
            <div class="mt-4 flex gap-2">
              <.td_button id="customer-panel-edit" glyph="pencil-simple" patch={~p"/distributor/customers/#{@selected.id}/edit"} label="Edit" />
              <.td_button id="customer-panel-new-order" variant="primary" navigate={~p"/distributor/orders/new"} label="New order" />
            </div>
          </div>
          <.td_card_header
            title="Recent orders"
            subtitle={
              case summary_for(@summaries, @selected).order_count do
                0 -> "No orders yet"
                n -> "#{n} #{if n == 1, do: "order", else: "orders"}"
              end
            }
          />
          <div id="customer-recent-orders">
            <.link
              :for={order <- @recent_orders}
              navigate={order_path(order, @selected)}
              class="td-li flex items-center justify-between gap-3 px-4 py-2.5"
              id={"customer-order-#{order.id}"}
            >
              <span class="min-w-0">
                <b>{order.order_number || order.reference}</b>
                <span class="td-sub td-s12">{TimeFormat.datetime(order.updated_at)}</span>
              </span>
              <.td_badge tone={order_tone(order.status)} label={Phoenix.Naming.humanize(order.status)} />
            </.link>
          </div>
        </aside>
      </div>
    </Layouts.distributor_shell>
    """
  end
end
