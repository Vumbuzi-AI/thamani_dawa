defmodule ThamaniDawaWeb.DarajaCallbackControllerTest do
  use ThamaniDawaWeb.ConnCase, async: false

  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PaymentsFixtures
  import ThamaniDawa.PrescriptionsFixtures

  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.WalletEntry
  alias ThamaniDawa.Prescriptions.Prescription
  alias ThamaniDawa.Repo

  @token "test-callback-token"

  setup do
    previous_config = Application.get_env(:thamani_dawa, ThamaniDawa.Daraja)

    Application.put_env(
      :thamani_dawa,
      ThamaniDawa.Daraja,
      Keyword.put(previous_config || [], :callback_token, @token)
    )

    on_exit(fn ->
      if previous_config do
        Application.put_env(:thamani_dawa, ThamaniDawa.Daraja, previous_config)
      else
        Application.delete_env(:thamani_dawa, ThamaniDawa.Daraja)
      end
    end)

    :ok
  end

  defp callback_path(token \\ @token), do: ~p"/api/mpesa/callback/#{token}"

  defp success_body(checkout_request_id) do
    %{
      "Body" => %{
        "stkCallback" => %{
          "MerchantRequestID" => "merchant-1",
          "CheckoutRequestID" => checkout_request_id,
          "ResultCode" => 0,
          "ResultDesc" => "The service request is processed successfully.",
          "CallbackMetadata" => %{
            "Item" => [
              %{"Name" => "Amount", "Value" => 100},
              %{"Name" => "MpesaReceiptNumber", "Value" => "NLJ7RT61SV"},
              %{"Name" => "TransactionDate", "Value" => 20_260_724_181_000},
              %{"Name" => "PhoneNumber", "Value" => 254_712_345_678}
            ]
          }
        }
      }
    }
  end

  defp failure_body(checkout_request_id, result_code, result_desc) do
    %{
      "Body" => %{
        "stkCallback" => %{
          "MerchantRequestID" => "merchant-1",
          "CheckoutRequestID" => checkout_request_id,
          "ResultCode" => result_code,
          "ResultDesc" => result_desc
        }
      }
    }
  end

  describe "POST /api/mpesa/callback/:token" do
    test "rejects a request with the wrong token", %{conn: conn} do
      conn = post(conn, callback_path("wrong-token"), success_body("ws_CO_1"))

      assert json_response(conn, 401)
    end

    test "success callback completes the payment and credits the wallet", %{conn: conn} do
      organization = organization_fixture()
      prescription = prescription_fixture(%{organization_id: organization.id})

      payment =
        payment_fixture(%{
          organization_id: organization.id,
          prescription_id: prescription.id,
          provider_reference: "ws_CO_success"
        })

      conn = post(conn, callback_path(), success_body("ws_CO_success"))

      assert json_response(conn, 200)

      completed = Payments.get_payment!(organization.id, payment.id)
      assert completed.status == :completed
      assert Repo.aggregate(WalletEntry, :count) == 1
      assert Repo.get!(Prescription, prescription.id).has_paid
    end

    test "cancellation callback fails the payment with cancelled_by_user", %{conn: conn} do
      payment = payment_fixture(%{provider_reference: "ws_CO_cancel"})

      conn =
        post(
          conn,
          callback_path(),
          failure_body("ws_CO_cancel", 1032, "Request cancelled by user")
        )

      assert json_response(conn, 200)

      failed = Payments.get_payment!(payment.organization_id, payment.id)
      assert failed.status == :failed
      assert failed.failure_reason == "cancelled_by_user"
    end

    test "timeout callback fails the payment with timeout", %{conn: conn} do
      payment = payment_fixture(%{provider_reference: "ws_CO_timeout"})

      conn =
        post(conn, callback_path(), failure_body("ws_CO_timeout", 1037, "DS timeout"))

      assert json_response(conn, 200)

      failed = Payments.get_payment!(payment.organization_id, payment.id)
      assert failed.status == :failed
      assert failed.failure_reason == "timeout"
    end

    test "another provider error code fails the payment with a descriptive reason", %{
      conn: conn
    } do
      payment = payment_fixture(%{provider_reference: "ws_CO_other"})

      conn =
        post(conn, callback_path(), failure_body("ws_CO_other", 1, "Insufficient funds"))

      assert json_response(conn, 200)

      failed = Payments.get_payment!(payment.organization_id, payment.id)
      assert failed.status == :failed
      assert failed.failure_reason == "provider_error_1: Insufficient funds"
    end

    test "a malformed payload is ignored and still acknowledged", %{conn: conn} do
      conn = post(conn, callback_path(), %{"unexpected" => "shape"})

      assert json_response(conn, 200)
    end

    test "a stkCallback missing CheckoutRequestID/ResultCode is ignored and still acknowledged",
         %{conn: conn} do
      body = %{"Body" => %{"stkCallback" => %{"MerchantRequestID" => "merchant-1"}}}
      conn = post(conn, callback_path(), body)

      assert json_response(conn, 200)
    end

    test "a callback for an unknown reference is ignored and still acknowledged", %{conn: conn} do
      conn = post(conn, callback_path(), success_body("ws_CO_unknown"))

      assert json_response(conn, 200)
      assert Repo.aggregate(WalletEntry, :count) == 0
    end

    test "a duplicate success callback doesn't double-credit the wallet", %{conn: conn} do
      organization = organization_fixture()
      prescription = prescription_fixture(%{organization_id: organization.id})

      payment_fixture(%{
        organization_id: organization.id,
        prescription_id: prescription.id,
        provider_reference: "ws_CO_dup"
      })

      conn1 = post(conn, callback_path(), success_body("ws_CO_dup"))
      assert json_response(conn1, 200)

      conn2 = post(conn, callback_path(), success_body("ws_CO_dup"))
      assert json_response(conn2, 200)

      assert Repo.aggregate(WalletEntry, :count) == 1
    end

    test "a duplicate cancellation callback stays failed with the same reason", %{conn: conn} do
      payment = payment_fixture(%{provider_reference: "ws_CO_dup_cancel"})

      post(conn, callback_path(), failure_body("ws_CO_dup_cancel", 1032, "cancelled"))
      post(conn, callback_path(), failure_body("ws_CO_dup_cancel", 1032, "cancelled"))

      failed = Payments.get_payment!(payment.organization_id, payment.id)
      assert failed.status == :failed
      assert failed.failure_reason == "cancelled_by_user"
    end
  end
end
