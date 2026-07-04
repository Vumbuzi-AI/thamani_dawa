defmodule ThamaniDawa.LabTestTemplates do
  @moduledoc """
  The structured test catalog (§4.4, §8.3 "Test templates & categories"):
  `lab_test_categories` group `lab_test_templates`, and each template's
  `field_definitions` drives templated result entry and auto-flagging
  against a reference range (§9 "Lab order → verified result", step 2).
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.LabTestTemplates.{FieldDefinition, LabTestCategory, LabTestTemplate}

  ## Categories

  @doc "Lists an organization's lab test categories."
  def list_lab_test_categories(organization_id) do
    Repo.all(from c in LabTestCategory, where: c.organization_id == ^organization_id)
  end

  @doc "Gets a single lab test category scoped to an organization. Raises if not found."
  def get_lab_test_category!(organization_id, id) do
    Repo.get_by!(LabTestCategory, id: id, organization_id: organization_id)
  end

  @doc "Creates a lab test category under the given organization."
  def create_lab_test_category(organization_id, attrs) when is_integer(organization_id) do
    %LabTestCategory{}
    |> LabTestCategory.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  ## Templates

  @doc "Lists an organization's lab test templates."
  def list_lab_test_templates(organization_id) do
    Repo.all(from t in LabTestTemplate, where: t.organization_id == ^organization_id)
  end

  @doc "Gets a single lab test template scoped to an organization. Raises if not found."
  def get_lab_test_template!(organization_id, id) do
    Repo.get_by!(LabTestTemplate, id: id, organization_id: organization_id)
  end

  @doc "Creates a lab test template under the given organization."
  def create_lab_test_template(organization_id, attrs) when is_integer(organization_id) do
    %LabTestTemplate{}
    |> LabTestTemplate.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc "Updates a lab test template, including its `field_definitions`."
  def update_lab_test_template(%LabTestTemplate{} = lab_test_template, attrs) do
    lab_test_template
    |> LabTestTemplate.changeset(attrs)
    |> Repo.update()
  end

  ## Auto-flagging (§9 "Lab order → verified result", step 2)

  @doc """
  Computes each field's `flag` (`"low"` \| `"normal"` \| `"high"`) against
  `template`'s `field_definitions` reference range. A field with no matching
  definition, or no numeric `low`/`high` range, is stored with its raw value
  and no flag. Keys in `raw_values` may be atoms or strings; the returned
  map always has string keys, ready to store in `lab_order_tests.results`.
  """
  def compute_results(%LabTestTemplate{field_definitions: field_definitions}, raw_values) do
    Map.new(raw_values, fn {key, value} ->
      key = to_string(key)
      field_definition = Enum.find(field_definitions, &(&1.key == key))
      {key, %{"value" => value, "flag" => flag_for(field_definition, value)}}
    end)
  end

  defp flag_for(%FieldDefinition{low: low, high: high}, value) when not is_nil(low) and not is_nil(high) do
    case to_number(value) do
      {:ok, v} when v < low -> "low"
      {:ok, v} when v > high -> "high"
      {:ok, _v} -> "normal"
      :error -> nil
    end
  end

  defp flag_for(_field_definition, _value), do: nil

  defp to_number(value) when is_number(value), do: {:ok, value * 1.0}

  defp to_number(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  defp to_number(_value), do: :error
end
