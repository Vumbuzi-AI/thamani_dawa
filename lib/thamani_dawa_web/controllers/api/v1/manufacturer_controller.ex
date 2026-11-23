defmodule ThamaniDawaWeb.Api.V1.ManufacturerController do
  @moduledoc """
  The manufacturer portal's catalogue side for the mobile app, on top of
  `ThamaniDawa.Manufacturing`: dashboard, products, batches and their
  serials, serial generation (the "+ Serial" wizard), shipper SSCCs and
  their labels, inventory, serial exports, and the organization's GS1
  prefixes.

  Access matches the web's `require_manufacturer_access`; the GS1 prefixes
  live on the admin-only settings page, so they need manufacturer admin
  access (`require_manufacturer_admin_access`).
  """

  use ThamaniDawaWeb, :controller

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.GlnLookup
  alias ThamaniDawa.Manufacturing
  alias ThamaniDawa.Manufacturing.SerialExport
  alias ThamaniDawa.Manufacturing.SerialGeneration
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.Api.Params
  alias ThamaniDawaWeb.Api.Response
  alias ThamaniDawaWeb.Api.Serializer
  alias ThamaniDawaWeb.Api.V1.Helpers
  alias ThamaniDawaWeb.Api.V1.ManufacturerFallback
  alias ThamaniDawaWeb.Plugs.RequireIdempotency
  alias ThamaniDawaWeb.Plugs.RequirePortal

  import Helpers

  action_fallback ManufacturerFallback

  plug RequirePortal, :manufacturer
  plug RequirePortal, :manufacturer_admin when action in [:gs1_prefixes]
  plug RequireIdempotency when action in [:create_product, :generate_serials]

  def dashboard(conn, _params) do
    org_id = org_id(conn)

    pending = %{
      aggregations: Manufacturing.list_aggregations(org_id, %{status: "submitted"}).total_entries,
      shipments:
        Distributor.list_shipments(org_id, %{
          participant_tier: "manufacturer",
          status: "submitted"
        }).total_entries
    }

    Response.data(conn, %{
      counts: Manufacturing.dashboard_counts(org_id),
      awaiting_review: pending
    })
  end

  # Products

  def products(conn, params) do
    {page, per_page} = Params.page(params)

    result =
      Manufacturing.paginate_products_with_counts(org_id(conn),
        page: page,
        page_size: per_page,
        search: params["search"] || ""
      )

    entries =
      Enum.map(result.entries, fn row ->
        row.product
        |> Serializer.manufacturer_product()
        |> Map.merge(%{serial_count: row.serial_count, sscc_count: row.sscc_count})
      end)

    Response.page(conn, entries, meta(result))
  end

  def create_product(conn, params) do
    idempotent(conn, fn ->
      attrs =
        Map.take(params, [
          "gtin",
          "name",
          "description",
          "brand_owner",
          "brand_owner_address",
          "licence_type"
        ])

      with {:ok, product} <- Manufacturing.create_product(org_id(conn), attrs) do
        {:ok, 201, %{data: product_detail(conn, product)}}
      end
    end)
  end

  def show_product(conn, %{"id" => id}) do
    with {:ok, product} <- load_product(conn, id) do
      Response.data(conn, product_detail(conn, product))
    end
  end

  def show_product_by_gtin(conn, %{"gtin" => gtin}) do
    with {:ok, product} <- fetch(fn -> Manufacturing.get_product_by_gtin!(org_id(conn), gtin) end) do
      Response.data(conn, product_detail(conn, product))
    end
  end

  # Batches and serials

  def batches(conn, %{"id" => id} = params) do
    with {:ok, product} <- load_product(conn, id) do
      batches =
        conn
        |> org_id()
        |> Manufacturing.list_batches_for_serials(product.id, params["search"] || "")
        |> Enum.map(fn {batch, count} -> Serializer.manufacturer_batch(batch, count) end)

      Response.data(conn, batches)
    end
  end

  def serials(conn, %{"id" => id, "batch_id" => batch_id} = params) do
    with {:ok, product} <- load_product(conn, id),
         {:ok, batch} <- load_batch(conn, product, batch_id) do
      {page, per_page} = Params.page(params)

      result =
        Manufacturing.paginate_serials(org_id(conn), batch.id,
          page: page,
          page_size: per_page,
          search: params["search"] || ""
        )

      entries =
        Enum.map(result.entries, fn serial ->
          Serializer.manufacturer_serial(serial, Manufacturing.gs1_text(product, batch, serial))
        end)

      Response.page(conn, entries, meta(result))
    end
  end

  def export_serials(conn, %{"id" => id, "batch_id" => batch_id} = params) do
    with {:ok, product} <- load_product(conn, id),
         {:ok, batch} <- load_batch(conn, product, batch_id) do
      serials = Manufacturing.list_serials(org_id(conn), batch.id)

      export(
        conn,
        params["format"],
        "#{product.gtin}-#{batch.batch_no}-serials.csv",
        SerialExport.batch_header(),
        SerialExport.batch_rows(product, batch, serials)
      )
    end
  end

  @doc """
  The "+ Serial" wizard. `mode` is `stock` (primary serials only) or
  `order` (also shipper SSCCs under a pallet, labelled From/To). Serials
  are minted at the user's current manufacturing site, like the web.
  """
  def generate_serials(conn, %{"id" => id} = params) do
    idempotent(conn, fn ->
      with {:ok, product} <- load_product(conn, id),
           {:ok, mode} <- mode(params["mode"]),
           {:ok, site} <- generation_site(conn),
           params = generation_params(conn, params, site),
           {:ok, params} <- resolve_to_party(params, mode),
           [] <- SerialGeneration.errors(params, mode) do
        generate(conn, mode, product, site, params)
      else
        [_ | _] = errors -> {:error, {:fields, errors}}
        error -> error
      end
    end)
  end

  # SSCCs

  def ssccs(conn, %{"id" => id}) do
    with {:ok, product} <- load_product(conn, id) do
      Response.data(conn, sscc_groups(conn, product))
    end
  end

  def show_sscc(conn, %{"id" => id}) do
    with {:ok, sscc} <- load_sscc(conn, id) do
      Response.data(conn, Serializer.sscc(sscc))
    end
  end

  def sscc_serials(conn, %{"id" => id} = params) do
    with {:ok, sscc} <- load_sscc(conn, id) do
      {page, per_page} = Params.page(params)
      serials = Manufacturing.list_serials_for_sscc(org_id(conn), sscc.id)
      {entries, meta} = Params.slice(serials, page, per_page)
      Response.page(conn, Enum.map(entries, &Serializer.manufacturer_serial/1), meta)
    end
  end

  def sscc_label(conn, %{"id" => id}) do
    with {:ok, sscc} <- load_sscc(conn, id) do
      Response.data(conn, sscc |> Manufacturing.sscc_label() |> json_dates())
    end
  end

  def export_sscc(conn, %{"id" => id} = params) do
    with {:ok, sscc} <- load_sscc(conn, id) do
      serials = Manufacturing.list_serials_for_sscc(org_id(conn), sscc.id)

      export(
        conn,
        params["format"],
        "sscc-#{sscc.code}.csv",
        SerialExport.sscc_header(),
        SerialExport.sscc_rows(sscc, serials)
      )
    end
  end

  # Inventory: batches grouped by product, as on the web.

  def inventory(conn, _params) do
    org_id = org_id(conn)

    groups =
      org_id
      |> Manufacturing.list_products()
      |> Enum.map(fn product -> {product, Manufacturing.list_batches(org_id, product.id)} end)
      |> Enum.reject(fn {_product, batches} -> batches == [] end)
      |> Enum.map(fn {product, batches} ->
        %{
          product: Serializer.manufacturer_product(product),
          batches:
            Enum.map(batches, fn {batch, count} -> Serializer.manufacturer_batch(batch, count) end)
        }
      end)

    Response.data(conn, groups)
  end

  def gs1_prefixes(conn, _params) do
    prefixes = Organizations.list_gs1_prefixes(org_id(conn))
    Response.data(conn, Enum.map(prefixes, &Serializer.gs1_prefix/1))
  end

  defp generate(conn, "stock", product, site, params) do
    quantity = String.to_integer(params["primary_quantity"])

    conn
    |> org_id()
    |> Manufacturing.generate_primary_serials(
      product,
      SerialGeneration.batch_attrs(params),
      quantity,
      site.gln
    )
    |> generated(conn, product)
  end

  defp generate(conn, "order", product, site, params) do
    conn
    |> org_id()
    |> Manufacturing.generate_order_serials(
      product,
      SerialGeneration.batch_attrs(params),
      String.to_integer(params["primary_quantity"]),
      String.to_integer(params["shipper_quantity"]),
      site.gln,
      SerialGeneration.parties(params)
    )
    |> generated(conn, product)
  end

  defp generated({:ok, %{batch: batch, serials: serials} = result}, _conn, product) do
    body = %{
      batch: Serializer.manufacturer_batch(batch, length(serials)),
      serials:
        Enum.map(serials, fn serial ->
          Serializer.manufacturer_serial(serial, Manufacturing.gs1_text(product, batch, serial))
        end),
      pallet: result |> Map.get(:pallet) |> then(&(&1 && Serializer.pallet(&1))),
      shippers: result |> Map.get(:shippers, []) |> Enum.map(&Serializer.sscc/1)
    }

    {:ok, 201, %{data: body}}
  end

  defp generated({:error, %Ecto.Changeset{}} = error, _conn, _product), do: error
  defp generated({:error, :invalid_quantity} = error, _conn, _product), do: error
  defp generated({:error, reason}, _conn, _product), do: {:error, {:gs1, reason}}

  # String params as the wizard sends them; numbers from JSON become strings
  # so the shared rules see the same input. From defaults to the current
  # site and is always filled from the chosen facility.
  defp generation_params(conn, params, site) do
    params =
      params
      |> Map.take(
        ["batch_no", "production_date", "expiry_date", "primary_quantity", "shipper_quantity"] ++
          SerialGeneration.party_fields()
      )
      |> Map.new(fn {key, value} -> {key, if(is_nil(value), do: "", else: to_string(value))} end)
      |> Map.put_new("from_gln", site.gln || "")
      |> Map.put_new("from_company_name", site.name || "")
      |> Map.put_new("from_address", site.address || "")

    SerialGeneration.fill_from_facility(params, Sites.list_sites(org_id(conn)))
  end

  defp resolve_to_party(params, "order") do
    case GlnLookup.resolve_party(params["to_gln"]) do
      {:ok, party} ->
        {:ok, SerialGeneration.put_to_party(params, party)}

      {:error, :not_found} ->
        {:error, {:fields, [{:to_gln, {"could not be verified", []}}]}}
    end
  end

  defp resolve_to_party(params, _mode), do: {:ok, params}

  defp mode(mode) when mode in ["stock", "order"], do: {:ok, mode}
  defp mode(_mode), do: {:error, :invalid_mode}

  defp generation_site(conn) do
    case current_site(conn) do
      {:ok, %{gln: gln} = site} when is_binary(gln) and gln != "" -> {:ok, site}
      _none -> {:error, :site_gln_required}
    end
  end

  defp product_detail(conn, product) do
    batches =
      conn
      |> org_id()
      |> Manufacturing.list_batches(product.id)
      |> Enum.map(fn {batch, count} -> Serializer.manufacturer_batch(batch, count) end)

    product
    |> Serializer.manufacturer_product()
    |> Map.merge(%{batches: batches, ssccs: sscc_groups(conn, product)})
  end

  defp sscc_groups(conn, product) do
    conn
    |> org_id()
    |> Manufacturing.list_sscc_groups(product.id)
    |> Enum.map(fn %{sscc: sscc, serial_count: count} ->
      sscc |> Serializer.sscc() |> Map.put(:serial_count, count)
    end)
  end

  defp export(conn, "csv", filename, header, rows) do
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, SerialExport.to_csv([header | rows]))
  end

  defp export(conn, _format, filename, header, rows) do
    data = Enum.map(rows, fn row -> header |> Enum.zip(row) |> Map.new() |> json_dates() end)
    Response.page(conn, data, %{filename: filename, total: length(data)})
  end

  defp json_dates(map) do
    Map.new(map, fn
      {key, %Date{} = date} -> {key, Date.to_iso8601(date)}
      pair -> pair
    end)
  end

  defp meta(result) do
    %{
      page: result.page_number,
      per_page: result.page_size,
      total: result.total_entries,
      total_pages: result.total_pages
    }
  end

  defp load_product(conn, id) do
    with {:ok, id} <- parse_id(id) do
      fetch(fn -> Manufacturing.get_product!(org_id(conn), id) end)
    end
  end

  defp load_batch(conn, product, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, batch} <- fetch(fn -> Manufacturing.get_batch!(org_id(conn), id) end) do
      if batch.manufacturer_product_id == product.id,
        do: {:ok, batch},
        else: {:error, :not_found}
    end
  end

  defp load_sscc(conn, id) do
    with {:ok, id} <- parse_id(id),
         {:ok, sscc} <- fetch(fn -> Manufacturing.get_sscc_group!(org_id(conn), id) end) do
      {:ok, ThamaniDawa.Repo.preload(sscc, :batches)}
    end
  end
end
