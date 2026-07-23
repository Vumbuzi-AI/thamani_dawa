defmodule ThamaniDawa.Accounts.Scope do
  @moduledoc """
  The execution scope for the current request/session: which user is signed
  in, and which organization their data is confined to. Every context
  function that touches tenant data takes a scope (or its `organization_id`)
  as its first argument and filters on it — see `ThamaniDawa.Organizations`.
  """

  alias ThamaniDawa.Accounts.User

  defstruct user: nil, organization_id: nil

  @doc "Builds a scope for the given user, nil if there is no user."
  def for_user(%User{} = user) do
    %__MODULE__{user: user, organization_id: user.organization_id}
  end

  def for_user(nil), do: nil

  @doc "Whether the signed-in user has the given role (§7)."
  def role?(%__MODULE__{user: %User{role: role}}, wanted_role), do: role == wanted_role
  def role?(_scope, _wanted_role), do: false

  @doc """
  Whether the signed-in user is an org admin (§7) whose account is still active
  """
  def admin?(%__MODULE__{user: %User{role: :admin, is_active: true}}), do: true
  def admin?(_scope), do: false

  @doc "Whether the signed-in user is a pharmacist (§7)."
  def pharmacist?(scope), do: role?(scope, :pharmacist)

  @doc "Whether the signed-in user is a lab technician (§7)."
  def lab_technician?(scope), do: role?(scope, :lab_technician)

  @doc """
  Whether the signed-in user holds the combined pharmacy + lab role (§7).
  Combined staff work across both operational portals but never receive
  organization-admin access.
  """
  def pharma_lab?(scope), do: role?(scope, :pharma_lab)

  @doc """
  Whether the signed-in user can enter the pharmacy portal: an admin, a
  pharmacist, or combined pharmacy/lab staff.
  """
  def pharmacy_access?(scope), do: admin?(scope) or pharmacist?(scope) or pharma_lab?(scope)

  @doc """
  Whether the signed-in user can enter the lab portal: an admin, a lab
  technician, or combined pharmacy/lab staff.
  """
  def lab_access?(scope), do: admin?(scope) or lab_technician?(scope) or pharma_lab?(scope)
end
