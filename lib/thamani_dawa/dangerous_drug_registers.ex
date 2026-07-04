defmodule ThamaniDawa.DangerousDrugRegisters do
  @moduledoc """
  Site-scoped controlled-substance registers (§4.3): one
  `dangerous_drug_registers` row per `(site, product, month, year)`,
  tracking that drug's numbered `entries` for the month.
  """

  import Ecto.Query, warn: false
  alias ThamaniDawa.Repo
  alias ThamaniDawa.DangerousDrugRegisters.DangerousDrugRegister

  @doc "Lists an organization's dangerous drug registers."
  def list_dangerous_drug_registers(organization_id) do
    Repo.all(from r in DangerousDrugRegister, where: r.organization_id == ^organization_id)
  end

  @doc "Gets a single dangerous drug register scoped to an organization. Raises if not found."
  def get_dangerous_drug_register!(organization_id, id) do
    Repo.get_by!(DangerousDrugRegister, id: id, organization_id: organization_id)
  end

  @doc "Creates a dangerous drug register under the given organization."
  def create_dangerous_drug_register(organization_id, attrs) when is_integer(organization_id) do
    %DangerousDrugRegister{}
    |> DangerousDrugRegister.changeset(attrs)
    |> Ecto.Changeset.put_change(:organization_id, organization_id)
    |> Repo.insert()
  end

  @doc """
  Gets-or-creates the register row for `(site_id, product_id, month, year)`,
  bumps `last_entry_number`, and stores `entry_attrs` in `entries` under the
  new entry number (cast to a string key). Returns
  `{:ok, register} | {:error, changeset}`. `entry_attrs` is caller-supplied
  (e.g. `%{"quantity" => ..., "balance" => ..., "dispensed_to" => ...,
  "recorded_by_id" => ..., "recorded_at" => ...}`).
  """
  def record_entry(organization_id, site_id, product_id, month, year, entry_attrs)
      when is_integer(organization_id) and is_integer(site_id) and is_integer(product_id) and
             is_integer(month) and is_integer(year) and is_map(entry_attrs) do
    Repo.transaction(fn ->
      register = get_or_create_register(organization_id, site_id, product_id, month, year)
      next_number = register.last_entry_number + 1

      register
      |> Ecto.Changeset.change(
        entries: Map.put(register.entries, to_string(next_number), entry_attrs),
        last_entry_number: next_number
      )
      |> Repo.update()
      |> case do
        {:ok, register} -> register
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp get_or_create_register(organization_id, site_id, product_id, month, year) do
    case Repo.get_by(DangerousDrugRegister,
           organization_id: organization_id,
           product_id: product_id,
           month: month,
           year: year
         ) do
      nil ->
        {:ok, register} =
          create_dangerous_drug_register(organization_id, %{
            site_id: site_id,
            product_id: product_id,
            month: month,
            year: year,
            entries: %{},
            last_entry_number: 0
          })

        register

      register ->
        register
    end
  end
end
