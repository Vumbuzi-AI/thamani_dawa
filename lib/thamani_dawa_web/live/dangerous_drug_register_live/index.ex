defmodule ThamaniDawaWeb.DangerousDrugRegisterLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.DangerousDrugRegisters
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.SiteScoping

  import ThamaniDawaWeb.MonthlyLogComponents

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    products =
      organization_id
      |> Products.list_products()
      |> Enum.filter(& &1.is_dangerous_drug)

    {:ok,
     socket
     |> assign(:products, products)
     |> assign(:sites, Sites.list_sites(organization_id))
     |> assign(:site_id, SiteScoping.default_site_id(scope))}
  end

  def handle_params(params, _url, socket) do
    today = Date.utc_today()
    month = param_to_integer(params["month"], today.month)
    year = param_to_integer(params["year"], today.year)
    product_id = param_to_integer(params["product_id"], nil)
    site_id = param_to_integer(params["site_id"], socket.assigns.site_id)

    register = product_id && find_register(socket, product_id, month, year)

    {:noreply,
     socket
     |> assign(:month, month)
     |> assign(:year, year)
     |> assign(:product_id, product_id)
     |> assign(:site_id, site_id)
     |> assign(:register, register)}
  end

  defp find_register(socket, product_id, month, year) do
    organization_id = socket.assigns.current_scope.organization_id

    organization_id
    |> DangerousDrugRegisters.list_dangerous_drug_registers()
    |> Enum.find(&(&1.product_id == product_id and &1.month == month and &1.year == year))
  end

  defp param_to_integer(nil, default), do: default
  defp param_to_integer("", default), do: default
  defp param_to_integer(value, _default), do: String.to_integer(value)

  def handle_event("filter_change", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/pharmacy/dangerous-drug-register?#{%{month: params["month"], year: params["year"], product_id: params["product_id"], site_id: params["site_id"]}}"
     )}
  end

  def handle_event("add_entry", %{"quantity" => quantity, "balance" => balance, "dispensed_to" => dispensed_to}, socket) do
    %{organization_id: organization_id, user: user} = socket.assigns.current_scope

    entry_attrs = %{
      "quantity" => quantity,
      "balance" => balance,
      "dispensed_to" => dispensed_to,
      "recorded_by_id" => user.id,
      "recorded_at" => DateTime.utc_now()
    }

    case DangerousDrugRegisters.record_entry(
           organization_id,
           socket.assigns.site_id,
           socket.assigns.product_id,
           socket.assigns.month,
           socket.assigns.year,
           entry_attrs
         ) do
      {:ok, register} ->
        {:noreply, assign(socket, :register, register)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't add that entry.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app_shell flash={@flash} current_scope={@current_scope}>
      <.header>Dangerous drug register</.header>

      <.month_year_picker month={@month} year={@year} on_change="filter_change">
        <div>
          <label class="label">Product</label>
          <select name="product_id" class="select">
            <option value="">Choose a product</option>
            <option :for={p <- @products} value={p.id} selected={p.id == @product_id}>
              {p.generic_name || p.name}
            </option>
          </select>
        </div>
        <div :if={is_nil(SiteScoping.default_site_id(@current_scope))}>
          <label class="label">Recording site</label>
          <select name="site_id" class="select">
            <option value="">Choose a site</option>
            <option :for={s <- @sites} value={s.id} selected={s.id == @site_id}>{s.name}</option>
          </select>
        </div>
      </.month_year_picker>

      <div :if={@product_id && @site_id} class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="font-semibold mb-2">Add entry</h2>
          <form phx-submit="add_entry" class="flex flex-wrap gap-2 items-end">
            <input type="number" name="quantity" placeholder="Quantity" class="input" required />
            <input type="number" name="balance" placeholder="Balance" class="input" required />
            <input type="text" name="dispensed_to" placeholder="Dispensed to" class="input" />
            <.button variant="primary">Add entry</.button>
          </form>
        </div>
      </div>

      <p :if={@product_id && is_nil(@site_id)} class="text-sm text-error">
        Choose a recording site before adding entries.
      </p>

      <.entries_table :if={@product_id} entries={(@register && @register.entries) || %{}} key_label="Entry #">
        <:col :let={entry} label="Quantity">{entry["quantity"]}</:col>
        <:col :let={entry} label="Balance">{entry["balance"]}</:col>
        <:col :let={entry} label="Dispensed to">{entry["dispensed_to"]}</:col>
        <:col :let={entry} label="Recorded at">{entry["recorded_at"]}</:col>
      </.entries_table>
    </Layouts.app_shell>
    """
  end
end
