defmodule ThamaniDawaWeb.Gs1SsoControllerTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import ThamaniDawa.AccountsFixtures

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Repo

  describe "GET /auth/gs1" do
    test "stores fresh state and verifier and redirects with S256 PKCE", %{conn: conn} do
      first = get(conn, ~p"/auth/gs1")
      first_query = redirect_query(first)
      first_state = get_session(first, "gs1_sso_state")
      first_verifier = get_session(first, "gs1_sso_pkce_verifier")

      assert first_query["response_type"] == "code"
      assert first_query["client_id"] == "test-client-id"
      assert first_query["redirect_uri"] == "https://app.example.test/auth/gs1/callback"
      assert first_query["scope"] == "openid profile email"
      assert first_query["state"] == first_state
      assert first_query["code_challenge_method"] == "S256"

      assert first_query["code_challenge"] ==
               :sha256
               |> :crypto.hash(first_verifier)
               |> Base.url_encode64(padding: false)

      second = get(recycle(first), ~p"/auth/gs1")
      refute get_session(second, "gs1_sso_state") == first_state
      refute get_session(second, "gs1_sso_pkce_verifier") == first_verifier
    end
  end

  describe "GET /auth/gs1/callback" do
    test "rejects and consumes an invalid state without contacting GS1", %{conn: conn} do
      Req.Test.stub(ThamaniDawa.Gs1Sso, fn _conn ->
        flunk("invalid state must not reach the upstream provider")
      end)

      conn =
        conn
        |> get(~p"/auth/gs1")
        |> recycle()
        |> get(~p"/auth/gs1/callback?code=secret-code&state=wrong")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired or was invalid"
      assert get_session(conn, "gs1_sso_state") == nil
      assert get_session(conn, "gs1_sso_pkce_verifier") == nil
    end

    test "exchanges the code, links by verified email, renews the session, and signs in", %{
      conn: conn
    } do
      user = user_fixture()
      test_pid = self()

      Req.Test.stub(ThamaniDawa.Gs1Sso, fn upstream_conn ->
        case upstream_conn.request_path do
          "/oauth/token" ->
            {:ok, body, upstream_conn} = Plug.Conn.read_body(upstream_conn)
            send(test_pid, {:token_form, URI.decode_query(body)})
            Req.Test.json(upstream_conn, %{"access_token" => "server-only-token"})

          "/oauth/userinfo" ->
            send(
              test_pid,
              {:authorization, Plug.Conn.get_req_header(upstream_conn, "authorization")}
            )

            Req.Test.json(upstream_conn, %{
              "sub" => "gs1-user-123",
              "email" => user.email,
              "email_verified" => true,
              "organization" => nil
            })
        end
      end)

      started =
        conn |> init_test_session(%{"pre_auth_marker" => "must-be-cleared"}) |> get(~p"/auth/gs1")

      state = get_session(started, "gs1_sso_state")
      verifier = get_session(started, "gs1_sso_pkce_verifier")

      conn =
        started
        |> recycle()
        |> get(~p"/auth/gs1/callback?code=authorization-code&state=#{state}")

      assert_receive {:token_form, form}
      assert form["code"] == "authorization-code"
      assert form["code_verifier"] == verifier
      assert form["client_secret"] == "test-client-secret"
      assert form["redirect_uri"] == "https://app.example.test/auth/gs1/callback"
      assert_receive {:authorization, ["Bearer server-only-token"]}

      assert redirected_to(conn) == "/onboarding"
      assert get_session(conn, "user_token")
      assert get_session(conn, "pre_auth_marker") == nil
      assert Repo.reload!(user).gs1_sso_sub == "gs1-user-123"
    end

    test "uses the linked sub on later sign-in even when organization fields and email change", %{
      conn: conn
    } do
      user = user_fixture()
      {:ok, linked_user} = Accounts.link_gs1_sso_user("stable-sub", user.email)

      stub_success(%{
        "sub" => "stable-sub",
        "email" => "changed@example.com",
        "email_verified" => true,
        "organization" => nil
      })

      conn = complete_callback(conn)

      assert redirected_to(conn) == "/onboarding"

      assert Accounts.get_user_by_session_token(get_session(conn, "user_token")).id ==
               linked_user.id
    end

    test "rejects an unknown identity according to the existing account creation policy", %{
      conn: conn
    } do
      stub_success(%{
        "sub" => "unknown-sub",
        "email" => "unknown@example.com",
        "email_verified" => true
      })

      conn = complete_callback(conn)

      assert redirected_to(conn) == ~p"/login"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Create or accept your local account"
    end

    test "handles token and user-info upstream failures", %{conn: conn} do
      Req.Test.stub(ThamaniDawa.Gs1Sso, fn upstream_conn ->
        upstream_conn
        |> Plug.Conn.put_status(503)
        |> Req.Test.json(%{"error" => "temporarily_unavailable"})
      end)

      conn = complete_callback(conn)

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be completed"
      refute get_session(conn, "user_token")
    end

    test "handles a user-info failure after a successful token exchange", %{conn: conn} do
      Req.Test.stub(ThamaniDawa.Gs1Sso, fn upstream_conn ->
        case upstream_conn.request_path do
          "/oauth/token" ->
            Req.Test.json(upstream_conn, %{"access_token" => "test-token"})

          "/oauth/userinfo" ->
            upstream_conn
            |> Plug.Conn.put_status(502)
            |> Req.Test.json(%{"error" => "upstream_failure"})
        end
      end)

      conn = complete_callback(conn)

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "could not be completed"
      refute get_session(conn, "user_token")
    end
  end

  defp complete_callback(conn) do
    started = get(conn, ~p"/auth/gs1")
    state = get_session(started, "gs1_sso_state")

    started
    |> recycle()
    |> get(~p"/auth/gs1/callback?code=test-code&state=#{state}")
  end

  defp stub_success(userinfo) do
    Req.Test.stub(ThamaniDawa.Gs1Sso, fn upstream_conn ->
      case upstream_conn.request_path do
        "/oauth/token" -> Req.Test.json(upstream_conn, %{"access_token" => "test-token"})
        "/oauth/userinfo" -> Req.Test.json(upstream_conn, userinfo)
      end
    end)
  end

  defp redirect_query(conn) do
    conn
    |> redirected_to()
    |> URI.parse()
    |> Map.fetch!(:query)
    |> URI.decode_query()
  end
end
