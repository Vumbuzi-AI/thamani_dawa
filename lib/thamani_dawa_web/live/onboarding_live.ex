defmodule ThamaniDawaWeb.OnboardingLive do
  use ThamaniDawaWeb, :live_view

  alias ThamaniDawa.Organizations
  alias ThamaniDawa.Sites

  def mount(params, _session, socket) do
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

  defp item_icon(:invite_team), do: "hero-user-group"
  defp item_icon(:add_branch), do: "hero-building-office-2"
  defp item_icon(:first_product), do: "hero-cube"
  defp item_icon(_key), do: "hero-rocket-launch"

  defp progress_pct(current, total) when total > 0, do: current / total * 100
  defp progress_pct(_current, _total), do: 0

  defp completed_count(items, skipped) do
    Enum.count(items, & &1.done?) + length(skipped)
  end

  defp displayed_completed_count(true, items, _skipped), do: length(items)
  defp displayed_completed_count(false, items, skipped), do: completed_count(items, skipped)

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} navigation={false}>
      <div id="onboarding-shell" class="flex min-h-svh flex-col bg-[var(--thamani-surface)]">
        <header class="border-b border-[color-mix(in_srgb,var(--thamani-stone)_70%,transparent)]">
          <div class="mx-auto flex h-20 w-full max-w-7xl items-center justify-between gap-6 px-5 sm:px-8 lg:px-12">
            <.link
              navigate={~p"/org/dashboard"}
              aria-label="Thamani Dawa home"
              class="w-36 sm:w-[148px]"
            >
              <img src="/images/logo-transparent.png" alt="" class="h-auto w-full" />
            </.link>

            <div id="onboarding-user" class="flex min-w-0 items-center gap-3">
              <span
                class="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--thamani-forest)] text-sm font-semibold uppercase text-[var(--thamani-on-accent)] shadow-sm"
                aria-hidden="true"
              >
                {String.first(@current_scope.user.name || "U")}
              </span>
              <span class="max-w-44 truncate text-sm font-medium text-[var(--thamani-forest)]">
                {@current_scope.user.name}
              </span>
            </div>
          </div>
        </header>

        <div id="onboarding-progress" class="w-full" aria-label="Setup progress">
          <div class="h-1 w-full overflow-hidden bg-[var(--thamani-stone)]">
            <div
              class="h-full bg-[var(--thamani-forest)] transition-[width] duration-300 ease-out"
              style={
                "width: #{progress_pct(displayed_completed_count(@show_completion?, @items, @skipped), length(@items))}%"
              }
            />
          </div>
        </div>

        <main class={[
          "mx-auto w-full max-w-5xl flex-1 px-5 pb-16 pt-10 sm:px-8 sm:pt-12 md:pt-16 lg:pt-20"
        ]}>
          <section
            :if={@show_completion?}
            id="onboarding-complete"
            class="thamani-step-enter relative mx-auto flex max-w-3xl flex-col items-center overflow-hidden px-4 py-8 text-center sm:py-14"
          >
            <div
              class="pointer-events-none absolute left-1/2 top-16 size-36 -translate-x-1/2"
              aria-hidden="true"
            >
              <span
                class="onboarding-confetti-piece bg-[var(--color-td-accent-tint)]"
                style="--x:-92px; --y:-58px; --r:210deg; --d:0ms"
              />
              <span
                class="onboarding-confetti-piece rounded-full bg-[var(--thamani-forest)]"
                style="--x:88px; --y:-52px; --r:150deg; --d:60ms"
              />
              <span
                class="onboarding-confetti-piece bg-td-danger"
                style="--x:-118px; --y:4px; --r:280deg; --d:110ms"
              />
              <span
                class="onboarding-confetti-piece rounded-full bg-td-warning"
                style="--x:116px; --y:10px; --r:190deg; --d:150ms"
              />
              <span
                class="onboarding-confetti-piece bg-td-info"
                style="--x:-72px; --y:70px; --r:330deg; --d:190ms"
              />
              <span
                class="onboarding-confetti-piece bg-[var(--color-td-accent-tint)]"
                style="--x:76px; --y:72px; --r:240deg; --d:220ms"
              />
              <span
                class="onboarding-confetti-piece rounded-full bg-td-chart"
                style="--x:-28px; --y:-84px; --r:180deg; --d:80ms"
              />
              <span
                class="onboarding-confetti-piece bg-td-ev-rose-fg"
                style="--x:34px; --y:-82px; --r:300deg; --d:130ms"
              />
            </div>

            <div
              class="relative flex size-24 items-center justify-center rounded-full bg-[color-mix(in_srgb,var(--color-td-accent-tint)_13%,white)] text-[var(--thamani-forest)] shadow-[0_18px_45px_rgba(30,57,48,0.08)]"
              aria-hidden="true"
            >
              <.icon name="hero-check" class="size-12 stroke-[2.2]" />
            </div>

            <h1 class="mt-7 text-[34px] font-light leading-tight tracking-[-0.8px] text-[var(--thamani-forest)] sm:text-[44px]">
              Your workspace is ready
            </h1>
            <p class="mt-5 max-w-2xl text-base leading-7 text-[var(--thamani-pewter)] sm:text-[17px]">
              Your workspace is set up and ready to use. Take a quick tour to get familiar with Thamani Dawa, or head straight to your dashboard.
            </p>

            <div class="mt-9 flex w-full max-w-xl flex-col gap-3 sm:flex-row sm:justify-center">
              <.link
                id="onboarding-take-tour"
                navigate={~p"/org/dashboard?tour=1"}
                class="inline-flex min-h-12 flex-1 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent no-underline transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg"
              >
                Take the 2-minute tour
              </.link>
              <.link
                id="onboarding-go-dashboard"
                navigate={~p"/org/dashboard"}
                class="inline-flex min-h-12 flex-1 items-center justify-center rounded-full border border-[var(--thamani-stone)] bg-td-surface px-7 py-3 text-[15px] font-medium text-[var(--thamani-forest)] no-underline transition-all duration-200 hover:-translate-y-0.5 hover:border-[var(--thamani-forest)] hover:shadow-md"
              >
                Go to dashboard
              </.link>
            </div>
          </section>

          <section
            :if={@show_welcome? and not @show_completion?}
            id="onboarding-welcome"
            class="thamani-step-enter grid items-center gap-10 md:grid-cols-[0.9fr_1.1fr] md:gap-10 lg:gap-16"
          >
            <div class="flex flex-col items-center text-center md:block md:text-left">
              <div class="mb-7 flex size-12 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] text-[var(--thamani-forest)]">
                <.icon name="hero-sparkles" class="size-6" />
              </div>

              <h1 class="w-full max-w-md text-[30px] font-light leading-[1.08] tracking-[-0.7px] text-[var(--thamani-forest)] sm:text-[38px]">
                Your workspace is ready
              </h1>
              <p class="mt-6 w-full max-w-md text-base leading-7 text-[var(--thamani-pewter)] sm:text-[17px]">
                Your organization and main location are set. Next, prepare Thamani Dawa for day-to-day operations.
              </p>

              <button
                id="onboarding-start"
                type="button"
                phx-click="start_setup"
                class="mt-10 inline-flex min-h-12 items-center justify-center rounded-full bg-thamani-forest px-7 py-3 text-[15px] font-medium text-thamani-on-accent transition-all duration-200 ease-out hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--thamani-forest)]"
              >
                Start setup <.icon name="hero-arrow-right" class="ml-3 size-4" />
              </button>
            </div>

            <div class="rounded-3xl border border-[var(--thamani-stone)] bg-td-surface/70 p-5 shadow-[0_18px_60px_rgba(30,57,48,0.05)] sm:p-6">
              <div class="grid gap-3">
                <div
                  :for={item <- @items}
                  id={"onboarding-preview-#{item.key}"}
                  class="flex min-h-16 items-center gap-4 rounded-2xl bg-[var(--thamani-canvas)] px-4 py-3"
                >
                  <span class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
                    <.icon name={item_icon(item.key)} class="size-5" />
                  </span>
                  <span class="min-w-0 flex-1 text-[15px] font-medium text-[var(--thamani-forest)]">
                    {item.label}
                  </span>
                </div>
              </div>
            </div>
          </section>

          <section
            :if={not @show_welcome? and not @show_completion? and not is_nil(@current)}
            id={"onboarding-panel-#{@current.key}"}
            class="thamani-step-enter grid items-center gap-10 md:grid-cols-[0.9fr_1.1fr] md:gap-10 lg:gap-16"
          >
            <div class="flex flex-col items-center text-center md:block md:text-left">
              <div class="mb-7 flex size-12 items-center justify-center rounded-2xl bg-[color-mix(in_srgb,var(--color-td-accent-tint)_18%,white)] text-[var(--thamani-forest)]">
                <.icon name="hero-sparkles" class="size-6" />
              </div>

              <h1 class="w-full max-w-md text-[30px] font-light leading-[1.08] tracking-[-0.7px] text-[var(--thamani-forest)] sm:text-[38px]">
                Let's finish setting up
              </h1>
              <p class="mt-6 w-full max-w-md text-base leading-7 text-[var(--thamani-pewter)] sm:text-[17px]">
                A few more steps and you'll be ready for day-to-day operations.
              </p>

              <div class="mt-10 flex w-full flex-col items-stretch gap-3 sm:flex-row sm:items-center sm:justify-center md:w-auto md:justify-start">
                <.link
                  id="onboarding-cta"
                  navigate={onboarding_path(@current.path, @replay)}
                  class="inline-flex min-h-12 items-center justify-center rounded-full border-0 bg-thamani-forest px-6 py-3 text-[15px] font-medium text-thamani-on-accent no-underline transition-all duration-200 ease-out hover:-translate-y-0.5 hover:shadow-lg focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--thamani-forest)]"
                >
                  Continue setup <.icon name="hero-arrow-right" class="ml-2 size-4" />
                </.link>
                <button
                  id="onboarding-skip"
                  type="button"
                  phx-click="skip"
                  class="min-h-12 rounded-full px-5 text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:bg-[var(--thamani-canvas)] hover:text-[var(--thamani-forest)]"
                >
                  Skip this step
                </button>
              </div>

              <button
                :if={@skipped != []}
                id="onboarding-back"
                type="button"
                phx-click="back"
                class="mt-5 inline-flex items-center text-sm font-medium text-[var(--thamani-pewter)] transition-colors hover:text-[var(--thamani-forest)]"
              >
                <.icon name="hero-arrow-left" class="mr-2 size-4" /> Previous step
              </button>

              <p class="mt-8 max-w-md text-sm leading-6 text-[var(--thamani-subtle)]">
                Your progress is saved as you complete each task.
              </p>
            </div>

            <aside
              id="onboarding-setup-plan"
              aria-label="Setup plan"
              class="rounded-3xl border border-[var(--thamani-stone)] bg-td-surface/70 p-5 shadow-[0_18px_60px_rgba(30,57,48,0.05)] sm:p-6"
            >
              <div class="grid gap-3">
                <.link
                  :for={item <- @items}
                  id={"onboarding-plan-#{item.key}"}
                  navigate={onboarding_path(item.path)}
                  class={[
                    "flex min-h-16 items-center gap-4 rounded-2xl px-4 py-3 no-underline transition-colors hover:brightness-95",
                    if(item.key == @current.key,
                      do:
                        "bg-[color-mix(in_srgb,var(--color-td-accent-tint)_13%,white)] ring-1 ring-[color-mix(in_srgb,var(--thamani-forest)_18%,transparent)]",
                      else: "bg-[var(--thamani-canvas)]"
                    )
                  ]}
                >
                  <span class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-td-surface text-[var(--thamani-forest)] shadow-sm ring-1 ring-black/[0.04]">
                    <.icon name={item_icon(item.key)} class="size-5" />
                  </span>
                  <span class="min-w-0 flex-1 text-[15px] font-medium text-[var(--thamani-forest)]">
                    {item.label}
                  </span>
                  <span
                    :if={item.done? or item.key in @skipped}
                    class="flex size-6 shrink-0 items-center justify-center rounded-full bg-[var(--thamani-forest)] text-white"
                    aria-label="Complete"
                  >
                    <.icon name="hero-check" class="size-4" />
                  </span>
                  <span
                    :if={item.key == @current.key}
                    class="shrink-0 rounded-full bg-td-surface px-2.5 py-1 text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--thamani-forest)] ring-1 ring-black/[0.05]"
                  >
                    Current
                  </span>
                </.link>
              </div>
            </aside>
          </section>
        </main>
      </div>
    </Layouts.app>
    """
  end
end
