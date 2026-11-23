defmodule ThamaniDawaWeb.ManufacturerMobileUserLive.Index do
  @moduledoc """
  Manufacturer mobile scanning accounts. Same org-scoped accounts as the
  distributor list, limited to manufacturing sites. Deactivate asks first.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.MobileUser
  alias ThamaniDawa.Sites
  alias ThamaniDawa.Sites.Site

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    sites =
      organization_id
      |> Sites.list_sites()
      |> Enum.filter(&(Site.manufacturer?(&1) and &1.is_active))

    {:ok,
     socket
     |> assign(:page_title, "Mobile users")
     |> assign(:sites, sites)
     |> assign(:deactivate_user, nil)
     |> load_users()}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:mobile_user, %MobileUser{})
    |> assign(:form, to_form(Distributor.change_mobile_user(%MobileUser{}), as: :mobile_user))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    mobile_user = Distributor.get_mobile_user!(socket.assigns.current_scope.organization_id, id)

    socket
    |> assign(:mobile_user, mobile_user)
    |> assign(:form, to_form(Distributor.change_mobile_user(mobile_user), as: :mobile_user))
  end

  defp apply_action(socket, :index, _params), do: assign(socket, :mobile_user, nil)

  def handle_event("validate", %{"mobile_user" => params}, socket) do
    changeset =
      socket.assigns.mobile_user
      |> Distributor.change_mobile_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :mobile_user))}
  end

  def handle_event("save", %{"mobile_user" => params}, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    result =
      case socket.assigns.live_action do
        :new -> Distributor.create_mobile_user(organization_id, params)
        :edit -> Distributor.update_mobile_user(socket.assigns.mobile_user, params)
      end

    case result do
      {:ok, mobile_user} ->
        message =
          if socket.assigns.live_action == :new,
            do: "#{mobile_user.name} added. Their PIN has been emailed to #{mobile_user.email}.",
            else: "#{mobile_user.name} updated."

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> load_users()
         |> push_patch(to: ~p"/manufacturer/mobile-users")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :mobile_user))}
    end
  end

  def handle_event("resend_pin", %{"id" => id}, socket) do
    mobile_user = Distributor.get_mobile_user!(socket.assigns.current_scope.organization_id, id)
    {:ok, mobile_user} = Distributor.resend_mobile_user_pin(mobile_user)

    {:noreply,
     socket
     |> put_flash(
       :info,
       "A new PIN was emailed to #{mobile_user.email}. They've been signed out of the app."
     )
     |> load_users()}
  end

  def handle_event("ask_deactivate", %{"id" => id}, socket) do
    mobile_user = Distributor.get_mobile_user!(socket.assigns.current_scope.organization_id, id)
    {:noreply, assign(socket, :deactivate_user, mobile_user)}
  end

  def handle_event("cancel_deactivate", _params, socket) do
    {:noreply, assign(socket, :deactivate_user, nil)}
  end

  def handle_event("confirm_deactivate", _params, socket) do
    {:ok, mobile_user} = Distributor.set_mobile_user_active(socket.assigns.deactivate_user, false)

    {:noreply,
     socket
     |> assign(:deactivate_user, nil)
     |> put_flash(:info, "#{mobile_user.name} has been deactivated and signed out.")
     |> load_users()}
  end

  def handle_event("activate", %{"id" => id}, socket) do
    mobile_user = Distributor.get_mobile_user!(socket.assigns.current_scope.organization_id, id)
    {:ok, mobile_user} = Distributor.set_mobile_user_active(mobile_user, true)

    {:noreply,
     socket
     |> put_flash(:info, "#{mobile_user.name} can sign in to the app again.")
     |> load_users()}
  end

  defp load_users(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mobile_users = Distributor.list_mobile_users(organization_id)

    socket
    |> assign(:mobile_user_count, length(mobile_users))
    |> stream(:mobile_users, mobile_users, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.manufacturer_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/manufacturer/mobile-users"}
    >
      <.td_list_page
        title="Mobile users"
        subtitle="People who scan and pack with the Thamani Dawa mobile app. PINs are emailed, never shown here."
      >
        <:actions>
          <.td_button
            id="add-manufacturer-mobile-user"
            variant="primary"
            label="Add mobile user"
            patch={~p"/manufacturer/mobile-users/new"}
          />
        </:actions>
        <.td_data_table id="manufacturer-mobile-users" rows={@streams.mobile_users}>
          <:col :let={{_id, mobile_user}} label="Name">
            <.td_key_value label={mobile_user.name} value={"@#{mobile_user.username}"} mono />
          </:col>
          <:col :let={{_id, mobile_user}} label="Status">
            <.td_badge
              tone={if mobile_user.active, do: "success", else: "neutral"}
              label={if mobile_user.active, do: "Active", else: "Inactive"}
            />
          </:col>
          <:col :let={{_id, mobile_user}} label="Contact">
            <.td_key_value label={mobile_user.email} value={mobile_user.phone || "—"} />
          </:col>
          <:col :let={{_id, mobile_user}} label="Last sign-in">
            {date_time(mobile_user.last_login_at)}
          </:col>
          <:action :let={{_id, mobile_user}}>
            <.td_button
              variant="secondary"
              label="Edit"
              patch={~p"/manufacturer/mobile-users/#{mobile_user.id}/edit"}
            />
            <.td_button
              variant="secondary"
              label="Resend PIN"
              phx-click="resend_pin"
              phx-value-id={mobile_user.id}
            />
            <.td_button
              :if={mobile_user.active}
              id={"deactivate-mobile-user-#{mobile_user.id}"}
              variant="danger"
              label="Deactivate"
              phx-click="ask_deactivate"
              phx-value-id={mobile_user.id}
            />
            <.td_button
              :if={!mobile_user.active}
              variant="secondary"
              label="Activate"
              phx-click="activate"
              phx-value-id={mobile_user.id}
            />
          </:action>
          <:empty>
            <.td_empty
              title="No mobile users yet"
              hint="Add the people who scan and pack so they can sign in to the mobile app."
            />
          </:empty>
        </.td_data_table>
      </.td_list_page>

      <.td_overlay_form
        :if={@live_action in [:new, :edit]}
        id="manufacturer-mobile-user-modal"
        title={if @live_action == :new, do: "Add mobile user", else: "Edit mobile user"}
        subtitle="We'll email a 4-digit PIN to this address. They sign in with their username and PIN."
        submit={if @live_action == :new, do: "Add and email PIN", else: "Save changes"}
        on_cancel={JS.patch(~p"/manufacturer/mobile-users")}
      >
        <.form
          for={@form}
          id="manufacturer-mobile-user-modal-form"
          phx-change="validate"
          phx-submit="save"
        >
          <.td_input field={@form[:name]} label="Full name" required />
          <.td_input
            field={@form[:username]}
            label="Username"
            autocomplete="off"
            autocapitalize="none"
            required
          />
          <.td_input field={@form[:email]} type="email" label="Email (receives the PIN)" required />
          <.td_input field={@form[:phone]} type="tel" label="Phone" />
          <.td_select
            field={@form[:site_id]}
            label="Home site (optional)"
            options={Enum.map(@sites, &{&1.name, &1.id})}
            prompt="Leave blank to allow this account across your manufacturing sites."
          />
        </.form>
      </.td_overlay_form>

      <.td_confirm
        :if={@deactivate_user}
        id="deactivate-manufacturer-mobile-user"
        title={"Deactivate #{@deactivate_user.name}"}
        body="They will be signed out of the app and cannot sign in until you activate them again."
        confirm="Deactivate"
        confirm_click="confirm_deactivate"
        on_cancel={JS.push("cancel_deactivate")}
      />
    </Layouts.manufacturer_shell>
    """
  end
end
