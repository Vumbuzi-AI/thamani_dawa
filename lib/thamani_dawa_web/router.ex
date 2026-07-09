defmodule ThamaniDawaWeb.Router do
  use ThamaniDawaWeb, :router

  import ThamaniDawaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ThamaniDawaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ThamaniDawaWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/privacy", PageController, :privacy
    get "/terms", PageController, :terms
    get "/contact", PageController, :contact

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
  end

  scope "/", ThamaniDawaWeb do
    pipe_through :browser

    live_session :unauthenticated, on_mount: [{ThamaniDawaWeb.UserAuth, :mount_current_scope}] do
      live "/signup", SignupLive, :new
      live "/invites/:token", AcceptInviteLive, :edit
    end

    live_session :organization, on_mount: [{ThamaniDawaWeb.UserAuth, :require_admin}] do
      live "/org/team", TeamLive.Index, :index
      live "/org/team/new", TeamLive.Index, :new

      live "/org/sites", SiteLive.Index, :index
      live "/org/sites/new", SiteLive.Index, :new
      live "/org/sites/:id/edit", SiteLive.Index, :edit

      live "/org/products", ProductLive.Index, :index
      live "/org/products/new", ProductLive.Index, :new
      live "/org/products/:id", ProductLive.Show, :show
      live "/org/products/:id/edit", ProductLive.Index, :edit
    end

    live_session :pharmacy, on_mount: [{ThamaniDawaWeb.UserAuth, :require_pharmacy_access}] do
      live "/pharmacy", PharmacyDashboardLive, :index
      live "/pharmacy/scan", PharmacyScanLive, :index

      live "/pharmacy/receive-stock", ReceiveStockLive, :new

      live "/pharmacy/prescriptions", PrescriptionLive.Index, :index
      live "/pharmacy/prescriptions/new", PrescriptionLive.Index, :new
      live "/pharmacy/prescriptions/:id", PrescriptionLive.Show, :show
    end

    live_session :lab, on_mount: [{ThamaniDawaWeb.UserAuth, :require_lab_access}] do
      live "/lab", LabDashboardLive, :index
      live "/lab/scan", LabScanLive, :index

      live "/lab/orders", LabOrderLive.Index, :index
      live "/lab/orders/new", LabOrderLive.Index, :new
      live "/lab/orders/:id", LabOrderLive.Show, :show

      live "/lab/orders/:lab_order_id/results/:id/edit", ResultEntryLive, :edit

      live "/lab/verification-queue", VerificationQueueLive, :index

      live "/lab/receive-stock", LabReceiveStockLive, :new
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ThamaniDawaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:thamani_dawa, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ThamaniDawaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
