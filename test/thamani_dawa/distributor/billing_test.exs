defmodule ThamaniDawa.Distributor.BillingTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.DistributorFixtures
  alias ThamaniDawa.Distributor.{Billing, SerialUsage}
  alias ThamaniDawa.Organizations

  setup do
    organization = distributor_organization_fixture()
    user = distributor_user_fixture(%{organization_id: organization.id})
    %{organization: organization, user: user}
  end

  describe "prepay" do
    test "a confirmed bundle becomes the active allowance with an invoice", ctx do
      payment = prepay_allowance_fixture(ctx.organization.id, ctx.user, 200)

      assert payment.status == "paid"
      assert "INV-SER-" <> _ = payment.invoice_number

      usage = Billing.active_usage(ctx.organization.id)
      assert usage.type == "prepay"
      assert SerialUsage.serials_left(usage) == 200
    end

    test "confirm_paid/1 is idempotent", ctx do
      payment = prepay_allowance_fixture(ctx.organization.id, ctx.user, 200)

      assert {:ok, again} = Billing.confirm_paid(payment)
      assert again.invoice_number == payment.invoice_number
      assert SerialUsage.serials_left(Billing.active_usage(ctx.organization.id)) == 200
    end

    test "authorize_generation/2 spends serials, then the buffer", ctx do
      prepay_allowance_fixture(ctx.organization.id, ctx.user, 100)

      assert {:ok, usage} = Billing.authorize_generation(ctx.organization.id, 100)
      assert SerialUsage.serials_left(usage) == 0

      assert {:ok, usage} = Billing.authorize_generation(ctx.organization.id, 3)
      assert usage.running_buffer == 3

      assert {:error, :insufficient_allowance} =
               Billing.authorize_generation(ctx.organization.id, 10_000)
    end

    test "the next purchase bills the buffer", ctx do
      prepay_allowance_fixture(ctx.organization.id, ctx.user, 100)
      {:ok, _} = Billing.authorize_generation(ctx.organization.id, 103)

      charge = Billing.prepay_quote(Organizations.get_organization!(ctx.organization.id), 100)
      assert charge.buffer_quantity == 3
      assert charge.quantity == 103
    end

    test "rejects a bundle below the minimum", ctx do
      {:ok, organization} = Billing.choose_prepay(ctx.organization)

      assert {:error, :quantity_below_minimum} =
               Billing.start_prepay_payment(organization, ctx.user, %{
                 "quantity" => "1",
                 "method" => "manual",
                 "manual_reference" => "X"
               })
    end
  end

  describe "flex" do
    test "opens a cycle and bills exactly what was generated", ctx do
      assert {:ok, %SerialUsage{type: "flex"}} =
               Billing.ensure_first_postpay_cycle(ctx.organization)

      assert {:ok, _} = Billing.authorize_generation(ctx.organization.id, 7)

      organization = Organizations.get_organization!(ctx.organization.id)
      assert Billing.postpay_quote(organization).quantity == 7

      assert {:ok, payment} =
               Billing.start_postpay_payment(organization, ctx.user, %{
                 "method" => "manual",
                 "manual_reference" => "BANK-1"
               })

      assert payment.status == "paid"
      assert SerialUsage.generated(Billing.active_usage(ctx.organization.id)) == 0
    end

    test "caps usage at the buffer limit once overdue", ctx do
      {:ok, usage} = Billing.ensure_first_postpay_cycle(ctx.organization)

      billing_date =
        DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.truncate(:second)

      usage
      |> Ecto.Changeset.change(billing_date: billing_date)
      |> Repo.update!()

      assert {:ok, usage} = Billing.authorize_generation(ctx.organization.id, 2)
      assert usage.running_buffer == 2
      assert {:error, :overdue} = Billing.authorize_generation(ctx.organization.id, 100_000)
    end
  end

  test "a plan can't be chosen twice", ctx do
    {:ok, organization} = Billing.choose_prepay(ctx.organization)
    assert {:error, :plan_already_selected} = Billing.ensure_first_postpay_cycle(organization)
  end

  test "a manual reference confirms payment immediately", ctx do
    {:ok, organization} = Billing.choose_prepay(ctx.organization)

    attrs = %{
      "quantity" => "200",
      "method" => "manual",
      "manual_reference" => "BANK-UNIQUE-1"
    }

    assert {:ok, payment} = Billing.start_prepay_payment(organization, ctx.user, attrs)
    assert payment.status == "paid"
    assert payment.manual_reference == "BANK-UNIQUE-1"
    assert "INV-SER-" <> _ = payment.invoice_number
    assert SerialUsage.serials_left(Billing.active_usage(ctx.organization.id)) == 200
  end

  test "M-Pesa cannot be selected while Daraja is disabled", ctx do
    {:ok, organization} = Billing.choose_prepay(ctx.organization)

    assert {:error, :mpesa_unavailable} =
             Billing.start_prepay_payment(organization, ctx.user, %{
               "quantity" => "200",
               "method" => "mpesa",
               "phone" => "0712345678"
             })
  end
end
