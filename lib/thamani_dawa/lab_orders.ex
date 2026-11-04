defmodule ThamaniDawa.LabOrders do
  @moduledoc """
  Laboratory dispensing/testing workflow (§4.4, §9): a `lab_orders` header
  with one or more `lab_order_results` rows recording per-test results.
  `template_id` still exists on `lab_order_results` but there is currently no
  template-based computation — result values are stored as-is with no flag.
  Reagent draws against a site's own `batches` stock log are recorded in
  `lab_consumable_usage`.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Batches

  alias ThamaniDawa.LabOrders.{
    LabConsumableUsage,
    LabOrder,
    LabOrderResult,
    LabOrderResultAmendment,
    LabSpecimen,
    LabSpecimenResult
  }

  alias ThamaniDawa.LabTests.LabTest
  alias ThamaniDawa.Patients.Patient
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.PatientVisits.PatientVisit
  alias ThamaniDawa.Repo
  alias ThamaniDawa.ScanEvents

  ## Lab orders

  @doc "Lists an organization's lab orders."
  def list_lab_orders(organization_id) do
    Repo.all(from o in LabOrder, where: o.organization_id == ^organization_id)
  end

  @doc """
  Lists an organization's lab orders, preloaded with `patient_visit: :patient`
  (both scoped to the same organization) — for screens that display the
  patient's name per order without a separate lookup.
  """
  def list_lab_orders_with_patient(organization_id) do
    patient_query = from p in Patient, where: p.organization_id == ^organization_id

    patient_visit_query =
      from pv in PatientVisit,
        where: pv.organization_id == ^organization_id,
        preload: [patient: ^patient_query]

    Repo.all(
      from o in LabOrder,
        where: o.organization_id == ^organization_id,
        preload: [patient_visit: ^patient_visit_query]
    )
  end

  @doc "Gets a single lab order scoped to an organization. Raises if not found."
  def get_lab_order!(organization_id, id) do
    Repo.get_by!(LabOrder, id: id, organization_id: organization_id)
  end

  @doc "Creates a lab order header under the given organization."
  def create_lab_order(organization_id, attrs) when is_integer(organization_id) do
    %LabOrder{}
    |> LabOrder.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  @doc """
  Creates a lab order header together with its `lab_order_results`, all in
  one transaction (§9 "Lab order → completed result", step 1). Rolls back the
  header if any result fails to validate. Returns
  `{:ok, %{lab_order: lab_order, lab_order_results: results}}`.
  """
  def create_lab_order_with_results(organization_id, attrs, results_attrs)
      when is_integer(organization_id) and is_list(results_attrs) do
    Repo.transaction(fn ->
      with {:ok, lab_order} <- create_lab_order(organization_id, attrs),
           {:ok, results} <-
             create_lab_order_results(organization_id, lab_order.id, results_attrs) do
        %{lab_order: lab_order, lab_order_results: results}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Creates a patient visit, then a lab order header and its results, all in one
  transaction. If any step fails the entire transaction is rolled back — no
  orphaned visits or headers are left behind.
  """
  def create_lab_order_with_results(organization_id, attrs, results_attrs, visit_attrs)
      when is_integer(organization_id) and is_list(results_attrs) and is_map(visit_attrs) do
    Repo.transaction(fn ->
      with {:ok, visit} <- PatientVisits.create_patient_visit(organization_id, visit_attrs),
           {:ok, lab_order} <-
             create_lab_order(
               organization_id,
               Map.put(attrs, "patient_visit_id", visit.id)
             ),
           {:ok, results} <-
             create_lab_order_results(organization_id, lab_order.id, results_attrs) do
        %{lab_order: lab_order, lab_order_results: results}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_lab_order_results(organization_id, lab_order_id, results_attrs) do
    results_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case create_lab_order_result(organization_id, lab_order_id, attrs) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  ## Lab order results

  @doc "Gets a single lab order result scoped to an organization. Raises if not found."
  def get_lab_order_result!(organization_id, id) do
    Repo.get_by!(LabOrderResult, id: id, organization_id: organization_id)
  end

  @doc "Lists every lab order result in an organization (across all lab orders)."
  def list_lab_order_results(organization_id) do
    Repo.all(from r in LabOrderResult, where: r.organization_id == ^organization_id)
  end

  @doc """
  Lists a single lab order's results, preloaded with `lab_test`,
  `performed_by`, and `collected_by` — all scoped to the organization.
  """
  def list_lab_order_results_for_order(organization_id, lab_order_id) do
    lab_test_query = from t in LabTest, where: t.organization_id == ^organization_id
    user_query = from u in User, where: u.organization_id == ^organization_id

    Repo.all(
      from r in LabOrderResult,
        where: r.organization_id == ^organization_id,
        where: r.lab_order_id == ^lab_order_id,
        preload: [
          lab_test: ^lab_test_query,
          performed_by: ^user_query,
          collected_by: ^user_query,
          lab_specimen: [
            collected_by: ^user_query,
            received_by: ^user_query,
            rejected_by: ^user_query
          ]
        ]
    )
  end

  @doc "Creates a lab order result under the given lab order."
  def create_lab_order_result(organization_id, lab_order_id, attrs)
      when is_integer(organization_id) and is_integer(lab_order_id) do
    %LabOrderResult{}
    |> LabOrderResult.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:lab_order_id, lab_order_id)
    |> Repo.audited_insert()
  end

  @doc """
  Records sample collection for a result: sets the collected date, who
  collected it, any notes, and advances the result status to `:collected`.
  Also rolls up the parent order status in the same transaction.

  `attrs` may contain `"collection_date"` (ISO-8601 string) and
  `"collection_notes"` (free text). Both are optional.
  """
  def mark_sample_collected(organization_id, lab_order_result_id, user_id, attrs \\ %{}) do
    date = parse_collection_date(Map.get(attrs, "collection_date"))
    notes = Map.get(attrs, "collection_notes")

    Repo.transaction(fn ->
      lab_order_result = get_lab_order_result!(organization_id, lab_order_result_id)

      with {:ok, updated} <-
             lab_order_result
             |> Ecto.Changeset.change(
               status: :collected,
               sample_collected_on: date,
               collected_by_id: user_id,
               collection_notes: notes
             )
             |> Repo.audited_update(),
           {:ok, _specimen} <-
             record_specimen_collected(organization_id, updated, user_id, date, notes),
           {:ok, _} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Collects ONE specimen that covers multiple lab-order results (medic-style):
  inserts the specimen, links it to each selected result via
  `lab_specimen_results`, advances those results to `:collected`, and rolls
  up the parent order status — all in one transaction. `attrs` may carry
  `"specimen_type"`, `"collection_date"` (ISO-8601), and `"collection_notes"`.
  """
  def collect_specimen(organization_id, lab_order_id, result_ids, user_id, attrs \\ %{})
      when is_integer(organization_id) and is_integer(lab_order_id) and is_list(result_ids) do
    specimen_type = Map.get(attrs, "specimen_type")
    date = parse_collection_date(Map.get(attrs, "collection_date"))
    notes = Map.get(attrs, "collection_notes")

    Repo.transaction(fn ->
      results =
        Repo.all(
          from r in LabOrderResult,
            where:
              r.organization_id == ^organization_id and r.lab_order_id == ^lab_order_id and
                r.id in ^result_ids
        )

      with :ok <- ensure_results_present(results, result_ids),
           {:ok, specimen} <-
             insert_collected_specimen(organization_id, specimen_type, user_id, date, notes),
           :ok <- link_specimen_to_results(organization_id, specimen, results),
           :ok <- mark_results_collected(results, user_id, date, notes),
           {:ok, _} <- recompute_lab_order_status(organization_id, lab_order_id) do
        specimen
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ensure_results_present([], _ids), do: {:error, :no_results_selected}

  defp ensure_results_present(results, ids) do
    if length(results) == length(Enum.uniq(ids)), do: :ok, else: {:error, :invalid_results}
  end

  defp insert_collected_specimen(organization_id, specimen_type, user_id, date, notes) do
    {:ok, collected_at} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")

    %LabSpecimen{}
    |> LabSpecimen.changeset(%{
      specimen_number: generate_specimen_number(System.unique_integer([:positive])),
      specimen_type: specimen_type,
      status: :collected,
      collected_by_id: user_id,
      collected_at: collected_at,
      notes: notes
    })
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  defp link_specimen_to_results(organization_id, specimen, results) do
    Enum.reduce_while(results, :ok, fn result, :ok ->
      case %LabSpecimenResult{}
           |> LabSpecimenResult.changeset(%{
             lab_specimen_id: specimen.id,
             lab_order_result_id: result.id,
             organization_id: organization_id
           })
           |> Repo.audited_insert() do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp mark_results_collected(results, user_id, date, notes) do
    Enum.reduce_while(results, :ok, fn result, :ok ->
      case result
           |> Ecto.Changeset.change(
             status: :collected,
             sample_collected_on: date,
             collected_by_id: user_id,
             collection_notes: notes
           )
           |> Repo.audited_update() do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Results on an order still awaiting collection (status `:pending`), with their test preloaded."
  def list_collectable_results(organization_id, lab_order_id) do
    Repo.all(
      from r in LabOrderResult,
        where:
          r.organization_id == ^organization_id and r.lab_order_id == ^lab_order_id and
            r.status == :pending,
        order_by: [asc: r.id],
        preload: [:lab_test]
    )
  end

  @doc "Specimens collected for an order, preloaded with the tests each one covers and its collector."
  def list_specimens_for_order(organization_id, lab_order_id) do
    user_query = from u in User, where: u.organization_id == ^organization_id
    lab_test_query = from t in LabTest, where: t.organization_id == ^organization_id
    result_query = from r in LabOrderResult, preload: [lab_test: ^lab_test_query]

    specimen_ids =
      Repo.all(
        from s in LabSpecimen,
          join: sr in LabSpecimenResult,
          on: sr.lab_specimen_id == s.id,
          join: r in LabOrderResult,
          on: r.id == sr.lab_order_result_id,
          where: s.organization_id == ^organization_id and r.lab_order_id == ^lab_order_id,
          distinct: true,
          select: s.id
      )

    Repo.all(
      from s in LabSpecimen,
        where: s.id in ^specimen_ids,
        order_by: [desc: s.collected_at],
        preload: [
          collected_by: ^user_query,
          received_by: ^user_query,
          rejected_by: ^user_query,
          lab_order_results: ^result_query
        ]
    )
  end

  ## Specimen traceability (§4.6)

  @doc "Gets a single specimen scoped to an organization. Raises if not found."
  def get_specimen!(organization_id, id) do
    Repo.get_by!(LabSpecimen, id: id, organization_id: organization_id)
  end

  # Creates the specimen row the first time a result's sample is collected,
  # or re-marks it `:collected` if it had been rejected and is being
  # re-collected. One specimen per result (enforced by a unique index).
  defp record_specimen_collected(organization_id, lab_order_result, user_id, _date, notes) do
    collected_at = DateTime.utc_now(:second)

    case Repo.get_by(LabSpecimen, lab_order_result_id: lab_order_result.id) do
      nil ->
        %LabSpecimen{}
        |> LabSpecimen.changeset(%{
          specimen_number: generate_specimen_number(lab_order_result.id),
          specimen_type: lab_order_result.sample_type,
          status: :collected,
          collected_by_id: user_id,
          collected_at: collected_at,
          notes: notes,
          lab_order_result_id: lab_order_result.id
        })
        |> Ecto.Changeset.put_change(:organization_id, organization_id)
        |> Repo.audited_insert()

      specimen ->
        specimen
        |> LabSpecimen.changeset(%{
          status: :collected,
          collected_by_id: user_id,
          collected_at: collected_at,
          notes: notes
        })
        |> Repo.audited_update()
    end
  end

  defp generate_specimen_number(lab_order_result_id) do
    "SP-#{lab_order_result_id}-#{Base.encode16(:crypto.strong_rand_bytes(3))}"
  end

  @doc """
  Marks a specimen as received at the lab bench (the step between bedside
  collection and testing). Only valid from `:collected`.
  """
  def receive_specimen(organization_id, specimen_id, user_id) do
    specimen = get_specimen!(organization_id, specimen_id)

    if specimen.status == :collected do
      specimen
      |> LabSpecimen.changeset(%{
        status: :received,
        received_by_id: user_id,
        received_at: DateTime.utc_now(:second)
      })
      |> Repo.audited_update()
    else
      {:error, :not_collected}
    end
  end

  @doc """
  Rejects a specimen (e.g. haemolysed, mislabelled, insufficient volume),
  recording who rejected it, when, and why.
  """
  def reject_specimen(organization_id, specimen_id, user_id, reason)
      when is_binary(reason) and reason != "" do
    specimen = get_specimen!(organization_id, specimen_id)

    specimen
    |> LabSpecimen.changeset(%{
      status: :rejected,
      rejected_by_id: user_id,
      rejected_at: DateTime.utc_now(:second),
      rejection_reason: reason
    })
    |> Repo.audited_update()
  end

  defp parse_collection_date(date_str) when is_binary(date_str) and date_str != "" do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp parse_collection_date(_), do: Date.utc_today()

  ## Result entry (§9 "Lab order → completed result", step 2)

  @doc """
  Records `raw_values` into a `lab_order_results` row's `results`, storing
  each value with no flag (template-based computation is currently not
  supported). Marks the result `completed`, attributes it to
  `performer_id`, and rolls the parent `lab_orders.status` forward, all in
  one transaction.

  If the result was already `completed` (i.e. this call is *amending* a
  previously recorded result), a `reason` must be supplied via `opts` — the
  previous `results`/`test_performed_on`/`performed_by_id` are snapshotted
  into a `lab_order_result_amendments` row before being overwritten.
  Returns `{:error, :reason_required}` if a reason is missing for an
  amendment.
  """
  def record_result(organization_id, lab_order_result_id, performer_id, raw_values, opts \\ [])
      when is_integer(organization_id) and is_integer(performer_id) and is_map(raw_values) do
    reason = Keyword.get(opts, :reason)

    Repo.transaction(fn ->
      lab_order_result = get_lab_order_result!(organization_id, lab_order_result_id)
      results = compute_results(raw_values)

      with :ok <- ensure_amendment_reason(lab_order_result, reason),
           {:ok, _amendment} <-
             maybe_record_amendment(organization_id, lab_order_result, performer_id, reason),
           {:ok, updated} <- save_results(lab_order_result, performer_id, results),
           {:ok, _lab_order} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp ensure_amendment_reason(%LabOrderResult{status: :completed}, reason)
       when reason in [nil, ""],
       do: {:error, :reason_required}

  defp ensure_amendment_reason(_lab_order_result, _reason), do: :ok

  defp maybe_record_amendment(
         organization_id,
         %LabOrderResult{status: :completed} = lab_order_result,
         performer_id,
         reason
       ) do
    %LabOrderResultAmendment{}
    |> LabOrderResultAmendment.changeset(%{
      lab_order_result_id: lab_order_result.id,
      previous_results: lab_order_result.results,
      previous_test_performed_on: lab_order_result.test_performed_on,
      previous_performed_by_id: lab_order_result.performed_by_id,
      reason: reason,
      amended_by_id: performer_id
    })
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  defp maybe_record_amendment(_organization_id, _lab_order_result, _performer_id, _reason),
    do: {:ok, nil}

  @doc "Lists a result's amendment history, newest first, preloaded with the amending user."
  def list_amendments_for_result(organization_id, lab_order_result_id) do
    user_query = from u in User, where: u.organization_id == ^organization_id

    Repo.all(
      from a in LabOrderResultAmendment,
        where: a.organization_id == ^organization_id,
        where: a.lab_order_result_id == ^lab_order_result_id,
        order_by: [desc: a.inserted_at, desc: a.id],
        preload: [amended_by: ^user_query]
    )
  end

  defp compute_results(raw_values) do
    Map.new(raw_values, fn {key, value} -> {to_string(key), %{"value" => value}} end)
  end

  defp save_results(%LabOrderResult{} = lab_order_result, performer_id, results) do
    lab_order_result
    |> Ecto.Changeset.change(
      results: results,
      status: :completed,
      performed_by_id: performer_id,
      test_performed_on: Date.utc_today()
    )
    |> Repo.audited_update()
  end

  # Rolls the parent order status up from its child results: `completed` once
  # every result is completed, `in_progress` once any result has moved past
  # pending, and left alone otherwise. A `cancelled` order is never
  # resurrected, no matter what happens to its results. The order row is
  # locked FOR UPDATE so concurrent recomputes (e.g. two results completed at
  # the same moment) serialize instead of both reading a stale snapshot of
  # their siblings.
  defp recompute_lab_order_status(organization_id, lab_order_id) do
    lab_order =
      Repo.one!(
        from o in LabOrder,
          where: o.id == ^lab_order_id and o.organization_id == ^organization_id,
          lock: "FOR UPDATE"
      )

    if lab_order.status == :cancelled do
      {:ok, lab_order}
    else
      results = Repo.all(from r in LabOrderResult, where: r.lab_order_id == ^lab_order_id)

      status =
        cond do
          results == [] ->
            lab_order.status

          Enum.all?(results, &(&1.status == :completed)) ->
            :completed

          Enum.any?(results, &(&1.status in [:completed, :collected])) ->
            :in_progress

          true ->
            lab_order.status
        end

      lab_order
      |> Ecto.Changeset.change(status: status)
      |> Repo.audited_update()
    end
  end

  ## Consumable usage (§9 "Lab order → completed result", step 4)

  @doc """
  Draws `quantity` from a `batches` row for reagent/consumable usage,
  decrementing its `remaining_quantity` and recording a
  `lab_consumable_usage` row — in one transaction, so stock and usage
  records never drift apart. `:lab_order_id`/`:purpose` are optional
  (`opts`) since a reagent draw doesn't have to tie back to a specific
  order. Returns `{:error, changeset}` if `quantity` would take the batch's
  `remaining_quantity` below zero.
  """
  def record_consumable_usage(organization_id, batch_id, used_by_id, quantity, opts \\ [])
      when is_integer(organization_id) and is_integer(batch_id) and is_integer(quantity) and
             quantity > 0 do
    Repo.transaction(fn ->
      batch = Batches.get_batch!(organization_id, batch_id)

      with {:ok, _batch} <- Batches.decrement_remaining_quantity(batch, quantity),
           {:ok, usage} <-
             insert_consumable_usage(organization_id, batch_id, used_by_id, quantity, opts),
           {:ok, _scan_event} <-
             log_consumable_scan_event(organization_id, batch, used_by_id, usage) do
        usage
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_consumable_usage(organization_id, batch_id, used_by_id, quantity, opts) do
    %LabConsumableUsage{}
    |> LabConsumableUsage.changeset(%{
      batch_id: batch_id,
      used_by_id: used_by_id,
      quantity: quantity,
      lab_order_id: Keyword.get(opts, :lab_order_id),
      lab_order_result_id: Keyword.get(opts, :lab_order_result_id),
      specimen_id: Keyword.get(opts, :specimen_id),
      purpose: Keyword.get(opts, :purpose),
      used_at: DateTime.utc_now(:second)
    })
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.audited_insert()
  end

  # Every reagent/consumable draw is also a traceable scan event (§4.6),
  # keyed off the batch it was drawn from.
  defp log_consumable_scan_event(organization_id, batch, used_by_id, usage) do
    ScanEvents.log_scan_event(organization_id, %{
      gtin: batch.gtin,
      batch_no: batch.batch_no,
      event_type: :lab_consumption,
      reference_id: usage.id,
      user_id: used_by_id
    })
  end

  @doc """
  Lists all consumable usage records for a lab order, preloaded with the
  batch (including its product) and the user who recorded the usage.
  Grouped usage can be accessed by `lab_order_result_id`.
  """
  def list_consumable_usages_for_order(organization_id, lab_order_id) do
    batch_query =
      from b in ThamaniDawa.Batches.Batch,
        where: b.organization_id == ^organization_id,
        preload: :product

    user_query = from u in User, where: u.organization_id == ^organization_id

    Repo.all(
      from u in LabConsumableUsage,
        where: u.organization_id == ^organization_id,
        where: u.lab_order_id == ^lab_order_id,
        preload: [batch: ^batch_query, used_by: ^user_query]
    )
  end
end
