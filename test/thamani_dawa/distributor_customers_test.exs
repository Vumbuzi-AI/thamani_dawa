defmodule ThamaniDawa.DistributorCustomersTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures,
    only: [customer_fixture: 1, distributor_organization_fixture: 0]

  alias ThamaniDawa.DistributorCustomers

  setup do
    %{organization: distributor_organization_fixture()}
  end

  describe "create_customer/2 phone validation" do
    for phone <- ["12345678", "+1 212 555 0100", "+44 (0)20-1234-5678"] do
      test "accepts #{phone}", %{organization: organization} do
        assert {:ok, customer} =
                 DistributorCustomers.create_customer(organization.id, %{
                   name: "Customer #{System.unique_integer([:positive])}",
                   phone: unquote(phone)
                 })

        assert customer.phone == unquote(phone)
      end
    end

    test "rejects letters", %{organization: organization} do
      assert {:error, changeset} =
               DistributorCustomers.create_customer(organization.id, %{
                 name: "Bad phone",
                 phone: "12345678n"
               })

      assert "Enter a phone number using digits, spaces, hyphens, parentheses, and an optional leading +" in errors_on(
               changeset
             ).phone
    end

    test "phone is optional", %{organization: organization} do
      for phone <- [nil, ""] do
        assert {:ok, customer} =
                 DistributorCustomers.create_customer(organization.id, %{
                   name: "No phone #{System.unique_integer([:positive])}",
                   phone: phone
                 })

        assert is_nil(customer.phone)
      end
    end
  end

  test "update_customer/2 applies the same phone validation", %{organization: organization} do
    customer = customer_fixture(organization.id)

    assert {:error, changeset} =
             DistributorCustomers.update_customer(customer, %{phone: "12345678n"})

    assert "Enter a phone number using digits, spaces, hyphens, parentheses, and an optional leading +" in errors_on(
             changeset
           ).phone

    assert {:ok, updated} =
             DistributorCustomers.update_customer(customer, %{phone: "+1 (212) 555-0100"})

    assert updated.phone == "+1 (212) 555-0100"
  end
end
