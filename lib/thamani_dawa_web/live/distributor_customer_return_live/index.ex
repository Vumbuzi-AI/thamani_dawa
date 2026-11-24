defmodule ThamaniDawaWeb.DistributorCustomerReturnLive.Index do
  @moduledoc """
  Customer-return queue: start a draft (customer, site), add items with
  their lot details, mark received, assign a condition per item during
  inspection, then complete to put the stock away into new batches.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.CustomerReturns
  alias ThamaniDawa.CustomerReturns.CustomerReturn
  alias ThamaniDawa.CustomerReturns.CustomerReturnItem
  alias ThamaniDawa.Customers
  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Products
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  @shipment_match_limit 8

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites =
      organization_id
      |> Sites.list_sites()
      |> Enum.filter(&(Site.distribution?(&1) and &1.is_active))

    {:ok,
     socket
     |> assign(:page_title, "Customer returns")
     |> assign(:sites, sites)
     |> assign(:customers, Customers.list_customers(organization_id))
     |> assign(:products, Products.list_products(organization_id))
     |> assign(:detail_id, nil)
     |> assign(:customer_return, nil)
     |> assign(:return_source, "shipment")
     |> assign(:shipment_query, "")
     |> assign(:shipment_matches, [])
     |> assign(:selected_shipment, nil)
     |> assign(:customer_query, "")
     |> assign(:customer_matches, [])
     |> assign(:selected_customer, nil)
     |> assign(:customer_gln, "")
     |> assign(:customer_name_error, nil)
     |> assign(:customer_gln_error, nil)
     |> assign(:document_error, nil)
     |> allow_return_uploads()
     |> load_returns()}
  end

  def handle_params(params, _url, socket) do
    status = if params["status"] in ~w(draft received inspected completed), do: params["status"], else: ""

    {:noreply,
     socket
     |> assign(:cr_status, status)
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    site_id =
      case locked_site(socket.assigns.sites, socket.assigns.current_scope) do
        nil -> nil
        site -> site.id
      end

    socket
    |> assign(:return_source, "shipment")
    |> assign(:shipment_query, "")
    |> assign(:shipment_matches, [])
    |> assign(:selected_shipment, nil)
    |> assign(:customer_query, "")
    |> assign(:customer_matches, [])
    |> assign(:selected_customer, nil)
    |> assign(:customer_gln, "")
    |> assign(:customer_name_error, nil)
    |> assign(:customer_gln_error, nil)
    |> assign(:detail_id, nil)
    |> assign(:customer_return, nil)
    |> assign(
      :form,
      to_form(
        CustomerReturns.change_return(%CustomerReturn{}, %{"site_id" => site_id}),
        as: :customer_return
      )
    )
  end

  defp apply_action(socket, :show, %{"id" => id} = params) do
    customer_return =
      CustomerReturns.get_return!(socket.assigns.current_scope.organization_id, id)

    socket
    |> assign(:form, nil)
    |> assign(:detail_id, nil)
    |> assign(:customer_return, customer_return)
    |> assign(:return_to, ThamaniDawaWeb.ReturnTo.path(params, ~p"/distributor/customer-returns"))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:form, nil)
    |> assign(:detail_id, nil)
    |> assign(:customer_return, nil)
  end

  def handle_event("validate", %{"customer_return" => attrs}, socket) do
    changeset =
      %CustomerReturn{}
      |> CustomerReturns.change_return(attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :customer_return))}
  end

  def handle_event("search_shipment", %{"query" => query}, socket) do
    query = String.trim(query)

    {:noreply,
     socket
     |> assign(:shipment_query, query)
     |> assign(:shipment_matches, shipment_matches(socket, query))
     |> assign(:selected_shipment, nil)}
  end

  def handle_event("select_shipment", %{"id" => id}, socket) do
    shipment = Distributor.get_shipment!(socket.assigns.current_scope.organization_id, id)
    site = return_site(socket, shipment)

    {:noreply,
     socket
     |> assign(:selected_shipment, shipment)
     |> assign(:shipment_matches, [])
     |> assign(:form, return_form(socket, site))}
  end

  def handle_event("switch_return_source", %{"source" => source}, socket)
      when source in ["shipment", "customer"] do
    {:noreply,
     socket
     |> assign(:return_source, source)
     |> assign(:selected_shipment, nil)
     |> assign(:shipment_matches, [])
     |> assign(:customer_query, "")
     |> assign(:customer_matches, [])
     |> assign(:selected_customer, nil)
     |> assign(:customer_gln, "")
     |> assign(:customer_name_error, nil)
     |> assign(:customer_gln_error, nil)
     |> assign(
       :form,
       return_form(socket, locked_site(socket.assigns.sites, socket.assigns.current_scope))
     )}
  end

  def handle_event("sync_return_form", params, socket) do
    socket = assign(socket, :document_error, nil)

    if socket.assigns.return_source == "customer" do
      name = String.trim(params["customer_name"] || "")
      gln = String.trim(params["customer_gln"] || socket.assigns.customer_gln)

      selected =
        case socket.assigns.selected_customer do
          %{name: selected_name} = customer ->
            if names_match?(selected_name, name), do: customer, else: nil

          _ ->
            nil
        end

      {:noreply,
       socket
       |> assign(:customer_query, name)
       |> assign(:customer_gln, gln)
       |> assign(:selected_customer, selected)
       |> assign(:customer_name_error, nil)
       |> assign(:customer_gln_error, nil)
       |> assign(:customer_matches, customer_matches(socket.assigns.customers, name, selected))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cancel_return_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :return_documents, ref)}
  end

  def handle_event("select_customer", %{"id" => id}, socket) do
    customer = Customers.get_customer!(socket.assigns.current_scope.organization_id, id)

    {:noreply,
     socket
     |> assign(:selected_customer, customer)
     |> assign(:customer_query, customer.name)
     |> assign(:customer_matches, [])
     |> assign(:customer_name_error, nil)}
  end

  def handle_event("save", %{"customer_return" => attrs} = params, socket) do
    if message = missing_return_document(socket) do
      {:noreply, assign(socket, :document_error, message)}
    else
      save_return(params, attrs, socket)
    end
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    {:noreply, assign(socket, :detail_id, id)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :detail_id, nil)}
  end

  def handle_event(
        "add_item",
        %{
          "customer_return_id" => return_id_str,
          "product_id" => product_id_str,
          "quantity" => quantity_str,
          "batch_no" => batch_no,
          "expiry_date" => expiry_date_str
        },
        socket
      )
      when product_id_str != "" do
    scope = socket.assigns.current_scope

    with {return_id, ""} <- Integer.parse(return_id_str) do
      customer_return = CustomerReturns.get_return!(scope.organization_id, return_id)

      if customer_return.shipment_id do
        {:noreply,
         put_flash(
           socket,
           :error,
           "This return is linked to a shipment — only packs from that shipment can be added."
         )}
      else
        attrs = %{
          "product_id" => product_id_str,
          "quantity" => quantity_str,
          "batch_no" => batch_no,
          "expiry_date" => expiry_date_str,
          "matched" => false
        }

        case CustomerReturns.add_item(customer_return, attrs) do
          {:ok, _item} ->
            {:noreply, socket |> put_flash(:info, "Item added.") |> load_returns()}

          {:error, :not_draft} ->
            {:noreply, put_flash(socket, :error, "This return is no longer a draft.")}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, item_error(changeset))}
        end
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("add_item", _params, socket) do
    {:noreply, put_flash(socket, :error, "Fill in every field to add an item.")}
  end

  def handle_event(
        "add_shipment_item",
        %{"shipment_item_id" => item_id_str, "customer_return_id" => return_id_str},
        socket
      ) do
    scope = socket.assigns.current_scope

    with {return_id, ""} <- Integer.parse(return_id_str),
         {item_id, ""} <- Integer.parse(item_id_str) do
      customer_return = CustomerReturns.get_return!(scope.organization_id, return_id)
      shipment_item = Enum.find(customer_return.shipment.items, &(&1.id == item_id))

      cond do
        is_nil(shipment_item) ->
          {:noreply, put_flash(socket, :error, "That pack is not on this shipment.")}

        is_nil(shipment_item.product_id) or is_nil(shipment_item.batch) or
            is_nil(shipment_item.expiry_date) ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "This pack has no catalogue product or lot. Add it as a line that was not on the shipment."
           )}

        true ->
          attrs = %{
            "product_id" => shipment_item.product_id,
            "quantity" => 1,
            "batch_no" => shipment_item.batch,
            "expiry_date" => Date.to_iso8601(shipment_item.expiry_date),
            "serial" => shipment_item.serial,
            "shipment_item_id" => shipment_item.id,
            "matched" => true
          }

          case CustomerReturns.add_item(customer_return, attrs) do
            {:ok, _item} ->
              {:noreply,
               socket |> put_flash(:info, "Pack added to the return.") |> load_returns()}

            {:error, :not_draft} ->
              {:noreply, put_flash(socket, :error, "This return is no longer a draft.")}

            {:error, changeset} ->
              {:noreply, put_flash(socket, :error, item_error(changeset))}
          end
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "add_all_shipment_items",
        %{"customer_return_id" => return_id_str},
        socket
      ) do
    scope = socket.assigns.current_scope

    with {return_id, ""} <- Integer.parse(return_id_str) do
      customer_return = CustomerReturns.get_return!(scope.organization_id, return_id)

      {added, skipped} =
        customer_return
        |> pending_shipment_lines()
        |> Enum.reduce({0, 0}, fn line, {added, skipped} ->
          add_pending_shipment_line(customer_return, line, added, skipped)
        end)

      {:noreply, socket |> put_flash(:info, bulk_add_message(added, skipped)) |> load_returns()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "remove_item",
        %{"item_id" => item_id_str, "customer_return_id" => return_id_str},
        socket
      ) do
    scope = socket.assigns.current_scope

    with {item_id, ""} <- Integer.parse(item_id_str),
         {return_id, ""} <- Integer.parse(return_id_str) do
      customer_return = CustomerReturns.get_return!(scope.organization_id, return_id)
      item = Enum.find(customer_return.items, &(&1.id == item_id))

      case item && CustomerReturns.remove_item(item) do
        {:ok, _item} ->
          {:noreply, socket |> put_flash(:info, "Item removed.") |> load_returns()}

        {:error, :not_draft} ->
          {:noreply, put_flash(socket, :error, "This return is no longer a draft.")}

        _ ->
          {:noreply, socket}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("mark_received", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope
    {id, ""} = Integer.parse(id_str)
    customer_return = CustomerReturns.get_return!(scope.organization_id, id)

    case CustomerReturns.mark_received(customer_return, scope.user.id) do
      {:ok, _received} ->
        {:noreply, socket |> put_flash(:info, "Marked received.") |> load_returns()}

      {:error, :no_items} ->
        {:noreply, put_flash(socket, :error, "Add at least one item first.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't mark this return received.")}
    end
  end

  def handle_event(
        "set_condition",
        %{
          "item_id" => item_id_str,
          "customer_return_id" => return_id_str,
          "condition" => condition
        },
        socket
      ) do
    scope = socket.assigns.current_scope
    {item_id, ""} = Integer.parse(item_id_str)
    {return_id, ""} = Integer.parse(return_id_str)
    customer_return = CustomerReturns.get_return!(scope.organization_id, return_id)
    item = Enum.find(customer_return.items, &(&1.id == item_id))

    case item && CustomerReturns.set_item_condition(item, condition) do
      {:ok, _item} -> {:noreply, load_returns(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Couldn't set that item's condition.")}
    end
  end

  def handle_event("mark_inspected", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope
    {id, ""} = Integer.parse(id_str)
    customer_return = CustomerReturns.get_return!(scope.organization_id, id)

    case CustomerReturns.mark_inspected(customer_return) do
      {:ok, _inspected} ->
        {:noreply, socket |> put_flash(:info, "Inspection complete.") |> load_returns()}

      {:error, :items_not_inspected} ->
        {:noreply, put_flash(socket, :error, "Every item needs a condition first.")}
    end
  end

  def handle_event("complete", %{"id" => id_str}, socket) do
    scope = socket.assigns.current_scope
    {id, ""} = Integer.parse(id_str)

    case CustomerReturns.complete_return(scope.organization_id, id, scope.user.id) do
      {:ok, _completed} ->
        socket =
          socket
          |> put_flash(:info, "Return completed. Stock has been put away.")
          |> load_returns()

        if socket.assigns.live_action == :show do
          {:noreply, push_navigate(socket, to: ~p"/distributor/customer-returns")}
        else
          {:noreply, socket}
        end

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Couldn't complete this return.")}
    end
  end

  defp allow_return_uploads(socket) do
    allow_upload(socket, :return_documents,
      accept: ~w(.pdf .jpg .jpeg .png),
      max_entries: 8,
      max_file_size: 5_000_000,
      auto_upload: true
    )
  end

  defp missing_return_document(socket) do
    entries = socket.assigns.uploads.return_documents.entries

    cond do
      Enum.any?(entries, &(not &1.done?)) ->
        "Wait for the documents to finish uploading."

      Enum.count(entries, &(&1.done? and &1.valid?)) == 0 ->
        "Attach the related documents."

      true ->
        nil
    end
  end

  defp store_return_documents(socket, customer_return) do
    user_id = socket.assigns.current_scope.user.id

    consume_uploaded_entries(socket, :return_documents, fn %{path: tmp_path}, entry ->
      CustomerReturns.store_attachment!(customer_return, tmp_path, entry, user_id)
      {:ok, :stored}
    end)
  end

  defp upload_error_to_string(:too_large), do: "That file is larger than 5MB."
  defp upload_error_to_string(:too_many_files), do: "You can attach up to 8 documents."
  defp upload_error_to_string(:not_accepted), do: "Use a PDF, JPG, or PNG."
  defp upload_error_to_string(_), do: "That file could not be attached."

  defp save_return(params, attrs, socket) do
    scope = socket.assigns.current_scope
    attrs = force_locked_site(attrs, socket.assigns.sites, scope)

    result =
      case socket.assigns.selected_shipment do
        nil ->
          create_return_for_named_customer(scope.organization_id, socket, attrs, params)

        shipment ->
          case CustomerReturns.customer_for_shipment(scope.organization_id, shipment) do
            {:ok, customer} ->
              attrs =
                attrs
                |> Map.put("customer_id", to_string(customer.id))
                |> Map.put("shipment_id", to_string(shipment.id))

              CustomerReturns.create_return(scope.organization_id, attrs)

            {:error, changeset} ->
              {:error, changeset}
          end
      end

    case result do
      {:ok, customer_return} ->
        store_return_documents(socket, customer_return)

        {:noreply,
         socket
         |> put_flash(:info, "Draft return started.")
         |> assign(:customers, Customers.list_customers(scope.organization_id))
         |> push_navigate(to: ~p"/distributor/customer-returns/#{customer_return.id}")}

      {:error, %Ecto.Changeset{data: %ThamaniDawa.Customers.Customer{}} = changeset} ->
        {:noreply,
         socket
         |> assign(:customer_name_error, customer_field_error(changeset, :name))
         |> assign(:customer_gln_error, customer_field_error(changeset, :gln))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(
           socket,
           :form,
           to_form(Map.put(changeset, :action, :validate), as: :customer_return)
         )}

      {:error, :name_required} ->
        {:noreply, assign(socket, :customer_name_error, "Enter the customer name.")}
    end
  end

  defp create_return_for_named_customer(organization_id, socket, attrs, params) do
    name = String.trim(params["customer_name"] || socket.assigns.customer_query || "")
    gln = String.trim(params["customer_gln"] || socket.assigns.customer_gln || "")

    case customer_for_name(organization_id, socket, name, gln) do
      {:ok, customer} ->
        attrs = Map.put(attrs, "customer_id", to_string(customer.id))
        CustomerReturns.create_return(organization_id, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp customer_for_name(_organization_id, _socket, "", _gln), do: {:error, :name_required}

  defp customer_for_name(organization_id, socket, name, gln) do
    selected =
      case socket.assigns.selected_customer do
        %{name: selected_name} = customer ->
          if names_match?(selected_name, name), do: customer, else: nil

        _ ->
          nil
      end

    by_name = Enum.find(socket.assigns.customers, &names_match?(&1.name, name))
    by_gln = if gln == "", do: nil, else: Customers.get_by_gln(organization_id, gln)

    cond do
      selected ->
        {:ok, selected}

      by_name ->
        {:ok, by_name}

      by_gln ->
        {:ok, by_gln}

      true ->
        attrs = %{"name" => name, "customer_type" => "other"}
        attrs = if gln == "", do: attrs, else: Map.put(attrs, "gln", gln)
        Customers.create_customer(organization_id, attrs)
    end
  end

  defp customer_matches(customers, query, selected) do
    cond do
      String.length(query) < 2 ->
        []

      selected && names_match?(selected.name, query) ->
        []

      true ->
        needle = String.downcase(query)

        customers
        |> Enum.filter(&String.contains?(String.downcase(&1.name), needle))
        |> Enum.take(8)
    end
  end

  defp names_match?(left, right) do
    String.downcase(String.trim(left || "")) == String.downcase(String.trim(right || ""))
  end

  defp customer_field_error(%Ecto.Changeset{} = changeset, field) do
    case changeset.errors[field] do
      nil -> nil
      {message, _opts} -> message
    end
  end

  defp load_returns(socket) do
    organization_id = socket.assigns.current_scope.organization_id

    returns =
      organization_id
      |> CustomerReturns.list_returns()
      |> filter_locked_site(socket.assigns.sites, socket.assigns.current_scope)

    socket =
      socket
      |> assign(:returns, returns)
      |> maybe_stream_returns(returns)

    if socket.assigns.live_action == :show && socket.assigns.customer_return do
      id = socket.assigns.customer_return.id

      assign(
        socket,
        :customer_return,
        CustomerReturns.get_return!(socket.assigns.current_scope.organization_id, id)
      )
    else
      socket
    end
  end

  defp maybe_stream_returns(socket, returns) do
    if socket.assigns.live_action == :show do
      socket
    else
      stream(socket, :returns, returns, reset: true)
    end
  end

  defp locked_site(sites, scope) do
    case Enum.find(sites, &(&1.id == scope.current_site_id)) do
      %Site{} = site -> site
      nil -> if length(sites) == 1, do: hd(sites), else: nil
    end
  end

  defp force_locked_site(attrs, sites, scope) do
    case locked_site(sites, scope) do
      nil -> attrs
      site -> Map.put(attrs, "site_id", to_string(site.id))
    end
  end

  defp filter_locked_site(returns, sites, scope) do
    case locked_site(sites, scope) do
      nil -> returns
      site -> Enum.filter(returns, &(&1.site_id == site.id))
    end
  end

  defp shipment_matches(socket, query) do
    if String.length(query) < 2 do
      []
    else
      opts = %{status: "approved", search: query}

      opts =
        case locked_site(socket.assigns.sites, socket.assigns.current_scope) do
          nil -> opts
          site -> Map.put(opts, :origin_site_id, site.id)
        end

      socket.assigns.current_scope.organization_id
      |> Distributor.list_shipments(opts)
      |> Map.fetch!(:entries)
      |> Enum.reject(& &1.is_return)
      |> Enum.take(@shipment_match_limit)
    end
  end

  defp shipment_left_on(shipment) do
    case shipment.approved_at || shipment.inserted_at do
      nil -> "—"
      datetime -> ThamaniDawaWeb.TimeFormat.date(datetime)
    end
  end

  defp return_site(socket, shipment) do
    sites = socket.assigns.sites

    locked_site(sites, socket.assigns.current_scope) ||
      Enum.find(sites, &(&1.id == shipment.origin_site_id))
  end

  defp return_form(socket, site) do
    attrs = %{
      "site_id" => site && site.id,
      "reason" => form_value(socket, :reason),
      "notes" => form_value(socket, :notes)
    }

    to_form(CustomerReturns.change_return(%CustomerReturn{}, attrs), as: :customer_return)
  end

  defp form_value(%{assigns: %{form: %{source: source}}}, field) when not is_nil(source) do
    Ecto.Changeset.get_field(source, field)
  end

  defp form_value(_socket, _field), do: nil

  defp item_error(changeset) do
    if Keyword.has_key?(changeset.errors, :shipment_item_id) do
      "That pack is already on a return."
    else
      "Couldn't add that item — check the fields."
    end
  end

  defp pending_shipment_lines(%{shipment: %{items: items}} = customer_return)
       when is_list(items) do
    taken = MapSet.new(customer_return.items, & &1.shipment_item_id)

    Enum.reject(items, &MapSet.member?(taken, &1.id))
  end

  defp pending_shipment_lines(_customer_return), do: []

  defp add_pending_shipment_line(customer_return, line, added, skipped) do
    if is_nil(line.product_id) or is_nil(line.batch) or is_nil(line.expiry_date) do
      {added, skipped + 1}
    else
      attrs = %{
        "product_id" => line.product_id,
        "quantity" => 1,
        "batch_no" => line.batch,
        "expiry_date" => Date.to_iso8601(line.expiry_date),
        "serial" => line.serial,
        "shipment_item_id" => line.id,
        "matched" => true
      }

      case CustomerReturns.add_item(customer_return, attrs) do
        {:ok, _item} -> {added + 1, skipped}
        _ -> {added, skipped + 1}
      end
    end
  end

  defp bulk_add_message(added, 0), do: "Added #{added} pack(s) to the return."

  defp bulk_add_message(added, skipped) do
    "Added #{added} pack(s); #{skipped} need manual details and were skipped."
  end

  defp different_origin?(sites, scope, shipment) do
    case locked_site(sites, scope) do
      nil -> false
      site -> shipment.origin_site_id != site.id
    end
  end

  defp shipment_line_name(item) do
    cond do
      item.product -> product_name(item.product)
      is_binary(item.product_name) and item.product_name != "" -> item.product_name
      true -> item.gtin || "Unknown pack"
    end
  end

  @return_steps [:draft, :received, :inspected, :completed]

  attr :status, :atom, required: true

  defp return_status_stepper(assigns) do
    assigns = assign(assigns, :steps, @return_steps)

    ~H"""
    <ol class="flex flex-wrap items-center gap-x-1.5 gap-y-1">
      <li :for={{step, index} <- Enum.with_index(@steps)} class="flex items-center gap-1.5">
        <span :if={index > 0} class="h-px w-4 shrink-0 bg-thamani-stone" aria-hidden="true"></span>
        <span class={[
          "flex items-center gap-1.5 text-xs font-medium",
          return_step_reached?(@status, step) && "text-thamani-forest",
          !return_step_reached?(@status, step) && "text-thamani-pewter"
        ]}>
          <span class={[
            "flex size-4 shrink-0 items-center justify-center rounded-full text-[10px] font-semibold",
            return_step_passed?(@status, step) && "bg-thamani-forest text-td-on-accent",
            return_step_current?(@status, step) &&
              "border-2 border-thamani-forest text-thamani-forest",
            !return_step_reached?(@status, step) && "border border-thamani-stone"
          ]}>
            <.icon
              :if={return_step_passed?(@status, step)}
              name="hero-check"
              class="size-2.5"
            /> {if !return_step_passed?(@status, step), do: index + 1}
          </span>
          {Phoenix.Naming.humanize(step)}
        </span>
      </li>
    </ol>
    """
  end

  defp return_step_index(step), do: Enum.find_index(@return_steps, &(&1 == step))

  defp return_step_reached?(status, step),
    do: return_step_index(status) >= return_step_index(step)

  defp return_step_current?(status, step), do: status == step
  defp return_step_passed?(status, step), do: return_step_index(status) > return_step_index(step)

  defp detail_return(_returns, nil), do: nil
  defp detail_return(returns, id), do: Enum.find(returns, &(&1.id == id))

  defp open_return(customer_return) do
    JS.navigate(
      ThamaniDawaWeb.ReturnTo.with_query(
        ~p"/distributor/customer-returns/#{customer_return.id}",
        ~p"/distributor/customer-returns"
      )
    )
  end

  defp condition_totals(items) do
    items
    |> Enum.group_by(&(&1.condition || "unset"))
    |> Enum.map(fn {condition, rows} -> {to_string(condition), rows |> Enum.map(&(&1.quantity || 0)) |> Enum.sum()} end)
  end

  defp reason_label(nil), do: "—"
  defp reason_label(reason), do: Phoenix.Naming.humanize(reason)

  defp item_count(items) do
    count = length(items)
    "#{count} #{if count == 1, do: "item", else: "items"}"
  end

  defp product_name(%{generic_name: generic, brand_name: brand}),
    do: generic || brand || "(unnamed)"

  defp status_message(:draft), do: "Add items with their lot details, then mark received."
  defp status_message(:received), do: "Assign a condition to every item, then mark inspected."
  defp status_message(:inspected), do: "Ready to complete — stock will be put away."
  defp status_message(:completed), do: "Completed. Stock was put away."

  attr :customer_return, :map, required: true
  attr :products, :list, required: true
  attr :heading, :boolean, default: false

  defp return_panel(assigns) do
    ~H"""
    <div :if={@heading} class="flex flex-wrap items-start justify-between gap-3 pr-8">
      <div>
        <h2 class="text-base font-semibold text-thamani-forest">
          {@customer_return.customer.name}
        </h2>
        <p class="mt-0.5 text-sm leading-6 text-thamani-pewter">
          Return #{@customer_return.id} · {@customer_return.site.name} · {status_message(
            @customer_return.status
          )}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <.status_badge status={@customer_return.status} />
        <.button variant="ghost" type="button" phx-click="close_detail">Close</.button>
      </div>
    </div>

    <div class={["space-y-5", @heading && "mt-4 border-t border-thamani-stone pt-4"]}>
      <.return_status_stepper status={@customer_return.status} />

      <div
        :if={@customer_return.shipment || @customer_return.attachments != []}
        class="rounded-xl bg-thamani-canvas px-3 py-2.5"
      >
        <p :if={@customer_return.shipment} class="text-sm text-thamani-pewter">
          Shipment
          <span class="font-medium tracking-tight text-thamani-forest tabular-nums">
            {@customer_return.shipment.reference}
          </span>
        </p>
        <ul
          :if={@customer_return.attachments != []}
          id={"return-attachments-#{@customer_return.id}"}
          class={["space-y-0.5", @customer_return.shipment && "mt-1.5"]}
        >
          <li
            :for={attachment <- @customer_return.attachments}
            class="flex items-center gap-1.5 text-sm text-thamani-pewter"
          >
            <.icon name="hero-paper-clip" class="size-3.5 shrink-0" />
            <span class="truncate">{attachment.filename}</span>
          </li>
        </ul>
      </div>

      <div
        :if={@customer_return.status == :draft and @customer_return.shipment}
        id="shipment-return-lines"
        class="space-y-2"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="text-xs font-semibold uppercase tracking-wide text-thamani-pewter">
            Packs on this shipment
          </h3>
          <button
            :if={length(pending_shipment_lines(@customer_return)) > 1}
            type="button"
            id="add-all-shipment-items"
            phx-click="add_all_shipment_items"
            phx-value-customer_return_id={@customer_return.id}
            class="text-xs font-semibold text-thamani-forest underline decoration-thamani-forest/40 underline-offset-2 hover:decoration-thamani-forest"
          >
            All packs came back
          </button>
        </div>
        <p
          :if={pending_shipment_lines(@customer_return) == []}
          class="text-sm text-thamani-pewter"
        >
          Every scanned pack from this shipment is already on the return.
        </p>
        <div
          :for={line <- pending_shipment_lines(@customer_return)}
          id={"shipment-line-#{line.id}"}
          class="flex flex-wrap items-center justify-between gap-3 rounded-lg bg-thamani-canvas px-3 py-2"
        >
          <div class="min-w-0">
            <p class="text-sm font-medium text-thamani-forest">{shipment_line_name(line)}</p>
            <p class="text-xs text-thamani-pewter">
              {line.batch || "No batch"} · {line.serial || "No serial"} · exp {line.expiry_date || "—"}
            </p>
          </div>
          <button
            type="button"
            id={"return-pack-#{line.id}"}
            phx-click="add_shipment_item"
            phx-value-shipment_item_id={line.id}
            phx-value-customer_return_id={@customer_return.id}
            class="rounded-full bg-td-surface px-3 py-1.5 text-sm font-medium text-thamani-forest ring-1 ring-thamani-stone"
          >
            Came back
          </button>
        </div>
      </div>
      <form
        :if={@customer_return.status == :draft and is_nil(@customer_return.shipment)}
        id="add-return-item-form"
        phx-submit="add_item"
        class="grid gap-3 sm:grid-cols-5 sm:items-end"
      >
        <input type="hidden" name="customer_return_id" value={@customer_return.id} />
        <div class="sm:col-span-2 [&>div]:mb-0">
          <.input
            type="select"
            name="product_id"
            label="Product"
            value={nil}
            options={Enum.map(@products, &{product_name(&1), &1.id})}
            prompt="Choose a product"
          />
        </div>
        <div class="[&>div]:mb-0">
          <.input type="number" name="quantity" label="Quantity" min="1" required />
        </div>
        <div class="[&>div]:mb-0">
          <.input type="text" name="batch_no" label="Batch no." required />
        </div>
        <div class="[&>div]:mb-0">
          <.date_picker name="expiry_date" label="Expiry date" required />
        </div>
        <div class="sm:col-span-5">
          <.button variant="primary" phx-disable-with="Adding…">Add item</.button>
        </div>
      </form>

      <div :if={@customer_return.items != []} class="td-card" id="customer-return-items">
        <.td_card_header
          title="Returned items"
          subtitle={if @customer_return.status == :received, do: "Set the condition of each item after inspection.", else: "#{length(@customer_return.items)} on this return"}
        />
        <div class="td-list-table">
          <table class="td-rows is-static">
            <thead>
              <tr>
                <th>Product</th>
                <th>Batch</th>
                <th class="is-num">Units</th>
                <th>Condition</th>
                <th><span class="sr-only">Actions</span></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @customer_return.items} id={"return-item-#{item.id}"}>
                <td>
                  {product_name(item.product)}
                  <span :if={item.serial} class="td-sub td-mono td-s12">{item.serial}</span>
                  <span :if={@customer_return.shipment && not item.matched} class="td-sub td-s12">
                    <.td_badge tone="warning" label="Not on this shipment" />
                  </span>
                </td>
                <td>
                  <span class="td-mono">{item.batch_no}</span>
                  <span :if={item.expiry_date} class="td-sub td-s12">Exp {ThamaniDawaWeb.TimeFormat.date(item.expiry_date)}</span>
                </td>
                <td class="is-num">{item.quantity}</td>
                <td>
                  <%= if @customer_return.status == :received do %>
                    <form
                      id={"condition-form-#{item.id}"}
                      class="[&>div]:mb-0"
                      phx-value-item_id={item.id}
                      phx-value-customer_return_id={@customer_return.id}
                    >
                      <.input
                        type="select"
                        id={"condition-#{item.id}"}
                        name="condition"
                        value={item.condition}
                        options={Enum.map(CustomerReturnItem.conditions(), &{Phoenix.Naming.humanize(&1), &1})}
                        prompt="Needs a condition"
                        phx-change="set_condition"
                      />
                    </form>
                  <% else %>
                    {(item.condition && Phoenix.Naming.humanize(item.condition)) || "—"}
                  <% end %>
                </td>
                <td class="td-row-actions">
                  <button
                    :if={@customer_return.status == :draft}
                    type="button"
                    class="td-icon-btn"
                    phx-click="remove_item"
                    phx-value-item_id={item.id}
                    phx-value-customer_return_id={@customer_return.id}
                    aria-label="Remove"
                    title="Remove"
                  >
                    <.td_icon name="trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <div :if={@customer_return.status == :draft} class="flex items-center justify-end gap-3">
        <p
          :if={@customer_return.items == []}
          id="mark-received-needs-items"
          class="text-xs font-medium text-amber-800"
        >
          <%= if @customer_return.shipment do %>
            Click "Came back" on a pack above before marking this return received.
          <% else %>
            Add at least one item above before marking this return received.
          <% end %>
        </p>
        <.button
          variant="primary"
          type="button"
          phx-click="mark_received"
          phx-value-id={@customer_return.id}
          disabled={@customer_return.items == []}
        >
          Mark received
        </.button>
      </div>
      <div
        :if={@customer_return.status == :received}
        class="flex items-center justify-end gap-3"
      >
        <p
          :if={Enum.any?(@customer_return.items, &is_nil(&1.condition))}
          id="mark-inspected-needs-conditions"
          class="text-xs font-medium text-amber-800"
        >
          Set a condition for every item above before marking this return inspected.
        </p>
        <.button
          variant="primary"
          type="button"
          phx-click="mark_inspected"
          phx-value-id={@customer_return.id}
          disabled={Enum.any?(@customer_return.items, &is_nil(&1.condition))}
        >
          Mark inspected
        </.button>
      </div>
      <div class="flex justify-end gap-3">
        <.td_button
          :if={@customer_return.status == :inspected}
          id="open-complete-return"
          variant="primary"
          glyph="check"
          label="Complete return"
          phx-click={show_modal("complete-return-modal")}
        />
      </div>
      <.modal
        :if={@customer_return.status == :inspected}
        id="complete-return-modal"
        size="confirm"
        title={"Inspection done. Complete return ##{@customer_return.id}?"}
        subtitle="You can complete it now or later from this page."
      >
        <dl class="td-kv-list">
          <div :for={{condition, units} <- condition_totals(@customer_return.items)}>
            <dt>{Phoenix.Naming.humanize(condition)}</dt>
            <dd>{units} units</dd>
          </div>
        </dl>
        <:footer>
          <.td_button type="button" label="Not yet" phx-click={hide_modal("complete-return-modal")} />
          <.td_button
            id="confirm-complete-return"
            variant="primary"
            label="Complete return"
            phx-click={JS.push("complete", value: %{id: to_string(@customer_return.id)}) |> hide_modal("complete-return-modal")}
          />
        </:footer>
      </.modal>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path="/distributor/customer-returns"
    >
      <%= if @live_action == :show do %>
        <div class="td-recipe td-detail-page" id="customer-return-page">
          <.td_back_link
            id="customer-return-back"
            to={@return_to}
            label={ThamaniDawaWeb.ReturnTo.label(@return_to, "Back to Customer returns")}
          />
          <header class="td-idh">
            <div class="td-idh-text">
              <h1 class="td-idh-title">
                <span>Return #{@customer_return.id}</span>
                <.status_badge status={@customer_return.status} />
              </h1>
              <p class="td-idh-sub">
                {@customer_return.customer.name} · {@customer_return.site.name} · {status_message(@customer_return.status)}
              </p>
            </div>
          </header>
          <section class="td-card" id="customer-return-summary">
            <dl class="td-kv-grid is-pad is-6">
              <div class="td-kv">
                <dt class="td-kv-label">Customer</dt>
                <dd class="td-kv-value">{@customer_return.customer.name}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Customer GLN</dt>
                <dd class="td-kv-value td-mono">{@customer_return.customer.gln || "—"}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Shipment</dt>
                <dd class="td-kv-value">
                  <.link
                    :if={@customer_return.shipment}
                    navigate={ThamaniDawaWeb.ReturnTo.with_query(~p"/distributor/shipments/#{@customer_return.shipment.id}", "/distributor/customer-returns/#{@customer_return.id}")}
                  >
                    {@customer_return.shipment.order_number || @customer_return.shipment.reference}
                  </.link>
                  <span :if={@customer_return.shipment} class="td-sub td-s12">{@customer_return.shipment.reference}</span>
                  <span :if={!@customer_return.shipment}>—</span>
                </dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Reason</dt>
                <dd class="td-kv-value">{reason_label(@customer_return.reason)}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Items</dt>
                <dd class="td-kv-value">{length(@customer_return.items)}</dd>
              </div>
              <div class="td-kv">
                <dt class="td-kv-label">Created (EAT)</dt>
                <dd class="td-kv-value">{ThamaniDawaWeb.TimeFormat.datetime(@customer_return.inserted_at)}</dd>
              </div>
            </dl>
          </section>
        </div>
        <section id="customer-return-detail" class="mt-5 rounded-2xl ff-surface-card p-5 sm:p-6">
          <.return_panel customer_return={@customer_return} products={@products} />
        </section>
      <% else %>
        <div class="td-recipe td-list-page">
          <.td_page_header
            title="Customer returns"
            subtitle="Stock your customers send back. Receive it, inspect each item, then complete the return."
          >
            <:actions>
              <.td_button id="new-customer-return" variant="primary" glyph="plus" patch={~p"/distributor/customer-returns/new"} label="New customer return" />
            </:actions>
          </.td_page_header>
        </div>

        <.modal
          :if={@live_action == :new}
          id="customer-return-modal"
          show
          on_cancel={JS.patch(~p"/distributor/customer-returns")}
          title="New customer return"
          subtitle="Pick the customer and, if you can, the shipment it came from."
        >
          <.td_segmented>
            <.td_segment
              id="return-source-shipment"
              label="From a shipment"
              active={@return_source == "shipment"}
              phx-click="switch_return_source"
              phx-value-source="shipment"
            />
            <.td_segment
              id="return-source-customer"
              label="No shipment on record"
              active={@return_source == "customer"}
              phx-click="switch_return_source"
              phx-value-source="customer"
            />
          </.td_segmented>
          <form
            :if={@return_source == "shipment" and is_nil(@selected_shipment)}
            id="shipment-search-form"
            phx-change="search_shipment"
            class="mb-4"
          >
            <.input
              type="text"
              name="query"
              value={@shipment_query}
              label="Find the shipment"
              placeholder="Order number, shipment reference, SSCC, or serial"
              phx-debounce="300"
            />
            <div
              :if={@shipment_matches != []}
              id="shipment-matches"
              class="mt-1 overflow-hidden rounded-lg border border-thamani-stone bg-td-surface"
            >
              <button
                :for={shipment <- @shipment_matches}
                type="button"
                id={"shipment-match-#{shipment.id}"}
                phx-click="select_shipment"
                phx-value-id={shipment.id}
                class="block w-full border-b border-thamani-stone px-3 py-2 text-left last:border-b-0 hover:bg-thamani-canvas"
              >
                <span class="block text-sm font-semibold text-thamani-forest">
                  {shipment.order_number}
                </span>
                <span class="block text-xs text-thamani-pewter">
                  {shipment.destination_company || shipment.destination_gln} · {shipment_left_on(
                    shipment
                  )}
                </span>
              </button>
            </div>
            <p
              :if={String.length(@shipment_query) >= 2 and @shipment_matches == []}
              id="shipment-matches-empty"
              class="mt-2 text-sm text-thamani-pewter"
            >
              No shipment matches that.
            </p>
          </form>
          <.form
            for={@form}
            id="customer-return-form"
            phx-submit="save"
            phx-change="sync_return_form"
          >
            <div
              :if={@selected_shipment}
              id="selected-shipment"
              class="mb-3 rounded-lg bg-thamani-canvas px-3 py-2 text-sm"
            >
              <p class="font-semibold text-thamani-forest">
                {@selected_shipment.order_number} · {@selected_shipment.reference}
              </p>
              <p class="text-thamani-pewter">
                Customer {@selected_shipment.destination_company || @selected_shipment.destination_gln}
              </p>
              <p
                :if={different_origin?(@sites, @current_scope, @selected_shipment)}
                id="return-origin-warning"
                class="mt-1 text-xs font-semibold text-amber-800"
              >
                This shipment left a different warehouse. The return is recorded at {locked_site(
                  @sites,
                  @current_scope
                ).name}.
              </p>
            </div>
            <div :if={@return_source == "customer"} class="mb-3">
              <.input
                id="return-customer-name"
                type="text"
                name="customer_name"
                value={@customer_query}
                label="Customer"
                placeholder="Who sent this stock back"
                errors={if(@customer_name_error, do: [@customer_name_error], else: [])}
                phx-debounce="300"
                required
              />
              <div
                :if={@customer_matches != []}
                id="customer-matches"
                class="mt-1 overflow-hidden rounded-lg border border-thamani-stone bg-td-surface"
              >
                <button
                  :for={customer <- @customer_matches}
                  type="button"
                  id={"customer-match-#{customer.id}"}
                  phx-click="select_customer"
                  phx-value-id={customer.id}
                  class="block w-full border-b border-thamani-stone px-3 py-2 text-left last:border-b-0 hover:bg-thamani-canvas"
                >
                  <span class="block text-sm font-semibold text-thamani-forest">{customer.name}</span>
                  <span :if={customer.gln} class="block text-xs text-thamani-pewter">
                    GLN {customer.gln}
                  </span>
                </button>
              </div>
              <p
                :if={
                  String.length(@customer_query) >= 2 and @customer_matches == [] and
                    is_nil(@selected_customer)
                }
                id="customer-matches-empty"
                class="mt-2 text-sm text-thamani-pewter"
              >
                No saved customer matches. This name will be added when you start the return.
              </p>
              <.input
                id="return-customer-gln"
                type="text"
                name="customer_gln"
                value={@customer_gln}
                label="GLN"
                placeholder="13-digit GLN, if it is on the paperwork"
                errors={if(@customer_gln_error, do: [@customer_gln_error], else: [])}
                phx-debounce="300"
              />
            </div>
            <%= if site = locked_site(@sites, @current_scope) do %>
              <.input field={@form[:site_id]} type="hidden" value={site.id} />
            <% else %>
              <.input
                field={@form[:site_id]}
                type="select"
                label="Warehouse"
                options={Enum.map(@sites, &{&1.name, &1.id})}
                prompt="Choose a warehouse"
                required
              />
            <% end %>
            <div
              id="return-documents"
              class="mb-3 rounded-xl border border-dashed border-td-hairline bg-td-surface px-3 py-3"
              phx-drop-target={@uploads.return_documents.ref}
            >
              <div class="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p class="text-sm font-medium text-thamani-forest">Related documents</p>
                  <p class="mt-1 text-xs text-thamani-pewter">
                    PDF, JPG, or PNG, up to 5MB each. Up to 8 files.
                  </p>
                </div>
                <label class="group inline-flex cursor-pointer items-center rounded-full border border-thamani-forest bg-td-surface px-4 py-1.5 text-xs font-semibold transition-colors hover:bg-thamani-forest">
                  <span class="text-thamani-forest group-hover:text-thamani-on-accent">Choose files</span>
                  <.live_file_input upload={@uploads.return_documents} class="sr-only" />
                </label>
              </div>
              <div :if={@uploads.return_documents.entries != []} class="mt-3 space-y-2">
                <div
                  :for={entry <- @uploads.return_documents.entries}
                  id={"return-document-#{entry.ref}"}
                  class="rounded-lg border border-thamani-stone bg-thamani-canvas px-3 py-2"
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="truncate text-sm text-thamani-forest" title={entry.client_name}>
                      {entry.client_name}
                    </span>
                    <button
                      type="button"
                      phx-click="cancel_return_upload"
                      phx-value-ref={entry.ref}
                      class="shrink-0 text-xs font-medium text-red-700"
                    >
                      Remove
                    </button>
                  </div>
                  <p
                    :for={err <- upload_errors(@uploads.return_documents, entry)}
                    class="mt-1 text-xs text-red-700"
                  >
                    {upload_error_to_string(err)}
                  </p>
                </div>
              </div>
              <p
                :for={err <- upload_errors(@uploads.return_documents)}
                class="mt-2 text-xs text-red-700"
              >
                {upload_error_to_string(err)}
              </p>
              <p :if={@document_error} id="return-documents-error" class="mt-2 text-sm text-red-700">
                {@document_error}
              </p>
            </div>
            <.input
              field={@form[:reason]}
              type="select"
              label="Reason"
              options={Enum.map(CustomerReturn.reasons(), &{Phoenix.Naming.humanize(&1), &1})}
              prompt="Choose a reason"
            />
            <.input field={@form[:notes]} type="textarea" label="Notes" rows="3" />
            <p
              :if={@return_source == "shipment" and is_nil(@selected_shipment)}
              id="return-needs-shipment"
              class="mt-3 text-xs font-medium text-amber-800"
            >
              Select a shipment from the matches above to continue.
            </p>
            <.button
              variant="primary"
              class="mt-3 w-full"
              disabled={@return_source == "shipment" and is_nil(@selected_shipment)}
            >
              Start return
            </.button>
          </.form>
        </.modal>

        <div class="td-list-page" id="customer-returns-page">
          <nav class="td-tabs" aria-label="Customer return status">
            <.td_tab id="cr-tab-all" label="All" count={length(@returns)} active={@cr_status == ""} patch={~p"/distributor/customer-returns"} />
            <.td_tab
              :for={{status, label} <- [{"draft", "Draft"}, {"received", "Received"}, {"inspected", "Inspected"}, {"completed", "Completed"}]}
              id={"cr-tab-#{status}"}
              label={label}
              count={Enum.count(@returns, &(Atom.to_string(&1.status) == status))}
              active={@cr_status == status}
              patch={~p"/distributor/customer-returns?#{%{status: status}}"}
            />
          </nav>
          <% shown = Enum.filter(@returns, &(@cr_status == "" or Atom.to_string(&1.status) == @cr_status)) %>
          <div :if={shown == []} id="customer-returns-empty" class="td-pad td-empty-wrap">
            <div class="td-card td-empty-card">
              <%= if @returns == [] do %>
                <p class="td-empty-title">No customer returns yet</p>
                <p class="td-note">Start a return when a customer sends stock back.</p>
                <.td_button id="customer-returns-empty-new" variant="primary" patch={~p"/distributor/customer-returns/new"} label="New customer return" />
              <% else %>
                <p class="td-empty-title">Nothing here</p>
                <p class="td-note">No returns are at this step right now.</p>
                <.td_button patch={~p"/distributor/customer-returns"} label="Show all" />
              <% end %>
            </div>
          </div>
          <div class="td-list-table" hidden={shown == []}>
            <table class="td-rows">
              <thead>
                <tr>
                  <th>Return</th>
                  <th>Customer</th>
                  <th>From order</th>
                  <th>Reason</th>
                  <th class="is-num">Items</th>
                  <th>Status</th>
                  <th>Updated (EAT)</th>
                </tr>
              </thead>
              <tbody id="customer-returns">
                <tr
                  :for={customer_return <- shown}
                  id={"returns-#{customer_return.id}"}
                  class="is-link"
                  phx-click={open_return(customer_return)}
                >
                  <td><b>Return #{customer_return.id}</b><span class="td-sub td-s12">{customer_return.site.name}</span></td>
                  <td>{customer_return.customer.name}</td>
                  <td>{(customer_return.shipment && (customer_return.shipment.order_number || customer_return.shipment.reference)) || "—"}</td>
                  <td>{reason_label(customer_return.reason)}</td>
                  <td class="is-num">{item_count(customer_return.items)}</td>
                  <td><.status_badge status={customer_return.status} /></td>
                  <td>{ThamaniDawaWeb.TimeFormat.datetime(customer_return.updated_at)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <.modal
          :if={customer_return = detail_return(@returns, @detail_id)}
          id="customer-return-detail-modal"
          show
          on_cancel={JS.push("close_detail")}
        >
          <.return_panel customer_return={customer_return} products={@products} heading={true} />
        </.modal>
      <% end %>
    </Layouts.distributor_shell>
    """
  end
end
