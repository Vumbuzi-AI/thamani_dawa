defmodule ThamaniDawa.PaymentsTest do
  use ThamaniDawa.DataCase, async: true

  alias ThamaniDawa.Payments
  alias ThamaniDawa.Payments.Payment
  alias ThamaniDawa.Payments.WalletEntry

  import ThamaniDawa.LabOrdersFixtures
  import ThamaniDawa.OrganizationsFixtures
  import ThamaniDawa.PaymentsFixtures
  import ThamaniDawa.PrescriptionsFixtures

  describe "create_payment/2" do
    test "requires amount and payment_type" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{lab_order_id: lab_order.id})

      assert %{amount: ["can't be blank"], payment_type: ["can't be blank"]} =
               errors_on(changeset)
    end

    test "creates a payment against a lab_order, deriving order_type and site_id" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:ok, %Payment{} = payment} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert payment.organization_id == organization.id
      assert payment.order_type == :lab_order
      assert payment.site_id == lab_order.site_id
      assert payment.status == :pending
    end

    test "creates a payment against a prescription, deriving order_type and site_id from its patient_visit" do
      organization = organization_fixture()
      prescription = prescription_fixture(%{organization_id: organization.id})

      patient_visit =
        Repo.get!(ThamaniDawa.PatientVisits.PatientVisit, prescription.patient_visit_id)

      assert {:ok, %Payment{} = payment} =
               Payments.create_payment(organization.id, %{
                 prescription_id: prescription.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert payment.order_type == :prescription
      assert payment.site_id == patient_visit.site_id
    end

    test "rejects an amount of zero" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order.id,
                 amount: Decimal.new("0"),
                 payment_type: "Cash"
               })

      assert %{amount: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "rejects a payment_type outside the approved list" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order.id,
                 amount: Decimal.new("100"),
                 payment_type: "Bitcoin"
               })

      assert %{payment_type: ["must be one of the approved payment methods"]} =
               errors_on(changeset)
    end

    test "rejects a payment referencing neither a prescription nor a lab_order" do
      organization = organization_fixture()

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert %{order_type: ["must reference exactly one of prescription_id or lab_order_id"]} =
               errors_on(changeset)
    end

    test "rejects a payment referencing both a prescription and a lab_order" do
      organization = organization_fixture()
      prescription = prescription_fixture(%{organization_id: organization.id})
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 prescription_id: prescription.id,
                 lab_order_id: lab_order.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert %{order_type: ["must reference exactly one of prescription_id or lab_order_id"]} =
               errors_on(changeset)
    end

    test "accepts an explicit nil for the unused order reference" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert {:ok, %Payment{order_type: :lab_order}} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order.id,
                 prescription_id: nil,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })
    end

    test "rejects a lab_order_id belonging to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      hostile_lab_order = lab_order_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: hostile_lab_order.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert %{lab_order_id: ["does not belong to this organization"]} = errors_on(changeset)
      assert Payments.list_payments(organization.id) == []
    end

    test "rejects a prescription_id belonging to a different organization" do
      organization = organization_fixture()
      other_org = organization_fixture()
      hostile_prescription = prescription_fixture(%{organization_id: other_org.id})

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 prescription_id: hostile_prescription.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert %{prescription_id: ["does not belong to this organization"]} = errors_on(changeset)
      assert Payments.list_payments(organization.id) == []
    end

    test "rejects a duplicate provider_reference within the same organization" do
      organization = organization_fixture()
      lab_order_a = lab_order_fixture(%{organization_id: organization.id})
      lab_order_b = lab_order_fixture(%{organization_id: organization.id})

      assert {:ok, _payment} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order_a.id,
                 amount: Decimal.new("100"),
                 payment_type: "Mobile Money",
                 provider_reference: "TXN-1"
               })

      assert {:error, changeset} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order_b.id,
                 amount: Decimal.new("50"),
                 payment_type: "Mobile Money",
                 provider_reference: "TXN-1"
               })

      assert %{provider_reference: ["has already been used for a payment"]} =
               errors_on(changeset)
    end

    test "allows the same provider_reference to be reused across different organizations" do
      organization_a = organization_fixture()
      organization_b = organization_fixture()
      lab_order_a = lab_order_fixture(%{organization_id: organization_a.id})
      lab_order_b = lab_order_fixture(%{organization_id: organization_b.id})

      assert {:ok, _payment_a} =
               Payments.create_payment(organization_a.id, %{
                 lab_order_id: lab_order_a.id,
                 amount: Decimal.new("100"),
                 payment_type: "Mobile Money",
                 provider_reference: "SHARED-REF"
               })

      assert {:ok, _payment_b} =
               Payments.create_payment(organization_b.id, %{
                 lab_order_id: lab_order_b.id,
                 amount: Decimal.new("100"),
                 payment_type: "Mobile Money",
                 provider_reference: "SHARED-REF"
               })
    end

    test "allows multiple payments with no provider_reference" do
      organization = organization_fixture()
      lab_order_a = lab_order_fixture(%{organization_id: organization.id})
      lab_order_b = lab_order_fixture(%{organization_id: organization.id})

      assert {:ok, _payment_a} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order_a.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })

      assert {:ok, _payment_b} =
               Payments.create_payment(organization.id, %{
                 lab_order_id: lab_order_b.id,
                 amount: Decimal.new("100"),
                 payment_type: "Cash"
               })
    end
  end

  describe "complete_payment/1" do
    test "transitions pending to completed, stamping paid_at" do
      payment = payment_fixture()

      assert is_nil(payment.paid_at)
      assert {:ok, completed} = Payments.complete_payment(payment)
      assert completed.status == :completed
      assert %DateTime{} = completed.paid_at
    end

    test "credits the site wallet exactly once" do
      payment = payment_fixture(%{amount: Decimal.new("250")})

      assert {:ok, completed} = Payments.complete_payment(payment)

      assert [%WalletEntry{} = entry] =
               Repo.all(from w in WalletEntry, where: w.payment_id == ^completed.id)

      assert entry.organization_id == completed.organization_id
      assert entry.site_id == completed.site_id
      assert Decimal.equal?(entry.amount, Decimal.new("250"))
    end

    test "is idempotent when called again on an already-completed payment" do
      payment = payment_fixture()

      assert {:ok, completed} = Payments.complete_payment(payment)
      assert {:ok, ^completed} = Payments.complete_payment(completed)

      assert Repo.aggregate(WalletEntry, :count) == 1
    end

    test "rejects completing an already-failed payment, creating no wallet credit" do
      payment = payment_fixture()

      assert {:ok, failed} = Payments.fail_payment(payment, "declined")
      assert {:error, :already_failed} = Payments.complete_payment(failed)
      assert Repo.aggregate(WalletEntry, :count) == 0
    end
  end

  describe "fail_payment/2" do
    test "transitions pending to failed, recording the reason" do
      payment = payment_fixture()

      assert {:ok, failed} = Payments.fail_payment(payment, "card declined")
      assert failed.status == :failed
      assert failed.failure_reason == "card declined"
      assert Repo.aggregate(WalletEntry, :count) == 0
    end

    test "is idempotent when called again on an already-failed payment" do
      payment = payment_fixture()

      assert {:ok, failed} = Payments.fail_payment(payment, "card declined")
      assert {:ok, ^failed} = Payments.fail_payment(failed, "a different reason")
    end

    test "rejects failing an already-completed payment" do
      payment = payment_fixture()

      assert {:ok, completed} = Payments.complete_payment(payment)
      assert {:error, :already_completed} = Payments.fail_payment(completed, "oops")
    end
  end

  describe "site_earnings/2" do
    test "returns 0 when there are no wallet entries" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      assert Decimal.equal?(
               Payments.site_earnings(organization.id, lab_order.site_id),
               Decimal.new(0)
             )
    end

    test "does not count a failed payment" do
      payment = payment_fixture()
      {:ok, _failed} = Payments.fail_payment(payment, "declined")

      assert Decimal.equal?(
               Payments.site_earnings(payment.organization_id, payment.site_id),
               Decimal.new(0)
             )
    end

    test "sums wallet credits for completed payments at a site" do
      organization = organization_fixture()
      lab_order = lab_order_fixture(%{organization_id: organization.id})

      payment_a =
        payment_fixture(%{
          organization_id: organization.id,
          lab_order_id: lab_order.id,
          amount: Decimal.new("100")
        })

      payment_b =
        payment_fixture(%{
          organization_id: organization.id,
          lab_order_id: lab_order.id,
          amount: Decimal.new("40")
        })

      {:ok, _} = Payments.complete_payment(payment_a)
      {:ok, _} = Payments.complete_payment(payment_b)

      assert Decimal.equal?(
               Payments.site_earnings(organization.id, lab_order.site_id),
               Decimal.new("140")
             )
    end
  end
end
