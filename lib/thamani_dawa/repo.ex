defmodule ThamaniDawa.Repo do
  use Ecto.Repo,
    otp_app: :thamani_dawa,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 8

  alias ThamaniDawa.AuditLog

  @audit_actor_key {__MODULE__, :audit_actor}
  @sensitive_fields [:hashed_password, :hashed_pin, :token, :password, :password_confirmation]

  @doc "Sets the actor attached to audited writes in the current request/LiveView process."
  def put_audit_actor(user) do
    Process.put(@audit_actor_key, %{user_id: user.id, organization_id: user.organization_id})
  end

  @doc "Clears the current process's audit actor. Useful for background/system work."
  def clear_audit_actor, do: Process.delete(@audit_actor_key)

  def audited_insert(changeset_or_struct, opts \\ []) do
    audited_write(:insert, changeset_or_struct, &insert(&1, opts))
  end

  def audited_update(changeset_or_struct, opts \\ []) do
    audited_write(:update, changeset_or_struct, &update(&1, opts))
  end

  def audited_delete(struct, opts \\ []) do
    audited_write(:delete, struct, &delete(&1, opts))
  end

  def audited_update!(changeset_or_struct, opts \\ []) do
    {:ok, record} =
      transaction(fn ->
        record = update!(changeset_or_struct, opts)
        audit_change(:update, changeset_or_struct, record)
        record
      end)

    record
  end

  defp audited_write(action, input, write) do
    transaction(fn ->
      case write.(input) do
        {:ok, record} ->
          audit_change(action, input, record)
          record

        {:error, reason} ->
          rollback(reason)
      end
    end)
  end

  # `on_conflict: :nothing` can return a struct without an ID. It did not
  # create or alter a record, so there is no change to audit.
  defp audit_change(_action, _input, %{id: nil}), do: :ok

  defp audit_change(action, input, record) do
    case Process.get(@audit_actor_key) do
      nil ->
        :ok

      actor ->
        record_organization_id = Map.get(record, :organization_id)

        if record_organization_id && record_organization_id != actor.organization_id do
          rollback(:audit_actor_organization_mismatch)
        end

        attrs = %{
          user_id: actor.user_id,
          organization_id: record_organization_id || actor.organization_id,
          action: Atom.to_string(action),
          table_name: record.__struct__.__schema__(:source),
          record_id: record.id,
          previous_state: previous_state(action, input),
          new_state: new_state(action, record),
          changed_fields: changed_fields(action, input)
        }

        %AuditLog{}
        |> AuditLog.changeset(attrs)
        |> insert!()
    end
  end

  defp previous_state(:insert, _input), do: nil
  defp previous_state(:delete, struct), do: sanitize_state(struct)
  defp previous_state(:update, %Ecto.Changeset{data: data}), do: sanitize_state(data)
  defp previous_state(:update, struct), do: sanitize_state(struct)

  defp new_state(:delete, _record), do: nil
  defp new_state(_action, record), do: sanitize_state(record)

  defp changed_fields(:update, %Ecto.Changeset{changes: changes}),
    do: changes |> Map.keys() |> Enum.map(&Atom.to_string/1)

  defp changed_fields(_action, _input), do: []

  defp sanitize_state(struct) do
    associations = struct.__struct__.__schema__(:associations)

    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__ | @sensitive_fields])
    |> Map.drop(associations)
    |> Map.new(fn {field, value} -> {Atom.to_string(field), sanitize_value(value)} end)
  end

  defp sanitize_value(%Decimal{} = value), do: Decimal.to_string(value)
  defp sanitize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp sanitize_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp sanitize_value(%Date{} = value), do: Date.to_iso8601(value)
  defp sanitize_value(%Time{} = value), do: Time.to_iso8601(value)
  defp sanitize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp sanitize_value(value) when is_list(value), do: Enum.map(value, &sanitize_value/1)

  defp sanitize_value(value) when is_map(value),
    do: Map.new(value, fn {key, nested} -> {to_string(key), sanitize_value(nested)} end)

  defp sanitize_value(value), do: value
end
