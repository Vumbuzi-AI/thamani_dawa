defmodule ThamaniDawa.Distributor do
  @moduledoc """
  The distributor shipment workflow (the ErpLive "Healthcare Distributor"
  flow).

  A distributor does not generate codes up front. Instead:

    1. A portal administrator creates a **draft** shipment: order number,
       origin GLN (one of the organization's own sites) and destination GLN
       (one of its customers).
    2. A **mobile app user** finds the draft by order number, claims it,
       groups physical units into **shippers** (cases) by scanning their GS1
       DataMatrix codes, and **submits** it — which reserves every scanned
       serial so no other shipment can claim it.
    3. The administrator reviews the shipment and either **approves** it —
       charging the serialisation allowance and issuing one SSCC per shipper
       — or **rejects** it with a reason, releasing the reserved units. A
       rejected shipment can be **reopened** as a draft and resubmitted.

  The state machine is owned entirely by this module:

      draft --submit--> submitted --approve--> approved
                            |
                         reject (+ reason)
                            v
                         rejected --reopen--> draft

  Every transition row-locks the shipment, appends a `ShipmentEvent`, and
  broadcasts `{:distributor_shipment, event, shipment_id}` on `topic/1`.
  Mobile-side functions take the authenticated `%MobileUser{}` and scope
  everything through it, never through a client-supplied organization id.
  """

  import Ecto.Query, warn: false

  alias ThamaniDawa.Accounts.UserNotifier
  alias ThamaniDawa.Batches.Batch

  alias ThamaniDawa.Distributor.{
    Billing,
    GlnLookup,
    MobileAuth,
    MobileUser,
    ProductLookup,
    SerialReservation,
    Shipment,
    ShipmentEvent,
    ShipmentItem,
    Shipper
  }

  alias ThamaniDawa.GS1.Sscc
  alias ThamaniDawa.GS1Decoder
  alias ThamaniDawa.Organizations.Organization
  alias ThamaniDawa.Repo

  @page_size 20

  ## PubSub

  @doc "PubSub topic for an organization's shipment updates."
  def topic(organization_id), do: "distributor_shipments:#{organization_id}"

  def subscribe(organization_id),
    do: Phoenix.PubSub.subscribe(ThamaniDawa.PubSub, topic(organization_id))

  defp broadcast(%Shipment{} = shipment, event) do
    Phoenix.PubSub.broadcast(
      ThamaniDawa.PubSub,
      topic(shipment.organization_id),
      {:distributor_shipment, event, shipment.id}
    )
  end

  ## Mobile users

  def list_mobile_users(organization_id) do
    Repo.all(
      from m in MobileUser,
        where: m.organization_id == ^organization_id,
        order_by: [asc: m.name]
    )
  end

  def get_mobile_user!(organization_id, id),
    do: Repo.get_by!(MobileUser, id: id, organization_id: organization_id)

  def change_mobile_user(%MobileUser{} = mobile_user, attrs \\ %{}),
    do: MobileUser.changeset(mobile_user, attrs)

  @doc """
  Creates a mobile app user with a random 4-digit PIN. Only the PIN's hash
  is stored; the plaintext is emailed once via `pin_notifier/0` and never
  shown in the portal.
  """
  def create_mobile_user(organization_id, attrs) do
    pin = MobileUser.generate_pin()

    changeset =
      %MobileUser{organization_id: organization_id}
      |> MobileUser.changeset(attrs)
      |> Ecto.Changeset.put_change(:pin_hash, Bcrypt.hash_pwd_salt(pin))

    with {:ok, mobile_user} <- Repo.insert(changeset) do
      deliver_pin(mobile_user, pin)
      {:ok, mobile_user}
    end
  end

  def update_mobile_user(%MobileUser{} = mobile_user, attrs) do
    mobile_user
    |> MobileUser.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Issues a brand-new PIN (the old plaintext is unrecoverable), clears any
  lockout, revokes every session for the user, and emails the new PIN.
  """
  def resend_mobile_user_pin(%MobileUser{} = mobile_user) do
    pin = MobileUser.generate_pin()

    with {:ok, mobile_user} <- mobile_user |> MobileUser.pin_changeset(pin) |> Repo.update() do
      MobileAuth.revoke_sessions(mobile_user)
      deliver_pin(mobile_user, pin)
      {:ok, mobile_user}
    end
  end

  @doc "Activates or deactivates a mobile user. Deactivating revokes their sessions."
  def set_mobile_user_active(%MobileUser{} = mobile_user, active) when is_boolean(active) do
    with {:ok, mobile_user} <-
           mobile_user |> Ecto.Changeset.change(active: active) |> Repo.update() do
      unless active, do: MobileAuth.revoke_sessions(mobile_user)
      {:ok, mobile_user}
    end
  end

  @doc "Per-mobile-user shipment totals: `%{mobile_user_id => %{status => count, total: n}}`."
  def mobile_user_activity(organization_id) do
    rows =
      Repo.all(
        from s in Shipment,
          where: s.organization_id == ^organization_id,
          where: not is_nil(s.assigned_mobile_user_id),
          group_by: [s.assigned_mobile_user_id, s.status],
          select: {s.assigned_mobile_user_id, s.status, count(s.id)}
      )

    Enum.reduce(rows, %{}, fn {mobile_user_id, status, count}, acc ->
      Map.update(acc, mobile_user_id, %{status => count, total: count}, fn totals ->
        totals |> Map.put(status, count) |> Map.update!(:total, &(&1 + count))
      end)
    end)
  end

  defp deliver_pin(mobile_user, pin) do
    organization = Repo.get!(Organization, mobile_user.organization_id)
    pin_notifier().deliver_mobile_pin(mobile_user, organization.name, pin)
  end

  defp pin_notifier,
    do: Application.get_env(:thamani_dawa, :distributor_pin_notifier, UserNotifier)

  ## Shipments — portal

  @doc """
  Lists an organization's shipments. Options: `status`, `search` (free text
  across reference, order number, GLNs, company names and addresses, mobile
  user name, and scanned GTIN/batch/serial/SSCC), `mobile_user_id`,
  `date_from`/`date_to` (`Date`s, on creation date), and `page`.

  Returns `%{entries:, page_number:, total_pages:, total_entries:}`.
  """
  def list_shipments(organization_id, opts \\ %{}) do
    query =
      from(s in Shipment, as: :shipment, where: s.organization_id == ^organization_id)
      |> filter_status(opts[:status])
      |> search(opts[:search])
      |> filter_mobile_user(opts[:mobile_user_id])
      |> filter_date_from(opts[:date_from])
      |> filter_date_to(opts[:date_to])

    total_entries = Repo.aggregate(query, :count, :id)
    total_pages = max(ceil(total_entries / @page_size), 1)
    page_number = min(max(opts[:page] || 1, 1), total_pages)

    entries =
      Repo.all(
        from s in query,
          order_by: [desc: s.updated_at, desc: s.id],
          limit: ^@page_size,
          offset: ^((page_number - 1) * @page_size),
          preload: [:assigned_to, :submitted_by, shippers: :items]
      )

    %{
      entries: entries,
      page_number: page_number,
      page_size: @page_size,
      total_pages: total_pages,
      total_entries: total_entries
    }
  end

  @doc "Shipment counts per status for an organization."
  def status_counts(organization_id) do
    counts =
      Repo.all(
        from s in Shipment,
          where: s.organization_id == ^organization_id,
          group_by: s.status,
          select: {s.status, count(s.id)}
      )

    counts = Map.new(counts)
    Map.new(Shipment.statuses(), &{&1, Map.get(counts, &1, 0)})
  end

  @doc """
  Free-text search over shipments, using `exists()` subqueries so a match on
  a scanned unit or shipper doesn't duplicate shipment rows.
  """
  def search(query, term) when term in [nil, ""], do: query

  def search(query, term) do
    pattern = "%" <> escape_like(String.trim(term)) <> "%"

    from [shipment: s] in query,
      where:
        ^shipment_field_match(pattern) or exists(mobile_user_match(pattern)) or
          exists(item_match(pattern)) or exists(shipper_match(pattern))
  end

  defp shipment_field_match(pattern) do
    dynamic(
      [shipment: s],
      ilike(s.reference, ^pattern) or ilike(s.order_number, ^pattern) or
        ilike(s.origin_gln, ^pattern) or ilike(s.destination_gln, ^pattern) or
        ilike(s.origin_company, ^pattern) or ilike(s.destination_company, ^pattern) or
        ilike(s.origin_address, ^pattern) or ilike(s.destination_address, ^pattern)
    )
  end

  defp mobile_user_match(pattern) do
    from m in MobileUser,
      where:
        (m.id == parent_as(:shipment).assigned_mobile_user_id or
           m.id == parent_as(:shipment).submitted_by_mobile_user_id) and
          ilike(m.name, ^pattern)
  end

  defp item_match(pattern) do
    from i in ShipmentItem,
      where:
        i.shipment_id == parent_as(:shipment).id and
          (ilike(i.gtin, ^pattern) or ilike(i.batch, ^pattern) or ilike(i.serial, ^pattern))
  end

  defp shipper_match(pattern) do
    from sh in Shipper,
      where: sh.shipment_id == parent_as(:shipment).id and ilike(sh.sscc, ^pattern)
  end

  defp filter_status(query, status) when status in ["draft", "submitted", "approved", "rejected"],
    do: from(s in query, where: s.status == ^status)

  defp filter_status(query, _status), do: query

  defp filter_mobile_user(query, id) when is_integer(id),
    do:
      from(s in query,
        where: s.assigned_mobile_user_id == ^id or s.submitted_by_mobile_user_id == ^id
      )

  defp filter_mobile_user(query, _id), do: query

  defp filter_date_from(query, %Date{} = date) do
    from_dt = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    from(s in query, where: s.inserted_at >= ^from_dt)
  end

  defp filter_date_from(query, _date), do: query

  defp filter_date_to(query, %Date{} = date) do
    to_dt = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    from(s in query, where: s.inserted_at < ^to_dt)
  end

  defp filter_date_to(query, _date), do: query

  @doc "Gets an organization's shipment with shippers, items, actors, and events."
  def get_shipment!(organization_id, id) do
    Shipment
    |> Repo.get_by!(id: id, organization_id: organization_id)
    |> preload_shipment()
  end

  defp preload_shipment(shipment) do
    Repo.preload(
      shipment,
      [
        :assigned_to,
        :submitted_by,
        :created_by,
        :approved_by,
        :rejected_by,
        shippers: [items: :scanned_by],
        events: [:user, :mobile_user]
      ],
      force: true
    )
  end

  def change_shipment(%Shipment{} = shipment, attrs \\ %{}),
    do: Shipment.changeset(shipment, attrs)

  @doc """
  Creates a draft shipment, snapshotting the resolved origin site and
  destination customer onto the row.
  """
  def create_shipment(organization_id, user, attrs) do
    changeset =
      %Shipment{organization_id: organization_id, status: "draft", created_by_id: user.id}
      |> Shipment.changeset(attrs)
      |> resolve_glns(organization_id)
      |> Ecto.Changeset.put_change(:reference, generate_reference())

    result =
      Repo.transaction(fn ->
        case Repo.insert(changeset) do
          {:ok, shipment} ->
            log_event!(shipment, "created", user: user)
            shipment

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    tap_broadcast(result, "created")
  end

  @doc """
  Fetches a shipment for editing on the web. Returns
  `{:error, :not_editable}` once it has left draft.
  """
  def fetch_editable_shipment(organization_id, id) do
    case Repo.get_by(Shipment, id: id, organization_id: organization_id) do
      nil -> {:error, :not_found}
      %Shipment{status: "draft"} = shipment -> {:ok, shipment}
      _shipment -> {:error, :not_editable}
    end
  end

  @doc "Updates a draft shipment's order number and GLNs."
  def update_shipment(organization_id, user, %Shipment{id: id}, attrs) do
    result =
      Repo.transaction(fn ->
        shipment = lock_shipment!(organization_id, id)
        if shipment.status != "draft", do: Repo.rollback(:not_editable)

        changeset =
          shipment
          |> Shipment.changeset(attrs)
          |> resolve_glns(organization_id)

        case Repo.update(changeset) do
          {:ok, shipment} ->
            log_event!(shipment, "updated", user: user)
            shipment

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end)

    tap_broadcast(result, "updated")
  end

  defp resolve_glns(changeset, organization_id) do
    changeset
    |> resolve_gln(:origin, &GlnLookup.resolve_origin(organization_id, &1))
    |> resolve_gln(:destination, &GlnLookup.resolve_destination(organization_id, &1))
  end

  defp resolve_gln(changeset, side, resolver) do
    gln_field = :"#{side}_gln"
    gln = Ecto.Changeset.get_field(changeset, gln_field)

    case gln && changeset.errors[gln_field] == nil && resolver.(gln) do
      {:ok, resolved} ->
        record_field = if side == :origin, do: :origin_site_id, else: :destination_customer_id

        Ecto.Changeset.change(changeset, %{
          record_field => resolved.record.id,
          :"#{side}_company" => resolved.company,
          :"#{side}_address" => resolved.address,
          :"#{side}_po_box" => resolved.po_box
        })

      {:error, :not_found} ->
        message =
          if side == :origin,
            do: "is not one of your active sites",
            else: "is not one of your active customers"

        Ecto.Changeset.add_error(changeset, gln_field, message)

      _ ->
        changeset
    end
  end

  defp generate_reference do
    suffix =
      6
      |> :crypto.strong_rand_bytes()
      |> Base.encode32(padding: false)
      |> binary_part(0, 8)

    "SHP-" <> suffix
  end

  ## Shipments — mobile

  @doc "The mobile user's own shipments (any status), newest first, paginated."
  def list_shipments_for_mobile_user(mobile_user, page \\ 1)

  def list_shipments_for_mobile_user(%MobileUser{} = mobile_user, page) when is_integer(page) do
    Repo.all(
      from s in Shipment,
        where: s.organization_id == ^mobile_user.organization_id,
        where:
          s.assigned_mobile_user_id == ^mobile_user.id or
            s.submitted_by_mobile_user_id == ^mobile_user.id,
        order_by: [desc: s.updated_at, desc: s.id],
        limit: ^@page_size,
        offset: ^((max(page, 1) - 1) * @page_size)
    )
  end

  def list_shipments_for_mobile_user(%MobileUser{} = mobile_user, opts) when is_map(opts) do
    {page, per_page} = mobile_pagination(opts)

    mobile_user
    |> mobile_shipments_query(opts["status"] || opts[:status])
    |> order_by([s], desc: s.updated_at, desc: s.id)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> preload(shippers: :items)
    |> Repo.all()
  end

  def count_shipments_for_mobile_user(%MobileUser{} = mobile_user, opts \\ %{}) do
    mobile_user
    |> mobile_shipments_query(opts["status"] || opts[:status])
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Finds draft shipments by order number that the mobile user can work on:
  unclaimed, or already claimed by this same user.
  """
  def search_shipments_for_mobile_user(%MobileUser{} = mobile_user, order_number)
      when is_binary(order_number) or is_nil(order_number) do
    order_number = String.trim(order_number || "")

    Repo.all(
      from s in Shipment,
        where: s.organization_id == ^mobile_user.organization_id and s.status == "draft",
        where: ilike(s.order_number, ^("%" <> escape_like(order_number) <> "%")),
        where: is_nil(s.assigned_mobile_user_id) or s.assigned_mobile_user_id == ^mobile_user.id,
        order_by: [asc: s.order_number],
        limit: 20
    )
  end

  def search_shipments_for_mobile_user(%MobileUser{} = mobile_user, opts) when is_map(opts) do
    {page, per_page} = mobile_pagination(opts)

    mobile_user
    |> mobile_search_query(opts["order_number"] || opts[:order_number])
    |> order_by([s], desc: s.updated_at, desc: s.id)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> preload(shippers: :items)
    |> Repo.all()
  end

  def count_search_shipments_for_mobile_user(%MobileUser{} = mobile_user, opts \\ %{}) do
    mobile_user
    |> mobile_search_query(opts["order_number"] || opts[:order_number])
    |> Repo.aggregate(:count, :id)
  end

  defp mobile_shipments_query(mobile_user, status) do
    from s in Shipment,
      where: s.organization_id == ^mobile_user.organization_id,
      where:
        s.assigned_mobile_user_id == ^mobile_user.id or
          s.submitted_by_mobile_user_id == ^mobile_user.id,
      where: ^mobile_status_filter(status)
  end

  defp mobile_search_query(mobile_user, order_number) do
    order_number = String.trim(order_number || "")

    from s in Shipment,
      where: s.organization_id == ^mobile_user.organization_id and s.status == "draft",
      where: ilike(s.order_number, ^("%" <> escape_like(order_number) <> "%")),
      where: is_nil(s.assigned_mobile_user_id) or s.assigned_mobile_user_id == ^mobile_user.id
  end

  defp mobile_status_filter(status) when status in ~w(draft submitted approved rejected),
    do: dynamic([s], s.status == ^status)

  defp mobile_status_filter(_status), do: dynamic(true)

  defp mobile_pagination(opts) do
    page = positive_integer(opts["page"] || opts[:page], 1)
    per_page = min(positive_integer(opts["per_page"] || opts[:per_page], 25), 100)
    {page, per_page}
  end

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value || "")) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  @doc "Gets one of the mobile user's shipments with shippers and items."
  def get_shipment_for_mobile_user(%MobileUser{} = mobile_user, id) do
    query =
      from s in Shipment,
        where: s.id == ^id and s.organization_id == ^mobile_user.organization_id,
        where:
          s.assigned_mobile_user_id == ^mobile_user.id or
            s.submitted_by_mobile_user_id == ^mobile_user.id or
            (s.status == "draft" and is_nil(s.assigned_mobile_user_id)),
        preload: [shippers: :items]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      shipment -> {:ok, shipment}
    end
  end

  @doc "Gets a shipment already selected or submitted by the mobile user."
  def get_selected_shipment_for_mobile_user(%MobileUser{} = mobile_user, id) do
    query =
      from s in Shipment,
        where: s.id == ^id and s.organization_id == ^mobile_user.organization_id,
        where:
          s.assigned_mobile_user_id == ^mobile_user.id or
            s.submitted_by_mobile_user_id == ^mobile_user.id,
        preload: [shippers: :items]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      shipment -> {:ok, shipment}
    end
  end

  @doc """
  Claims a draft shipment for the mobile user. Returns `{:ok, shipment}` on
  a fresh claim, `{:unchanged, shipment}` if this user already holds it, or
  `{:error, :already_assigned | {:invalid_state, status} | :not_found}`.
  """
  def select_shipment(%MobileUser{} = mobile_user, id) do
    result =
      Repo.transaction(fn ->
        shipment = lock_mobile_shipment!(mobile_user, id)

        cond do
          shipment.assigned_mobile_user_id == mobile_user.id ->
            Repo.rollback({:unchanged, shipment})

          shipment.status != "draft" ->
            Repo.rollback({:invalid_state, shipment.status})

          not is_nil(shipment.assigned_mobile_user_id) ->
            Repo.rollback(:already_assigned)

          true ->
            shipment =
              shipment
              |> Ecto.Changeset.change(assigned_mobile_user_id: mobile_user.id)
              |> Repo.update!()

            log_event!(shipment, "selected", mobile_user: mobile_user)
            shipment
        end
      end)

    case result do
      {:error, {:unchanged, shipment}} -> {:unchanged, shipment}
      result -> tap_broadcast(result, "selected")
    end
  end

  @doc "Gives up a held draft; its shippers and items are kept for the next user."
  def release_shipment(%MobileUser{} = mobile_user, id) do
    result =
      edit_draft(mobile_user, id, fn shipment ->
        shipment =
          shipment
          |> Ecto.Changeset.change(assigned_mobile_user_id: nil)
          |> Repo.update!()

        log_event!(shipment, "released", mobile_user: mobile_user)
        shipment
      end)

    tap_broadcast(result, "released")
  end

  @doc "Adds the next shipper (\"Shipper N\") to a held draft shipment."
  def create_shipper(%MobileUser{} = mobile_user, shipment_id, attrs) do
    edit_draft(mobile_user, shipment_id, fn shipment ->
      sequence =
        Repo.one(
          from sh in Shipper,
            where: sh.shipment_id == ^shipment.id,
            select: coalesce(max(sh.sequence), 0)
        ) + 1

      Repo.insert!(%Shipper{
        organization_id: shipment.organization_id,
        shipment_id: shipment.id,
        sequence: sequence,
        name: shipper_name(attrs, sequence),
        material_description: shipper_material_description(attrs)
      })
    end)
  end

  @doc "Renames a shipper on a held draft shipment."
  def update_shipper(%MobileUser{} = mobile_user, shipper_id, attrs) do
    with {:ok, shipper} <- fetch_mobile_shipper(mobile_user, shipper_id) do
      edit_draft(mobile_user, shipper.shipment_id, fn _shipment ->
        shipper
        |> Ecto.Changeset.change(
          name: shipper_name(attrs, shipper.sequence),
          material_description: shipper_material_description(attrs, shipper.material_description)
        )
        |> Repo.update!()
      end)
    end
  end

  @doc "Removes a shipper (and its scanned items) from a held draft shipment."
  def delete_shipper(%MobileUser{} = mobile_user, shipper_id) do
    with {:ok, shipper} <- fetch_mobile_shipper(mobile_user, shipper_id) do
      edit_draft(mobile_user, shipper.shipment_id, fn _shipment -> Repo.delete!(shipper) end)
    end
  end

  defp shipper_name(attrs, sequence) do
    case String.trim(
           to_string(
             attrs["temporary_label"] || attrs[:temporary_label] || attrs["name"] || attrs[:name] ||
               ""
           )
         ) do
      "" -> "Shipper #{sequence}"
      name -> name
    end
  end

  defp shipper_material_description(attrs, fallback \\ nil) do
    case Map.get(attrs, "material_description", Map.get(attrs, :material_description, fallback)) do
      value when is_binary(value) -> String.trim(value)
      value -> value
    end
  end

  @doc """
  Records one scanned unit into a shipper. `attrs["raw_data_matrix"]` is the
  authoritative GS1 payload; if the app also sends its own parsed `gtin`,
  `batch`, `serial`, `production_date` or `expiry_date`, they must agree with
  the server's parse or the scan is rejected (`:parsed_mismatch`).

  Product details are resolved before the draft is locked (see
  `ProductLookup`). The unit is then checked for duplicates in this
  shipment and for serials committed to another submitted/approved
  shipment, and stored with a `validation_status` against the
  organization's received batches.
  """
  def scan_item(%MobileUser{} = mobile_user, shipper_id, attrs) do
    with {:ok, shipper} <- fetch_mobile_shipper(mobile_user, shipper_id),
         {:ok, parsed} <- parse_data_matrix(attrs["raw_data_matrix"]),
         :ok <- compare_client_reading(parsed, attrs),
         {:ok, product} <- lookup_product(mobile_user.organization_id, parsed.gtin) do
      edit_draft(mobile_user, shipper.shipment_id, fn shipment ->
        record_scan(mobile_user, shipment, shipper.id, parsed, product, attrs["raw_data_matrix"])
      end)
    end
  end

  defp record_scan(mobile_user, shipment, shipper_id, parsed, product, raw_data_matrix) do
    shipper = Repo.get_by(Shipper, id: shipper_id, shipment_id: shipment.id)
    if is_nil(shipper), do: Repo.rollback(:not_found)

    ensure_not_scanned!(shipment, parsed)
    ensure_not_committed!(shipment, parsed)
    insert_item!(mobile_user, shipment, shipper, parsed, product, raw_data_matrix)
  end

  defp parse_data_matrix(raw) when is_binary(raw) and raw != "" do
    case GS1Decoder.parse(raw) do
      {:ok, %{gtin: nil}} -> {:error, {:invalid_scan, :missing_gtin}}
      {:ok, %{serial: nil}} -> {:error, {:invalid_scan, :missing_serial}}
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:invalid_scan, {:unreadable, reason}}}
    end
  end

  defp parse_data_matrix(_raw), do: {:error, {:invalid_scan, :missing_data_matrix}}

  @client_fields [
    {"gtin", :gtin},
    {"batch", :batch_no},
    {"serial", :serial},
    {"production_date", :production_date},
    {"expiry_date", :expiry_date}
  ]

  @doc false
  def compare_client_reading(parsed, attrs) do
    mismatched =
      Enum.filter(@client_fields, fn {param, field} ->
        case attrs[param] do
          value when value in [nil, ""] -> false
          value -> normalize_reading(value, field) != Map.get(parsed, field)
        end
      end)

    if mismatched == [], do: :ok, else: {:error, :parsed_mismatch}
  end

  defp normalize_reading(value, field) when field in [:production_date, :expiry_date] do
    value = to_string(value)

    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> parse_yymmdd(value)
    end
  end

  defp normalize_reading(value, :gtin) do
    case ThamaniDawa.Gtin.normalize(to_string(value)) do
      {:ok, gtin} -> gtin
      _ -> value
    end
  end

  defp normalize_reading(value, _field), do: value |> to_string() |> String.trim()

  defp parse_yymmdd(<<yy::binary-size(2), mm::binary-size(2), dd::binary-size(2)>> = value) do
    with {year, ""} <- Integer.parse(yy),
         {month, ""} <- Integer.parse(mm),
         {day, ""} <- Integer.parse(dd),
         {:ok, date} <- Date.new(2000 + year, month, max(day, 1)) do
      if day == 0, do: Date.end_of_month(date), else: date
    else
      _ -> value
    end
  end

  defp parse_yymmdd(value), do: value

  defp lookup_product(organization_id, gtin) do
    case ProductLookup.lookup(organization_id, gtin) do
      {:ok, product} -> {:ok, product}
      {:error, :gtin_not_found} -> {:error, {:invalid_scan, :gtin_not_found, gtin}}
    end
  end

  defp ensure_not_scanned!(shipment, parsed) do
    if Repo.exists?(
         from i in ShipmentItem,
           where: i.shipment_id == ^shipment.id,
           where: i.gtin == ^parsed.gtin and i.serial == ^parsed.serial
       ),
       do: Repo.rollback(:duplicate_scan)
  end

  defp ensure_not_committed!(shipment, parsed) do
    if Repo.exists?(
         from r in SerialReservation,
           where: r.barcode == ^parsed.gtin and r.serial == ^parsed.serial,
           where: r.shipment_id != ^shipment.id
       ),
       do: Repo.rollback(:serial_already_shipped)
  end

  defp insert_item!(mobile_user, shipment, shipper, parsed, product, raw) do
    {validation_status, batch} = known_unit_status(shipment.organization_id, parsed)

    Repo.insert!(%ShipmentItem{
      organization_id: shipment.organization_id,
      shipment_id: shipment.id,
      shipper_id: shipper.id,
      raw_data_matrix: raw,
      gtin: parsed.gtin,
      batch: parsed.batch_no,
      serial: parsed.serial,
      production_date: parsed.production_date,
      expiry_date: parsed.expiry_date,
      product_id: product.product_id || (batch && batch.product_id),
      batch_id: batch && batch.id,
      product_name: product.product_name,
      product_source: product.source,
      validation_status: validation_status,
      scanned_by_mobile_user_id: mobile_user.id,
      scanned_at: now()
    })
  end

  @doc """
  Checks a scanned unit against the organization's received batches:
  `"ok"` when a received batch carries the GTIN + serial with matching
  batch number and dates, `"data_mismatch"` when the serial is known but
  its details differ, and `"unknown_serial"` otherwise.
  """
  def known_unit_status(organization_id, parsed) do
    batches =
      Repo.all(
        from b in Batch,
          where: b.organization_id == ^organization_id,
          where: b.gtin == ^parsed.gtin and b.serial == ^parsed.serial,
          where: not is_nil(b.received_at),
          order_by: [asc: b.id]
      )

    case batches do
      [] ->
        {"unknown_serial", nil}

      [first | _] ->
        case Enum.find(batches, &unit_matches_batch?(&1, parsed)) do
          nil -> {"data_mismatch", first}
          batch -> {"ok", batch}
        end
    end
  end

  defp unit_matches_batch?(batch, parsed) do
    batch.batch_no == parsed.batch_no and batch.expiry_date == parsed.expiry_date and
      (is_nil(parsed.production_date) or is_nil(batch.manufacture_date) or
         batch.manufacture_date == parsed.production_date)
  end

  @doc "Removes a scanned unit from a held draft shipment."
  def delete_item(%MobileUser{} = mobile_user, item_id) do
    with {:ok, item} <- fetch_mobile_item(mobile_user, item_id) do
      edit_draft(mobile_user, item.shipment_id, fn _shipment -> Repo.delete!(item) end)
    end
  end

  @doc "Moves a scanned unit to another shipper of the same shipment."
  def move_item(%MobileUser{} = mobile_user, item_id, target_shipper_id) do
    with {:ok, item} <- fetch_mobile_item(mobile_user, item_id) do
      edit_draft(mobile_user, item.shipment_id, fn shipment ->
        move_item_to_shipper(item, target_shipper_id, shipment.id)
      end)
    end
  end

  defp move_item_to_shipper(item, target_shipper_id, shipment_id) do
    case Repo.get_by(Shipper, id: target_shipper_id, shipment_id: shipment_id) do
      nil ->
        Repo.rollback(:invalid_shipper)

      target ->
        item |> Ecto.Changeset.change(shipper_id: target.id) |> Repo.update!()
    end
  end

  @doc """
  Submits a held draft for approval: validates it, reserves every scanned
  serial, and moves it to `"submitted"`. Fails with
  `{:error, {:invalid, problems}}` when validation fails, including a
  `:serial_conflict` if another shipment won a race on any unit.
  """
  def submit_shipment(%MobileUser{} = mobile_user, id) do
    result =
      edit_draft(mobile_user, id, fn shipment ->
        shipment = preload_shipment(shipment)

        case validate_shipment(shipment) do
          [] -> :ok
          problems -> Repo.rollback({:invalid, problems})
        end

        reserve_serials!(shipment)

        shipment =
          shipment
          |> Ecto.Changeset.change(
            status: "submitted",
            submitted_by_mobile_user_id: mobile_user.id,
            submitted_at: now(),
            rejection_reason: nil,
            rejected_at: nil,
            rejected_by_id: nil
          )
          |> Repo.update!()

        log_event!(shipment, "submitted", mobile_user: mobile_user)
        shipment
      end)

    tap_broadcast(result, "submitted")
  end

  defp reserve_serials!(shipment) do
    items = Enum.flat_map(shipment.shippers, & &1.items)
    timestamp = now()

    entries =
      Enum.map(items, fn item ->
        %{
          organization_id: shipment.organization_id,
          shipment_id: shipment.id,
          barcode: item.gtin,
          serial: item.serial,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    Repo.insert_all(SerialReservation, entries,
      on_conflict: :nothing,
      conflict_target: [:barcode, :serial]
    )

    if owned_reservation_count(shipment.id) != length(items) do
      Repo.rollback({:invalid, [problem(:serial_conflict, conflict_message())]})
    end
  end

  defp owned_reservation_count(shipment_id) do
    Repo.aggregate(
      from(r in SerialReservation, where: r.shipment_id == ^shipment_id),
      :count,
      :id
    )
  end

  defp conflict_message,
    do: "One or more scanned units are already part of another submitted or approved shipment."

  @doc "Returns a rejected shipment to draft so it can be corrected and resubmitted."
  def reopen_shipment(%MobileUser{} = mobile_user, id) do
    result =
      Repo.transaction(fn ->
        shipment = lock_mobile_shipment!(mobile_user, id)
        if shipment.status != "rejected", do: Repo.rollback({:invalid_state, shipment.status})

        shipment =
          shipment
          |> Ecto.Changeset.change(status: "draft", assigned_mobile_user_id: mobile_user.id)
          |> Repo.update!()

        log_event!(shipment, "reopened", mobile_user: mobile_user)
        shipment
      end)

    tap_broadcast(result, "reopened")
  end

  ## Review — portal

  @doc """
  Validates a shipment (preloaded with shippers and items) for submission
  or approval. Returns a list of `%{code:, message:}` problems; empty means
  valid.
  """
  def validate_shipment(%Shipment{} = shipment) do
    organization_id = shipment.organization_id

    [
      gln_problem(
        :origin_not_found,
        GlnLookup.resolve_origin(organization_id, shipment.origin_gln)
      ),
      gln_problem(
        :destination_not_found,
        GlnLookup.resolve_destination(organization_id, shipment.destination_gln)
      ),
      shipment.origin_gln == shipment.destination_gln &&
        problem(:same_gln, "Origin and destination GLNs must be different."),
      blank?(shipment.order_number) && problem(:missing_order_number, "Order number is missing."),
      shipment.shippers == [] && problem(:no_shippers, "Add at least one shipper.")
    ]
    |> Enum.concat(empty_shipper_problems(shipment))
    |> Enum.concat(conflict_problems(shipment))
    |> Enum.filter(& &1)
  end

  defp gln_problem(:origin_not_found, {:error, :not_found}),
    do: problem(:origin_not_found, "The origin GLN is not one of your active sites.")

  defp gln_problem(:destination_not_found, {:error, :not_found}),
    do:
      problem(:destination_not_found, "The destination GLN is not one of your active customers.")

  defp gln_problem(_code, {:ok, _resolved}), do: nil

  defp empty_shipper_problems(shipment) do
    shipment.shippers
    |> Enum.filter(&(&1.items == []))
    |> Enum.map(&problem(:empty_shipper, "#{&1.name} has no scanned units."))
  end

  defp conflict_problems(shipment) do
    items = Enum.flat_map(shipment.shippers, & &1.items)

    conflicts =
      Enum.filter(items, fn item ->
        Repo.exists?(
          from r in SerialReservation,
            where: r.barcode == ^item.gtin and r.serial == ^item.serial,
            where: r.shipment_id != ^shipment.id
        )
      end)

    Enum.map(conflicts, fn item ->
      problem(
        :serial_conflict,
        "Unit #{item.gtin} / #{item.serial} is already in another submitted or approved shipment."
      )
    end)
  end

  defp problem(code, message), do: %{code: code, message: message}

  @doc """
  Approves a submitted shipment: re-validates it, confirms every unit still
  holds its reservation, charges the serialisation allowance (one serial per
  shipper), issues one SSCC per shipper with a contents snapshot, and makes
  the reservations permanent.

  Idempotent: approving an already-approved shipment returns
  `{:already_approved, shipment}` and issues nothing. Errors:
  `{:invalid_state, status}`, `{:invalid, problems}`, `:reservation_missing`,
  `:missing_gs1_company_prefix`, or `{:billing, reason}`.
  """
  def approve_shipment(organization_id, user, id) do
    result =
      Repo.transaction(fn ->
        shipment = lock_shipment!(organization_id, id)

        case shipment.status do
          "approved" -> Repo.rollback({:already_approved, shipment})
          "submitted" -> :ok
          status -> Repo.rollback({:invalid_state, status})
        end

        shipment = preload_shipment(shipment)

        case validate_shipment(shipment) do
          [] -> :ok
          problems -> Repo.rollback({:invalid, problems})
        end

        ensure_reserved!(shipment)
        issue_ssccs!(shipment)
        commit_reservations!(shipment)

        shipment =
          shipment
          |> Ecto.Changeset.change(
            status: "approved",
            approved_at: now(),
            approved_by_id: user.id
          )
          |> Repo.update!()

        log_event!(shipment, "approved", user: user)
        shipment
      end)

    case result do
      {:error, {:already_approved, shipment}} -> {:already_approved, shipment}
      result -> tap_broadcast(result, "approved")
    end
  end

  defp ensure_reserved!(shipment) do
    item_count = shipment.shippers |> Enum.flat_map(& &1.items) |> length()
    if owned_reservation_count(shipment.id) != item_count, do: Repo.rollback(:reservation_missing)
  end

  defp issue_ssccs!(shipment) do
    shipper_count = length(shipment.shippers)

    with {:ok, _prefix} <- Sscc.prefix_for_organization(shipment.organization_id),
         {:ok, _usage} <- charge_allowance(shipment.organization_id, shipper_count),
         {:ok, ssccs} <- Sscc.allocate(shipment.organization_id, shipper_count) do
      timestamp = now()

      shipment.shippers
      |> Enum.zip(ssccs)
      |> Enum.each(fn {shipper, sscc} ->
        shipper
        |> Ecto.Changeset.change(
          Map.merge(shipper_contents(shipper), %{sscc: sscc, sscc_assigned_at: timestamp})
        )
        |> Repo.update!()
      end)
    else
      {:error, :missing_gs1_company_prefix} -> Repo.rollback(:missing_gs1_company_prefix)
      {:error, {:billing, _reason} = error} -> Repo.rollback(error)
    end
  end

  defp charge_allowance(organization_id, count) do
    case Billing.authorize_generation(organization_id, count) do
      {:ok, usage} -> {:ok, usage}
      {:error, reason} -> {:error, {:billing, reason}}
    end
  end

  @doc false
  def shipper_contents(%Shipper{items: items}) do
    combinations =
      items
      |> Enum.map(&{&1.gtin, &1.batch, &1.production_date, &1.expiry_date})
      |> Enum.uniq()

    case combinations do
      [{gtin, batch, production_date, expiry_date}] ->
        %{
          gtin: gtin,
          batch: batch,
          production_date: production_date,
          expiry_date: expiry_date,
          product_name: items |> hd() |> Map.get(:product_name),
          unit_count: length(items)
        }

      _mixed ->
        %{
          gtin: nil,
          batch: nil,
          production_date: nil,
          expiry_date: nil,
          product_name: nil,
          unit_count: length(items)
        }
    end
  end

  defp commit_reservations!(shipment) do
    Repo.update_all(
      from(r in SerialReservation, where: r.shipment_id == ^shipment.id),
      set: [committed_at: now()]
    )
  end

  @doc """
  Rejects a submitted shipment with a reason, releasing all of its serial
  reservations so the units can go into other shipments.
  """
  def reject_shipment(organization_id, user, id, reason) do
    reason = String.trim(reason || "")

    if reason == "" do
      {:error, :reason_required}
    else
      result = Repo.transaction(fn -> do_reject_shipment(organization_id, id, reason, user) end)
      tap_broadcast(result, "rejected")
    end
  end

  defp do_reject_shipment(organization_id, id, reason, user) do
    shipment = lock_shipment!(organization_id, id)
    if shipment.status != "submitted", do: Repo.rollback({:invalid_state, shipment.status})

    Repo.delete_all(from r in SerialReservation, where: r.shipment_id == ^shipment.id)

    shipment =
      shipment
      |> Ecto.Changeset.change(
        status: "rejected",
        rejection_reason: reason,
        rejected_at: now(),
        rejected_by_id: user.id
      )
      |> Repo.update!()

    log_event!(shipment, "rejected", user: user, details: %{reason: reason})
    shipment
  end

  @doc """
  Removes one scanned unit (and its reservation) from a shipment under
  review. Blocked once the shipment is approved.
  """
  def remove_item(organization_id, user, shipment_id, item_id) do
    result =
      Repo.transaction(fn ->
        shipment = lock_shipment!(organization_id, shipment_id)
        if shipment.status == "approved", do: Repo.rollback(:already_approved)

        item =
          Repo.get_by(ShipmentItem, id: item_id, shipment_id: shipment.id) ||
            Repo.rollback(:not_found)

        Repo.delete_all(
          from r in SerialReservation,
            where: r.shipment_id == ^shipment.id,
            where: r.barcode == ^item.gtin and r.serial == ^item.serial
        )

        Repo.delete!(item)

        log_event!(shipment, "item_removed",
          user: user,
          details: %{gtin: item.gtin, serial: item.serial}
        )

        shipment
      end)

    tap_broadcast(result, "updated")
  end

  ## Helpers

  defp edit_draft(%MobileUser{} = mobile_user, shipment_id, fun) do
    Repo.transaction(fn ->
      shipment = lock_mobile_shipment!(mobile_user, shipment_id)

      cond do
        shipment.status != "draft" -> Repo.rollback({:invalid_state, shipment.status})
        shipment.assigned_mobile_user_id != mobile_user.id -> Repo.rollback(:not_assigned)
        true -> :ok
      end

      result = fun.(shipment)

      shipment
      |> Ecto.Changeset.change(updated_at: now())
      |> Repo.update!()

      result
    end)
  end

  defp fetch_mobile_shipper(mobile_user, shipper_id) do
    case Repo.get_by(Shipper, id: shipper_id, organization_id: mobile_user.organization_id) do
      nil -> {:error, :not_found}
      shipper -> {:ok, shipper}
    end
  end

  defp fetch_mobile_item(mobile_user, item_id) do
    case Repo.get_by(ShipmentItem, id: item_id, organization_id: mobile_user.organization_id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  defp lock_shipment!(organization_id, id) do
    Repo.one(
      from s in Shipment,
        where: s.id == ^id and s.organization_id == ^organization_id,
        lock: "FOR UPDATE"
    ) || Repo.rollback(:not_found)
  end

  defp lock_mobile_shipment!(%MobileUser{organization_id: organization_id}, id),
    do: lock_shipment!(organization_id, id)

  defp log_event!(shipment, event, opts) do
    user = opts[:user]
    mobile_user = opts[:mobile_user]

    Repo.insert!(%ShipmentEvent{
      organization_id: shipment.organization_id,
      shipment_id: shipment.id,
      event: event,
      user_id: user && user.id,
      mobile_user_id: mobile_user && mobile_user.id,
      details: opts[:details] || %{}
    })
  end

  defp tap_broadcast({:ok, %Shipment{} = shipment} = result, event) do
    broadcast(shipment, event)
    result
  end

  defp tap_broadcast(result, _event), do: result

  defp escape_like(term),
    do: Regex.replace(~r/[\\%_]/, term, fn char -> "\\" <> char end)

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
