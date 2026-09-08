defmodule ThamaniDawa.SerialCatalogTest do
  use ThamaniDawa.DataCase, async: true

  import ThamaniDawa.AccountsFixtures
  import ThamaniDawa.OrganizationsFixtures

  alias ThamaniDawa.Accounts.Scope
  alias ThamaniDawa.Gs1Api
  alias ThamaniDawa.SerialCatalog
  alias ThamaniDawa.SerialCatalog.CatalogItem

  setup do
    organization = organization_fixture()
    user = user_fixture(%{organization_id: organization.id})
    %{scope: Scope.for_user(user), organization: organization}
  end

  describe "preview_item/2" do
    test "a GS1 match is returned unsaved — searching must not write", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        Req.Test.json(conn, %{"name" => "Panadol 500mg", "company_name" => "GSK Kenya"})
      end)

      assert {:ok, %CatalogItem{} = item, :gs1} =
               SerialCatalog.preview_item(scope, "6161100000018")

      assert item.id == nil
      assert item.name == "Panadol 500mg"
      assert item.comp_name == "GSK Kenya"
      assert item.source == :external
      assert SerialCatalog.list_items(scope.organization_id) == []
    end

    test "the local catalog answers before GS1 is consulted", %{scope: scope} do
      # No stub registered: reaching the network here would raise.
      {:ok, saved} =
        SerialCatalog.ensure_item(scope.organization_id, %{
          gtin: "6161100000018",
          name: "Locally known"
        })

      assert {:ok, item, :catalog} = SerialCatalog.preview_item(scope, "6161100000018")
      assert item.id == saved.id
    end

    test "a malformed GTIN is rejected without a network call", %{scope: scope} do
      assert SerialCatalog.preview_item(scope, "12345") == {:error, :invalid_gtin}
    end

    test "a GS1 rejection is passed through with its message intact", %{scope: scope} do
      Req.Test.stub(Gs1Api, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"result" => "Barcode does not exist on the platform"})
      end)

      assert {:error, error} = SerialCatalog.preview_item(scope, "6161100000018")
      assert error.message == "Barcode does not exist on the platform"
    end
  end

  describe "ensure_item/2" do
    test "normalizes the GTIN to canonical GTIN-14 on save", %{scope: scope} do
      assert {:ok, item} =
               SerialCatalog.ensure_item(scope.organization_id, %{gtin: "6161100000018"})

      assert item.gtin == "06161100000018"
    end

    test "saving the same GTIN twice returns the existing row rather than erroring", %{
      scope: scope
    } do
      {:ok, first} = SerialCatalog.ensure_item(scope.organization_id, %{gtin: "6161100000018"})
      {:ok, second} = SerialCatalog.ensure_item(scope.organization_id, %{gtin: "06161100000018"})

      assert first.id == second.id
      assert length(SerialCatalog.list_items(scope.organization_id)) == 1
    end

    test "two organizations may hold the same GTIN", %{scope: scope} do
      other = organization_fixture()

      {:ok, mine} = SerialCatalog.ensure_item(scope.organization_id, %{gtin: "6161100000018"})
      {:ok, theirs} = SerialCatalog.ensure_item(other.id, %{gtin: "6161100000018"})

      refute mine.id == theirs.id
    end

    test "an invalid GTIN is a changeset error, not a saved row", %{scope: scope} do
      assert {:error, changeset} =
               SerialCatalog.ensure_item(scope.organization_id, %{gtin: "6161100000019"})

      assert %{gtin: ["is not a valid GTIN"]} = errors_on(changeset)
      assert SerialCatalog.list_items(scope.organization_id) == []
    end
  end

  describe "list_items_paginated/3" do
    test "searches GTIN, name and company, and filters by source", %{scope: scope} do
      {:ok, _panadol} =
        SerialCatalog.ensure_item(scope.organization_id, %{
          gtin: "6161100000018",
          name: "Panadol",
          source: :local
        })

      {:ok, _brufen} =
        SerialCatalog.ensure_item(scope.organization_id, %{
          gtin: "6161100000025",
          name: "Brufen",
          comp_name: "Abbott",
          source: :external
        })

      assert %{entries: [item]} =
               SerialCatalog.list_items_paginated(scope.organization_id, 1, search: "panadol")

      assert item.name == "Panadol"

      assert %{entries: [abbott]} =
               SerialCatalog.list_items_paginated(scope.organization_id, 1, search: "Abbott")

      assert abbott.name == "Brufen"

      assert %{entries: [local]} =
               SerialCatalog.list_items_paginated(scope.organization_id, 1, source: "local")

      assert local.source == :local
    end

    test "only lists the caller's organization", %{scope: scope} do
      other = organization_fixture()
      {:ok, _theirs} = SerialCatalog.ensure_item(other.id, %{gtin: "6161100000018"})

      assert %{entries: []} = SerialCatalog.list_items_paginated(scope.organization_id)
    end
  end
end
