defmodule ThamaniDawa.Customers do
  @moduledoc """
  Distributor customers — who a distributor sells to. Address book to track
  who you sell to without re-entering GLN details each time.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Customers.Customer
  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Repo

  def list_customers(organization_id) do
    Repo.all(from c in Customer, where: c.organization_id == ^organization_id, order_by: c.name)
  end

  def get_customer!(organization_id, id) do
    Repo.get_by!(Customer, organization_id: organization_id, id: id)
  end

  def get_by_gln(organization_id, gln) do
    Repo.get_by(Customer, organization_id: organization_id, gln: gln)
  end

  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  def create_customer(organization_id, attrs) do
    %Customer{}
    |> Customer.changeset(Map.put(attrs, "organization_id", organization_id))
    |> Repo.insert()
  end

  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Resolves a GLN to GS1 business details, for prefilling a customer's name
  and address before it's saved. Does not persist anything.
  """
  @spec lookup_gln(String.t()) :: {:ok, GlnLookup.resolved()} | {:error, :not_found}
  def lookup_gln(gln), do: GlnLookup.resolve_party(gln)
end
