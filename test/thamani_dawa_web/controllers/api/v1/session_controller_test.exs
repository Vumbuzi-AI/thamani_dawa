defmodule ThamaniDawaWeb.Api.V1.SessionControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures

  test "login returns a bearer pair and no password", %{conn: conn} do
    user = user_fixture()

    conn = post(conn, ~p"/api/v1/login", %{email: user.email, password: valid_user_password()})
    body = json_response(conn, 200)

    assert body["token_type"] == "Bearer"
    assert is_binary(body["access_token"])
    assert is_binary(body["refresh_token"])
    assert body["user"]["id"] == user.id
    assert body["user"]["email"] == user.email
    refute Map.has_key?(body["user"], "hashed_password")
    refute body["user"]["password"]
  end

  test "a bad password is invalid credentials", %{conn: conn} do
    user = user_fixture()

    conn = post(conn, ~p"/api/v1/login", %{email: user.email, password: "not the password"})

    assert json_response(conn, 401)["error"]["code"] == "invalid_credentials"
  end

  test "me requires a bearer token", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/me")

    assert json_response(conn, 401)["error"]["code"] == "unauthorized"
  end

  test "me returns the signed-in user", %{conn: conn} do
    user = user_fixture()
    token = access_token(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/v1/me")

    assert json_response(conn, 200)["data"]["email"] == user.email
  end

  test "logout revokes the access token", %{conn: conn} do
    user = user_fixture()
    token = access_token(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> post(~p"/api/v1/logout")

    assert response(conn, 204)

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/v1/me")

    assert json_response(conn, 401)["error"]["code"] == "unauthorized"
  end

  defp access_token(user) do
    conn =
      post(build_conn(), ~p"/api/v1/login", %{email: user.email, password: valid_user_password()})

    json_response(conn, 200)["access_token"]
  end
end
