defmodule ThamaniDawa.LabOrders do
  @moduledoc """
  Laboratory dispensing/testing workflow (§4.4, §9 "Lab order → verified
  result"): a `lab_orders` header with one or more `lab_order_tests`, each
  optionally backed by a `lab_test_templates` row for structured result
  entry and auto-flagging, then signed off by a second technician. Reagent
  draws against a site's own `batches` stock log in `lab_consumable_usage`.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Batches
  alias ThamaniDawa.LabTestTemplates
  alias ThamaniDawa.Repo
  alias ThamaniDawa.LabOrders.{LabConsumableUsage, LabOrder, LabOrderTest}

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
  Creates a lab order header together with its `lab_order_tests`, all in one
  transaction (§9 "Lab order → verified result", step 1). Rolls back the
  header if any test fails to validate. Returns
  `{:ok, %{lab_order: lab_order, lab_order_tests: tests}}`.
  """
  def create_lab_order_with_tests(organization_id, attrs, tests_attrs)
      when is_integer(organization_id) and is_list(tests_attrs) do
    Repo.transaction(fn ->
      with {:ok, lab_order} <- create_lab_order(organization_id, attrs),
           {:ok, tests} <- create_lab_order_tests(organization_id, lab_order.id, tests_attrs) do
        %{lab_order: lab_order, lab_order_tests: tests}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp create_lab_order_tests(organization_id, lab_order_id, tests_attrs) do
    tests_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case create_lab_order_test(organization_id, lab_order_id, attrs) do
        {:ok, test} -> {:cont, {:ok, [test | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, tests} -> {:ok, Enum.reverse(tests)}
      error -> error
    end
  end

  ## Lab order tests

  @doc "Gets a single lab order test scoped to an organization. Raises if not found."
  def get_lab_order_test!(organization_id, id) do
    Repo.get_by!(LabOrderTest, id: id, organization_id: organization_id)
  end

  @doc "Lists every lab order test in an organization (across all lab orders)."
  def list_lab_order_tests(organization_id) do
    Repo.all(from t in LabOrderTest, where: t.organization_id == ^organization_id)
  end

  @doc "Creates a lab order test under the given lab order."
  def create_lab_order_test(organization_id, lab_order_id, attrs)
      when is_integer(organization_id) and is_integer(lab_order_id) do
    %LabOrderTest{}
    |> LabOrderTest.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:lab_order_id, lab_order_id)
    |> Repo.insert()
  end

  @doc "Records the date a test's sample was physically collected."
  def mark_sample_collected(organization_id, lab_order_test_id, date \\ Date.utc_today()) do
    organization_id
    |> get_lab_order_test!(lab_order_test_id)
    |> Ecto.Changeset.change(sample_collected_on: date)
    |> Repo.update()
  end

  ## Result entry (§9 "Lab order → verified result", step 2)

  @doc """
  Records `raw_values` into a `lab_order_tests` row's `results`, auto-computing
  each field's flag against the test's `lab_test_templates` reference range
  when `template_id` is set (`ThamaniDawa.LabTestTemplates.compute_results/2`)
  — otherwise storing each value with no flag. Marks the test `completed`,
  attributes it to `performer_id`, and rolls the parent `lab_orders.status`
  forward, all in one transaction.
  """
  def record_result(organization_id, lab_order_test_id, performer_id, raw_values)
      when is_integer(organization_id) and is_integer(performer_id) and is_map(raw_values) do
    Repo.transaction(fn ->
      lab_order_test = get_lab_order_test!(organization_id, lab_order_test_id)
      results = compute_results(organization_id, lab_order_test, raw_values)

      with {:ok, updated} <- save_results(lab_order_test, performer_id, results),
           {:ok, _lab_order} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp compute_results(_organization_id, %LabOrderTest{template_id: nil}, raw_values) do
    Map.new(raw_values, fn {key, value} -> {to_string(key), %{"value" => value}} end)
  end

  defp compute_results(organization_id, %LabOrderTest{template_id: template_id}, raw_values) do
    template = LabTestTemplates.get_lab_test_template!(organization_id, template_id)
    LabTestTemplates.compute_results(template, raw_values)
  end

  defp save_results(%LabOrderTest{} = lab_order_test, performer_id, results) do
    lab_order_test
    |> Ecto.Changeset.change(
      results: results,
      status: :completed,
      performed_by_id: performer_id,
      test_performed_on: Date.utc_today()
    )
    |> Repo.update()
  end

  ## Second-technician verification (§9 "Lab order → verified result", step 3)

  @doc """
  A second technician verifies a completed `lab_order_tests` row, moving it
  to `verified` and rolling the parent `lab_orders.status` to `verified` once
  every test on that order is. Returns `{:error, :not_completed}` if results
  haven't been entered yet, or `{:error, :same_technician}` if `verifier_id`
  matches whoever performed the test — verification always needs a second,
  different set of eyes.
  """
  def verify_lab_order_test(organization_id, lab_order_test_id, verifier_id)
      when is_integer(organization_id) and is_integer(verifier_id) do
    Repo.transaction(fn ->
      lab_order_test = get_lab_order_test!(organization_id, lab_order_test_id)

      with :ok <- validate_completed(lab_order_test),
           :ok <- validate_different_technician(lab_order_test, verifier_id),
           {:ok, updated} <- save_verification(lab_order_test, verifier_id),
           {:ok, _lab_order} <- recompute_lab_order_status(organization_id, updated.lab_order_id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp validate_completed(%LabOrderTest{status: :pending}), do: {:error, :not_completed}
  defp validate_completed(%LabOrderTest{}), do: :ok

  defp validate_different_technician(%LabOrderTest{performed_by_id: performed_by_id}, verifier_id) do
    if performed_by_id == verifier_id do
      {:error, :same_technician}
    else
      :ok
    end
  end

  defp save_verification(%LabOrderTest{} = lab_order_test, verifier_id) do
    lab_order_test
    |> Ecto.Changeset.change(verified_by_id: verifier_id, verified_at: DateTime.utc_now(:second), status: :verified)
    |> Repo.update()
  end

  # A lab order is `verified` once every test on it is, `completed` once
  # every test has results (but not all verified yet), `in_progress` once at
  # least one test has results, and left alone otherwise (e.g. `cancelled`).
  defp recompute_lab_order_status(organization_id, lab_order_id) do
    lab_order = get_lab_order!(organization_id, lab_order_id)
    tests = Repo.all(from t in LabOrderTest, where: t.lab_order_id == ^lab_order_id)

    status =
      cond do
        tests == [] -> lab_order.status
        Enum.all?(tests, &(&1.status == :verified)) -> :verified
        Enum.all?(tests, &(&1.status in [:completed, :verified])) -> :completed
        Enum.any?(tests, &(&1.status in [:completed, :verified])) -> :in_progress
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
      when is_integer(organization_id) and is_integer(batch_id) and is_integer(quantity) and quantity > 0 do
    Repo.transaction(fn ->
      batch = Batches.get_batch!(organization_id, batch_id)

      with {:ok, _batch} <- Batches.decrement_remaining_quantity(batch, quantity),
           {:ok, usage} <- insert_consumable_usage(organization_id, batch_id, used_by_id, quantity, opts) do
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
