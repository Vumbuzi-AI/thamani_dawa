defmodule ThamaniDawa.InventoryDisposalsFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.InventoryDisposals`.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.BatchesFixtures
  alias ThamaniDawa.InventoryDisposals
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.SitesFixtures
  alias ThamaniDawa.SuppliersFixtures

  def valid_disposal_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      reason: "Routine disposal #{System.unique_integer()}",
      kind: :expiry,
      inventory_type: :medicine
    })
  end

  @doc """
  Creates a draft disposal requested by a user. Lazily creates an
  organization, site, and requester unless supplied via `organization_id`,
  `site_id`, and `requested_by_id`.
  """
  def disposal_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn ->
        SitesFixtures.site_fixture(%{organization_id: organization_id}).id
      end)

    attrs =
      if Map.has_key?(attrs, :admin_id) do
        attrs
      else
        {requested_by_id, attrs} =
          Map.pop_lazy(attrs, :requested_by_id, fn ->
            AccountsFixtures.user_fixture(%{organization_id: organization_id}).id
          end)

        Map.put(attrs, :requested_by_id, requested_by_id)
      end

    attrs = Map.merge(attrs, %{site_id: site_id})

    {:ok, disposal} =
      attrs
      |> valid_disposal_attributes()
      |> then(&InventoryDisposals.create_disposal(organization_id, &1))

    disposal
  end

  @doc """
  Creates a disposal item (adds a batch to a disposal). Lazily creates a
  disposal and a received batch unless supplied. For a `:returned`
  disposal the batch is given a supplier unless one is already set.
  """
  def disposal_item_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {disposal, attrs} =
      Map.pop_lazy(attrs, :disposal, fn ->
        disposal_fixture(%{organization_id: organization_id})
      end)

    {quantity, attrs} = Map.pop(attrs, :quantity, 10)

    {batch, _attrs} =
      Map.pop_lazy(attrs, :batch, fn ->
        batch_attrs = %{
          organization_id: organization_id,
          site_id: disposal.site_id,
          quantity: quantity
        }

        batch_attrs =
          cond do
            disposal.kind == :returned ->
              supplier = SuppliersFixtures.supplier_fixture(%{organization_id: organization_id})
              Map.put(batch_attrs, :supplier_id, supplier.id)

            disposal.kind == :expiry ->
              Map.put(batch_attrs, :expiry_date, Date.add(Date.utc_today(), -1))

            true ->
              batch_attrs
          end

        BatchesFixtures.batch_fixture(batch_attrs)
      end)

    {:ok, item} = InventoryDisposals.add_item(disposal, batch, quantity)
    item
  end
end
