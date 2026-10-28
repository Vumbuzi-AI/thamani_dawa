defmodule ThamaniDawaWeb.RequisitionQueueLive.Index do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Batches
  alias ThamaniDawa.Products
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.Sites

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    products_by_id =
      organization_id |> Products.list_products() |> Map.new(&{&1.id, &1})

    sites_by_id =
      organization_id |> Sites.list_sites() |> Map.new(&{&1.id, &1})

    requisitions = Requisitions.list_requisitions(organization_id)

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:reject_requisition, nil)
     |> assign(:reject_form, nil)
     |> assign(:fulfill_requisition, nil)
     |> assign(:fulfill_org_batches, [])
     |> assign(:fulfill_form, nil)
     |> stream(:requisitions, requisitions)}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, String.to_integer(id))}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, apply_index(socket)}
  end

  defp apply_action(socket, :reject, id) do
    organization_id = socket.assigns.current_scope.organization_id
    requisition = Requisitions.get_requisition!(organization_id, id)

    socket
    |> assign(:reject_requisition, requisition)
    |> assign(:reject_form, to_form(%{"rejection_reason" => ""}, as: :reject))
  end

  defp apply_action(socket, :fulfill, id) do
    organization_id = socket.assigns.current_scope.organization_id
    requisition = Requisitions.get_requisition!(organization_id, id)

    org_batches =
      Batches.list_undispatched_batches_for_product(organization_id, requisition.product_id)

    outstanding = requisition.quantity - Requisitions.fulfilled_quantity(requisition.id)

    socket
    |> assign(:fulfill_requisition, requisition)
    |> assign(:fulfill_org_batches, org_batches)
    |> assign(:fulfill_form, to_form(%{"quantity" => max(outstanding, 0)}, as: :fulfill))
  end

  defp apply_index(socket) do
    socket
    |> assign(:reject_requisition, nil)
    |> assign(:reject_form, nil)
    |> assign(:fulfill_requisition, nil)
    |> assign(:fulfill_org_batches, [])
    |> assign(:fulfill_form, nil)
  end

  def handle_event("approve", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    reviewer_id = socket.assigns.current_scope.user.id

    case Requisitions.approve_requisition(organization_id, String.to_integer(id), reviewer_id) do
      {:ok, requisition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Requisition approved.")
         |> stream_insert(:requisitions, requisition)
         |> push_patch(to: ~p"/org/requisitions/#{requisition.id}/fulfill")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "That requisition is no longer pending.")}
    end
  end

  def handle_event("reject", %{"reject" => %{"rejection_reason" => reason}}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    reviewer_id = socket.assigns.current_scope.user.id
    requisition = socket.assigns.reject_requisition

    case Requisitions.reject_requisition(organization_id, requisition.id, reviewer_id, reason) do
      {:ok, rejected} ->
        {:noreply,
         socket
         |> put_flash(:info, "Requisition rejected.")
         |> stream_insert(:requisitions, rejected)
         |> push_patch(to: ~p"/org/requisitions")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :reject_form, to_form(changeset, as: :reject))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't reject that requisition.")}
    end
  end

  def handle_event(
        "fulfill",
        %{"fulfill" => %{"org_batch_id" => org_batch_id, "quantity" => quantity}},
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    requisition = socket.assigns.fulfill_requisition

    with {org_batch_id, ""} <- Integer.parse(org_batch_id),
         {quantity, ""} <- Integer.parse(quantity),
         org_batch when not is_nil(org_batch) <-
           Enum.find(socket.assigns.fulfill_org_batches, &(&1.id == org_batch_id)) do
      case Requisitions.fulfill_requisition(organization_id, requisition.id, org_batch, quantity) do
        {:ok, fulfilled} ->
          {:noreply,
           socket
           |> put_flash(:info, "Stock dispatched — awaiting receipt at the site.")
           |> stream_insert(:requisitions, fulfilled)
           |> push_patch(to: ~p"/org/requisitions")}

        {:error, :insufficient_quantity} ->
          {:noreply, put_flash(socket, :error, "That batch doesn't have enough stock.")}

        {:error, :not_approved} ->
          {:noreply, put_flash(socket, :error, "That requisition can no longer be fulfilled.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Couldn't dispatch that batch.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a batch and a valid quantity.")}
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
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/requisitions">
      <.header icon="hero-clipboard-document-list">
        Requisitions
        <:subtitle>Stock requests raised by your sites, awaiting review or fulfillment.</:subtitle>
      </.header>

      <.modal
        :if={@live_action == :reject and not is_nil(@reject_requisition)}
        id="reject-requisition-modal"
        show
        on_cancel={JS.patch(~p"/org/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Reject requisition
        </h2>
        <.form for={@reject_form} id="reject-form" phx-submit="reject" class="flex flex-col gap-4">
          <.input
            field={@reject_form[:rejection_reason]}
            type="textarea"
            label="Reason"
            required
          />
          <.button variant="destructive" phx-disable-with="Rejecting…" class="w-full">
            Reject requisition
          </.button>
        </.form>
      </.modal>

      <.modal
        :if={@live_action == :fulfill and not is_nil(@fulfill_requisition)}
        id="fulfill-requisition-modal"
        show
        on_cancel={JS.patch(~p"/org/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Fulfill requisition
        </h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          {product_name(@products_by_id, @fulfill_requisition.product_id)} · {site_name(
            @sites_by_id,
            @fulfill_requisition.site_id
          )} · {@fulfill_requisition.quantity} requested
        </p>
        <.form
          :if={@fulfill_org_batches != []}
          for={@fulfill_form}
          id="fulfill-form"
          phx-submit="fulfill"
          class="flex flex-col gap-4"
        >
          <.input
            field={@fulfill_form[:org_batch_id]}
            type="select"
            label="Warehouse batch"
            options={
              Enum.map(@fulfill_org_batches, fn b ->
                {"#{b.batch_no} — #{b.remaining_quantity} available — expires #{b.expiry_date}", b.id}
              end)
            }
            prompt="Choose a batch"
            required
          />
          <.input
            field={@fulfill_form[:quantity]}
            type="number"
            label="Quantity to dispatch"
            min="1"
            required
          />
          <.button variant="primary" phx-disable-with="Dispatching…" class="w-full">
            Dispatch to site
          </.button>
        </.form>
        <.blank_state
          :if={@fulfill_org_batches == []}
          icon="hero-archive-box"
          title="No warehouse stock"
        >
          There's no organization-level stock for this product — order more before fulfilling.
        </.blank_state>
      </.modal>

      <.table id="requisitions" rows={@streams.requisitions}>
        <:col :let={{_id, r}} label="Product">
          {product_name(@products_by_id, r.product_id)}
        </:col>
        <:col :let={{_id, r}} label="Site">{site_name(@sites_by_id, r.site_id)}</:col>
        <:col :let={{_id, r}} label="Quantity">
          <span class="tabular-nums">{r.quantity}</span>
        </:col>
        <:col :let={{_id, r}} label="Status">
          <div class="flex items-center gap-2">
            <.status_badge status={r.status} />
            <span :if={r.needs_reorder} class="text-xs font-medium text-thamani-error">
              Needs reorder
            </span>
          </div>
        </:col>
        <:action :let={{_id, r}}>
          <div :if={r.status == :pending} class="flex gap-2">
            <.button
              type="button"
              variant="primary"
              phx-click="approve"
              phx-value-id={r.id}
            >
              Approve
            </.button>
            <.button variant="ghost" patch={~p"/org/requisitions/#{r.id}/reject"}>Reject</.button>
          </div>
          <.button
            :if={r.status in [:approved, :partially_fulfilled]}
            variant="primary"
            patch={~p"/org/requisitions/#{r.id}/fulfill"}
          >
            Fulfill
          </.button>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-clipboard-document-list" title="No requisitions yet">
            Stock requests raised by sites will appear here.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.org_shell>
    """
  end
end
