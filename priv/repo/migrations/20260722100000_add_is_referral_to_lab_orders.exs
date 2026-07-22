defmodule ThamaniDawa.Repo.Migrations.AddIsReferralToLabOrders do
  use Ecto.Migration

  def change do
    alter table(:lab_orders) do
      add :is_referral, :boolean, null: false, default: false
    end

    # Existing orders that already carry referral details are treated as
    # referrals. Guard against empty/whitespace-only strings so blank columns
    # aren't mistaken for real referral data.
    execute(
      """
      UPDATE lab_orders
      SET is_referral = true
      WHERE (referring_facility IS NOT NULL AND btrim(referring_facility) <> '')
         OR (referring_doctor IS NOT NULL AND btrim(referring_doctor) <> '')
      """,
      "UPDATE lab_orders SET is_referral = false"
    )
  end
end
