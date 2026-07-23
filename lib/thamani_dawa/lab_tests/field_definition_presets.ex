defmodule ThamaniDawa.LabTests.FieldDefinitionPresets do
  @moduledoc """
  A curated, non-tenant list of common lab tests — approved name + category + field_definitions
  triples a lab tech can pick from when creating a `LabTest`, instead of hand-authoring
  `field_definitions` JSON from scratch every time. Plain module data, not a database table —
  matches `ThamaniDawa.Gtin`/`GS1Decoder`'s "domain logic lives in plain modules" convention.
  Categories stay org-scoped and freely named as they already are; this is a starting-point
  library to pick from, not a source of truth to enforce. Mirrors the same test/category set
  already seeded in `priv/repo/seeds.exs`.
  """

  @presets [
    %{
      name: "Complete Blood Count",
      category_name: "Hematology",
      field_definitions: %{
        "haemoglobin" => %{"type" => "number", "unit" => "g/dL"},
        "wbc" => %{"type" => "number", "unit" => "×10³/µL"},
        "platelets" => %{"type" => "number", "unit" => "×10³/µL"}
      }
    },
    %{
      name: "Malaria Parasite",
      category_name: "Hematology",
      field_definitions: %{
        "parasites" => %{"type" => "select", "options" => ["Not seen", "Seen"]}
      }
    },
    %{
      name: "Blood Group and Rhesus",
      category_name: "Hematology",
      field_definitions: %{"blood_group" => %{"type" => "text", "unit" => ""}}
    },
    %{
      name: "Liver Function Test",
      category_name: "Clinical Chemistry",
      field_definitions: %{
        "alt" => %{"type" => "number", "unit" => "U/L"},
        "ast" => %{"type" => "number", "unit" => "U/L"}
      }
    },
    %{
      name: "Renal Function Test",
      category_name: "Clinical Chemistry",
      field_definitions: %{
        "creatinine" => %{"type" => "number", "unit" => "µmol/L"},
        "urea" => %{"type" => "number", "unit" => "mmol/L"}
      }
    },
    %{
      name: "Random Blood Sugar",
      category_name: "Clinical Chemistry",
      field_definitions: %{"glucose" => %{"type" => "number", "unit" => "mmol/L"}}
    },
    %{
      name: "HIV Rapid Test",
      category_name: "Serology",
      field_definitions: %{
        "result" => %{"type" => "select", "options" => ["Non-reactive", "Reactive"]}
      }
    },
    %{
      name: "Hepatitis B Surface Antigen",
      category_name: "Serology",
      field_definitions: %{
        "result" => %{"type" => "select", "options" => ["Negative", "Positive"]}
      }
    },
    %{
      name: "Urinalysis",
      category_name: "Urinalysis",
      field_definitions: %{
        "ph" => %{"type" => "number", "unit" => ""},
        "protein" => %{"type" => "text", "unit" => ""}
      }
    },
    %{
      name: "Stool Microscopy",
      category_name: "Microbiology",
      field_definitions: %{"ova_cysts" => %{"type" => "text", "unit" => ""}}
    }
  ]

  @doc "Returns every preset, each a map with `:name`, `:category_name`, `:field_definitions`."
  def all, do: @presets

  @doc ~s'Returns `{name, name}` option tuples for a `<.input type="select">`, sorted by name.'
  def options do
    @presets
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Enum.map(&{&1, &1})
  end

  @doc "Fetches a preset by its exact name. Returns `nil` if there's no match."
  def get(name), do: Enum.find(@presets, &(&1.name == name))
end
