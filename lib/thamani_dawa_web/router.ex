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

    patch "/switch-site", SiteSwitchController, :update
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
      live "/org/team/:id/edit", TeamLive.Index, :edit

      live "/org/sites", SiteLive.Index, :index
      live "/org/sites/new", SiteLive.Index, :new
      live "/org/sites/:id", SiteLive.Show, :show
      live "/org/sites/:id/edit", SiteLive.Index, :edit

      live "/org/products", ProductLive.Index, :index
      live "/org/products/new", ProductLive.Index, :new
      live "/org/products/:id", ProductLive.Show, :show
      live "/org/products/:id/batches/new", ProductLive.Show, :new_batch
      live "/org/products/:id/edit", ProductLive.Index, :edit

      live "/org/batches/:id", BatchLive.Show, :show

      live "/org/suppliers", SupplierLive.Index, :index
      live "/org/suppliers/new", SupplierLive.Index, :new
      live "/org/suppliers/:id/edit", SupplierLive.Index, :edit
    end

    live_session :pharmacy, on_mount: [{ThamaniDawaWeb.UserAuth, :require_pharmacy_access}] do
      live "/pharmacy", PharmacyDashboardLive, :index
      live "/pharmacy/scan", PharmacyScanLive, :index
      live "/pharmacy/stock", PharmacyStockLive, :index
      live "/pharmacy/stock/products/:id", PharmacyStockProductLive, :show
      live "/pharmacy/stock/batches/:id", PharmacyStockBatchLive, :show

      live "/pharmacy/receive-stock", ReceiveStockLive, :index
      live "/pharmacy/receive-stock/:id/receive", ReceiveStockLive, :receive

      live "/pharmacy/stock-takes", StockTakeLive.Index, :index
      live "/pharmacy/stock-takes/new", StockTakeLive.Index, :new
      live "/pharmacy/stock-takes/:id", StockTakeLive.Show, :show

      live "/pharmacy/prescriptions", PrescriptionLive.Index, :index
      live "/pharmacy/prescriptions/new", PrescriptionLive.Index, :new
      live "/pharmacy/prescriptions/:id", PrescriptionLive.Show, :show
      live "/pharmacy/prescriptions/:id/payments/new", PrescriptionLive.Show, :new_payment

      live "/pharmacy/patients", PatientLive.Index, :index
      live "/pharmacy/patients/new", PatientLive.Index, :new
      live "/pharmacy/patients/:id", PatientLive.Show, :show
    end

    live_session :lab, on_mount: [{ThamaniDawaWeb.UserAuth, :require_lab_access}] do
      live "/lab", LabDashboardLive, :index
      live "/lab/scan", LabScanLive, :index

      live "/lab/patients", LabPatientLive.Index, :index
      live "/lab/patients/new", LabPatientLive.Index, :new
      live "/lab/patients/:id", LabPatientLive.Show, :show

      live "/lab/orders", LabOrderLive.Index, :index
      live "/lab/orders/new", LabOrderLive.Index, :new
      live "/lab/orders/:id", LabOrderLive.Show, :show
      live "/lab/orders/:id/tests/new", LabOrderLive.Show, :add_test
      live "/lab/orders/:id/results/:result_id/edit", LabOrderLive.Show, :edit_result
      live "/lab/orders/:id/payments/new", LabOrderLive.Show, :new_payment

      live "/lab/receive-stock", LabReceiveStockLive, :index
      live "/lab/receive-stock/:id/receive", LabReceiveStockLive, :receive

      live "/lab/tests", LabTestLive.Index, :index
      live "/lab/tests/new", LabTestLive.Index, :new
      live "/lab/tests/:id/edit", LabTestLive.Index, :edit
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
