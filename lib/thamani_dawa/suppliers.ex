defmodule ThamaniDawa.Suppliers do
  @moduledoc """
  Suppliers that organizations receive stock from (§4.1). `batches.supplier_id`
  is nullable — a batch arriving via an inter-site transfer has no supplier of
  its own.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Gln
  alias ThamaniDawa.Repo
  alias ThamaniDawa.Suppliers.Supplier

  @doc "Lists an organization's suppliers."
  def list_suppliers(organization_id) do
    Repo.all(from s in Supplier, where: s.organization_id == ^organization_id)
  end

  @doc "Lists an organization's suppliers with pagination."
  def list_suppliers_paginated(organization_id, page \\ 1) do
    from(s in Supplier, where: s.organization_id == ^organization_id)
    |> Repo.paginate(page: page)
  end

  @doc "Gets a single supplier scoped to an organization. Raises if not found."
  def get_supplier!(organization_id, id) do
    Repo.get_by!(Supplier, id: id, organization_id: organization_id)
  end

  @doc "Creates a supplier under the given organization."
  def create_supplier(organization_id, attrs) when is_integer(organization_id) do
    %Supplier{}
    |> Supplier.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Ecto.Changeset.put_change(:gln, Gln.generate!())
    |> Repo.insert()
  end

  @doc "Updates a supplier."
  def update_supplier(%Supplier{} = supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
  end

  @doc "Returns a changeset for the given supplier."
  def change_supplier(supplier_or_changeset, attrs \\ %{}) do
    Supplier.changeset(supplier_or_changeset, attrs)
  end
end
