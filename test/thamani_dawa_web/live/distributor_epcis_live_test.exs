defmodule ThamaniDawaWeb.DistributorEpcisLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Epcis.OutboxEvent

  setup %{conn: conn} do
    distributor = distributor_user_fixture()

    conn =
      conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(distributor)

    %{conn: conn, distributor: distributor}
  end

  test "lists outbox events with their status", %{conn: conn, distributor: distributor} do
    accepted = insert_event(distributor.organization_id, "accepted")
    pending = insert_event(distributor.organization_id, "pending")

    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")

    assert has_element?(view, "#epcis-events-#{accepted.id}", "Accepted")
    assert has_element?(view, "#epcis-events-#{pending.id}", "Pending")
  end

  test "filters events by status and can return to all events", %{
    conn: conn,
    distributor: distributor
  } do
    accepted = insert_event(distributor.organization_id, "accepted")
    pending = insert_event(distributor.organization_id, "pending")

    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")

    view |> element("#epcis-filter-pending") |> render_click()

    assert has_element?(view, "#epcis-filter-pending[aria-pressed='true']")
    assert has_element?(view, "#epcis-events-#{pending.id}", "Pending")
    refute has_element?(view, "#epcis-events-#{accepted.id}")

    view |> element("#epcis-filter-all") |> render_click()

    assert has_element?(view, "#epcis-filter-all[aria-pressed='true']")
    assert has_element?(view, "#epcis-events-#{accepted.id}", "Accepted")
    assert has_element?(view, "#epcis-events-#{pending.id}", "Pending")
  end

  test "warns when hub submission is disabled", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")
    assert has_element?(view, "#epcis-submission-disabled")
  end

  test "flags a halted queue when a rejected event blocks the org", %{
    conn: conn,
    distributor: distributor
  } do
    rejected = insert_event(distributor.organization_id, "rejected")

    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")

    assert has_element?(view, "#epcis-queue-halted")
    assert has_element?(view, "#epcis-events-#{rejected.id}", "Rejected")
    assert has_element?(view, "#resubmit-epcis-event-#{rejected.id}")
  end

  test "resubmitting a rejected event requeues it with the same eventID", %{
    conn: conn,
    distributor: distributor
  } do
    rejected = insert_event(distributor.organization_id, "rejected")

    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")

    view |> element("#resubmit-epcis-event-#{rejected.id}") |> render_click()

    assert [%OutboxEvent{} = event] = Outbox.pending_for_organization(distributor.organization_id)
    assert event.id == rejected.id
    assert event.event_id == rejected.event_id

    assert has_element?(view, "#flash-group", "requeued")
  end

  test "warning events surface their stored warnings", %{conn: conn, distributor: distributor} do
    event = insert_event(distributor.organization_id, "warning")

    {:ok, view, _html} = live(conn, ~p"/distributor/epcis")

    assert has_element?(view, "#epcis-events-#{event.id}", "UNKNOWN_SGLN")
  end

  defp insert_event(organization_id, status) do
    response =
      case status do
        "warning" -> %{"warnings" => ["UNKNOWN_SGLN"]}
        "rejected" -> %{"raw" => "MISSING_NEEDED_FIELDS"}
        _ -> %{}
      end

    %OutboxEvent{
      organization_id: organization_id,
      event_id: Ecto.UUID.generate(),
      event_type: "receiving",
      participant_tier: "distributor",
      payload: %{"bizStep" => "receiving"},
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
      status: status,
      http_status: if(status in ~w(accepted warning rejected), do: 202),
      response: response,
      source_type: "goods_receipt",
      source_id: 1
    }
    |> ThamaniDawa.Repo.insert!()
  end
end
