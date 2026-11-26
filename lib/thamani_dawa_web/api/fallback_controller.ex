defmodule ThamaniDawaWeb.Api.FallbackController do
  use ThamaniDawaWeb, :controller

  alias ThamaniDawaWeb.Api.Response

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    Response.changeset(conn, changeset)
  end

  def call(conn, {:error, {:account_locked, _} = reason}) do
    Response.reason(conn, reason)
  end

  def call(conn, {:error, {:invalid, message}}) when is_binary(message) do
    Response.reason(conn, {:invalid, message})
  end

  def call(conn, {:error, {_index, reason}}) do
    Response.reason(conn, reason)
  end

  def call(conn, {:error, reason}) do
    Response.reason(conn, reason)
  end
end
