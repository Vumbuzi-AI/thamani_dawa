defmodule ThamaniDawa.Repo.Migrations.AddIsReferralToLabOrders do
  use Ecto.Migration

  def change do
    alter table(:lab_orders) do
      add :is_referral, :boolean, null: false, default: false
    end

    # Existing orders that already carry referral details are treated as referrals.
    execute(
      """
      UPDATE lab_orders
      SET is_referral = true
      WHERE referring_facility IS NOT NULL OR referring_doctor IS NOT NULL
      """,
      "UPDATE lab_orders SET is_referral = false"
    )
  end
end
