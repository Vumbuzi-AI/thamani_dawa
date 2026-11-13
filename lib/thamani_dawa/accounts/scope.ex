defmodule ThamaniDawa.Accounts.Scope do
  @moduledoc """
  The execution scope for the current request/session: which user is signed
  in, and which organization their data is confined to. Every context
  function that touches tenant data takes a scope (or its `organization_id`)
  as its first argument and filters on it — see `ThamaniDawa.Organizations`.
  """

  alias ThamaniDawa.Accounts.User

  defstruct user: nil, organization_id: nil, current_site_id: nil

  @doc "Builds a scope for the given user, nil if there is no user."
  def for_user(%User{roles: [:superadmin]} = user) do
    %__MODULE__{
      user: %{user | sites: []},
      organization_id: nil,
      current_site_id: nil
    }
  end

  def for_user(%User{} = user) do
    %__MODULE__{
      user: user,
      organization_id: user.organization_id,
      current_site_id: user.current_site_id
    }
  end

  def for_user(nil), do: nil

  @doc "Whether the signed-in user holds the given role (§7). A user may hold several."
  def role?(%__MODULE__{user: %User{roles: roles}}, wanted_role), do: wanted_role in roles
  def role?(_scope, _wanted_role), do: false

  @doc """
  Whether the signed-in user is an org admin (§7) whose account is still active
  """
  def admin?(%__MODULE__{user: %User{is_active: true}} = scope), do: role?(scope, :admin)
  def admin?(_scope), do: false

  @doc "Whether the signed-in user is an active platform superadmin, not an organization admin."
  def superadmin?(%__MODULE__{user: %User{roles: roles, is_active: true}}),
    do: :superadmin in roles

  def superadmin?(_scope), do: false

  @doc "Whether the signed-in user is a pharmacist (§7)."
  def pharmacist?(scope), do: role?(scope, :pharmacist)

  @doc "Whether the signed-in user is a lab technician (§7)."
  def lab_technician?(scope), do: role?(scope, :lab_technician)

  @doc """
  Whether the signed-in user holds both the pharmacist and lab technician
  roles (§7). Combined staff work across both operational portals.
  """
  def pharma_lab?(scope), do: pharmacist?(scope) and lab_technician?(scope)

  @doc "Whether the signed-in user is a distributor."
  def distributor?(scope), do: role?(scope, :distributor)

  @doc """
  Whether the signed-in user can enter the distributor portal: an active
  user holding the distributor role. The organization's operating model is
  checked separately by `ThamaniDawaWeb.UserAuth` since it needs a database read.
  """
  def distributor_access?(%__MODULE__{user: %User{is_active: true}} = scope),
    do: distributor?(scope)

  def distributor_access?(_scope), do: false

  @doc """
  Whether the signed-in user can enter the pharmacy portal: an admin or a
  pharmacist (combined pharmacy/lab staff hold the pharmacist role too).
  """
  def pharmacy_access?(scope), do: admin?(scope) or pharmacist?(scope)

  @doc """
  Whether the signed-in user can enter the lab portal: an admin or a lab
  technician (combined pharmacy/lab staff hold the lab technician role too).
  """
  def lab_access?(scope), do: admin?(scope) or lab_technician?(scope)
end
