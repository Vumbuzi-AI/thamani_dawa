defmodule ThamaniDawaWeb.ReturnTo do
  @moduledoc false

  def safe(path, default) when is_binary(path) and is_binary(default) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") and
         not String.contains?(path, "://") do
      path
    else
      default
    end
  end

  def safe(_path, default), do: default

  def with_query(path, return_to) when is_binary(path) and is_binary(return_to) do
    sep = if String.contains?(path, "?"), do: "&", else: "?"
    path <> sep <> "return_to=" <> URI.encode_www_form(return_to)
  end
end
