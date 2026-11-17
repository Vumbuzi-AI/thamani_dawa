defmodule ThamaniDawa.Epcis.SubmissionWorkerTest do
  use ThamaniDawa.DataCase, async: false

  alias ThamaniDawa.DistributorFixtures
  alias ThamaniDawa.Epcis.Client
  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.SubmissionWorker
  alias ThamaniDawa.EpcisClientStub
  alias ThamaniDawa.Repo

  setup do
    original = Application.get_env(:thamani_dawa, Client, [])

    Application.put_env(
      :thamani_dawa,
      Client,
      Keyword.merge(original,
        enabled: true,
        base_url: "https://hub.test",
        api_key: "test-key",
        client: EpcisClientStub
      )
    )

    on_exit(fn -> Application.put_env(:thamani_dawa, Client, original) end)

    organization = DistributorFixtures.distributor_organization_fixture()
    EpcisClientStub.expect([])
    %{organization: organization}
  end

  defp enqueue(organization, overrides \\ %{}) do
    Outbox.enqueue(
      Map.merge(
        %{
          organization_id: organization.id,
          event_type: "receiving",
          participant_tier: "distributor",
          payload: %{"eventID" => "urn:uuid:#{Ecto.UUID.generate()}"},
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        overrides
      )
    )
  end

  defp perform(organization) do
    SubmissionWorker.perform(%Oban.Job{args: %{"organization_id" => organization.id}})
  end

  test "drains pending events in occurred_at order and marks them accepted", %{
    organization: organization
  } do
    base = DateTime.utc_now() |> DateTime.truncate(:second)
    second = enqueue(organization, %{occurred_at: DateTime.add(base, 10)})
    first = enqueue(organization, %{occurred_at: base})

    EpcisClientStub.expect([
      {:ok, 202, %{"status" => "ACCEPTED"}},
      {:ok, 202, %{"status" => "ACCEPTED"}}
    ])

    assert :ok = perform(organization)

    assert Repo.reload!(first).status == "accepted"
    assert Repo.reload!(second).status == "accepted"

    assert [first_doc, second_doc] = EpcisClientStub.submitted_documents()

    assert hd(first_doc["epcisBody"]["eventList"])["eventID"] ==
             first.payload["eventID"]

    assert hd(second_doc["epcisBody"]["eventList"])["eventID"] ==
             second.payload["eventID"]
  end

  test "a 201 with warnings is stored as warning status", %{organization: organization} do
    event = enqueue(organization)

    EpcisClientStub.expect([
      {:ok, 201, %{"warnings" => [%{"errorCode" => "RECEIVING_WITHOUT_SHIPPING"}]}}
    ])

    assert :ok = perform(organization)

    reloaded = Repo.reload!(event)
    assert reloaded.status == "warning"
    assert [%{"errorCode" => "RECEIVING_WITHOUT_SHIPPING"}] = reloaded.response["warnings"]
  end

  test "a 409 duplicate is treated as accepted", %{organization: organization} do
    event = enqueue(organization)
    EpcisClientStub.expect([{:ok, 409, %{"status" => "DUPLICATE"}}])

    assert :ok = perform(organization)
    assert Repo.reload!(event).status == "accepted"
  end

  test "a 400 halts the queue behind the rejected event", %{organization: organization} do
    base = DateTime.utc_now() |> DateTime.truncate(:second)
    first = enqueue(organization, %{occurred_at: base})
    second = enqueue(organization, %{occurred_at: DateTime.add(base, 10)})

    EpcisClientStub.expect([{:ok, 400, %{"errorCode" => "MISSING_NEEDED_FIELDS"}}])

    assert :ok = perform(organization)

    assert Repo.reload!(first).status == "rejected"
    assert Repo.reload!(second).status == "pending"
    assert Outbox.halted?(organization.id)

    assert :ok = perform(organization)
    assert length(EpcisClientStub.submitted_documents()) == 1
  end

  test "resubmitting a rejected event reuses its eventID and unblocks the queue", %{
    organization: organization
  } do
    event = enqueue(organization)
    EpcisClientStub.expect([{:ok, 400, %{"errorCode" => "MISSING_NEEDED_FIELDS"}}])
    assert :ok = perform(organization)

    rejected = Repo.reload!(event)
    assert rejected.status == "rejected"

    Outbox.resubmit(rejected)
    refute Outbox.halted?(organization.id)

    EpcisClientStub.expect([{:ok, 202, %{"status" => "ACCEPTED"}}])
    assert :ok = perform(organization)

    final = Repo.reload!(event)
    assert final.status == "accepted"
    assert final.event_id == event.event_id
  end

  test "transient failures snooze and schedule a retry", %{organization: organization} do
    event = enqueue(organization)
    EpcisClientStub.expect([{:error, %RuntimeError{message: "timeout"}}])

    assert {:snooze, seconds} = perform(organization)
    assert seconds >= 1

    reloaded = Repo.reload!(event)
    assert reloaded.status == "pending"
    assert reloaded.attempts == 1
    assert reloaded.next_attempt_at
  end

  test "disabled client leaves everything pending", %{organization: organization} do
    config = Application.get_env(:thamani_dawa, Client)
    Application.put_env(:thamani_dawa, Client, Keyword.put(config, :enabled, false))

    event = enqueue(organization)
    assert :ok = perform(organization)
    assert Repo.reload!(event).status == "pending"
    assert EpcisClientStub.submitted_documents() == []
  end
end
