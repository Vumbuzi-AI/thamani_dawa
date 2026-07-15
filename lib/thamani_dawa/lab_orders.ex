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
  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabOrders.{LabConsumableUsage, LabOrder, LabOrderResult}
  alias ThamaniDawa.PatientVisits
  alias ThamaniDawa.Repo

  ## Lab orders

  @doc "Lists an organization's lab orders."
  def list_lab_orders(organization_id) do
    Repo.all(from o in LabOrder, where: o.organization_id == ^organization_id)
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
    |> Repo.insert()
  end

  @doc """
  Creates a lab order header together with its `lab_order_results`, all in
  one transaction (§9 "Lab order → verified result", step 1). Rolls back the
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
               attrs
               |> Map.put("patient_visit_id", visit.id)
               |> Map.put("patient_id", visit.patient_id)
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

  @doc "Creates a lab order result under the given lab order."
  def create_lab_order_result(organization_id, lab_order_id, attrs)
      when is_integer(organization_id) and is_integer(lab_order_id) do
    %LabOrderResult{}
    |> LabOrderResult.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:lab_order_id, lab_order_id)
    |> Repo.insert()
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
             |> Repo.update(),
           {:ok, _} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp parse_collection_date(date_str) when is_binary(date_str) and date_str != "" do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp parse_collection_date(_), do: Date.utc_today()

  ## Result entry (§9 "Lab order → verified result", step 2)

  @doc """
  Records `raw_values` into a `lab_order_results` row's `results`, storing
  each value with no flag (template-based computation is currently not
  supported). Marks the result `completed`, attributes it to
  `performer_id`, and rolls the parent `lab_orders.status` forward, all in
  one transaction.
  """
  def record_result(organization_id, lab_order_result_id, performer_id, raw_values)
      when is_integer(organization_id) and is_integer(performer_id) and is_map(raw_values) do
    Repo.transaction(fn ->
      lab_order_result = get_lab_order_result!(organization_id, lab_order_result_id)
      results = compute_results(raw_values)

      with {:ok, updated} <- save_results(lab_order_result, performer_id, results),
           {:ok, _lab_order} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
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
    |> Repo.update()
  end

  # A lab order is `completed` once every result has results, `in_progress`
  # once at least one result has been completed, and left alone otherwise
  # (e.g. `cancelled`).
  defp recompute_lab_order_status(organization_id, lab_order_id) do
    lab_order = get_lab_order!(organization_id, lab_order_id)
    results = Repo.all(from r in LabOrderResult, where: r.lab_order_id == ^lab_order_id)

    status =
      cond do
        results == [] -> lab_order.status
        Enum.all?(results, &(&1.status == :completed)) -> :completed
        Enum.any?(results, &(&1.status in [:completed, :collected])) -> :in_progress
        true -> lab_order.status
      end

    lab_order
    |> Ecto.Changeset.change(status: status)
    |> Repo.update()
  end

  ## Consumable usage (§9 "Lab order → verified result", step 4)

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
             insert_consumable_usage(organization_id, batch_id, used_by_id, quantity, opts) do
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
      purpose: Keyword.get(opts, :purpose),
      used_at: DateTime.utc_now(:second)
    })
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end
end
