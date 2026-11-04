defmodule ThamaniDawaWeb.DistributorMobileUserLive.Index do
  @moduledoc """
  Manages the organization's mobile scanning-app users: add, edit, resend
  PIN (always a brand-new PIN, emailed only — never shown here), and
  activate/deactivate. Deactivating or resending a PIN signs the user out
  of the app everywhere.
  """

  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Distributor
  alias ThamaniDawa.Distributor.MobileUser

  on_mount {ThamaniDawaWeb.DistributorAccess, :require_serialisation_plan}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Mobile users")
     |> assign(:app_download_url, app_download_url())
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
         |> push_patch(to: ~p"/distributor/mobile-users")}

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

  def handle_event("toggle_active", %{"id" => id}, socket) do
    mobile_user = Distributor.get_mobile_user!(socket.assigns.current_scope.organization_id, id)
    {:ok, mobile_user} = Distributor.set_mobile_user_active(mobile_user, !mobile_user.active)

    message =
      if mobile_user.active,
        do: "#{mobile_user.name} can sign in to the app again.",
        else: "#{mobile_user.name} has been deactivated and signed out."

    {:noreply, socket |> put_flash(:info, message) |> load_users()}
  end

  defp load_users(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    mobile_users = Distributor.list_mobile_users(organization_id)

    socket
    |> assign(:activity, Distributor.mobile_user_activity(organization_id))
    |> assign(:mobile_user_count, length(mobile_users))
    |> stream(:mobile_users, mobile_users, reset: true)
  end

  defp app_download_url do
    Application.get_env(:thamani_dawa, :distributor_app_download_url)
  end

  defp activity(activity, mobile_user, key), do: get_in(activity, [mobile_user.id, key]) || 0

  def render(assigns) do
    ~H"""
    <Layouts.distributor_shell
      flash={@flash}
      current_scope={@current_scope}
      current_path={~p"/distributor/mobile-users"}
    >
      <.header icon="hero-device-phone-mobile">
        Mobile users
        <:subtitle>
          People who pack shipments with the Thamani Dawa mobile app. PINs are emailed, never shown here.
        </:subtitle>
        <:actions>
          <.button
            :if={@app_download_url}
            id="download-distributor-app"
            href={@app_download_url}
          >
            <.icon name="hero-arrow-down-tray" class="size-4" /> Get the app
          </.button>
          <.button
            id="add-distributor-mobile-user"
            variant="primary"
            patch={~p"/distributor/mobile-users/new"}
          >
            <.icon name="hero-plus" class="size-4" /> Add mobile user
          </.button>
        </:actions>
      </.header>

      <.modal
        :if={@live_action in [:new, :edit]}
        id="distributor-mobile-user-modal"
        show
        on_cancel={JS.patch(~p"/distributor/mobile-users")}
      >
        <h2 class="mb-1 text-2xl font-medium tracking-tight text-thamani-forest">
          {if @live_action == :new, do: "Add mobile user", else: "Edit mobile user"}
        </h2>
        <p :if={@live_action == :new} class="mb-4 text-sm text-thamani-pewter">
          We'll email a 4-digit PIN to this address. They sign in to the app with their username and PIN.
        </p>
        <.form
          for={@form}
          id="distributor-mobile-user-form"
          phx-change="validate"
          phx-submit="save"
        >
          <.input field={@form[:name]} label="Full name" required />
          <.input
            field={@form[:username]}
            label="Username"
            autocomplete="off"
            autocapitalize="none"
            required
          />
          <div class="grid gap-x-4 sm:grid-cols-2">
            <.input field={@form[:email]} type="email" label="Email (receives the PIN)" required />
            <.input field={@form[:phone]} type="tel" label="Phone" />
          </div>
          <.button id="save-distributor-mobile-user" class="mt-3 w-full" variant="primary">
            {if @live_action == :new, do: "Add and email PIN", else: "Save changes"}
          </.button>
        </.form>
      </.modal>

      <.table id="distributor-mobile-users" rows={@streams.mobile_users}>
        <:col :let={{_id, mobile_user}} label="Name">
          <div>
            <p class="font-medium text-thamani-forest">{mobile_user.name}</p>
            <p class="font-mono text-xs text-thamani-pewter">@{mobile_user.username}</p>
          </div>
        </:col>
        <:col :let={{_id, mobile_user}} label="Status" mobile="aside">
          <.status_badge status={if mobile_user.active, do: :active, else: :inactive} />
        </:col>
        <:col :let={{_id, mobile_user}} label="Contact" tablet="hidden">
          <p class="text-sm">{mobile_user.email}</p>
          <p class="text-xs text-thamani-pewter">{mobile_user.phone || "—"}</p>
        </:col>
        <:col :let={{_id, mobile_user}} label="Last sign-in">
          <span class="text-sm">{date_time(mobile_user.last_login_at)}</span>
        </:col>
        <:col :let={{_id, mobile_user}} label="Shipments">
          <span class="text-sm">
            {activity(@activity, mobile_user, :total)} total
            <span class="text-thamani-pewter">
              · {activity(@activity, mobile_user, "approved")} approved
            </span>
          </span>
        </:col>
        <:action :let={{_id, mobile_user}}>
          <div class="flex flex-wrap justify-end gap-1">
            <.button
              id={"edit-mobile-user-#{mobile_user.id}"}
              variant="ghost-edit"
              patch={~p"/distributor/mobile-users/#{mobile_user.id}/edit"}
            >
              Edit
            </.button>
            <.button
              id={"resend-pin-#{mobile_user.id}"}
              variant="ghost"
              phx-click="resend_pin"
              phx-value-id={mobile_user.id}
              data-confirm={"Email #{mobile_user.name} a new PIN? Their current PIN stops working and they'll be signed out."}
            >
              Resend PIN
            </.button>
            <.button
              id={"toggle-mobile-user-#{mobile_user.id}"}
              variant={if mobile_user.active, do: "ghost-delete", else: "ghost"}
              phx-click="toggle_active"
              phx-value-id={mobile_user.id}
            >
              {if mobile_user.active, do: "Deactivate", else: "Activate"}
            </.button>
          </div>
        </:action>
        <:empty_state>
          <.blank_state icon="hero-device-phone-mobile" title="No mobile users yet">
            Add the people who pack shipments so they can sign in to the mobile app.
          </.blank_state>
        </:empty_state>
      </.table>
    </Layouts.distributor_shell>
    """
  end
end
