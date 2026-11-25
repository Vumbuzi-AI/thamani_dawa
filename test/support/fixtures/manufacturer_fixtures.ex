defmodule ThamaniDawa.ManufacturerFixtures do
  @moduledoc """
  Test helpers for the manufacturer portal: manufacturer organizations and
  users, manufacturing sites, and manufactured products/batches.
  """

  alias ThamaniDawa.AccountsFixtures
  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.DistributorFixtures
  alias ThamaniDawa.Gln
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.OrganizationsFixtures
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Sites

  @doc "Creates an organization operating as a manufacturer, with a GS1 Company Prefix."
  def manufacturer_organization_fixture(attrs \\ %{}) do
    org =
      attrs
      |> Enum.into(%{operating_models: [:manufacturer]})
      |> OrganizationsFixtures.organization_fixture()

    {:ok, _prefix} = Organizations.add_gs1_prefix(org, %{prefix: "0614141"})

    org
  end

  @doc "Creates an active manufacturer-role user in a manufacturer organization."
  def manufacturer_user_fixture(attrs \\ %{}) do
    {organization_id, attrs} =
      Map.pop_lazy(attrs, :organization_id, fn -> manufacturer_organization_fixture().id end)

    {site_id, attrs} =
      Map.pop_lazy(attrs, :site_id, fn -> manufacturing_site_fixture(organization_id).id end)

    attrs
    |> Map.put(:organization_id, organization_id)
    |> Map.put(:site_id, site_id)
    |> Map.put(:role, :manufacturer)
    |> AccountsFixtures.staff_fixture()
  end

  def manufacturing_site_fixture(organization_id, attrs \\ %{}) do
    {:ok, site} =
      attrs
      |> Enum.into(%{
        name: "Plant #{System.unique_integer([:positive])}",
        activities: [:manufacturing],
        address: "#{System.unique_integer([:positive])} Industrial Area",
        gln: Gln.generate!(),
        is_active: true
      })
      |> then(&Sites.create_site(organization_id, &1))

    site
  end

  def manufacturer_product_fixture(organization_id, attrs \\ %{}) do
    serial =
      System.unique_integer([:positive])
      |> rem(100_000)
      |> Integer.to_string()
      |> String.pad_leading(5, "0")

    body = "00614141" <> serial
    gtin = body <> Integer.to_string(ThamaniDawa.GS1.Sscc.mod10_check_digit(body))

    {:ok, product} =
      attrs
      |> Enum.into(%{
        gtin: gtin,
        name: "Paracetamol 500mg",
        description: "Pain relief tablets"
      })
      |> then(&Manufacturing.create_product(organization_id, &1))

    product
  end

  @doc """
  A PIN packer on a manufacturing site. Returns `{mobile_user, pin}`.
  """
  def manufacturer_packer_fixture(organization_id, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    pin = Map.get(attrs, :pin, "2411")
    site_id = Map.get(attrs, :site_id) || manufacturing_site_fixture(organization_id).id

    mobile_user =
      organization_id
      |> DistributorFixtures.mobile_user_fixture(
        attrs
        |> Map.drop([:pin, :site_id])
        |> Map.put("site_id", site_id)
      )
      |> MobileUser.pin_changeset(pin)
      |> Repo.update!()

    {Repo.preload(mobile_user, [:organization, :site]), pin}
  end

  def manufacturer_batch_fixture(organization_id, product_id, attrs \\ %{}) do
    {:ok, batch} =
      attrs
      |> Enum.into(%{
        batch_no: "B#{System.unique_integer([:positive])}",
        production_date: Date.utc_today(),
        expiry_date: Date.add(Date.utc_today(), 365)
      })
      |> then(&Manufacturing.create_batch(organization_id, product_id, &1))

    batch
  end
end
