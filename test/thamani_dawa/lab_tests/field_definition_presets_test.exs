defmodule ThamaniDawa.LabTests.FieldDefinitionPresetsTest do
  use ExUnit.Case, async: true

  alias ThamaniDawa.LabTests.FieldDefinitionPresets

  describe "all/0" do
    test "every preset has a name, category_name, and non-empty field_definitions" do
      for preset <- FieldDefinitionPresets.all() do
        assert is_binary(preset.name) and preset.name != ""
        assert is_binary(preset.category_name) and preset.category_name != ""
        assert is_map(preset.field_definitions) and map_size(preset.field_definitions) > 0
      end
    end

    test "preset names are unique" do
      names = Enum.map(FieldDefinitionPresets.all(), & &1.name)
      assert Enum.uniq(names) == names
    end
  end

  describe "options/0" do
    test "returns sorted {name, name} tuples for every preset" do
      options = FieldDefinitionPresets.options()
      preset_names = Enum.map(FieldDefinitionPresets.all(), & &1.name)
      sorted_names = Enum.sort(preset_names)

      assert options == Enum.map(sorted_names, &{&1, &1})
    end
  end

  describe "get/1" do
    test "finds a preset by exact name" do
      assert %{name: "Complete Blood Count", category_name: "Hematology"} =
               FieldDefinitionPresets.get("Complete Blood Count")
    end

    test "returns nil for an unknown name" do
      assert FieldDefinitionPresets.get("Not A Real Preset") == nil
    end
  end
end
