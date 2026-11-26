defmodule ThamaniDawaWeb.ApiKeysLiveTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.DistributorFixtures
  import ThamaniDawa.ManufacturerFixtures

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
    assert has_element?(view, "#gs1-api-key-settings", "GS1 member API key")
    assert has_element?(view, "#gs1-api-key-row", "No key saved")
    assert has_element?(view, "span[id='nav-label-/distributor/api-keys']", "API keys")
    refute has_element?(view, "[data-confirm]")
    refute has_element?(view, ".is-ghost, [variant=ghost]")
  end

  test "saves the GS1 key used to create and fetch SSCCs", %{conn: conn, distributor: distributor} do
    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys")

    view |> element("#edit-gs1-key") |> render_click()

    view
    |> form("#gs1-api-key-form", %{key: "gs1-secret-key-9876"})
    |> render_submit()

    assert has_element?(view, "#gs1-api-key-row code", "9876")
    assert has_element?(view, "#gs1-api-key-row", "Key ending")

    organization = Organizations.get_organization!(distributor.organization_id)
    assert organization.gs1_api_key == "gs1-secret-key-9876"
    assert organization.gs1_api_key_last4 == "9876"
  end

  test "clears a saved key behind a TD confirm instead of the browser dialog", %{
    conn: conn,
    distributor: distributor
  } do
    {:ok, _} =
      Organizations.set_gs1_api_key(
        Organizations.get_organization!(distributor.organization_id),
        "gs1-secret-key-9876"
      )

    {:ok, view, _html} = live(conn, ~p"/distributor/api-keys")

    refute has_element?(view, "#clear-key-confirm")
    view |> element("#clear-gs1-key") |> render_click()

    assert has_element?(view, "#clear-key-confirm", "Clear this key?")
    assert has_element?(view, "#clear-key-confirm", "GS1 key ending 9876")

    view |> element("#confirm-clear-key") |> render_click()

    refute has_element?(view, "#clear-key-confirm")
    assert has_element?(view, "#gs1-api-key-row", "No key saved")

    organization = Organizations.get_organization!(distributor.organization_id)
    assert organization.gs1_api_key_last4 in [nil, ""]
  end

  test "the organization admin page is the same set of keys", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/org/api-keys")

    assert has_element?(view, "#epcis-api-key-settings", "TNT API key")
    assert has_element?(view, "#gs1-api-key-settings", "GS1 member API key")
    assert has_element?(view, "a[href$='/api-keys']", "API keys")
  end

  test "the manufacturer page stores the same keys", %{conn: conn} do
    manufacturer = manufacturer_user_fixture(%{roles: [:admin, :manufacturer]})
    conn = conn |> init_test_session(%{}) |> ThamaniDawaWeb.UserAuth.log_in_user(manufacturer)

    {:ok, view, _html} = live(conn, ~p"/manufacturer/api-keys")

    assert has_element?(view, "#epcis-api-key-settings", "Add your TNT API key")
    assert has_element?(view, "#tnt-api-key-manufacturer", "No key saved")
    assert has_element?(view, "#gs1-api-key-settings", "GS1 member API key")
    assert has_element?(view, "span[id='nav-label-/manufacturer/api-keys']", "API keys")
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
