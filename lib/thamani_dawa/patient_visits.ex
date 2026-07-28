defmodule ThamaniDawa.PatientVisits do
  @moduledoc """
  Patient visits link a patient to a site (and the staff member who served
  them) for a single encounter — lab orders and prescriptions can optionally
  be tied back to the visit they arose from.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Patients
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Repo

  @doc "Lists an organization's patient visits."
  def list_patient_visits(organization_id) do
    Repo.all(from pv in PatientVisit, where: pv.organization_id == ^organization_id)
  end

  @doc """
  Lists an organization's patient visits with pagination. Each returned
  struct has virtual `patient_name`, `patient_phone`, `site_name`, and
  `user_name` fields populated from the associated patient/site/user rows,
  for display and for `SiteScoping.for_current_site/2` to filter on `site_id`.

  Pass `visit_type: :lab` or `visit_type: :pharmacy` in `opts` to restrict
  the listing to one visit type; omit it to list all visit types.
  """
  def list_patient_visits_paginated(organization_id, page \\ 1, opts \\ []) do
    query =
      from(pv in PatientVisit,
        join: pat in ThamaniDawa.Patients.Patient,
        on: pat.id == pv.patient_id,
        join: s in ThamaniDawa.Sites.Site,
        on: s.id == pv.site_id,
        join: u in ThamaniDawa.Accounts.User,
        on: u.id == pv.user_id,
        where: pv.organization_id == ^organization_id,
        select: %{
          pv
          | patient_name: pat.full_name,
            patient_phone: pat.phone,
            site_name: s.name,
            user_name: u.name
        },
        order_by: [desc: pv.inserted_at]
      )

    query =
      case Keyword.get(opts, :visit_type) do
        nil -> query
        visit_type -> where(query, [pv], pv.visit_type == ^visit_type)
      end

    query =
      case Keyword.get(opts, :site_id) do
        nil -> query
        site_id -> where(query, [pv], pv.site_id == ^site_id)
      end

    query =
      case Keyword.get(opts, :search) do
        nil ->
          query

        "" ->
          query

        search ->
          pattern = "%#{String.trim(search)}%"

          from([pv, pat, s, u] in query,
            where: ilike(pat.full_name, ^pattern) or ilike(pat.phone, ^pattern)
          )
      end

    Repo.paginate(query, page: page)
  end

  @doc "Gets a single patient visit scoped to an organization. Raises if not found."
  def get_patient_visit!(organization_id, id) do
    Repo.get_by!(PatientVisit, id: id, organization_id: organization_id)
  end

  @doc """
  Lists all of a patient's visits (across every site), most recent first.
  Each returned struct has virtual `site_name` and `user_name` fields
  populated for display.
  """
  def list_patient_visits_for_patient(organization_id, patient_id) do
    Repo.all(
      from pv in PatientVisit,
        join: s in ThamaniDawa.Sites.Site,
        on: s.id == pv.site_id,
        join: u in ThamaniDawa.Accounts.User,
        on: u.id == pv.user_id,
        where: pv.organization_id == ^organization_id and pv.patient_id == ^patient_id,
        select: %{pv | site_name: s.name, user_name: u.name},
        order_by: [desc: pv.inserted_at]
    )
  end

  @doc "Creates a patient visit under the given organization."
  def create_patient_visit(organization_id, attrs) when is_integer(organization_id) do
    %PatientVisit{}
    |> PatientVisit.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc """
  Creates a new patient and a patient visit for that patient in a single
  transaction. Rolls back if either fails to prevent orphaned records.
  """
  def create_patient_visit_with_new_patient(organization_id, patient_attrs, visit_attrs)
      when is_integer(organization_id) do
    Repo.transaction(fn ->
      with {:ok, patient} <- Patients.create_patient(organization_id, patient_attrs),
           visit_attrs = Map.put(visit_attrs, :patient_id, patient.id),
           {:ok, visit} <- create_patient_visit(organization_id, visit_attrs) do
        visit
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
