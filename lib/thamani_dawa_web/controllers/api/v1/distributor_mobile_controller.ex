defmodule ThamaniDawaWeb.Api.V1.DistributorMobileController do
  @moduledoc """
  The distributor packing app: mobile users sign in with a username and
  4-digit PIN, claim a draft shipment, add shippers, scan units into them,
  and submit the shipment for a distributor admin to approve on the web.

  Every action calls the `ThamaniDawa.Distributor` mobile functions the web
  portal is built on; this controller only translates JSON.
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.MobileAuth
  alias ThamaniDawa.Distributor.Shipment
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Plugs.ApiAuth

  def login(conn, params) do
    meta = %{device_id: params["device_id"], ip: client_ip(conn)}

    case MobileAuth.login(params["username"], params["pin"], meta) do
      {:ok, tokens} -> json(conn, Serializer.mobile_session(tokens))
      {:error, reason} -> error(conn, reason)
    end
  end

  def refresh(conn, params) do
    case MobileAuth.refresh(params["refresh_token"]) do
      {:ok, tokens} -> json(conn, Serializer.mobile_session(tokens))
      {:error, reason} -> error(conn, reason)
    end
  end

  def logout(conn, _params) do
    :ok = MobileAuth.logout(ApiAuth.bearer(conn))
    send_resp(conn, 204, "")
  end

  def me(conn, _params) do
    Response.data(conn, Serializer.mobile_user(mobile_user(conn)))
  end

  def shipments(conn, params) do
    {page, per_page} = Params.page(params)
    opts = %{"status" => params["status"], "page" => page, "per_page" => per_page}
    shipments = Distributor.list_shipments_for_mobile_user(mobile_user(conn), opts)
    total = Distributor.count_shipments_for_mobile_user(mobile_user(conn), opts)
    page(conn, shipments, page, per_page, total)
  end

  # Draft shipments matching an order number that this packer can claim.
  def search(conn, params) do
    {page, per_page} = Params.page(params)
    opts = %{"order_number" => params["order_number"], "page" => page, "per_page" => per_page}
    shipments = Distributor.search_shipments_for_mobile_user(mobile_user(conn), opts)
    total = Distributor.count_search_shipments_for_mobile_user(mobile_user(conn), opts)
    page(conn, shipments, page, per_page, total)
  end

  def show(conn, %{"id" => id}) do
    with_id(conn, id, &Distributor.get_shipment_for_mobile_user(mobile_user(conn), &1))
  end

  def select(conn, %{"id" => id}) do
    with_id(conn, id, &reload_after(Distributor.select_shipment(mobile_user(conn), &1), conn))
  end

  def release(conn, %{"id" => id}) do
    with_id(conn, id, &reload_after(Distributor.release_shipment(mobile_user(conn), &1), conn))
  end

  def create_shipper(conn, %{"id" => id} = params) do
    with_id(
      conn,
      id,
      &reload_after(Distributor.create_shipper(mobile_user(conn), &1, params), conn)
    )
  end

  def update_shipper(conn, %{"shipper_id" => shipper_id} = params) do
    with_id(
      conn,
      shipper_id,
      &reload_after(Distributor.update_shipper(mobile_user(conn), &1, params), conn)
    )
  end

  def delete_shipper(conn, %{"shipper_id" => shipper_id}) do
    with_id(
      conn,
      shipper_id,
      &reload_after(Distributor.delete_shipper(mobile_user(conn), &1), conn)
    )
  end

  def scan(conn, %{"shipper_id" => shipper_id} = params) do
    with_id(conn, shipper_id, &scanned(Distributor.scan_item(mobile_user(conn), &1, params)))
  end

  def delete_item(conn, %{"item_id" => item_id}) do
    with_id(conn, item_id, &reload_after(Distributor.delete_item(mobile_user(conn), &1), conn))
  end

  def move_item(conn, %{"item_id" => item_id} = params) do
    case Params.integer(params["shipper_id"]) do
      {:ok, target} ->
        with_id(
          conn,
          item_id,
          &reload_after(Distributor.move_item(mobile_user(conn), &1, target), conn)
        )

      :error ->
        error(conn, :bad_request)
    end
  end

  def submit(conn, %{"id" => id}) do
    with_id(conn, id, &reload_after(Distributor.submit_shipment(mobile_user(conn), &1), conn))
  end

  def reopen(conn, %{"id" => id}) do
    with_id(conn, id, &reload_after(Distributor.reopen_shipment(mobile_user(conn), &1), conn))
  end

  # After a change, answer with the whole shipment so the app redraws once.
  defp reload_after({status, %Shipment{id: id}}, conn) when status in [:ok, :unchanged],
    do: reload(conn, id)

  defp reload_after({:ok, %{shipment_id: id}}, conn), do: reload(conn, id)
  defp reload_after(other, _conn), do: other

  defp scanned({:ok, item}), do: {:created, Serializer.shipment_item(item)}
  defp scanned(other), do: other

  defp mobile_user(conn), do: conn.assigns.mobile_user

  defp page(conn, shipments, page, per_page, total) do
    Response.page(conn, Enum.map(shipments, &Serializer.shipment/1), %{
      page: page,
      per_page: per_page,
      total: total,
      total_pages: if(total == 0, do: 0, else: div(total + per_page - 1, per_page))
    })
  end

  defp reload(conn, id), do: Distributor.get_shipment_for_mobile_user(mobile_user(conn), id)

  # Several context functions look rows up with `!`; an id that is not the
  # mobile user's own is reported as not found.
  defp with_id(conn, raw_id, fun) do
    result =
      case Params.integer(raw_id) do
        {:ok, id} -> fun.(id)
        :error -> {:error, :not_found}
      end

    case result do
      {:ok, shipment} -> Response.data(conn, Serializer.shipment(shipment))
      {:created, body} -> Response.data(conn, body, 201)
      {:error, reason} -> error(conn, reason)
    end
  rescue
    Ecto.NoResultsError -> error(conn, :not_found)
  end

  defp client_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp error(conn, %Ecto.Changeset{} = changeset), do: Response.changeset(conn, changeset)

  defp error(conn, {:invalid, problems}) when is_list(problems) do
    Response.error(conn, 422, "shipment_invalid", "Fix these before submitting.", %{
      problems: Enum.map(problems, &problem/1)
    })
  end

  defp error(conn, {:invalid_state, status}) do
    Response.error(conn, 409, "invalid_state", "This shipment is #{status}.", %{status: status})
  end

  defp error(conn, {:invalid_scan, reason}),
    do:
      Response.error(conn, 422, "invalid_scan", scan_message(reason), %{
        reason: scan_reason(reason)
      })

  defp error(conn, {:invalid_scan, :gtin_not_found, gtin}) do
    Response.error(conn, 422, "invalid_scan", "No product has GTIN #{gtin}.", %{
      reason: "gtin_not_found",
      gtin: gtin
    })
  end

  defp error(conn, reason) when is_atom(reason) do
    case mobile_reason(reason) do
      {status, code, message} -> Response.error(conn, status, code, message)
      nil -> Response.reason(conn, reason)
    end
  end

  defp error(conn, reason), do: Response.reason(conn, reason)

  defp mobile_reason(:invalid_credentials),
    do: {401, "invalid_credentials", "Wrong username or PIN."}

  defp mobile_reason(:locked),
    do: {423, "locked", "Too many wrong PINs. Try again in 15 minutes."}

  defp mobile_reason(:rate_limited),
    do: {429, "rate_limited", "Too many sign-in attempts. Wait a few minutes."}

  defp mobile_reason(:inactive), do: {403, "account_inactive", "This account is disabled."}

  defp mobile_reason(:already_assigned),
    do: {409, "already_assigned", "Someone else is already packing this shipment."}

  defp mobile_reason(:not_assigned),
    do: {403, "not_assigned", "Select this shipment before changing it."}

  defp mobile_reason(:parsed_mismatch),
    do: {422, "parsed_mismatch", "The app's reading of this code does not match the server's."}

  defp mobile_reason(:invalid_shipper),
    do: {422, "invalid_shipper", "Pick a shipper in the same shipment."}

  defp mobile_reason(_reason), do: nil

  defp scan_reason({:unreadable, _detail}), do: "unreadable"
  defp scan_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp scan_reason(_reason), do: "invalid_scan"

  defp scan_message(:missing_data_matrix), do: "Send the scanned code as raw_data_matrix."
  defp scan_message(:missing_gtin), do: "This code has no GTIN."
  defp scan_message(:missing_serial), do: "This code has no serial number."
  defp scan_message(_reason), do: "This code could not be read."

  defp problem(%{code: code, message: message}), do: %{code: to_string(code), message: message}
  defp problem(other), do: %{code: "invalid", message: inspect(other)}
end
