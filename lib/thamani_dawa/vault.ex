defmodule ThamaniDawa.Vault do
  @moduledoc """
  Cloak vault for at-rest encryption of org-supplied secrets (currently the
  per-organization PPB Track & Trace API keys — `Organizations` §epcis
  settings). Cipher/key are configured in `config/runtime.exs` from
  `EPCIS_CRED_ENCRYPTION_KEY`; rotating that key means adding a new
  `:default` cipher here and re-tagging the old one, per Cloak's own
  rotation support — no hand-rolled migration logic needed.
  """

  use Cloak.Vault, otp_app: :thamani_dawa
end
