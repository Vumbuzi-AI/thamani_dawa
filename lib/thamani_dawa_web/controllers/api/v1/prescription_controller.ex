defmodule ThamaniDawaWeb.Api.V1.PrescriptionController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Patients
  alias ThamaniDawa.Payments
  alias ThamaniDawa.Prescriptions
  alias ThamaniDawa.Repo
  alias ThamaniDawaWeb.Api.Access
  alias ThamaniDawaWeb.Api.FallbackController
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal
  alias ThamaniDawaWeb.Plugs.RequireSite

  import Helpers

  action_fallback FallbackController

  plug RequirePortal, :pharmacy
  plug RequireSite
  plug RequireIdempotency when action in [:create, :dispense, :pay]

  def index(conn, params) do
    {page, per_page} = Params.page(params)
    site = site_id(conn)

    prescriptions =
      conn
      |> org_id()
      |> Prescriptions.list_prescriptions()
      |> Enum.filter(&(&1.site_id == site))

    {entries, meta} = Params.slice(prescriptions, page, per_page)
    Response.page(conn, Enum.map(entries, &Serializer.prescription/1), meta)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, prescription} <- fetch_for_site(conn, id) do
      Response.data(conn, Serializer.prescription(preload(prescription, :items)))
    end
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      attrs = Params.drop_tenant(params)

      result =
        cond do
          is_map(attrs["patient"]) ->
            create_with_new_patient(conn, attrs)

          patient_id = attrs["patient_id"] ->
            create_for_patient(conn, attrs, patient_id)

          true ->
            Prescriptions.create_prescription_without_patient(
              org_id(conn),
              site_id(conn),
              actor_id(conn),
              attrs
            )
        end

      case result do
        {:ok, prescription} ->
          {:ok, 201, %{data: Serializer.prescription(preload(prescription, :items))}}

        {:error, reason} ->
          {:error, reason}

        :error ->
          {:error, :bad_request}
      end
    end)
  end

  def dispense(conn, %{"id" => id, "item_id" => item_id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, _prescription} <- fetch_for_site(conn, id),
           {:ok, item_id} <- parse_id(item_id),
           {:ok, quantity} <- Params.integer(params["quantity"]) do
        dispense_quantity(conn, item_id, quantity, params["raw"])
      else
        :error -> {:error, :bad_request}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def verify(conn, %{"id" => id, "item_id" => item_id} = params) do
    with {:ok, id} <- parse_id(id),
         {:ok, _prescription} <- fetch_for_site(conn, id),
         {:ok, item_id} <- parse_id(item_id),
         gtin when is_binary(gtin) <- params["gtin"],
         {:ok, item} <- Prescriptions.verify_dispensed_item(org_id(conn), item_id, gtin) do
      Response.data(conn, Serializer.prescription_item(item))
    else
      nil -> {:error, :bad_request}
      false -> {:error, :bad_request}
      :error -> {:error, :bad_request}
      {:error, reason} -> {:error, reason}
    end
  end

  def pay(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, id} <- parse_id(id),
           {:ok, _prescription} <- fetch_for_site(conn, id),
           {:ok, payment} <-
             Payments.create_payment(org_id(conn), %{
               "prescription_id" => id,
               "amount" => money(params["amount"]),
               "payment_type" => params["payment_type"],
               "provider_reference" => params["provider_reference"]
             }) do
        {:ok, 201, %{data: Serializer.payment(payment)}}
      end
    end)
  end

  defp create_for_patient(conn, attrs, patient_id) do
    case Params.integer(patient_id) do
      {:ok, patient_id} ->
        Prescriptions.create_prescription_for_patient(
          org_id(conn),
          patient_id,
          site_id(conn),
          actor_id(conn),
          attrs
        )

      :error ->
        :error
    end
  end

  defp dispense_quantity(conn, item_id, quantity, raw) when is_binary(raw) and raw != "" do
    conn
    |> org_id()
    |> Prescriptions.dispense_scanned_item(item_id, actor_id(conn), quantity, raw)
    |> dispense_result()
  end

  defp dispense_quantity(conn, item_id, quantity, _raw) do
    conn
    |> org_id()
    |> Prescriptions.dispense_item(item_id, actor_id(conn), quantity)
    |> dispense_result()
  end

  defp dispense_result({:ok, item}), do: {:ok, 200, %{data: Serializer.prescription_item(item)}}
  defp dispense_result({:error, reason}), do: {:error, reason}

  defp create_with_new_patient(conn, attrs) do
    patient_attrs = Params.drop_tenant(attrs["patient"])

    Repo.transaction(fn ->
      with {:ok, patient} <- Patients.create_patient(org_id(conn), patient_attrs),
           {:ok, prescription} <-
             Prescriptions.create_prescription_for_patient(
               org_id(conn),
               patient.id,
               site_id(conn),
               actor_id(conn),
               attrs
             ) do
        prescription
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp fetch_for_site(conn, id) do
    with {:ok, prescription} <- fetch(fn -> Prescriptions.get_prescription!(org_id(conn), id) end) do
      prescription = preload(prescription, :patient_visit)
      site_id = prescription.patient_visit && prescription.patient_visit.site_id

      if Access.same_site?(scope(conn), site_id) do
        {:ok, prescription}
      else
        {:error, :not_found}
      end
    end
  end

  defp money(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact, decimals: 2])

  defp money(value), do: value
end
