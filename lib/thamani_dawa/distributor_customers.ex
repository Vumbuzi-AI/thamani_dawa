defmodule ThamaniDawa.DistributorCustomers do
  import Ecto.Query, warn: false

  alias ThamaniDawa.DistributorCustomers.Customer
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
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}),
    do: Customer.changeset(customer, attrs)
end
