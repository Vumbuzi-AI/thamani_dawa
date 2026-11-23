defmodule ThamaniDawaWeb.ApiKeysLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures

  alias ThamaniDawa.Organizations

  setup %{conn: conn} do
    distributor = distributor_user_fixture(%{roles: [:admin, :distributor]})

    conn =
      conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(distributor)

    %{conn: conn, distributor: distributor}
  end

  test "holds the TNT key card and a GS1 key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys")

    assert has_element?(view, "#epcis-api-key-settings", "Add your TNT API key")
    assert has_element?(view, "#tnt-api-key-distributor", "No key saved")
    assert has_element?(view, "#gs1-api-key-settings", "GS1 API key")
    assert has_element?(view, "#gs1-api-key-row", "No key saved")
  end

  test "saves the GS1 key used to create and fetch SSCCs", %{conn: conn, distributor: distributor} do
    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys")

    view |> element("#edit-gs1-key") |> render_click()

    view
    |> form("#gs1-api-key-form", %{key: "gs1-secret-key-9876"})
    |> render_submit()

    assert has_element?(view, "#gs1-api-key-row", "9876")

    organization = Organizations.get_organization!(distributor.organization_id)
    assert organization.gs1_api_key == "gs1-secret-key-9876"
    assert organization.gs1_api_key_last4 == "9876"
  end

  test "the organization admin page is the same set of keys", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/org/api-keys")

    assert has_element?(view, "#epcis-api-key-settings", "TNT API key")
    assert has_element?(view, "#gs1-api-key-settings", "GS1 API key")
  end

  test "renders inside the onboarding shell when return_to=onboarding", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys?return_to=onboarding")

    assert has_element?(view, "#keys-onboarding-continue")
    assert has_element?(view, "#keys-onboarding-back")
    assert has_element?(view, "#keys-onboarding-skip")
  end

  test "continue navigates back to onboarding on completion", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys?return_to=onboarding")

    {:error, {:live_redirect, %{to: to}}} =
      view |> element("#keys-onboarding-continue") |> render_click()

    assert to == ~p"/onboarding?complete=1"
  end
end
