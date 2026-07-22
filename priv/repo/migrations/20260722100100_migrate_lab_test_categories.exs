defmodule ThamaniDawa.Repo.Migrations.MigrateLabTestCategories do
  use Ecto.Migration

  # Maps legacy free-text categories onto their approved equivalents so every
  # existing lab test satisfies the new `LabTest` category validation.
  @mappings %{
    "Hematology" => "Haematology",
    "Haematology " => "Haematology",
    "Micro" => "Microbiology",
    "Biochem" => "Biochemistry"
  }

  def up do
    for {from, to} <- @mappings do
      execute("""
      UPDATE lab_tests SET category = '#{to}' WHERE category = '#{from}'
      """)
    end
  end

  def down do
    execute("UPDATE lab_tests SET category = 'Hematology' WHERE category = 'Haematology'")
  end
end
