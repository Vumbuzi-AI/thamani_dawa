defmodule ThamaniDawa.StockTakesFixtures do
  @moduledoc """
  Test helpers for creating entities via `ThamaniDawa.StockTakes`.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.SitesFixtures
  alias ThamaniDawa.StockTakes

  @doc """
  Starts a stock take under a fresh organization/site/user unless given. Any batches already
  at the given (or freshly-created) site become its entries, matching real `start_stock_take/4`
  behavior — create batches at the site *before* calling this if entries are needed.
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

    {user_id, attrs} =
      Map.pop_lazy(attrs, :user_id, fn ->
        AccountsFixtures.user_fixture(%{organization_id: organization_id}).id
      end)

    {:ok, stock_take} = StockTakes.start_stock_take(organization_id, site_id, user_id, attrs)
    StockTakes.get_stock_take!(organization_id, stock_take.id)
  end
end
