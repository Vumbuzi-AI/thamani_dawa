defmodule ThamaniDawaWeb.DistributorPagination do
  @default_page_size 10

  def page(entries, page_number, page_size \\ @default_page_size) do
    total_entries = length(entries)
    total_pages = max(ceil(total_entries / page_size), 1)
    page_number = min(max(page_number, 1), total_pages)

    %{
      entries: Enum.slice(entries, (page_number - 1) * page_size, page_size),
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages
    }
  end

  def page_number(params, param \\ "page") do
    case Integer.parse(Map.get(params, param, "1")) do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end
end
