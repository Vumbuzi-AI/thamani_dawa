defmodule ThamaniDawaWeb.OnboardingLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Accounts
  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites
  alias ThamaniDawaWeb.Portals

  def mount(params, _session, socket) do
    if Accounts.demo_login_account?(socket.assigns.current_scope.user) do
      {:ok, redirect(socket, to: Portals.default_path(socket.assigns.current_scope))}
    else
      mount_checklist(params, socket)
    end
  end

  defp mount_checklist(params, socket) do
    skipped =
      case params["skip"] do
        "add_branch" -> [:add_branch]
        "invite_team" -> [:invite_team]
        "first_product" -> [:first_product]
        "connect_keys" -> [:connect_keys]
        _other -> []
      end

    replay =
      case params["replay"] do
        "invite_team" -> :invite_team
        "first_product" -> :first_product
        _other -> nil
      end

    completion_requested? = params["complete"] == "1"
    force_completion? = params["force"] == "1"

    socket
    |> assign(:skipped, skipped)
    |> assign(:replay, replay)
    |> assign(:completion_requested?, completion_requested?)
    |> assign(:force_completion?, force_completion?)
    |> assign(:show_completion?, false)
    |> assign(:show_welcome?, false)
    |> load_items()
    |> redirect_if_finished()
  end

  defp load_items(socket) do
    organization_id = socket.assigns.current_scope.organization_id
    organization = Organizations.get_organization!(organization_id)
    primary_site = organization_id |> Sites.list_sites() |> List.first()
    items = Organizations.onboarding_checklist(organization, primary_site)

    show_welcome? =
      is_nil(socket.assigns.replay) and socket.assigns.skipped == [] and items != [] and
        Enum.all?(items, &(not &1.done?))

    socket
    |> assign(:organization, organization)
    |> assign(:primary_site, primary_site)
    |> assign(:items, items)
    |> assign(:show_welcome?, show_welcome?)
    |> assign_remaining()
  end

  defp assign_remaining(socket) do
    remaining =
      if socket.assigns.replay do
        Enum.filter(socket.assigns.items, &(&1.key == socket.assigns.replay))
      else
        Enum.reject(socket.assigns.items, fn item ->
          item.done? or item.key in socket.assigns.skipped
        end)
      end

    socket
    |> assign(:remaining, remaining)
    |> assign(:current, List.first(remaining))
  end

  defp redirect_if_finished(socket) do
    cond do
      socket.assigns.completion_requested? and
          (is_nil(socket.assigns.current) or socket.assigns.force_completion?) ->
        {:ok, assign(socket, :show_completion?, true)}

      is_nil(socket.assigns.current) ->
        {:ok, push_navigate(socket, to: ~p"/org/dashboard?tour=1")}

      not socket.assigns.show_welcome? and socket.assigns.current.key == :invite_team ->
        {:ok,
         push_navigate(socket,
           to: onboarding_path(socket.assigns.current.path, socket.assigns.replay)
         )}

      true ->
        {:ok, socket}
    end
  end

  def handle_event("skip", _params, socket) do
    socket =
      socket
      |> update(:skipped, &(&1 ++ [socket.assigns.current.key]))
      |> assign_remaining()

    if socket.assigns.current do
      {:noreply, socket}
    else
      {:noreply, assign(socket, :show_completion?, true)}
    end
  end

  def handle_event("start_setup", _params, socket) do
    {:noreply, push_navigate(socket, to: onboarding_path(socket.assigns.current.path))}
  end

  def handle_event("back", _params, socket) do
    socket =
      socket
      |> update(:skipped, &List.delete_at(&1, -1))
      |> assign_remaining()

    if socket.assigns.current.key == :invite_team do
      {:noreply, push_navigate(socket, to: onboarding_path(socket.assigns.current.path))}
    else
      {:noreply, socket}
    end
  end

  defp onboarding_path(path) do
    uri = URI.parse(path)
    query = (uri.query || "") |> URI.decode_query() |> Map.put("return_to", "onboarding")
    %{uri | query: URI.encode_query(query)} |> URI.to_string()
  end

  defp onboarding_path(path, :first_product) do
    uri = URI.parse(onboarding_path(path))
    query = (uri.query || "") |> URI.decode_query() |> Map.put("finish", "tour")
    %{uri | query: URI.encode_query(query)} |> URI.to_string()
  end

  defp onboarding_path(path, :invite_team) do
    uri = URI.parse(onboarding_path(path))
    query = (uri.query || "") |> URI.decode_query() |> Map.put("replay_next", "first_product")
    %{uri | query: URI.encode_query(query)} |> URI.to_string()
  end

  defp onboarding_path(path, _replay), do: onboarding_path(path)

  defp completed_count(items, skipped) do
    Enum.count(items, & &1.done?) + length(skipped)
  end

  defp displayed_completed_count(true, items, _skipped), do: length(items)
  defp displayed_completed_count(false, items, skipped), do: completed_count(items, skipped)

  defp rail_state(_item, _current, _skipped, true), do: :done

  defp rail_state(item, current, skipped, _show_completion?) do
    cond do
      item.done? or item.key in skipped -> :done
      current && item.key == current.key -> :current
      true -> :todo
    end
  end

  defp welcome_lead(organization, nil),
    do:
      "#{organization.name} is registered. A few quick steps and you're ready for day-to-day operations."

  defp welcome_lead(organization, site),
    do:
      "#{organization.name} is registered and #{site.name} is your main location. A few quick steps and you're ready for day-to-day operations."

  def render(assigns) do
    completed =
      displayed_completed_count(assigns.show_completion?, assigns.items, assigns.skipped)

    total = length(assigns.items)

    assigns =
      assigns
      |> assign(:completed_count, completed)
      |> assign(:total_count, total)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={false}>
      <div id="onboarding-shell" class="td-onb">
        <header class="td-onb-bar">
          <.link navigate={~p"/org/dashboard"} aria-label="Thamani Dawa home">
            <img src="/images/logo-transparent.png" alt="" />
          </.link>
          <span id="onboarding-user" class="td-onb-who">
            {@organization.name} · {@current_scope.user.name}
          </span>
        </header>

        <div class="td-onb-bd">
          <nav class="td-onb-sp" aria-label="Setup plan">
            <p
              id="onboarding-progress"
              class="td-onb-sec"
              aria-label="Setup progress"
            >
              Setup progress · {@completed_count} of {@total_count}
            </p>

            <.link
              :for={{item, index} <- Enum.with_index(@items, 1)}
              id={
                if(@show_welcome? and not @show_completion?,
                  do: "onboarding-preview-#{item.key}",
                  else: "onboarding-plan-#{item.key}"
                )
              }
              navigate={onboarding_path(item.path)}
              class={[
                "td-onb-it",
                rail_state(item, @current, @skipped, @show_completion?) == :current && "is-current",
                rail_state(item, @current, @skipped, @show_completion?) == :done && "is-done"
              ]}
            >
              <span class="td-onb-n">{index}</span>
              {item.label}
            </.link>

            <div class="td-onb-sp-foot">
              <.td_button
                id="onboarding-go-dashboard"
                variant="secondary"
                label="Go to dashboard"
                navigate={~p"/org/dashboard"}
              />
            </div>
          </nav>

          <main class="td-onb-ct">
            <section
              :if={@show_completion?}
              id="onboarding-complete"
              class="td-onb-hero is-welcome thamani-step-enter"
            >
              <h1>Your workspace is ready</h1>
              <p class="td-onb-lead">
                {welcome_lead(@organization, @primary_site)} Take a quick tour, or go to your dashboard.
              </p>
              <div class="td-onb-actions">
                <.td_button
                  id="onboarding-take-tour"
                  variant="primary"
                  size="lg"
                  label="Take the 2-minute tour"
                  navigate={~p"/org/dashboard?tour=1"}
                />
              </div>
            </section>

            <section
              :if={@show_welcome? and not @show_completion?}
              id="onboarding-welcome"
              class="td-onb-hero is-welcome thamani-step-enter"
            >
              <h1>Your workspace is ready</h1>
              <p class="td-onb-lead">{welcome_lead(@organization, @primary_site)}</p>
              <div class="td-onb-actions">
                <.td_button
                  id="onboarding-start"
                  variant="primary"
                  size="lg"
                  label="Start setup"
                  glyph="arrow-right"
                  type="button"
                  phx-click="start_setup"
                />
                <.td_button
                  variant="secondary"
                  size="lg"
                  label="Take the 2-minute tour"
                  navigate={~p"/org/dashboard?tour=1"}
                />
              </div>
            </section>

            <section
              :if={not @show_welcome? and not @show_completion? and not is_nil(@current)}
              id={"onboarding-panel-#{@current.key}"}
              class="td-onb-hero thamani-step-enter"
            >
              <h1>{@current.label}</h1>
              <p class="td-onb-lead">{@current.description}</p>
              <div class="td-onb-actions">
                <.td_button
                  :if={@skipped != []}
                  id="onboarding-back"
                  variant="secondary"
                  label="Back"
                  glyph="arrow-left"
                  type="button"
                  phx-click="back"
                />
                <.td_button
                  id="onboarding-cta"
                  variant="primary"
                  size="lg"
                  label="Continue setup"
                  glyph="arrow-right"
                  navigate={onboarding_path(@current.path, @replay)}
                />
                <.td_button
                  id="onboarding-skip"
                  variant="secondary"
                  label="Skip this step"
                  type="button"
                  phx-click="skip"
                />
              </div>
            </section>
          </main>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
