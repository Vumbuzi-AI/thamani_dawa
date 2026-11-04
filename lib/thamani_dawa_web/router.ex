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
    get "/reset-password", PasswordResetController, :new
    post "/reset-password", PasswordResetController, :create
    get "/reset-password/:token", PasswordResetController, :edit
    post "/reset-password/:token", PasswordResetController, :update

    patch "/switch-site", SiteSwitchController, :update
  end

  scope "/api", ThamaniDawaWeb do
    pipe_through :api

    post "/mpesa/callback/:token", DarajaCallbackController, :create
  end

  scope "/", ThamaniDawaWeb do
    pipe_through :browser

    live_session :unauthenticated, on_mount: [{ThamaniDawaWeb.UserAuth, :mount_current_scope}] do
      live "/signup", SignupLive, :new
      live "/invites/:token", AcceptInviteLive, :edit
    end

    live_session :organization, on_mount: [{ThamaniDawaWeb.UserAuth, :require_admin}] do
      live "/org/dashboard", OrgDashboardLive, :index
      live "/org/earnings", EarningsLive, :index

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
      live "/org/products/:id/batches/:batch_id/dispatch", ProductLive.Show, :dispatch_batch
      live "/org/products/:id/edit", ProductLive.Index, :edit

      live "/org/batches/:id", BatchLive.Show, :show

      live "/org/suppliers", SupplierLive.Index, :index
      live "/org/suppliers/new", SupplierLive.Index, :new
      live "/org/suppliers/:id/edit", SupplierLive.Index, :edit

      live "/org/requisitions", RequisitionQueueLive.Index, :index
      live "/org/requisitions/:id/review", RequisitionQueueLive.Index, :review
      live "/org/requisitions/:id/reject", RequisitionQueueLive.Index, :reject
      live "/org/requisitions/:id/fulfill", RequisitionQueueLive.Index, :fulfill
      live "/org/requisitions/:id", RequisitionQueueLive.Show, :show
    end

    live_session :pharmacy, on_mount: [{ThamaniDawaWeb.UserAuth, :require_pharmacy_access}] do
      live "/pharmacy", PharmacyDashboardLive, :index
      live "/pharmacy/transactions", EarningsLive, :pharmacy
      live "/pharmacy/scan", PharmacyScanLive, :index
      live "/pharmacy/stock", PharmacyStockLive, :index
      live "/pharmacy/stock/products/:id", PharmacyStockProductLive, :show
      live "/pharmacy/stock/batches/:id", PharmacyStockBatchLive, :show

      live "/pharmacy/receive-stock", ReceiveStockLive, :index
      live "/pharmacy/receive-stock/:id/receive", ReceiveStockLive, :receive

      live "/pharmacy/requisitions", RequisitionLive.Index, :index
      live "/pharmacy/requisitions/new", RequisitionLive.Index, :new
      live "/pharmacy/requisitions/:id", RequisitionLive.Show, :show

      live "/pharmacy/quick-sale", QuickSaleLive, :new

      live "/pharmacy/prescriptions", PrescriptionLive.Index, :index
      live "/pharmacy/prescriptions/new", PrescriptionLive.Index, :new
      live "/pharmacy/prescriptions/:id", PrescriptionLive.Show, :show
      live "/pharmacy/prescriptions/:id/receipt", PrescriptionLive.Show, :receipt
      live "/pharmacy/prescriptions/:id/payments/new", PrescriptionLive.Show, :new_payment

      live "/pharmacy/patients", PatientLive.Index, :index
      live "/pharmacy/patients/:id", PatientLive.Show, :show
    end

    live_session :lab, on_mount: [{ThamaniDawaWeb.UserAuth, :require_lab_access}] do
      live "/lab", LabDashboardLive, :index
      live "/lab/transactions", EarningsLive, :lab
      live "/lab/scan", LabScanLive, :index

      live "/lab/patients", LabPatientLive.Index, :index
      live "/lab/patients/:id", LabPatientLive.Show, :show

      live "/lab/orders", LabOrderLive.Index, :index
      live "/lab/orders/new", LabOrderLive.Index, :new
      live "/lab/orders/:id", LabOrderLive.Show, :show
      live "/lab/orders/:id/tests/new", LabOrderLive.Show, :add_test
      live "/lab/orders/:id/collect", LabOrderLive.Show, :collect_specimen

      live "/lab/orders/:id/specimens/:specimen_id/label",
           LabOrderLive.Show,
           :print_specimen_label

      live "/lab/orders/:id/results/:result_id/edit", LabOrderLive.Show, :edit_result
      live "/lab/orders/:id/consumables/new", LabOrderLive.Show, :record_consumable
      live "/lab/orders/:id/report", LabOrderLive.Show, :print_report
      live "/lab/orders/:id/payments/new", LabOrderLive.Show, :new_payment

      live "/lab/receive-stock", LabReceiveStockLive, :index
      live "/lab/receive-stock/:id/receive", LabReceiveStockLive, :receive

      live "/lab/requisitions", LabRequisitionLive.Index, :index
      live "/lab/requisitions/new", LabRequisitionLive.Index, :new
      live "/lab/requisitions/:id", LabRequisitionLive.Show, :show

      live "/lab/stock", LabStockLive, :index
      live "/lab/stock/products/:id", LabStockProductLive, :show
      live "/lab/stock/batches/:id", LabStockBatchLive, :show

      live "/lab/tests", LabTestLive.Index, :index
      live "/lab/tests/new", LabTestLive.Index, :new
      live "/lab/tests/:id/edit", LabTestLive.Index, :edit
    end

    live_session :distributor,
      on_mount: [{ThamaniDawaWeb.UserAuth, :require_distributor_access}] do
      live "/distributor", DistributorDashboardLive, :index

      # Serialisation billing — a plan must be chosen before the shipment
      # workflow is reachable (see ThamaniDawaWeb.DistributorAccess).
      live "/distributor/billing", DistributorBillingLive.Index, :index
      live "/distributor/billing/options", DistributorBillingLive.Options, :index
      live "/distributor/billing/payment", DistributorBillingLive.Payment, :prepay
      live "/distributor/billing/postpay-payment", DistributorBillingLive.Payment, :postpay
      live "/distributor/billing/invoices/:id", DistributorBillingLive.Invoice, :show

      live "/distributor/shipments", DistributorShipmentLive.Index, :index
      live "/distributor/shipments/new", DistributorShipmentLive.Form, :new
      live "/distributor/shipments/:id/edit", DistributorShipmentLive.Form, :edit
      live "/distributor/shipments/:id", DistributorShipmentLive.Show, :show

      live "/distributor/mobile-users", DistributorMobileUserLive.Index, :index
      live "/distributor/mobile-users/new", DistributorMobileUserLive.Index, :new
      live "/distributor/mobile-users/:id/edit", DistributorMobileUserLive.Index, :edit

      live "/distributor/products", DistributorProductLive.Index, :index
      live "/distributor/products/new", DistributorProductLive.Index, :new
      live "/distributor/products/:id", DistributorProductLive.Show, :show
      live "/distributor/batches/:id", DistributorBatchLive, :show
      live "/distributor/receiving", DistributorReceivingLive, :index
      live "/distributor/receiving/new", DistributorReceivingLive, :new
      live "/distributor/receiving/:id", DistributorGoodsReceiptLive, :show
      live "/distributor/suppliers", DistributorSupplierLive.Index, :index
      live "/distributor/suppliers/new", DistributorSupplierLive.Index, :new
      live "/distributor/suppliers/:id/edit", DistributorSupplierLive.Index, :edit
      live "/distributor/customers", DistributorCustomerLive.Index, :index
      live "/distributor/customers/new", DistributorCustomerLive.Index, :new
      live "/distributor/customers/:id/edit", DistributorCustomerLive.Index, :edit
      live "/distributor/warehouses", DistributorWarehouseLive.Index, :index
      live "/distributor/warehouses/new", DistributorWarehouseLive.Index, :new
      live "/distributor/settings", DistributorSettingsLive, :index
    end
  end

  scope "/", ThamaniDawaWeb do
    pipe_through [:browser, :require_distributor_user]

    get "/distributor/shipments/:id/export", DistributorShipmentExportController, :show
  end

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
