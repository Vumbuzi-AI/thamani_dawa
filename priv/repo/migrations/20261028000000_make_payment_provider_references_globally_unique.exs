defmodule ThamaniDawa.Repo.Migrations.MakePaymentProviderReferencesGloballyUnique do
  use Ecto.Migration

  def change do
    drop_if_exists index(:payments, [:organization_id, :provider_reference],
                     name: :payments_org_provider_reference_index
                   )

    create unique_index(:payments, [:provider_reference],
             where: "provider_reference IS NOT NULL",
             name: :payments_provider_reference_index
           )
  end
end
