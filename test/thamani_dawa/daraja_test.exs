defmodule ThamaniDawa.DarajaTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.Daraja

  describe "normalize_phone/1" do
    test "normalizes a leading-zero local number" do
      assert Daraja.normalize_phone("0712345678") == {:ok, "254712345678"}
    end

    test "normalizes a leading-zero 01xx number" do
      assert Daraja.normalize_phone("0112345678") == {:ok, "254112345678"}
    end

    test "accepts an already-international number" do
      assert Daraja.normalize_phone("254712345678") == {:ok, "254712345678"}
    end

    test "accepts a plus-prefixed international number" do
      assert Daraja.normalize_phone("+254712345678") == {:ok, "254712345678"}
    end

    test "accepts a bare 9-digit local number" do
      assert Daraja.normalize_phone("712345678") == {:ok, "254712345678"}
    end

    test "strips spaces and dashes" do
      assert Daraja.normalize_phone("0712-345-678") == {:ok, "254712345678"}
    end

    test "rejects a number with the wrong length" do
      assert Daraja.normalize_phone("12345") == {:error, :invalid_phone}
    end

    test "rejects a non-Safaricom-style leading digit" do
      assert Daraja.normalize_phone("0212345678") == {:error, :invalid_phone}
    end

    test "rejects a non-binary value instead of raising" do
      assert Daraja.normalize_phone(712_345_678) == {:error, :invalid_phone}
    end
  end

  describe "initiate_stk_push/4" do
    test "rejects an invalid phone without making any HTTP call" do
      assert Daraja.initiate_stk_push("not-a-phone", 100, "RX1", "Prescription payment") ==
               {:error, :invalid_phone}
    end

    test "rejects a zero/negative amount without making any HTTP call" do
      assert Daraja.initiate_stk_push("0712345678", 0, "RX1", "Prescription payment") ==
               {:error, :invalid_amount}
    end

    test "a successful push returns the checkout and merchant request ids" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token", "expires_in" => "3599"})

          "/mpesa/stkpush/v1/processrequest" ->
            Req.Test.json(conn, %{
              "MerchantRequestID" => "merchant-123",
              "CheckoutRequestID" => "ws_CO_checkout-123",
              "ResponseCode" => "0",
              "ResponseDescription" => "Success. Request accepted for processing",
              "CustomerMessage" => "Success. Request accepted for processing"
            })
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:ok,
                %{checkout_request_id: "ws_CO_checkout-123", merchant_request_id: "merchant-123"}}
    end

    test "an auth failure surfaces as :auth_failed without attempting the STK push" do
      Req.Test.stub(Daraja, fn conn ->
        assert conn.request_path == "/oauth/v1/generate"
        Plug.Conn.send_resp(conn, 401, "")
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :auth_failed}
    end

    test "a non-2xx STK push response surfaces as :provider_error" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            conn
            |> Plug.Conn.put_status(400)
            |> Req.Test.json(%{
              "requestId" => "req-1",
              "errorCode" => "500.001.1001",
              "errorMessage" => "Invalid Access Token"
            })
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :provider_error}
    end

    test "a rejected (non-zero ResponseCode) STK push surfaces as :provider_error" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            Req.Test.json(conn, %{"ResponseCode" => "1", "ResponseDescription" => "Rejected"})
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :provider_error}
    end

    test "a timed-out STK push request surfaces as :timeout" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            Req.Test.transport_error(conn, :timeout)
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :timeout}
    end

    test "a timed-out auth request surfaces as :timeout" do
      Req.Test.stub(Daraja, fn conn ->
        assert conn.request_path == "/oauth/v1/generate"
        Req.Test.transport_error(conn, :timeout)
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :timeout}
    end

    test "a non-timeout transport failure during auth also surfaces as :timeout" do
      Req.Test.stub(Daraja, fn conn ->
        assert conn.request_path == "/oauth/v1/generate"
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :timeout}
    end

    test "a non-timeout transport failure during the STK push also surfaces as :timeout" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            Req.Test.transport_error(conn, :econnrefused)
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :timeout}
    end

    test "a non-map STK push error body still surfaces as :provider_error" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            conn |> Plug.Conn.put_status(502) |> Plug.Conn.send_resp(502, "Bad Gateway")
        end
      end)

      assert Daraja.initiate_stk_push("0712345678", 100, "RX1", "Prescription payment") ==
               {:error, :provider_error}
    end

    test "a float amount is rounded up to a whole number" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            assert decoded["Amount"] == 101

            Req.Test.json(conn, %{
              "MerchantRequestID" => "merchant-123",
              "CheckoutRequestID" => "ws_CO_checkout-123",
              "ResponseCode" => "0"
            })
        end
      end)

      assert {:ok, _result} =
               Daraja.initiate_stk_push("0712345678", 100.01, "RX1", "Prescription payment")
    end

    test "a Decimal amount is rounded up to a whole number" do
      Req.Test.stub(Daraja, fn conn ->
        case conn.request_path do
          "/oauth/v1/generate" ->
            Req.Test.json(conn, %{"access_token" => "test-token"})

          "/mpesa/stkpush/v1/processrequest" ->
            {:ok, body, conn} = Plug.Conn.read_body(conn)
            decoded = Jason.decode!(body)
            assert decoded["Amount"] == 101

            Req.Test.json(conn, %{
              "MerchantRequestID" => "merchant-123",
              "CheckoutRequestID" => "ws_CO_checkout-123",
              "ResponseCode" => "0"
            })
        end
      end)

      assert {:ok, _result} =
               Daraja.initiate_stk_push(
                 "0712345678",
                 Decimal.new("100.01"),
                 "RX1",
                 "Prescription payment"
               )
    end
  end
end
