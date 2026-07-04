defmodule ThamaniDawa.LabTests do
  @moduledoc """
  The billable lab test catalog (§4.4): what a lab can order and charge for.
  Distinct from `ThamaniDawa.LabTestTemplates`, which drives *how* a test's
  results are structured and entered — a `lab_order_tests` row references a
  `lab_tests` row for pricing and, optionally, a `lab_test_templates` row for
  templated result entry.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.LabTests.LabTest

  @doc "Lists an organization's lab tests."
  def list_lab_tests(organization_id) do
    Repo.all(from t in LabTest, where: t.organization_id == ^organization_id)
  end

  @doc "Gets a single lab test scoped to an organization. Raises if not found."
  def get_lab_test!(organization_id, id) do
    Repo.get_by!(LabTest, id: id, organization_id: organization_id)
  end

  @doc "Creates a lab test under the given organization."
  def create_lab_test(organization_id, attrs) when is_integer(organization_id) do
    %LabTest{}
    |> LabTest.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end
end
