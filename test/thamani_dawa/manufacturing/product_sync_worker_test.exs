defmodule ThamaniDawa.Manufacturing.ProductSyncWorkerTest do
  use ThamaniDawa.DataCase, async: true
  use Oban.Testing, repo: ThamaniDawa.Repo

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.Manufacturing.ProductSyncWorker

  test "adding a manufacturing site enqueues a product sync" do
    organization = organization_fixture(%{operating_models: [:manufacturer]})
    site_fixture(%{organization_id: organization.id, activities: [:manufacturing]})

    assert_enqueued(worker: ProductSyncWorker, args: %{organization_id: organization.id})
  end

  test "adding a non-manufacturing site does not enqueue a product sync" do
    organization = organization_fixture(%{operating_models: [:pharmacy]})
    site_fixture(%{organization_id: organization.id, activities: [:pharmacy]})

    refute_enqueued(worker: ProductSyncWorker)
  end
end
