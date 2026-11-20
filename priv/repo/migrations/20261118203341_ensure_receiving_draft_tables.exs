defmodule ThamaniDawa.Repo.Migrations.EnsureReceivingDraftTables do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:receiving_drafts) do
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :origin, :map
      add :posting_key, :uuid, null: false

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists unique_index(:receiving_drafts, [:organization_id, :user_id])

    create_if_not_exists table(:receiving_draft_attachments) do
      add :receiving_draft_id, references(:receiving_drafts, on_delete: :delete_all), null: false
      add :doc_type, :string, null: false
      add :filename, :string, null: false
      add :path, :string, null: false
      add :content_type, :string
      add :byte_size, :integer

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists index(:receiving_draft_attachments, [:receiving_draft_id])
  end
end
