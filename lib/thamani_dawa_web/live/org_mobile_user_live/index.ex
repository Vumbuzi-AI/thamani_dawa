defmodule ThamaniDawaWeb.OrgMobileUserLive.Index do
  @moduledoc """
  Organization-level management of GS1 healthcare mobile users. The accounts
  live on the GS1 member API (`ThamaniDawa.GS1.MemberApi`), called with the
  organization's own GS1 API key: each user is either a distribution or a
  manufacturing user, and a manufacturing user can be limited to
  aggregation only. GS1 generates the four-digit PIN and emails it.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.GS1.MemberApi
  alias ThamaniDawa.Organizations

  @roles [{"Distribution", "distribution"}, {"Manufacturing", "manufacturing"}]
  @scopes [{"Full app", "full"}, {"Aggregation only", "aggregation_only"}]

  def mount(_params, _session, socket) do
    api_key = Organizations.gs1_api_key(socket.assigns.current_scope.organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Mobile users")
     |> assign(:api_key, api_key)
     |> assign(:users, [])
     |> assign(:load_error, nil)
     |> assign(:deactivate_user, nil)
     |> assign(:resend_user, nil)
     |> load_users()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:editing, nil)
    |> assign(:form_errors, %{})
    |> assign(:form, user_form(%{"role" => "manufacturing", "access_scope" => "full"}))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Enum.find(socket.assigns.users, &(&1["id"] == id)) do
      nil ->
        socket
        |> put_flash(:error, "Mobile user not found.")
        |> push_patch(to: ~p"/org/mobile-users")

      user ->
        socket
        |> assign(:editing, user)
        |> assign(:form_errors, %{})
        |> assign(:form, user_form(user))
    end
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:editing, nil) |> assign(:form, nil) |> assign(:form_errors, %{})
  end

  def handle_event("validate", %{"mobile_user" => params}, socket) do
    {:noreply, assign(socket, :form, user_form(params))}
  end

  def handle_event("save", %{"mobile_user" => params}, socket) do
    body = request_body(params)
    opts = [api_token: socket.assigns.api_key]

    result =
      case socket.assigns.editing do
        nil -> MemberApi.create_mobile_user(body, opts)
        user -> MemberApi.update_mobile_user(user["id"], body, opts)
      end

    case result do
      {:ok, response} ->
        {:noreply,
         socket
         |> put_flash(:info, save_flash(socket.assigns.editing, response))
         |> load_users()
         |> push_patch(to: ~p"/org/mobile-users")}

      {:error, {:validation, errors}} ->
        {:noreply,
         socket
         |> assign(:form_errors, errors)
         |> assign(:form, user_form(params, errors))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("ask_resend", %{"id" => id}, socket) do
    {:noreply, assign(socket, :resend_user, Enum.find(socket.assigns.users, &(&1["id"] == id)))}
  end

  def handle_event("cancel_resend", _params, socket) do
    {:noreply, assign(socket, :resend_user, nil)}
  end

  def handle_event("confirm_resend", _params, socket) do
    case socket.assigns.resend_user do
      nil ->
        {:noreply, socket}

      user ->
        socket
        |> assign(:resend_user, nil)
        |> then(fn socket ->
          # Reuse the existing event so the GS1 call stays in one place.
          handle_event("resend_pin", %{"id" => user["id"]}, socket)
        end)
    end
  end

  def handle_event("resend_pin", %{"id" => id}, socket) do
    case MemberApi.resend_mobile_user_pin(id, api_token: socket.assigns.api_key) do
      {:ok, %{"pin_delivery" => "failed"}} ->
        {:noreply, put_flash(socket, :error, "A new PIN was set, but the email failed to send.")}

      {:ok, response} ->
        {:noreply,
         put_flash(socket, :info, "A new PIN was emailed to #{user_email(response, socket, id)}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("ask_deactivate", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :deactivate_user, Enum.find(socket.assigns.users, &(&1["id"] == id)))}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, assign(socket, :deactivate_user, nil)}
  end

  def handle_event("confirm_deactivate", _params, socket) do
    case socket.assigns.deactivate_user do
      nil -> {:noreply, socket}
      user -> set_active(assign(socket, :deactivate_user, nil), user["id"], false)
    end
  end

  def handle_event("activate", %{"id" => id}, socket), do: set_active(socket, id, true)

  defp set_active(socket, id, active?) do
    case MemberApi.set_mobile_user_active(id, active?, api_token: socket.assigns.api_key) do
      {:ok, %{"mobile_user" => user}} ->
        verb = if active?, do: "reactivated", else: "deactivated and signed out"
        {:noreply, socket |> put_flash(:info, "#{user["name"]} #{verb}.") |> load_users()}

      {:ok, _response} ->
        {:noreply, load_users(socket)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  defp load_users(%{assigns: %{api_key: nil}} = socket), do: socket

  defp load_users(socket) do
    case MemberApi.list_mobile_users(api_token: socket.assigns.api_key) do
      {:ok, users} -> socket |> assign(:users, users) |> assign(:load_error, nil)
      {:error, reason} -> assign(socket, :load_error, error_message(reason))
    end
  end

  # The GS1 API takes a role and an `aggregation_only` boolean; the form
  # shows the boolean as a scope choice that only applies to manufacturing.
  defp request_body(params) do
    role = if params["role"] == "distribution", do: "distribution", else: "manufacturing"

    %{
      "name" => String.trim(params["name"] || ""),
      "username" => String.trim(params["username"] || ""),
      "email" => String.trim(params["email"] || ""),
      "phone" => String.trim(params["phone"] || ""),
      "role" => role,
      "aggregation_only" =>
        role == "manufacturing" and params["access_scope"] == "aggregation_only"
    }
  end

  defp user_form(params, errors \\ %{}) do
    params =
      Map.new(~w(name username email phone role access_scope), fn key ->
        {key, params[key] || ""}
      end)

    form_errors =
      for {field, messages} <- errors, message <- List.wrap(messages) do
        {safe_field(field), {message, []}}
      end

    to_form(params, as: :mobile_user, errors: form_errors)
  end

  @form_fields ~w(name username email phone role)a
  defp safe_field(field) do
    Enum.find(@form_fields, :name, &(Atom.to_string(&1) == to_string(field)))
  end

  defp save_flash(nil, %{"pin_delivery" => "failed", "mobile_user" => user}),
    do: "#{user["name"]} was added, but the PIN email failed. Use Resend PIN."

  defp save_flash(nil, %{"mobile_user" => user}),
    do: "#{user["name"]} was added. Their PIN was emailed to #{user["email"]}."

  defp save_flash(_editing, _response), do: "Mobile user saved."

  defp user_email(%{"mobile_user" => %{"email" => email}}, _socket, _id) when is_binary(email),
    do: email

  defp user_email(_response, socket, id) do
    case Enum.find(socket.assigns.users, &(&1["id"] == id)) do
      %{"email" => email} when is_binary(email) -> email
      _ -> "the user"
    end
  end

  defp error_message(:unconfigured),
    do: "Add your GS1 API key in Org settings to manage mobile users."

  defp error_message(:unauthorized),
    do: "GS1 rejected this organization's API key. Check it in Org settings."

  defp error_message(:not_found), do: "That mobile user no longer exists on GS1."
  defp error_message({:invalid, message}), do: message
  defp error_message({:validation, _errors}), do: "Please fix the highlighted fields."
  defp error_message(_reason), do: "GS1 is unavailable right now. Try again in a moment."

  defp role_label(%{"role" => "distribution"}), do: "Distribution"
  defp role_label(_user), do: "Manufacturing"

  defp scope_label(%{"role" => "distribution"}), do: "Full app"
  defp scope_label(%{"access_scope" => "aggregation_only"}), do: "Aggregation only"
  defp scope_label(_user), do: "Full app"

  defp roles, do: @roles
  defp scopes, do: @scopes

  def render(assigns) do
    ~H"""
    <Layouts.org_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/org/mobile-users"}
    >
      <.td_list_page
        title="Mobile users"
        subtitle="Scanning-app accounts for distribution and manufacturing, managed on GS1."
      >
        <:actions>
          <.td_button
            :if={@api_key}
            id="new-mobile-user"
            variant="primary"
            label="Add mobile user"
            patch={~p"/org/mobile-users/new"}
          />
        </:actions>

        <%= cond do %>
          <% is_nil(@api_key) -> %>
            <div id="mobile-users-unconfigured">
              <.td_empty
                icon="key"
                title="Connect GS1 first"
                hint="Mobile users are created on your GS1 member account. Add your GS1 API key in Org settings."
              >
                <:action>
                  <.td_button variant="secondary" label="Org settings" navigate={~p"/org/settings"} />
                </:action>
              </.td_empty>
            </div>
          <% @load_error -> %>
            <p id="mobile-users-error" class="td-note" style="color: var(--color-td-danger);">
              {@load_error}
            </p>
          <% @users == [] -> %>
            <div id="mobile-users-empty">
              <.td_empty
                icon="user"
                title="No mobile users yet"
                hint="Add a user, pick distribution or manufacturing, and GS1 emails them a PIN."
              >
                <:action>
                  <.td_button
                    id="empty-add-mobile-user"
                    variant="secondary"
                    label="Add mobile user"
                    patch={~p"/org/mobile-users/new"}
                  />
                </:action>
              </.td_empty>
            </div>
          <% true -> %>
            <.table id="mobile-users" rows={@users} row_id={&"mobile-user-#{&1["id"]}"}>
              <:col :let={user} label="Name">
                <div class="font-medium">{user["name"]}</div>
                <div class="text-xs text-[var(--thamani-pewter)]">@{user["username"]}</div>
              </:col>
              <:col :let={user} label="Email">{user["email"]}</:col>
              <:col :let={user} label="Role">
                <.td_badge tone="info" label={role_label(user)} />
              </:col>
              <:col :let={user} label="Access">{scope_label(user)}</:col>
              <:col :let={user} label="Status">
                <.td_badge
                  tone={if user["active"], do: "success", else: "neutral"}
                  label={if user["active"], do: "Active", else: "Inactive"}
                />
              </:col>
              <:action :let={user}>
                <.link
                  id={"edit-mobile-user-#{user["id"]}"}
                  patch={~p"/org/mobile-users/#{user["id"]}/edit"}
                >
                  Edit
                </.link>
              </:action>
              <:action :let={user}>
                <.link
                  id={"resend-pin-#{user["id"]}"}
                  phx-click="ask_resend"
                  phx-value-id={user["id"]}
                >
                  Resend PIN
                </.link>
              </:action>
              <:action :let={user}>
                <%= if user["active"] do %>
                  <.link
                    id={"deactivate-mobile-user-#{user["id"]}"}
                    phx-click="ask_deactivate"
                    phx-value-id={user["id"]}
                  >
                    Deactivate
                  </.link>
                <% else %>
                  <.link
                    id={"activate-mobile-user-#{user["id"]}"}
                    phx-click="activate"
                    phx-value-id={user["id"]}
                  >
                    Activate
                  </.link>
                <% end %>
              </:action>
            </.table>
        <% end %>
      </.td_list_page>

      <.td_overlay_form
        :if={@form}
        id="mobile-user-modal"
        title={if @editing, do: "Edit #{@editing["name"]}", else: "Add a mobile user"}
        subtitle={
          if @editing,
            do: "To send a new PIN, use Resend PIN from the list.",
            else: "GS1 generates a four-digit PIN and emails it to this address."
        }
        submit={if @editing, do: "Save", else: "Save and email PIN"}
        on_cancel={JS.patch(~p"/org/mobile-users")}
      >
        <.form
          for={@form}
          id="mobile-user-modal-form"
          phx-change="validate"
          phx-submit="save"
          autocomplete="off"
        >
          <.td_input field={@form[:name]} label="Name" required />
          <.td_input field={@form[:username]} label="Username" required />
          <.td_input field={@form[:email]} type="email" label="Email" required />
          <.td_input field={@form[:phone]} label="Phone (optional)" />
          <.td_select field={@form[:role]} label="Role" options={roles()} />
          <%= if @form[:role].value != "distribution" do %>
            <.td_select
              field={@form[:access_scope]}
              label="Manufacturing access"
              options={scopes()}
              hint="Aggregation only limits the user to scanning serials into shipper SSCCs."
            />
          <% end %>
        </.form>
      </.td_overlay_form>

      <.td_confirm
        :if={@resend_user}
        id="resend-pin-modal"
        title={"Send #{@resend_user["name"]} a new PIN?"}
        body="Their current PIN stops working. GS1 emails the new one."
        confirm="Send new PIN"
        confirm_click="confirm_resend"
        on_cancel={JS.push("cancel_resend")}
      />

      <.td_confirm
        :if={@deactivate_user}
        id="deactivate-mobile-user-modal"
        title={"Deactivate #{@deactivate_user["name"]}?"}
        body="They are signed out of the mobile app and can't sign in until reactivated."
        confirm="Deactivate"
        confirm_click="confirm_deactivate"
        on_cancel={JS.push("cancel_deactivate")}
      />
    </Layouts.org_shell>
    """
  end
end
