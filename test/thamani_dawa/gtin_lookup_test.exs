defmodule ThamaniDawa.GtinLookupTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.GtinLookup

  @valid_gtin "614141000012"
  @normalized "00614141000012"

  describe "lookup/1" do
    test "invalid GTIN returns an error without making any HTTP call" do
      # No Req.Test.stub registered — if this reached the network, it would raise, not return.
      assert GtinLookup.lookup("not-a-valid-gtin") == {:error, :invalid_gtin}
    end

    test "a match prefills only the fields the provider returned" do
      Req.Test.stub(GtinLookup, fn conn ->
        Req.Test.json(conn, [
          %{
            "brandName" => [%{"value" => "Panadol"}],
            "productDescription" => [%{"value" => "Paracetamol 500mg Tablets"}],
            "gs1Licence" => %{"licenseeName" => "GlaxoSmithKline"},
            "netContent" => [%{"value" => "100", "unitCode" => "H87"}]
          }
        ])
      end)

      assert GtinLookup.lookup(@valid_gtin) ==
               {:ok,
                %{
                  gtin: @normalized,
                  brand_name: "Panadol",
                  generic_name: "Paracetamol 500mg Tablets",
                  manufacturer: "GlaxoSmithKline",
                  uom: "H87"
                }}
    end

    test "a match missing some fields only prefills what's present" do
      Req.Test.stub(GtinLookup, fn conn ->
        Req.Test.json(conn, [%{"brandName" => [%{"value" => "Panadol"}]}])
      end)

      assert GtinLookup.lookup(@valid_gtin) == {:ok, %{gtin: @normalized, brand_name: "Panadol"}}
    end

    test "a missing or blank licensee name doesn't prefill manufacturer" do
      Req.Test.stub(GtinLookup, fn conn ->
        Req.Test.json(conn, [
          %{"brandName" => [%{"value" => "Panadol"}], "gs1Licence" => %{"licenseeName" => ""}}
        ])
      end)

      assert GtinLookup.lookup(@valid_gtin) == {:ok, %{gtin: @normalized, brand_name: "Panadol"}}
    end

    test "an empty result array is a miss, not a crash" do
      Req.Test.stub(GtinLookup, fn conn -> Req.Test.json(conn, []) end)

      assert GtinLookup.lookup(@valid_gtin) == {:error, :not_found}
    end

    test "a GS1 validationErrors response is a miss, not treated as a match" do
      Req.Test.stub(GtinLookup, fn conn ->
        Req.Test.json(conn, [
          %{
            "code" => 5,
            "gtin" => @normalized,
            "validationErrors" => [
              %{
                "errors" => [
                  %{"errorCode" => "E039", "message" => "not supported for open supply chains"}
                ],
                "property" => "gtin"
              }
            ]
          }
        ])
      end)

      assert GtinLookup.lookup(@valid_gtin) == {:error, :not_found}
    end

    test "a non-2xx status is a provider error" do
      Req.Test.stub(GtinLookup, fn conn -> Plug.Conn.send_resp(conn, 500, "") end)

      assert GtinLookup.lookup(@valid_gtin) == {:error, :provider_error}
    end

    test "a timed-out request surfaces as :timeout" do
      Req.Test.stub(GtinLookup, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert GtinLookup.lookup(@valid_gtin) == {:error, :timeout}
    end

    test "any other transport failure also surfaces as :timeout" do
      Req.Test.stub(GtinLookup, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert GtinLookup.lookup(@valid_gtin) == {:error, :timeout}
    end
  end
end
