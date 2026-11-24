defmodule ThamaniDawaWeb.Gs1SsoController do
  use ThamaniDawaWeb, :controller

  import Plug.Conn

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Gs1Sso
  alias ThamaniDawaWeb.SessionController
  alias ThamaniDawaWeb.UserAuth

  @state_key "gs1_sso_state"
  @verifier_key "gs1_sso_pkce_verifier"

  def new(conn, _params) do
    state = random_url_token(32)
    verifier = random_url_token(64)
    challenge = :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

    conn
    |> put_session(@state_key, state)
    |> put_session(@verifier_key, verifier)
    |> redirect(external: Gs1Sso.authorization_url(state, challenge))
  end

  def callback(conn, %{"code" => code, "state" => returned_state})
      when is_binary(code) and is_binary(returned_state) do
    expected_state = get_session(conn, @state_key)
    verifier = get_session(conn, @verifier_key)

    conn =
      conn
      |> delete_session(@state_key)
      |> delete_session(@verifier_key)

    with true <- valid_state?(expected_state, returned_state),
         true <- is_binary(verifier),
         {:ok, token} <- Gs1Sso.exchange_code(code, verifier),
         {:ok, identity} <- Gs1Sso.fetch_userinfo(token),
         {:ok, user} <- Accounts.link_gs1_sso_user(identity.sub, identity.email) do
      conn
      |> UserAuth.log_in_user(user)
      |> redirect(to: SessionController.login_redirect_path(user, false, false))
    else
      false ->
        authentication_failed(conn, "The GS1 sign-in request expired or was invalid.")

      {:error, :account_not_found} ->
        authentication_failed(
          conn,
          "Create or accept your local account before using GS1 sign-in."
        )

      {:error, :inactive_account} ->
        authentication_failed(conn, "This account is inactive.")

      {:error, _reason} ->
        authentication_failed(conn, "GS1 sign-in could not be completed. Please try again.")
    end
  end

  def callback(conn, _params) do
    conn
    |> delete_session(@state_key)
    |> delete_session(@verifier_key)
    |> authentication_failed("The GS1 sign-in request was cancelled or invalid.")
  end

  defp valid_state?(expected, returned)
       when is_binary(expected) and is_binary(returned) and
              byte_size(expected) == byte_size(returned),
       do: Plug.Crypto.secure_compare(expected, returned)

  defp valid_state?(_expected, _returned), do: false

  defp authentication_failed(conn, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/login")
  end

  defp random_url_token(bytes),
    do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
