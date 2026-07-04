defmodule ThamaniDawa.ScanEventsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.ScanEvents
  alias ThamaniDawa.ScanEvents.ScanEvent

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.ScanEventsFixtures

  describe "create_scan_event/2" do
    test "requires gtin, batch_no and event_type" do
      organization = organization_fixture()

      assert {:error, changeset} = ScanEvents.create_scan_event(organization.id, %{})

      assert %{
               gtin: ["can't be blank"],
               batch_no: ["can't be blank"],
               event_type: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "scopes to the organization and leaves gln/reference_id optional" do
      organization = organization_fixture()

      assert {:ok, %ScanEvent{} = event} =
               ScanEvents.create_scan_event(organization.id, %{
                 gtin: unique_gtin(),
                 batch_no: "LOT-1",
                 event_type: :receipt
               })

      assert event.organization_id == organization.id
      assert event.gln == nil
      assert event.reference_id == nil
    end

    test "rejects an event_type outside the known set" do
      organization = organization_fixture()

      assert {:error, changeset} =
               ScanEvents.create_scan_event(organization.id, %{
                 gtin: unique_gtin(),
                 batch_no: "LOT-1",
                 event_type: :not_a_real_type
               })

      assert %{event_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "list_scan_events/1" do
    test "only returns scan events for the given organization" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()

      event_a = scan_event_fixture(%{organization_id: organization_a.id})
      scan_event_fixture(%{organization_id: organization_b.id})

      assert [%ScanEvent{id: id}] = ScanEvents.list_scan_events(organization_a.id)
      assert id == event_a.id
    end
  end

  describe "get_scan_event!/2" do
    test "raises when the event belongs to a different organization" do
      other_organization = organization_fixture()
      event = scan_event_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        ScanEvents.get_scan_event!(other_organization.id, event.id)
      end
    end
  end

  describe "log_scan_event/5" do
    setup do
      organization = organization_fixture()
      user = user_fixture(%{organization_id: organization.id})

      batch =
        batch_fixture(%{
          organization_id: organization.id,
          gtin: "00614141000012",
          batch_no: "LOT-42"
        })

      %{organization: organization, user: user, batch: batch}
    end

    test "decodes the scan and logs it against the given reference", ctx do
      scanned = "01#{ctx.batch.gtin}10#{ctx.batch.batch_no}"

      assert {:ok, %ScanEvent{} = event} =
               ScanEvents.log_scan_event(
                 ctx.organization.id,
                 :dispense,
                 ctx.batch.id,
                 ctx.user.id,
                 scanned
               )

      assert event.gtin == ctx.batch.gtin
      assert event.batch_no == ctx.batch.batch_no
      assert event.event_type == :dispense
      assert event.reference_id == ctx.batch.id
      assert event.user_id == ctx.user.id
    end

    test "captures a scanned GLN when present", ctx do
      scanned = "01#{ctx.batch.gtin}10#{ctx.batch.batch_no}414#{"1234567890123"}"

      assert {:ok, %ScanEvent{gln: "1234567890123"}} =
               ScanEvents.log_scan_event(
                 ctx.organization.id,
                 :transfer_in,
                 ctx.batch.id,
                 ctx.user.id,
                 scanned
               )
    end

    test "returns an error when the scanned payload doesn't parse", ctx do
      assert {:error, {:unrecognized_ai, _rest}} =
               ScanEvents.log_scan_event(
                 ctx.organization.id,
                 :receipt,
                 ctx.batch.id,
                 ctx.user.id,
                 "99garbage"
               )
    end
  end
end
