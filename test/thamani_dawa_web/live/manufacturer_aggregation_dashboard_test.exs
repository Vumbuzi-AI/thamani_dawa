defmodule ThamaniDawaWeb.ManufacturerAggregationDashboardTest do
  use ThamaniDawaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ThamaniDawa.ManufacturerFixtures

  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.GenerationOperation
  alias ThamaniDawa.Repo

  setup %{conn: conn} do
    organization = manufacturer_organization_fixture()
    site = manufacturing_site_fixture(organization.id)
    user = manufacturer_user_fixture(%{organization_id: organization.id, site_id: site.id})
    %{conn: log_in_user(conn, user), organization: organization, site: site}
  end

  test "separates shipper and pallet aggregation workflows", %{
    conn: conn,
    organization: organization
  } do
    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations")

    assert has_element?(view, "#start-aggregation", "Start aggregation")
    assert has_element?(view, "#start-aggregation-options.td-start-menu")

    assert has_element?(
             view,
             "#start-shipper-aggregation.td-menu-item-rich",
             "Prepare shipper aggregation"
           )

    assert has_element?(view, "#start-pallet-aggregation.td-menu-item-rich", "Build a pallet")
    assert has_element?(view, "#aggregation-shippers-tab.is-active")
    assert has_element?(view, "#aggregation-pallets-tab")
    assert has_element?(view, "#aggregation-shippers-panel")
    assert has_element?(view, "#aggregation-active-batches")
    assert has_element?(view, "#aggregation-batches-empty")
    refute has_element?(view, "#aggregation-shippers")
    refute has_element?(view, "#aggregation-pallets-panel")

    {:ok, pallet} =
      Manufacturing.create_pallet(organization.id, %{
        "code" => "361640010000000184",
        "from_company_name" => "Thamani Pharma Limited",
        "to_company_name" => "Kilimo Distributors Ltd"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations")

    view |> element("#aggregation-pallets-tab") |> render_click()

    assert_patch(view, ~p"/manufacturer/aggregations?tab=pallets")
    assert has_element?(view, "#aggregation-pallets-tab.is-active")
    assert has_element?(view, "#aggregation-pallets-panel")
    refute has_element?(view, "#build-pallet")
    assert has_element?(view, "#aggregation-pallet-#{pallet.id}", "361640010000000184")
    refute has_element?(view, "#aggregation-shippers-panel")
  end

  test "shippers tab only lists batches prepared for or in aggregation", %{
    conn: conn,
    organization: organization
  } do
    create_batch = fn attrs ->
      product = manufacturer_product_fixture(organization.id)
      defaults = %{pack_quantity: 4, packs_per_shipper: 2}

      batch =
        manufacturer_batch_fixture(
          organization.id,
          product.id,
          Map.merge(defaults, attrs)
        )

      %GenerationOperation{
        organization_id: organization.id,
        manufacturer_product_id: product.id,
        manufacturer_batch_id: batch.id
      }
      |> GenerationOperation.changeset(%{
        operation_key: Ecto.UUID.generate(),
        serial_quantity: batch.pack_quantity,
        status: "completed",
        serial_allocation_status: "completed",
        sscc_allocation_status: "not_required"
      })
      |> Repo.insert!()

      batch
    end

    unprepared = create_batch.(%{status: "prepared"})
    ready = create_batch.(%{status: "prepared", shipper_preparation_method: "during_packing"})

    aggregating =
      create_batch.(%{status: "aggregating", shipper_preparation_method: "during_packing"})

    completed =
      create_batch.(%{status: "completed", shipper_preparation_method: "during_packing"})

    packed_product = manufacturer_product_fixture(organization.id)

    packed =
      manufacturer_batch_fixture(organization.id, packed_product.id, %{
        status: "prepared",
        shipper_preparation_method: "during_packing"
      })

    %GenerationOperation{
      organization_id: organization.id,
      manufacturer_product_id: packed_product.id,
      manufacturer_batch_id: packed.id
    }
    |> GenerationOperation.changeset(%{
      operation_key: Ecto.UUID.generate(),
      serial_quantity: 1,
      status: "completed",
      serial_allocation_status: "completed",
      sscc_allocation_status: "not_required"
    })
    |> Repo.insert!()

    {:ok, shipper} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "006141411234567890",
        "gtin" => packed_product.gtin,
        "batch" => packed.batch_no,
        "status" => "completed"
      })

    {:ok, _serial} =
      Manufacturing.create_manual_serial(organization.id, packed, shipper, %{
        "serial" => "PACKED-001"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations?tab=shippers")

    assert has_element?(view, "#aggregation-batch-#{ready.id}", "Ready to pack")
    assert has_element?(view, "#aggregation-batch-#{aggregating.id}", "Packing in progress")
    assert has_element?(view, "#prepare-shippers-#{ready.id}", "Create shippers")
    assert has_element?(view, "#prepare-shippers-#{aggregating.id}", "Continue packing")
    refute has_element?(view, "#aggregation-batch-#{completed.id}")
    refute has_element?(view, "#prepare-shippers-#{completed.id}")
    refute has_element?(view, "#aggregation-batch-#{packed.id}")
    refute has_element?(view, "#prepare-shippers-#{packed.id}")
    refute has_element?(view, "#aggregation-batch-#{unprepared.id}")
    refute has_element?(view, "#aggregation-batches-empty")
  end

  test "keeps the empty-state action in the shipper workflow when all are packed", %{
    conn: conn,
    organization: organization
  } do
    product = manufacturer_product_fixture(organization.id)

    batch =
      manufacturer_batch_fixture(organization.id, product.id, %{
        status: "completed",
        pack_quantity: 1,
        packs_per_shipper: 1,
        shipper_preparation_method: "during_packing"
      })

    %GenerationOperation{
      organization_id: organization.id,
      manufacturer_product_id: product.id,
      manufacturer_batch_id: batch.id
    }
    |> GenerationOperation.changeset(%{
      operation_key: Ecto.UUID.generate(),
      serial_quantity: 1,
      status: "completed",
      serial_allocation_status: "completed",
      sscc_allocation_status: "not_required"
    })
    |> Repo.insert!()

    {:ok, shipper} =
      Manufacturing.create_manual_sscc(organization.id, nil, %{
        "code" => "006141411234567891",
        "gtin" => product.gtin,
        "batch" => batch.batch_no,
        "status" => "completed"
      })

    {:ok, _serial} =
      Manufacturing.create_manual_serial(organization.id, batch, shipper, %{
        "serial" => "PACKED-ONLY-001"
      })

    {:ok, view, _html} = live(conn, ~p"/manufacturer/aggregations?tab=shippers")

    assert has_element?(view, "#aggregation-batches-empty", "All shippers are packed")
    assert has_element?(view, "#build-shipper-from-batches", "Build a shipper")

    assert has_element?(
             view,
             "#build-shipper-from-batches[href='/manufacturer/inventory?tab=batches']"
           )

    refute has_element?(view, "#aggregation-active-batches-table")
    refute has_element?(view, "#aggregation-batch-#{batch.id}")
  end
end
