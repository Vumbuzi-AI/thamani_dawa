defmodule ThamaniDawa.Repo.Migrations.AddOneCompletedPaymentPerOrderIndexes do
  use Ecto.Migration

  def change do
    create unique_index(:payments, [:prescription_id],
             where: "status = 'completed' AND prescription_id IS NOT NULL",
             name: :payments_one_completed_per_prescription_index
           )

    create unique_index(:payments, [:lab_order_id],
             where: "status = 'completed' AND lab_order_id IS NOT NULL",
             name: :payments_one_completed_per_lab_order_index
           )
  end
end
