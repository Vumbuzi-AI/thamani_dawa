defmodule ThamaniDawa.PlatformMonitoringTest do
  use ThamaniDawa.DataCase, async: true

  import Ecto.Changeset
  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.SitesFixtures

  alias ThamaniDawa.{PlatformMonitoring, Repo}

  test "reports organization health metadata and cross-organization audit activity" do
    first_organization = organization_fixture(%{name: "Alpha Health"})
    second_organization = organization_fixture(%{name: "Beta Health"})
    first_user = user_fixture(%{organization_id: first_organization.id})
    second_user = user_fixture(%{organization_id: second_organization.id})

    site_fixture(%{organization_id: first_organization.id})
    site_fixture(%{organization_id: second_organization.id})

    Repo.put_audit_actor(first_user)
    {:ok, _} = first_organization |> change(name: "Alpha Care") |> Repo.audited_update()
    Repo.put_audit_actor(second_user)
    {:ok, _} = second_organization |> change(name: "Beta Care") |> Repo.audited_update()

    summaries = PlatformMonitoring.list_organization_summaries()
    overview = PlatformMonitoring.overview()
    activity = PlatformMonitoring.list_recent_activity()

    assert Enum.any?(
             summaries,
             &(&1.organization.id == first_organization.id and &1.sites_count == 1)
           )

    assert Enum.any?(
             summaries,
             &(&1.organization.id == second_organization.id and &1.users_count == 1)
           )

    assert overview.organizations >= 2
    assert overview.activity_last_24h >= 2
    assert Enum.any?(activity, &(&1.organization_id == first_organization.id))
    assert Enum.any?(activity, &(&1.organization_id == second_organization.id))
  end
end
