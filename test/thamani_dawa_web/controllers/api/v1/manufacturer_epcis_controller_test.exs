defmodule ThamaniDawaWeb.Api.V1.ManufacturerEpcisControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Epcis.Outbox
  alias ThamaniDawa.Manufacturing

  setup do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    product = manufacturer_product_fixture(organization.id)

    # Generating serials queues a manufacturer commissioning event.
    {:ok, _result} =
      Manufacturing.generate_primary_serials(
        organization.id,
        product,
        %{
          "batch_no" => "LOT-TNT",
          "production_date" => "2026-11-20",
          "expiry_date" => "2027-11-20"
        },
        2,
        site.gln
      )

    {:ok, organization: organization, user: user}
  end

  test "the queue's status and its events", ctx do
    status =
      ctx.user |> auth() |> get(~p"/api/v1/manufacturer/epcis/status") |> json_response(200)

    counts = status["data"]["status_counts"]

    assert counts |> Map.keys() |> Enum.sort() ==
             ~w(accepted blocked dead pending rejected warning)

    assert Enum.sum(Map.values(counts)) >= 1
    assert is_boolean(status["data"]["queue_halted"])

    events =
      ctx.user |> auth() |> get(~p"/api/v1/manufacturer/epcis/events") |> json_response(200)

    assert [event | _] = events["data"]
    assert event["participant_tier"] == "manufacturer"
    refute Map.has_key?(event, "payload")

    searched =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/epcis/events?search=#{event["event_type"]}")
      |> json_response(200)

    assert Enum.any?(searched["data"], &(&1["id"] == event["id"]))

    none =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/epcis/events?search=no-such-event")
      |> json_response(200)

    assert none["data"] == []

    shown =
      ctx.user
      |> auth()
      |> get(~p"/api/v1/manufacturer/epcis/events/#{event["id"]}")
      |> json_response(200)

    assert is_map(shown["data"]["payload"])
  end

  test "another organization's event is not found", ctx do
    other = manufacturer_organization_fixture()
    other_site = manufacturing_site_fixture(other.id)
    other_product = manufacturer_product_fixture(other.id)

    {:ok, _result} =
      Manufacturing.generate_primary_serials(
        other.id,
        other_product,
        %{
          "batch_no" => "LOT-X",
          "production_date" => "2026-11-20",
          "expiry_date" => "2027-11-20"
        },
        1,
        other_site.gln
      )

    [foreign | _] = Outbox.list_events(other.id)

    assert ctx.user
           |> auth()
           |> get(~p"/api/v1/manufacturer/epcis/events/#{foreign.id}")
           |> json_response(404)
  end

  defp auth(user) do
    conn =
      post(build_conn(), ~p"/api/v1/login", %{email: user.email, password: valid_user_password()})

    token = json_response(conn, 200)["access_token"]

    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
  end
end
