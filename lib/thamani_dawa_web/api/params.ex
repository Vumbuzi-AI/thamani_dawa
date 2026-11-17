defmodule ThamaniDawaWeb.Api.Params do
  @moduledoc false

  def integer(value) when is_integer(value), do: {:ok, value}

  def integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  def integer(_value), do: :error

  def page(params) when is_map(params) do
    {:ok, page} = integer(params["page"] || 1)
    {:ok, per_page} = integer(params["per_page"] || 25)
    {max(page, 1), per_page |> max(1) |> min(100)}
  rescue
    MatchError -> {1, 25}
  end

  def slice(list, page, per_page) when is_list(list) do
    total = length(list)
    offset = (page - 1) * per_page
    entries = Enum.slice(list, offset, per_page)
    pages = if total == 0, do: 0, else: div(total + per_page - 1, per_page)
    {entries, %{page: page, per_page: per_page, total: total, total_pages: pages}}
  end

  def scrivener(page) do
    %{
      page: page.page_number,
      per_page: page.page_size,
      total: page.total_entries,
      total_pages: page.total_pages
    }
  end

  def drop_tenant(params) when is_map(params) do
    Map.drop(params, ["organization_id", "hashed_password", "password_hash"])
  end
end
