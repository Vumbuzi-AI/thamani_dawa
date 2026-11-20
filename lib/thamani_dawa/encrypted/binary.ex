defmodule ThamaniDawa.Encrypted.Binary do
  @moduledoc """
  Ecto type for columns encrypted at rest via `ThamaniDawa.Vault`.
  """

  use Cloak.Ecto.Binary, vault: ThamaniDawa.Vault
end
