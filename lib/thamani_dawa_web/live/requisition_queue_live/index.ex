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

    {:ok,
     socket
     |> assign(:products_by_id, products_by_id)
     |> assign(:sites_by_id, sites_by_id)
     |> assign(:tabs, Requisitions.tabs())
     |> assign(:filters, %{
       "status" => "pending",
       "search" => "",
       "date_from" => "",
       "date_to" => ""
     })
     |> assign(:tab_counts, Requisitions.tab_counts([]))
     |> assign(:review_requisition, nil)
     |> assign(:reject_requisition, nil)
     |> assign(:reject_form, nil)
     |> assign(:fulfill_requisition, nil)
     |> assign(:fulfill_org_batches, [])
     |> assign(:fulfill_form, nil)
     |> assign(:fulfill_batches_by_product, %{})
     |> stream(:requisitions, [])}
  end

  def handle_params(%{"id" => id}, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, String.to_integer(id))}
  end

  def handle_params(params, _url, socket) do
    filters = %{
      "status" => params["status"] || "pending",
      "search" => params["search"] || "",
      "date_from" => params["date_from"] || "",
      "date_to" => params["date_to"] || ""
    }

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> apply_index()
     |> load_requisitions()}
  end

  defp load_requisitions(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    filters = socket.assigns.filters

    all = Requisitions.list_requisitions(organization_id)

    requisitions =
      all
      |> Requisitions.filter_by_tab(filters["status"])
      |> Requisitions.filter_by_date_range(
        parse_date(filters["date_from"]),
        parse_date(filters["date_to"])
      )
      |> Requisitions.filter_by_search(filters["search"])

    socket
    |> assign(:tab_counts, Requisitions.tab_counts(all))
    |> stream(:requisitions, requisitions, reset: true)
  end

  defp parse_date(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp filter_path(socket, changes) do
    query =
      socket.assigns.filters
      |> Map.merge(changes)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/org/requisitions?#{query}"
  end

  defp tab_path(filters, status) do
    query =
      filters
      |> Map.put("status", status)
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/org/requisitions?#{query}"
  end

  defp active_filter_count(filters),
    do: Enum.count(["date_from", "date_to"], &(filters[&1] not in [nil, ""]))

  defp apply_action(socket, :review, id) do
    organization_id = socket.assigns.current_scope.organization_id
    requisition = Requisitions.get_requisition!(organization_id, id)

    assign(socket, :review_requisition, requisition)
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

    assign_fulfill(socket, organization_id, requisition)
  end

  defp assign_fulfill(socket, organization_id, %{lines: []} = requisition) do
    org_batches =
      Batches.list_undispatched_batches_for_product(organization_id, requisition.product_id)

    outstanding = requisition.quantity - Requisitions.fulfilled_quantity(requisition.id)

    socket
    |> assign(:fulfill_requisition, requisition)
    |> assign(:fulfill_org_batches, org_batches)
    |> assign(:fulfill_form, to_form(%{"quantity" => max(outstanding, 0)}, as: :fulfill))
  end

  defp assign_fulfill(socket, organization_id, requisition) do
    batches_by_product =
      requisition.lines
      |> Enum.map(& &1.product_id)
      |> Enum.uniq()
      |> Map.new(&{&1, Batches.list_undispatched_batches_for_product(organization_id, &1)})

    socket
    |> assign(:fulfill_requisition, requisition)
    |> assign(:fulfill_batches_by_product, batches_by_product)
  end

  defp apply_index(socket) do
    socket
    |> assign(:review_requisition, nil)
    |> assign(:reject_requisition, nil)
    |> assign(:reject_form, nil)
    |> assign(:fulfill_requisition, nil)
    |> assign(:fulfill_org_batches, [])
    |> assign(:fulfill_form, nil)
    |> assign(:fulfill_batches_by_product, %{})
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, push_patch(socket, to: filter_path(socket, %{"search" => search}))}
  end

  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    changes = Map.take(filters, ["date_from", "date_to"])
    {:noreply, push_patch(socket, to: filter_path(socket, changes))}
  end

  def handle_event("clear_filter", %{"filter" => filter}, socket)
      when filter in ["date_from", "date_to"] do
    {:noreply, push_patch(socket, to: filter_path(socket, %{filter => ""}))}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    reviewer_id = socket.assigns.current_scope.user.id

    case Requisitions.approve_requisition(organization_id, String.to_integer(id), reviewer_id) do
      {:ok, requisition} ->
        {:noreply,
         socket
         |> put_flash(:info, "Requisition approved.")
         |> stream_insert(:requisitions, reloaded(organization_id, requisition.id))
         |> push_patch(to: ~p"/org/requisitions/#{requisition.id}/fulfill")}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "That requisition is no longer pending.")}
    end
  end

  def handle_event("review_lines", %{"decisions" => decisions}, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    reviewer_id = socket.assigns.current_scope.user.id
    requisition = socket.assigns.review_requisition

    case Requisitions.review_lines(organization_id, requisition.id, reviewer_id, decisions) do
      {:ok, reviewed} ->
        {:noreply,
         socket
         |> put_flash(:info, "Requisition reviewed.")
         |> stream_insert(:requisitions, reloaded(organization_id, reviewed.id))
         |> push_patch(to: ~p"/org/requisitions/#{reviewed.id}/fulfill")}

      {:error, :invalid_approved_quantity} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Approved quantities must be between 0 and what was requested."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't review that requisition.")}
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
         |> stream_insert(:requisitions, reloaded(organization_id, rejected.id))
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
           |> stream_insert(:requisitions, reloaded(organization_id, fulfilled.id))
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

  def handle_event(
        "fulfill_lines",
        %{"fulfillment" => %{"dispatches" => dispatch_params}},
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    actor_id = socket.assigns.current_scope.user.id
    requisition = socket.assigns.fulfill_requisition
    lines = fulfillable_lines(requisition.lines)

    with {:ok, dispatches} <-
           build_line_dispatches(
             lines,
             dispatch_params,
             socket.assigns.fulfill_batches_by_product
           ),
         {:ok, _} <- Requisitions.fulfill_requisition_lines(organization_id, dispatches, actor_id) do
      updated = Requisitions.get_requisition!(organization_id, requisition.id)

      {:noreply,
       socket
       |> put_flash(:info, "Stock dispatched — awaiting receipt at the site.")
       |> stream_insert(:requisitions, updated)
       |> push_patch(to: ~p"/org/requisitions")}
    else
      {:error, :invalid_form} ->
        {:noreply, put_flash(socket, :error, "Choose a batch and valid quantity for every line.")}

      {:error, :insufficient_quantity} ->
        {:noreply, put_flash(socket, :error, "A selected batch doesn't have enough stock.")}

      {:error, :exceeds_approved_quantity} ->
        {:noreply,
         put_flash(socket, :error, "A quantity exceeds its outstanding approved amount.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't dispatch the selected batches.")}
    end
  end

  def handle_event(
        "fulfill_line",
        %{"line_id" => line_id, "org_batch_id" => org_batch_id, "quantity" => quantity},
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id
    actor_id = socket.assigns.current_scope.user.id
    line_id = String.to_integer(line_id)
    line = Enum.find(socket.assigns.fulfill_requisition.lines, &(&1.id == line_id))

    with {org_batch_id, ""} <- Integer.parse(org_batch_id),
         {quantity, ""} <- Integer.parse(quantity),
         batches when not is_nil(batches) <-
           Map.get(socket.assigns.fulfill_batches_by_product, line && line.product_id),
         org_batch when not is_nil(org_batch) <- Enum.find(batches, &(&1.id == org_batch_id)) do
      case Requisitions.fulfill_requisition_line(
             organization_id,
             line_id,
             org_batch,
             quantity,
             actor_id
           ) do
        {:ok, _} ->
          requisition = Requisitions.get_requisition!(organization_id, requisition_id(socket))

          {:noreply,
           socket
           |> put_flash(:info, "Stock dispatched — awaiting receipt at the site.")
           |> stream_insert(:requisitions, requisition)
           |> assign_fulfill(organization_id, requisition)}

        {:error, :insufficient_quantity} ->
          {:noreply, put_flash(socket, :error, "That batch doesn't have enough stock.")}

        {:error, :exceeds_approved_quantity} ->
          {:noreply, put_flash(socket, :error, "That's more than what's still outstanding.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Couldn't dispatch that batch.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a batch and a valid quantity.")}
    end
  end

  defp requisition_id(socket), do: socket.assigns.fulfill_requisition.id

  defp reloaded(organization_id, requisition_id),
    do: Requisitions.get_requisition!(organization_id, requisition_id)

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

  defp lines_summary(lines) do
    "#{lines_count_summary(lines)} · #{lines_total(lines)} units"
  end

  defp lines_count_summary(lines) do
    count = length(lines)
    "#{count} product#{if count == 1, do: "", else: "s"}"
  end

  defp lines_total(lines), do: Enum.sum(Enum.map(lines, & &1.requested_quantity))

  defp line_outstanding(line) do
    dispatched = Enum.sum(Enum.map(line.fulfillments, & &1.dispatched_quantity))
    (line.approved_quantity || 0) - dispatched
  end

  defp fulfillable_lines(lines) do
    Enum.filter(lines, fn line ->
      line.status in [:approved, :partially_approved, :partially_fulfilled] and
        line_outstanding(line) > 0
    end)
  end

  defp build_line_dispatches(lines, params, batches_by_product) do
    result =
      Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
        line_params = Map.get(params, to_string(line.id), %{})
        batches = Map.get(batches_by_product, line.product_id, [])

        with {batch_id, ""} <- Integer.parse(Map.get(line_params, "org_batch_id", "")),
             {quantity, ""} <- Integer.parse(Map.get(line_params, "quantity", "")),
             %ThamaniDawa.Batches.Batch{} = batch <- Enum.find(batches, &(&1.id == batch_id)),
             true <- quantity > 0 and quantity <= line_outstanding(line) do
          {:cont, {:ok, [{line.id, batch, quantity} | acc]}}
        else
          _ -> {:halt, {:error, :invalid_form}}
        end
      end)

    case result do
      {:ok, dispatches} -> {:ok, Enum.reverse(dispatches)}
      error -> error
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.org_shell flash={@flash} current_scope={@current_scope} current_path="/org/requisitions">
      <.header icon="hero-clipboard-document-list">
        Requisitions
        <:subtitle>Stock requests raised by your sites, awaiting review or fulfillment.</:subtitle>
        <:toolbar>
          <form id="requisition-search" phx-change="search" phx-submit="search">
            <.search_input
              name="search"
              value={@filters["search"]}
              placeholder="Search by reference"
            />
          </form>
          <.filter_drawer
            id="requisition-filters"
            title="Filter requisitions"
            apply_event="apply_filters"
            active_count={active_filter_count(@filters)}
          >
            <:group label="Requested between">
              <div class="grid grid-cols-2 gap-2">
                <.input
                  type="date"
                  id="filter-date-from"
                  name="filters[date_from]"
                  value={@filters["date_from"]}
                />
                <.input
                  type="date"
                  id="filter-date-to"
                  name="filters[date_to]"
                  value={@filters["date_to"]}
                />
              </div>
            </:group>
            <:chip
              :if={@filters["date_from"] != ""}
              label={"From #{@filters["date_from"]}"}
              clear={JS.push("clear_filter", value: %{filter: "date_from"})}
            />
            <:chip
              :if={@filters["date_to"] != ""}
              label={"To #{@filters["date_to"]}"}
              clear={JS.push("clear_filter", value: %{filter: "date_to"})}
            />
          </.filter_drawer>
        </:toolbar>
      </.header>

      <nav
        id="requisition-tabs"
        class="mb-4 mt-4 flex gap-1 overflow-x-auto rounded-xl border border-thamani-stone bg-white p-1"
        aria-label="Requisition status"
      >
        <.link
          :for={{status, label} <- @tabs}
          id={"requisition-tab-#{status}"}
          patch={tab_path(@filters, status)}
          class={[
            "flex flex-1 items-center justify-center gap-2 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium transition-colors duration-150",
            if(@filters["status"] == status,
              do: "bg-thamani-forest text-white shadow-sm",
              else: "text-thamani-pewter hover:bg-thamani-canvas hover:text-thamani-forest"
            )
          ]}
          aria-current={@filters["status"] == status && "page"}
        >
          {label}
          <span class={[
            "rounded-full px-2 py-0.5 text-xs font-semibold",
            if(@filters["status"] == status,
              do: "bg-white/20 text-white",
              else: "bg-thamani-stone text-thamani-forest"
            )
          ]}>
            {@tab_counts[status]}
          </span>
        </.link>
      </nav>

      <.modal
        :if={@live_action == :review and not is_nil(@review_requisition)}
        id="review-requisition-modal"
        show
        on_cancel={JS.patch(~p"/org/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Review requisition
        </h2>
        <p class="mb-1 text-sm text-thamani-pewter">
          {site_name(@sites_by_id, @review_requisition.site_id)} · {lines_summary(
            @review_requisition.lines
          )}
        </p>
        <p class="mb-4 text-xs text-thamani-pewter">
          Set each line's approved quantity — leave it at what was requested to approve in full, lower it to approve partially, or set it to 0 to decline that item.
        </p>
        <form phx-submit="review_lines" class="flex flex-col gap-4">
          <div
            :for={line <- @review_requisition.lines}
            class="rounded-xl border border-thamani-stone p-4"
          >
            <p class="text-sm font-medium text-thamani-forest">
              {product_name(@products_by_id, line.product_id)}
            </p>
            <p class="text-xs text-thamani-pewter">Requested {line.requested_quantity}</p>
            <.input
              type="number"
              name={"decisions[#{line.id}]"}
              label="Approved quantity"
              value={line.requested_quantity}
              min="0"
              max={line.requested_quantity}
              required
            />
          </div>
          <.button variant="primary" phx-disable-with="Approving…" class="w-full">
            Approve requisition
          </.button>
        </form>
      </.modal>

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
        :if={
          @live_action == :fulfill and not is_nil(@fulfill_requisition) and
            @fulfill_requisition.lines == []
        }
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

      <.modal
        :if={
          @live_action == :fulfill and not is_nil(@fulfill_requisition) and
            @fulfill_requisition.lines != []
        }
        id="fulfill-lines-modal"
        show
        on_cancel={JS.patch(~p"/org/requisitions")}
      >
        <h2 class="text-2xl font-medium tracking-tight text-thamani-forest mb-4">
          Fulfill requisition
        </h2>
        <p class="mb-4 text-sm text-thamani-pewter">
          {site_name(@sites_by_id, @fulfill_requisition.site_id)}
        </p>
        <.form
          for={%{}}
          as={:fulfillment}
          id="fulfill-lines-form"
          phx-submit="fulfill_lines"
          class="flex flex-col gap-4"
        >
          <div
            :for={line <- fulfillable_lines(@fulfill_requisition.lines)}
            class="rounded-xl border border-thamani-stone p-4"
          >
            <p class="text-sm font-medium text-thamani-forest">
              {product_name(@products_by_id, line.product_id)}
            </p>
            <p class="text-xs text-thamani-pewter">
              {line_outstanding(line)} of {line.approved_quantity} still outstanding
            </p>
            <.blank_state
              :if={Map.get(@fulfill_batches_by_product, line.product_id, []) == []}
              icon="hero-archive-box"
              title="No warehouse stock"
            >
              There's no organization-level stock for this product yet.
            </.blank_state>
            <div
              :if={Map.get(@fulfill_batches_by_product, line.product_id, []) != []}
              class="mt-2 flex flex-col gap-3"
            >
              <.input
                type="select"
                id={"org_batch_id-#{line.id}"}
                name={"fulfillment[dispatches][#{line.id}][org_batch_id]"}
                label="Warehouse batch"
                options={
                  Enum.map(Map.get(@fulfill_batches_by_product, line.product_id, []), fn b ->
                    {"#{b.batch_no} — #{b.remaining_quantity} available — expires #{b.expiry_date}",
                     b.id}
                  end)
                }
                prompt="Choose a batch"
                required
              />
              <.input
                type="number"
                id={"quantity-#{line.id}"}
                name={"fulfillment[dispatches][#{line.id}][quantity]"}
                label="Quantity to dispatch"
                value={line_outstanding(line)}
                min="1"
                max={line_outstanding(line)}
                required
              />
            </div>
          </div>
          <p
            :if={fulfillable_lines(@fulfill_requisition.lines) == []}
            class="text-sm text-thamani-pewter"
          >
            Every approved line has been fully dispatched.
          </p>
          <.button
            :if={
              fulfillable_lines(@fulfill_requisition.lines) != [] and
                Enum.all?(
                  fulfillable_lines(@fulfill_requisition.lines),
                  &(Map.get(@fulfill_batches_by_product, &1.product_id, []) != [])
                )
            }
            variant="primary"
            phx-disable-with="Dispatching…"
            class="w-full"
          >
            Dispatch all to site
          </.button>
        </.form>
      </.modal>

      <.table
        id="requisitions"
        rows={@streams.requisitions}
        row_click={fn {_id, r} -> JS.navigate(~p"/org/requisitions/#{r.id}") end}
      >
        <:col :let={{_id, r}} label="Reference">
          <span class="font-mono font-semibold text-thamani-forest">{r.number}</span>
        </:col>
        <:col :let={{_id, r}} label="Items">
          <%= if r.lines == [] do %>
            {product_name(@products_by_id, r.product_id)}
          <% else %>
            {lines_count_summary(r.lines)}
          <% end %>
        </:col>
        <:col :let={{_id, r}} label="Site">{site_name(@sites_by_id, r.site_id)}</:col>
        <:col :let={{_id, r}} label="Quantity">
          <span class="tabular-nums">
            {if r.lines == [], do: r.quantity, else: lines_total(r.lines)}
          </span>
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
          <div :if={r.status == :pending and r.lines == []} class="flex gap-2">
            <.button type="button" variant="primary" phx-click="approve" phx-value-id={r.id}>
              Approve
            </.button>
            <.button variant="ghost" patch={~p"/org/requisitions/#{r.id}/reject"}>Reject</.button>
          </div>
          <div :if={r.status == :pending and r.lines != []} class="flex gap-2">
            <.button variant="primary" patch={~p"/org/requisitions/#{r.id}/review"}>
              Review
            </.button>
            <.button variant="ghost" patch={~p"/org/requisitions/#{r.id}/reject"}>Reject</.button>
          </div>
          <.button
            :if={r.status in [:approved, :partially_approved, :partially_fulfilled]}
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
