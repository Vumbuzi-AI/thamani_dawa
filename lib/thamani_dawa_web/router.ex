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

    get "/confirm/:token", ConfirmationController, :confirm

    patch "/switch-site", SiteSwitchController, :update
  end

  scope "/api", ThamaniDawaWeb do
    pipe_through :api

    post "/mpesa/callback/:token", DarajaCallbackController, :create
  end

  scope "/api/v1", ThamaniDawaWeb.Api.V1, as: :api_v1 do
    pipe_through :api

    post "/login", SessionController, :login
    post "/token/refresh", SessionController, :refresh
    post "/signup", SessionController, :signup
    post "/invites/:token", SessionController, :accept_invite
  end

  scope "/api/v1", ThamaniDawaWeb.Api.V1, as: :api_v1 do
    pipe_through [:api, ThamaniDawaWeb.Plugs.ApiAuth]

    post "/logout", SessionController, :logout
    get "/me", SessionController, :me
    get "/session/sites", SessionController, :sites
    patch "/session/site", SessionController, :switch_site

    get "/pharmacy/dashboard", PharmacyController, :dashboard
    post "/pharmacy/scans", PharmacyController, :scan
    get "/pharmacy/stock", PharmacyController, :stock
    get "/pharmacy/stock/products/:id", PharmacyController, :stock_product
    get "/pharmacy/stock/batches/:id", PharmacyController, :stock_batch
    get "/pharmacy/catalog", PharmacyController, :catalog
    post "/pharmacy/sales", PharmacyController, :create_sale
    get "/pharmacy/receipts", PharmacyController, :receipts
    post "/pharmacy/receipts/:id/receive", PharmacyController, :confirm_receipt
    get "/pharmacy/transactions", PharmacyController, :transactions

    get "/pharmacy/prescriptions", PrescriptionController, :index
    post "/pharmacy/prescriptions", PrescriptionController, :create
    get "/pharmacy/prescriptions/:id", PrescriptionController, :show
    post "/pharmacy/prescriptions/:id/items/:item_id/dispense", PrescriptionController, :dispense
    post "/pharmacy/prescriptions/:id/items/:item_id/verify", PrescriptionController, :verify
    post "/pharmacy/prescriptions/:id/payments", PrescriptionController, :pay

    get "/pharmacy/patients", PatientController, :index
    post "/pharmacy/patients", PatientController, :create
    get "/pharmacy/patients/:id", PatientController, :show

    get "/pharmacy/requisitions", RequisitionController, :index
    post "/pharmacy/requisitions", RequisitionController, :create
    get "/pharmacy/requisitions/:id", RequisitionController, :show

    get "/lab/dashboard", LabController, :dashboard
    post "/lab/scans", LabController, :scan
    get "/lab/orders", LabController, :orders
    post "/lab/orders", LabController, :create_order
    get "/lab/orders/:id", LabController, :show_order
    post "/lab/orders/:id/specimens", LabController, :collect
    put "/lab/results/:id", LabController, :save_result
    post "/lab/orders/:id/consumables", LabController, :consume
    post "/lab/orders/:id/payments", LabController, :pay
    get "/lab/stock", LabController, :stock
    get "/lab/receipts", LabController, :receipts
    post "/lab/receipts", LabController, :create_receipt
    post "/lab/receipts/:id/receive", LabController, :receive_batch
    get "/lab/tests", LabController, :tests
    post "/lab/tests", LabController, :create_test
    patch "/lab/tests/:id", LabController, :update_test

    get "/org/dashboard", OrgController, :dashboard
    get "/org/earnings", OrgController, :earnings
    get "/org/team", TeamController, :index
    post "/org/team", TeamController, :create
    patch "/org/team/:id", TeamController, :update

    get "/org/requisitions", RequisitionController, :queue
    get "/org/requisitions/:id", RequisitionController, :queue_show
    post "/org/requisitions/:id/review", RequisitionController, :review
    post "/org/requisitions/:id/reject", RequisitionController, :reject
    post "/org/requisitions/:id/fulfill", RequisitionController, :fulfill

    get "/products", CatalogController, :products
    post "/products", CatalogController, :create_product
    get "/products/:id", CatalogController, :show_product
    patch "/products/:id", CatalogController, :update_product
    post "/products/:product_id/batches", CatalogController, :create_batch
    get "/batches/:id", CatalogController, :show_batch
    post "/batches/:id/dispatch", CatalogController, :dispatch

    get "/suppliers", CatalogController, :suppliers
    post "/suppliers", CatalogController, :create_supplier
    patch "/suppliers/:id", CatalogController, :update_supplier

    get "/sites", CatalogController, :sites
    post "/sites", CatalogController, :create_site
    get "/sites/:id", CatalogController, :show_site
    patch "/sites/:id", CatalogController, :update_site
  end

  scope "/", ThamaniDawaWeb do
    pipe_through :browser

    live_session :unauthenticated,
      on_mount: [{ThamaniDawaWeb.UserAuth, :redirect_if_authenticated}] do
      live "/signup", SignupLive, :new
    end

    # Not gated by :redirect_if_authenticated — accepting an invite must work
    # even when the browser already holds another user's session; the old
    # session is only ended once the invite is actually accepted (see
    # AcceptInviteLive's hard redirect to /login on save).
    live_session :accept_invite,
      on_mount: [{ThamaniDawaWeb.UserAuth, :mount_current_scope}] do
      live "/invites/:token", AcceptInviteLive, :edit
    end

    live_session :confirm_email, on_mount: [{ThamaniDawaWeb.UserAuth, :require_admin}] do
      live "/confirm-email", ConfirmEmailLive, :index
    end

    live_session :organization,
      on_mount: [
        {ThamaniDawaWeb.UserAuth, :require_admin},
        {ThamaniDawaWeb.UserAuth, :require_confirmed_email}
      ] do
      live "/onboarding", OnboardingLive, :index

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
      live "/org/products/import", ProductLive.Import, :new
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

      live "/org/stock-takes", StockTakeQueueLive.Index, :index
      live "/org/stock-takes/:id/approve", StockTakeQueueLive.Index, :approve
      live "/org/stock-takes/:id/reject", StockTakeQueueLive.Index, :reject
      live "/org/stock-takes/:id", StockTakeQueueLive.Show, :show

      live "/org/disposals", InventoryDisposalQueueLive.Index, :index
      live "/org/disposals/:id/approve", InventoryDisposalQueueLive.Index, :approve
      live "/org/disposals/:id/reject", InventoryDisposalQueueLive.Index, :reject
      live "/org/disposals/:id", InventoryDisposalQueueLive.Show, :show
      live "/org/api-keys", ApiKeysLive, :index
      live "/org/epcis", DistributorEpcisLive, :index
      live "/org/settings", OrganizationSettingsLive, :index
    end

    live_session :platform, on_mount: [{ThamaniDawaWeb.UserAuth, :require_superadmin}] do
      live "/platform", PlatformDashboardLive, :index
      live "/platform/audit", PlatformAuditLive, :index
      live "/platform/recalls", PlatformRecallLive, :index
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

      live "/pharmacy/stock-takes", StockTakeLive.Index, :index
      live "/pharmacy/stock-takes/new", StockTakeLive.Index, :new
      live "/pharmacy/stock-takes/:id", StockTakeLive.Show, :show

      live "/pharmacy/disposals", DisposalLive.Index, :index
      live "/pharmacy/disposals/new", DisposalLive.Index, :new
      live "/pharmacy/disposals/:id", DisposalLive.Show, :show

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

      live "/lab/stock-takes", LabStockTakeLive.Index, :index
      live "/lab/stock-takes/new", LabStockTakeLive.Index, :new
      live "/lab/stock-takes/:id", LabStockTakeLive.Show, :show

      live "/lab/disposals", LabDisposalLive.Index, :index
      live "/lab/disposals/new", LabDisposalLive.Index, :new
      live "/lab/disposals/:id", LabDisposalLive.Show, :show

      live "/lab/tests", LabTestLive.Index, :index
      live "/lab/tests/new", LabTestLive.Index, :new
      live "/lab/tests/:id/edit", LabTestLive.Index, :edit
    end

    live_session :distributor,
      on_mount: [{ThamaniDawaWeb.UserAuth, :require_distributor_access}] do
      live "/distributor", DistributorDashboardLive, :index

      live "/distributor/shipments", DistributorShipmentLive.Index, :index
      live "/distributor/shipments/new", DistributorShipmentLive.Form, :new
      live "/distributor/shipments/:id/edit", DistributorShipmentLive.Form, :edit

      live "/distributor/shipments/:id/delivery-note",
           DistributorShipmentLive.Document,
           :delivery_note

      live "/distributor/shipments/:id/packing-list",
           DistributorShipmentLive.Document,
           :packing_list

      live "/distributor/shipments/:id", DistributorShipmentLive.Show, :show

      live "/distributor/products", DistributorProductLive.Index, :index
      live "/distributor/products/new", DistributorProductLive.Index, :new
      live "/distributor/products/:id", DistributorProductLive.Show, :show
      live "/distributor/batches/:id", DistributorBatchLive, :show
      live "/distributor/cases/:id", DistributorCaseLive, :show
      live "/distributor/stock", DistributorStockLive.Index, :index
      live "/distributor/expiring", DistributorStockLive.Index, :expiry
      live "/distributor/receiving", DistributorReceivingLive, :distributor_index
      live "/distributor/receiving/new", DistributorReceivingLive, :distributor_new
      live "/distributor/receiving/:id", DistributorGoodsReceiptLive, :distributor_show

      live "/distributor/returns", DistributorSupplierReturnLive.Index, :index
      live "/distributor/returns/new", DistributorSupplierReturnLive.Index, :new
      live "/distributor/returns/:id", DistributorDisposalLive.Show, :show

      live "/distributor/customers", DistributorCustomerLive.Index, :index
      live "/distributor/customers/new", DistributorCustomerLive.Index, :new
      live "/distributor/customers/:id/edit", DistributorCustomerLive.Index, :edit

      live "/distributor/customer-returns", DistributorCustomerReturnLive.Index, :index
      live "/distributor/customer-returns/new", DistributorCustomerReturnLive.Index, :new
      live "/distributor/customer-returns/:id", DistributorCustomerReturnLive.Index, :show
    end

    # Admin-only within the distributor portal — "admin manages, distributor
    # staff only do specific things" (§ role separation). A non-admin
    # distributor user is bounced back to `/distributor`, not logged out.
    live_session :distributor_admin,
      on_mount: [{ThamaniDawaWeb.UserAuth, :require_distributor_admin_access}] do
      # Serialisation billing — a plan must be chosen before the shipment
      # workflow is reachable (see ThamaniDawaWeb.DistributorAccess).
      live "/distributor/billing", DistributorBillingLive.Index, :index
      live "/distributor/billing/options", DistributorBillingLive.Options, :index
      live "/distributor/billing/payment", DistributorBillingLive.Payment, :prepay
      live "/distributor/billing/postpay-payment", DistributorBillingLive.Payment, :postpay
      live "/distributor/billing/invoices/:id", DistributorBillingLive.Invoice, :show

      live "/distributor/mobile-users", DistributorMobileUserLive.Index, :index
      live "/distributor/mobile-users/new", DistributorMobileUserLive.Index, :new
      live "/distributor/mobile-users/:id/edit", DistributorMobileUserLive.Index, :edit

      live "/distributor/api-keys", ApiKeysLive, :index
      live "/distributor/settings", OrganizationSettingsLive, :index
      live "/distributor/epcis", DistributorEpcisLive, :index
    end

    live_session :manufacturer,
      on_mount: [{ThamaniDawaWeb.UserAuth, :require_manufacturer_access}] do
      live "/manufacturer", ManufacturerDashboardLive, :index

      live "/manufacturer/products", ManufacturerProductLive.Index, :index
      live "/manufacturer/products/new", ManufacturerProductLive.Index, :new
      live "/manufacturer/products/:gtin/serials", ManufacturerProductLive.Serials, :index

      live "/manufacturer/products/:gtin/serials/new",
           ManufacturerProductLive.Index,
           :new_serial

      live "/manufacturer/products/:gtin/ssccs", ManufacturerProductLive.Ssccs, :index
      live "/manufacturer/products/:id", ManufacturerProductLive.Show, :show

      live "/manufacturer/inventory", ManufacturerInventoryLive, :index
      live "/manufacturer/shipments", ManufacturerShipmentLive.List, :index
      live "/manufacturer/shipments/new", ManufacturerShipmentLive.Form, :new
      live "/manufacturer/shipments/:id", ManufacturerShipmentLive.Review, :show

      live "/manufacturer/aggregations", ManufacturerAggregationLive.Dashboard, :index
      live "/manufacturer/aggregations/new", ManufacturerAggregationLive.Wizard, :new

      live "/manufacturer/aggregations/pallets/:pallet_id/ssccs/new",
           ManufacturerAggregationLive.Wizard,
           :new_on_pallet

      live "/manufacturer/aggregations/pallets/:id",
           ManufacturerAggregationLive.PalletShow,
           :show

      live "/manufacturer/aggregations/ssccs/:id",
           ManufacturerAggregationLive.SsccShow,
           :show

      live "/manufacturer/aggregations/:id", ManufacturerAggregationLive.Review, :show

      live "/manufacturer/sscc/:id/serials", ManufacturerSsccLive.Serials, :show
      live "/manufacturer/sscc/:id/label", ManufacturerSsccLive.Label, :show
      live "/manufacturer/epcis", ManufacturerEpcisLive, :index
    end

    live_session :manufacturer_admin,
      on_mount: [{ThamaniDawaWeb.UserAuth, :require_manufacturer_admin_access}] do
      live "/manufacturer/api-keys", ApiKeysLive, :index
      live "/manufacturer/settings", OrganizationSettingsLive, :index
    end
  end

  scope "/", ThamaniDawaWeb do
    pipe_through [:browser, :require_distributor_user]

    get "/distributor/shipments/:id/export", DistributorShipmentExportController, :show
  end

  scope "/", ThamaniDawaWeb do
    pipe_through [:browser, :require_manufacturer_user]

    get "/manufacturer/sscc/:id/export", ManufacturerSsccExportController, :show

    get "/manufacturer/products/:gtin/batches/:batch_id/serials/export",
        ManufacturerSerialExportController,
        :show
  end

  scope "/", ThamaniDawaWeb do
    pipe_through :browser

    get "/org/products/import/template", ProductImportTemplateController, :show
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
