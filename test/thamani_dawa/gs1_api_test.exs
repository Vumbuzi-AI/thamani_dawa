defmodule ThamaniDawa.Gs1ApiTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.Gs1Api.Request

  setup do
    organization = organization_fixture()
    user = user_fixture(%{organization_id: organization.id})
    %{scope: Scope.for_user(user), organization: organization}
  end

  describe "create_sscc/2" do
    test "records the attempt before the call and settles it on success", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{"sscc" => %{"sscc" => "100000000000000018"}})
      end)

      assert {:ok, %{"sscc" => %{"sscc" => "100000000000000018"}}} =
               Gs1Api.create_sscc(scope, %{batch_info: [%{gtin: "6161100000018"}]})

      assert [%Request{} = record] = Gs1Api.list_requests(scope.organization_id)
      assert record.endpoint == "/api/create_sscc"
      assert record.status == :succeeded
      assert record.user_id == scope.user.id
      assert record.request_id =~ ~r/^[0-9a-f-]{36}$/
    end

    test "sends the recorded request_id so a replay is recognisable", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, %{"echoed_request_id" => Jason.decode!(body)["request_id"]})
      end)

      assert {:ok, %{"echoed_request_id" => sent_id}} = Gs1Api.create_sscc(scope, %{})
      assert [%Request{request_id: ^sent_id}] = Gs1Api.list_requests(scope.organization_id)
    end

    test "a rejection is passed through with GS1's own message", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        conn
        |> Plug.Conn.put_status(422)
        |> Req.Test.json(%{"result" => "You have no company prefix configured"})
      end)

      assert {:error, error} = Gs1Api.create_sscc(scope, %{})
      assert error.reason == :no_prefix
      assert error.message == "You have no company prefix configured"

      assert [%Request{status: :failed, error_message: message}] =
               Gs1Api.list_requests(scope.organization_id)

      assert message == "You have no company prefix configured"
    end

    test "the audit row summarises rather than stores a large serial list", %{scope: scope} do
      serials = Enum.map(1..1_000, &"serial-#{&1}")
      Req.Test.stub(Gs1Api, fn conn -> Req.Test.json(conn, %{"primary_serials" => serials}) end)

      assert {:ok, %{"primary_serials" => returned}} =
               Gs1Api.create_serialised_datamatrix(scope, %{barcode: "6161100000018"})

      assert length(returned) == 1_000

      assert [%Request{response_summary: summary}] = Gs1Api.list_requests(scope.organization_id)
      assert summary == %{"primary_serials" => %{"count" => 1_000}}
    end

    test "a transport failure leaves a failed row, not a pending one", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, error} = Gs1Api.create_sscc(scope, %{})
      assert error.reason == :timeout

      assert [%Request{status: :failed}] = Gs1Api.list_requests(scope.organization_id)
      assert Gs1Api.list_pending_requests(scope.organization_id) == []
    end

    test "audit rows are scoped to the organization that made the call", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn -> Req.Test.json(conn, %{"ok" => true}) end)

      other_organization = organization_fixture()
      assert {:ok, _body} = Gs1Api.create_sscc(scope, %{})

      assert Gs1Api.list_requests(other_organization.id) == []
    end
  end

  describe "verify_gtin/2" do
    test "sends the 13-digit form of a GTIN we store as GTIN-14", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        Req.Test.json(conn, %{"sent" => Jason.decode!(body)["barcode"]})
      end)

      assert {:ok, %{"sent" => "6161100000018"}} =
               Gs1Api.verify_gtin(scope, "06161100000018")
    end

    test "a malformed GTIN never reaches the network", %{scope: scope} do
      # No stub registered: a request here would raise rather than return.
      assert Gs1Api.verify_gtin(scope, "not-a-gtin") == {:error, :invalid_gtin}
    end

    test "reads are not written to the audit table", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn -> Req.Test.json(conn, %{"name" => "Panadol"}) end)

      assert {:ok, _body} = Gs1Api.verify_gtin(scope, "6161100000018")
      assert Gs1Api.list_requests(scope.organization_id) == []
    end
  end
end
