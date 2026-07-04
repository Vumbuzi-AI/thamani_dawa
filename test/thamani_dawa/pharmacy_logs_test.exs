defmodule ThamaniDawa.PharmacyLogsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.PharmacyLogs
  alias ThamaniDawa.PharmacyLogs.PharmacyLog

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PharmacyLogsFixtures
  import ThamaniDawa.SitesFixtures

  describe "create_pharmacy_log/2" do
    test "requires site_id, log_type, month and year" do
      organization = organization_fixture()

      assert {:error, changeset} = PharmacyLogs.create_pharmacy_log(organization.id, %{})

      assert %{
               site_id: ["can't be blank"],
               log_type: ["can't be blank"],
               month: ["can't be blank"],
               year: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "defaults daily_entries to an empty map and scopes to the organization" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert {:ok, %PharmacyLog{} = log} =
               PharmacyLogs.create_pharmacy_log(organization.id, %{
                 site_id: site.id,
                 log_type: "cold_chain_temperature",
                 month: 6,
                 year: 2026
               })

      assert log.organization_id == organization.id
      assert log.daily_entries == %{}
    end

    test "rejects a month outside 1..12" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               PharmacyLogs.create_pharmacy_log(organization.id, %{
                 site_id: site.id,
                 log_type: "cold_chain_temperature",
                 month: 13,
                 year: 2026
               })

      assert %{month: ["must be less than or equal to 12"]} = errors_on(changeset)
    end

    test "enforces uniqueness of (organization_id, log_type, month, year)" do
      organization = organization_fixture()
      site = site_fixture(%{organization_id: organization.id})

      pharmacy_log_fixture(%{
        organization_id: organization.id,
        site_id: site.id,
        log_type: "humidity",
        month: 3,
        year: 2026
      })

      assert {:error, changeset} =
               PharmacyLogs.create_pharmacy_log(organization.id, %{
                 site_id: site.id,
                 log_type: "humidity",
                 month: 3,
                 year: 2026
               })

      assert %{log_type: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows the same (log_type, month, year) in a different organization" do
      site_a = site_fixture()

      pharmacy_log_fixture(%{
        organization_id: site_a.organization_id,
        site_id: site_a.id,
        log_type: "humidity",
        month: 3,
        year: 2026
      })

      organization_b = organization_fixture()
      site_b = site_fixture(%{organization_id: organization_b.id})

      assert {:ok, _log} =
               PharmacyLogs.create_pharmacy_log(organization_b.id, %{
                 site_id: site_b.id,
                 log_type: "humidity",
                 month: 3,
                 year: 2026
               })
    end
  end

  describe "list_pharmacy_logs/1" do
    test "only returns pharmacy logs for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      log_a = pharmacy_log_fixture(%{organization_id: organization_a.id})
      pharmacy_log_fixture(%{organization_id: organization_b.id})

      assert [%PharmacyLog{id: id}] = PharmacyLogs.list_pharmacy_logs(organization_a.id)
      assert id == log_a.id
    end
  end

  describe "get_pharmacy_log!/2" do
    test "raises when the log belongs to a different organization" do
      other_organization = organization_fixture()
      log = pharmacy_log_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        PharmacyLogs.get_pharmacy_log!(other_organization.id, log.id)
      end
    end
  end
end
