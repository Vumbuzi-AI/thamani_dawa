defmodule ThamaniDawa.StockTakesFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.StockTakes`.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.BatchesFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.SitesFixtures
  alias ThamaniDawa.StockTakes

  def valid_stock_take_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      notes: "Quarterly count #{System.unique_integer()}",
      inventory_type: :medicine
    })
  end

  @doc """
  Creates a draft stock take requested by a user. Lazily creates an
  organization, site, and requester unless supplied via `organization_id`,
  `site_id`, and `requested_by_id`.
  """
  def stock_take_fixture(attrs \\ %{}) do
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

    {:ok, stock_take} =
      attrs
      |> valid_stock_take_attributes()
      |> then(&StockTakes.create_stock_take(organization_id, &1))

    stock_take
  end

  @doc """
  Creates a stock take item (adds a batch to a stock take). Lazily creates
  a stock take and a received batch unless supplied.
  """
  def stock_take_item_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn ->
        OrganizationsFixtures.organization_fixture().id
      end)

    {stock_take, attrs} =
      Map.pop_lazy(attrs, :stock_take, fn ->
        stock_take_fixture(%{organization_id: organization_id})
      end)

    {batch, _attrs} =
      Map.pop_lazy(attrs, :batch, fn ->
        BatchesFixtures.batch_fixture(%{
          organization_id: organization_id,
          site_id: stock_take.site_id
        })
      end)

    {:ok, item} = StockTakes.add_item(stock_take, batch)
    item
  end
end
