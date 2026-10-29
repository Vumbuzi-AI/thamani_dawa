defmodule ThamaniDawa.RequisitionsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.Requisitions`.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.ProductsFixtures
  alias ThamaniDawa.Requisitions
  alias ThamaniDawa.SitesFixtures

  def valid_requisition_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{quantity: 10})
  end

  @doc """
  Creates a pending requisition. Unless given, `organization_id` gets a
  fresh organization, and `site_id`/`product_id`/`requested_by_id` get
  fresh records under that organization.
  """
  def requisition_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    {product_id, attrs} =
      Map.pop_lazy(attrs, :product_id, fn ->
        ProductsFixtures.product_fixture(%{organization_id: organization_id}).id
      end)

    {requested_by_id, attrs} =
      Map.pop_lazy(attrs, :requested_by_id, fn ->
        AccountsFixtures.user_fixture(%{organization_id: organization_id}).id
      end)

    attrs = Map.merge(attrs, %{site_id: site_id, product_id: product_id})

    {:ok, requisition} =
      attrs
      |> valid_requisition_attributes()
      |> then(&Requisitions.create_requisition(organization_id, requested_by_id, &1))

    requisition
  end

  @doc """
  Creates a requisition and approves it. Pass `reviewer_id:` to override
  who approves it (defaults to a fresh admin under the same organization).
  """
  def approved_requisition_fixture(attrs \\ %{}) do
    {reviewer_id, attrs} = Map.pop(attrs, :reviewer_id, nil)
    requisition = requisition_fixture(attrs)

    reviewer_id =
      reviewer_id ||
        AccountsFixtures.user_fixture(%{organization_id: requisition.organization_id}).id

    {:ok, approved} =
      Requisitions.approve_requisition(requisition.organization_id, requisition.id, reviewer_id)

    approved
  end
end
