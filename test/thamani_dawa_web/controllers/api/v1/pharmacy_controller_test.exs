defmodule ThamaniDawaWeb.Api.V1.PharmacyControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.BatchesFixtures
  import ThamaniDawa.SitesFixtures

  setup do
    admin = user_fixture()
    pharmacy = site_fixture(%{organization_id: admin.organization_id, site_type: :pharmacy})
    lab = site_fixture(%{organization_id: admin.organization_id, site_type: :lab})

    pharmacist =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        site_id: pharmacy.id,
        role: :pharmacist
      })

    unassigned =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        role: :pharmacist
      })

    technician =
      staff_fixture(%{
        organization_id: admin.organization_id,
        invited_by_id: admin.id,
        site_id: lab.id,
        role: :lab_technician
      })

    {:ok,
     pharmacy: pharmacy, pharmacist: pharmacist, unassigned: unassigned, technician: technician}
  end

  test "a pharmacist scan of approved stock is found", %{
    pharmacy: pharmacy,
    pharmacist: pharmacist
  } do
    batch = batch_fixture(%{organization_id: pharmacist.organization_id, site_id: pharmacy.id})

    conn = post(auth(pharmacist), ~p"/api/v1/pharmacy/scans", %{raw: batch.gtin})
    body = json_response(conn, 200)

    assert body["data"]["state"] == "found"
    assert Enum.any?(body["data"]["batches"], &(&1["id"] == batch.id))
  end

  test "a lab technician cannot open the pharmacy counter", %{technician: technician} do
    conn = post(auth(technician), ~p"/api/v1/pharmacy/scans", %{raw: "01234567890128"})

    assert json_response(conn, 403)["error"]["code"] == "forbidden"
  end

  test "a pharmacist with no current site must choose one", %{unassigned: unassigned} do
    conn = post(auth(unassigned), ~p"/api/v1/pharmacy/scans", %{raw: "01234567890128"})

    assert json_response(conn, 422)["error"]["code"] == "site_required"
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
