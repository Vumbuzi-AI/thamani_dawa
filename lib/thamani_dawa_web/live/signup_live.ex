defmodule ThamaniDawaWeb.SignupLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts.User
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Organizations.Organization

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        :org_form,
        to_form(Organization.changeset(%Organization{}, %{}), as: :organization)
      )
      |> assign(:admin_form, to_form(User.registration_changeset(%User{}, %{}), as: :user))

    {:ok, socket}
  end

  def handle_event("validate", %{"organization" => org_params, "user" => admin_params}, socket) do
    org_changeset =
      %Organization{}
      |> Organization.changeset(org_params)
      |> Map.put(:action, :validate)

    admin_changeset =
      %User{}
      |> User.registration_changeset(admin_params, hash_password: false)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:org_form, to_form(org_changeset, as: :organization))
     |> assign(:admin_form, to_form(admin_changeset, as: :user))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("save", %{"organization" => org_params, "user" => admin_params}, socket) do
    case Organizations.signup(org_params, admin_params) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created — log in with the password you just set.")
         |> push_navigate(to: ~p"/login")}

      {:error, %Ecto.Changeset{data: %Organization{}} = changeset} ->
        {:noreply, assign(socket, :org_form, to_form(changeset, as: :organization))}

      {:error, %Ecto.Changeset{data: %User{}} = changeset} ->
        {:noreply, assign(socket, :admin_form, to_form(changeset, as: :user))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Something went wrong setting up your organization. Please try again."
         )}
    end
  end

  def render(assigns) do
    ~H"""
    <div style="min-height: 100vh; display: flex; flex-direction: row;">
      <div
        class="hidden lg:flex"
        style="width: 46%; background: var(--thamani-forest); flex-direction: column; justify-content: space-between; padding: 48px 52px; position: relative; overflow: hidden;"
      >
        <div
          aria-hidden="true"
          style="position: absolute; top: -120px; right: -120px; width: 420px; height: 420px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.08; pointer-events: none;"
        >
        </div>
        <div
          aria-hidden="true"
          style="position: absolute; bottom: -80px; left: -80px; width: 280px; height: 280px; border-radius: 50%; background: var(--thamani-lime); opacity: 0.06; pointer-events: none;"
        >
        </div>

        <.link
          navigate={~p"/"}
          style="font-size: 17px; font-weight: 500; color: var(--thamani-snow); text-decoration: none; letter-spacing: -0.01em; position: relative;"
        >
          Thamani Dawa
        </.link>

        <div style="position: relative;">
          <span
            class="thamani-badge"
            style="background: var(--thamani-lime); color: var(--thamani-forest); font-size: 11px; margin-bottom: 24px; display: inline-flex;"
          >
            Free to start · No credit card
          </span>
          <h2 style="font-size: clamp(28px, 2.8vw, 40px); font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-snow); text-wrap: balance; margin: 16px 0 20px;">
            Set up your pharmacy in under two minutes.
          </h2>
          <p style="font-size: 16px; line-height: 1.65; color: rgba(252,252,247,0.55); max-width: 340px;">
            Create your organization, add your team, and start managing stock, prescriptions, and lab orders — all GS1 compliant.
          </p>
        </div>

        <div style="position: relative; border-top: 1px solid rgba(252,252,247,0.1); padding-top: 28px;">
          <p style="font-size: 15px; font-weight: 350; color: rgba(252,252,247,0.75); line-height: 1.55; font-style: italic; margin-bottom: 16px;">
            "We were up and running in a single afternoon — stock, prescriptions, everything."
          </p>
          <p style="font-size: 13px; font-weight: 500; color: rgba(252,252,247,0.45);">
            Jane Mwangi · Owner, MedPoint Pharmacy, Nakuru
          </p>
        </div>
      </div>

      <div style="flex: 1; background: var(--thamani-snow); display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 48px 24px;">
        <.link
          navigate={~p"/"}
          class="lg:hidden"
          style="font-size: 16px; font-weight: 500; color: var(--thamani-forest); text-decoration: none; letter-spacing: -0.01em; margin-bottom: 40px; align-self: flex-start;"
        >
          Thamani Dawa
        </.link>

        <div style="width: 100%; max-width: 420px;">
          <ThamaniDawaWeb.Layouts.flash_group flash={@flash} />

          <h1 style="font-size: 32px; font-weight: 350; letter-spacing: -0.4px; line-height: 1.15; color: var(--thamani-forest); margin-bottom: 8px;">
            Create your account
          </h1>
          <p style="font-size: 15px; color: var(--thamani-pewter); line-height: 1.5; margin-bottom: 36px;">
            Set up your organization and admin profile to get started.
          </p>

          <form phx-submit="save" phx-change="validate" id="signup-form">
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-4">
              <.thamani_input
                field={@org_form[:name]}
                label="Pharmacy / lab name"
                placeholder="e.g. MedPoint Pharmacy"
                phx-debounce="blur"
                required
              />
              <.thamani_input
                field={@org_form[:license_number]}
                label="License number"
                placeholder="PPB-XXXX"
                phx-debounce="blur"
                required
              />
            </div>

            <div style="height: 12px;" />

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-4">
              <.thamani_input
                field={@admin_form[:name]}
                label="Your name"
                placeholder="Jane Mwangi"
                autocomplete="name"
                phx-debounce="blur"
                required
              />
              <.thamani_input
                field={@admin_form[:email]}
                type="email"
                label="Email address"
                placeholder="you@yourpharmacy.com"
                autocomplete="email"
                phx-debounce="blur"
                required
              />
            </div>

            <.thamani_input
              field={@admin_form[:password]}
              type="password"
              label="Password"
              placeholder="••••••••"
              autocomplete="new-password"
              class="mb-8"
              phx-debounce="blur"
              required
            />

            <.thamani_btn id="signup-submit" type="submit" variant="primary">
              Create account
            </.thamani_btn>
          </form>

          <p style="text-align: center; font-size: 14px; color: var(--thamani-pewter); margin-top: 28px;">
            Already have an account?
            <.link
              navigate={~p"/login"}
              style="color: var(--thamani-forest); text-decoration: underline; text-underline-offset: 3px; font-weight: 500;"
            >
              Log in here
            </.link>
          </p>
        </div>

        <div
          class="lg:hidden"
          style="margin-top: 48px; display: flex; gap: 20px; align-items: center;"
        >
          <.link
            navigate={~p"/privacy"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >Privacy</.link>
          <span style="font-size: 12px; color: var(--thamani-stone);">·</span>
          <.link
            navigate={~p"/terms"}
            style="font-size: 12px; color: var(--thamani-subtle); text-decoration: none;"
          >Terms</.link>
        </div>
      </div>
    </div>
    """
  end
end
