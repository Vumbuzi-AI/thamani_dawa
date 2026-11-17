defmodule ThamaniDawaWeb.Api.V1.PatientController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits
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

  plug RequirePortal, :pharmacy when action in [:index, :show, :create]
  plug RequireSite when action in [:index, :show, :create]
  plug RequireIdempotency when action in [:create]

  def index(conn, params) do
    {page, per_page} = Params.page(params)

    result =
      Patients.list_patients_paginated(org_id(conn), page,
        search: params["search"],
        page_size: per_page
      )

    Response.page(conn, Enum.map(result.entries, &Serializer.patient/1), Params.scrivener(result))
  end

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, patient} <- fetch(fn -> Patients.get_patient!(org_id(conn), id) end) do
      visits = PatientVisits.list_patient_visits_for_patient(org_id(conn), patient.id)

      Response.data(conn, %{
        patient: Serializer.patient(patient),
        visits:
          Enum.map(visits, fn visit ->
            %{
              id: visit.id,
              site_id: visit.site_id,
              visit_type: visit.visit_type,
              inserted_at: visit.inserted_at
            }
            |> Serializer.stats()
          end)
      })
    end
  end

  def create(conn, params) do
    idempotent(conn, fn ->
      case Patients.create_patient(org_id(conn), Params.drop_tenant(params)) do
        {:ok, patient} -> {:ok, 201, %{data: Serializer.patient(patient)}}
        {:error, reason} -> {:error, reason}
      end
    end)
  end
end
