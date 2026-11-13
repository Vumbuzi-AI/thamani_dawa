defmodule ThamaniDawa.DistributorCustomers do
  @moduledoc """
  Organization-scoped customers a distributor ships to. Every customer gets an
  auto-generated GLN on creation, which is what a shipment's destination GLN
  resolves against.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.DistributorCustomers.Customer
  alias ThamaniDawa.Gln
  alias ThamaniDawa.Repo

  def list_customers(organization_id) do
    Repo.all(
      from customer in Customer,
        where: customer.organization_id == ^organization_id,
        order_by: [asc: customer.name]
    )
  end

  def get_customer!(organization_id, id) do
    Repo.get_by!(Customer, id: id, organization_id: organization_id)
  end

  def create_customer(organization_id, attrs) do
    %Customer{}
    |> Customer.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:gln, Gln.generate!())
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc "Gets an organization's customer by GLN, or nil."
  def get_customer_by_gln(organization_id, gln) do
    Repo.get_by(Customer, organization_id: organization_id, gln: gln)
  end

  @doc """
  Searches an organization's active customers by name or GLN, for the
  shipment destination picker.
  """
  def search_customers(organization_id, term, limit \\ 10) do
    pattern = "%" <> String.trim(term || "") <> "%"

    Repo.all(
      from customer in Customer,
        where: customer.organization_id == ^organization_id,
        where: customer.is_active,
        where: ilike(customer.name, ^pattern) or ilike(customer.gln, ^pattern),
        order_by: [asc: customer.name],
        limit: ^limit
    )
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}),
    do: Customer.changeset(customer, attrs)
end
