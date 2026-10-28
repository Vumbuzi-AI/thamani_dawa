defmodule ThamaniDawaWeb.LabRequisitionLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Products
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Requisitions.Requisition
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site
  alias ThamaniDawaWeb.SiteScoping

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    organization_id = scope.organization_id

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites =
      scope
      |> Accounts.list_sites_for_user()
      |> Enum.filter(&Site.lab?/1)

    all_sites = Sites.list_sites(organization_id)

    requisitions =
      organization_id
      |> Requisitions.list_requisitions()
      |> SiteScoping.for_current_site(scope)
      |> Enum.filter(fn r ->
        Enum.any?(all_sites, &(&1.id == r.site_id and Site.lab?(&1)))
      end)

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites, sites)
     |> assign(:sites_by_id, Map.new(all_sites, &{&1.id, &1}))
     |> assign(:form, nil)
     |> stream(:requisitions, requisitions)}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    scope = socket.assigns.current_scope
    sites = socket.assigns.sites

    default_site_id =
      case sites do
        [single_site] -> single_site.id
        _ -> SiteScoping.default_site_id(scope)
      end

    changeset =
      Requisitions.change_requisition(%Requisition{}, %{
        site_id: default_site_id
      })

    assign(socket, :form, to_form(changeset, as: :requisition))
  end

  defp apply_action(socket, :index), do: assign(socket, :form, nil)

  def handle_event("validate", %{"requisition" => attrs}, socket) do
    changeset =
      %Requisition{}
      |> Requisitions.change_requisition(attrs)
      |> validate_site_access(socket.assigns.sites)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :requisition))}
  end

  def handle_event("save", %{"requisition" => attrs}, socket) do
    scope = socket.assigns.current_scope

    changeset =
      %Requisition{}
      |> Requisitions.change_requisition(attrs)
      |> validate_site_access(socket.assigns.sites)

    if changeset.valid? do
      case Requisitions.create_requisition(scope.organization_id, scope.user.id, attrs) do
        {:ok, requisition} ->
          {:noreply,
           socket
           |> put_flash(:info, "Requisition sent to the organization.")
           |> stream_insert(:requisitions, requisition, at: 0)
           |> push_patch(to: ~p"/lab/requisitions")}

        {:error, changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset, as: :requisition))}
      end
    else
      {:noreply,
       assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: :requisition))}
    end
  end

  defp validate_site_access(changeset, allowed_sites) do
    allowed_ids = Enum.map(allowed_sites, & &1.id)

    case Ecto.Changeset.get_field(changeset, :site_id) do
      nil ->
        changeset

      site_id ->
        if site_id in allowed_ids do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :site_id, "is not a site you can act on")
        end
    end
  end

  defp product_name(products_by_id, product_id) do
    case Map.get(products_by_id, product_id) do
      nil -> "(unknown product)"
      product -> product.generic_name || product.brand_name || "(unnamed)"
    end
  end

  defp site_name(sites_by_id, site_id) do
    case Map.get(sites_by_id, site_id) do
      nil -> "—"
      site -> site.name
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.lab_shell flash={@flash} current_scope={@current_scope} current_path="/lab/requisitions">
      <.header icon="hero-clipboard-document-list">
        Requisitions
        <:subtitle>
          Ask the organization for stock when your site's levels are running low.
        </:subtitle>
        <:actions>
          <.button variant="primary" patch={~p"/lab/requisitions/new"}>
            <.icon name="hero-plus" class="size-4" /> New requisition
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action == :new}
        id="new-requisition-modal"
        show
        on_cancel={JS.patch(~p"/lab/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          New requisition
        </h2>
        <.form
          for={@form}
          id="requisition-form"
          phx-submit="save"
          phx-change="validate"
          class="flex flex-col gap-4"
        >
          <%= if length(@sites) == 1 do %>
            <% site = hd(@sites) %>
            <.input field={@form[:site_id]} type="hidden" value={site.id} />
            <div>
              <span class="thamani-label">Site</span>
              <p class="text-sm font-medium text-slate-800">{site.name}</p>
            </div>
          <% else %>
            <.input
              field={@form[:site_id]}
              type="select"
              label="Site"
              options={Enum.map(@sites, &{&1.name, &1.id})}
              prompt="Choose a site"
              required
            />
          <% end %>
          <.input
            field={@form[:product_id]}
            type="select"
            label="Product"
            options={
              Enum.map(@products_by_id, fn {_id, p} -> {product_name(@products_by_id, p.id), p.id} end)
            }
            prompt="Choose a product"
            required
          />
          <.input field={@form[:quantity]} type="number" label="Quantity" min="1" required />
          <.input field={@form[:notes]} type="textarea" label="Notes (optional)" />
          <.button variant="primary" phx-disable-with="Sending…" class="w-full">
            Send requisition
          </.button>
        </.form>
      </.modal>

      <.table id="requisitions" rows={@streams.requisitions}>
        <:col :let={{_id, r}} label="Product">
          {product_name(@products_by_id, r.product_id)}
        </:col>
        <:col :let={{_id, r}} label="Site">{site_name(@sites_by_id, r.site_id)}</:col>
        <:col :let={{_id, r}} label="Quantity">
          <span class="tabular-nums">{r.quantity}</span>
        </:col>
        <:col :let={{_id, r}} label="Urgency">{r.urgency}</:col>
        <:col :let={{_id, r}} label="Status">
          <.status_badge status={r.status} />
          {if r.status == :rejected, do: r.rejection_reason}
        </:col>
        <:col :let={{_id, r}} label="Requested">{r.inserted_at}</:col>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No requisitions yet">
            Raise a requisition when your site needs more stock than it currently has.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.lab_shell>
    """
  end
end
