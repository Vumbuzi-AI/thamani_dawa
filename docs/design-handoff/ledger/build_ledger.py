import json,re,collections
c=json.load(open('canvas.json')); flows=json.load(open('flows.json'))
status=json.load(open('status.json'))
pages={p['id']:p['name'] for p in c['pages']}
fr={f['id']:f for f in c['frames']}
SHELL={'Command menu','Search','Search · results','Notifications','Product tour · step 1'}
def shellish(n):
    return any(n.endswith(s) for s in SHELL) or 'Account menu' in n or 'Site switcher' in n
R=[ # (regex on name, route, liveview)
(r'^ARCHIVED|SUPERSEDED|old, replaced','—','archived, not built'),
(r'Account menu open','(shell) account menu','Layouts · td_account_chip (SHELL-ACCOUNT, released 23 Nov)'),
(r'^Account menu','(shell) account menu','Layouts · td_account_chip (SHELL-ACCOUNT)'),
(r'Sidebar collapsed','(shell) collapsed sidebar','Layouts · td_app_shell .td-br collapsed (SHELL-COLLAPSED)'),
(r'Site switcher open','(shell) site switcher','Layouts · site switcher'),
(r'Log out confirm','(shell) log out','Layouts · account menu'),
(r'Product tour','(shell) product tour','Layouts · tour hook'),
(r'^Notifications$','(shell) notifications','Layouts · td-notifications (empty feed)'),
(r'Command menu$','(shell) ⌘K command menu','Layouts · Cmd-K (manufacturer palette MvYOMauO8O; others focus global search)'),
(r'· Search · results$|· Search$','(shell) global search','Layouts · td-global-search'),
(r'^Filter menu · (.*)','(component) filter menu','td_components filter chip popover (per list page)'),
(r'^Export CSV|^Download ready','(component) export CSV','per list page export (verify)'),
(r'^Print$','(component) print dialog','—'),
(r'^Period menu|^Calendar view menu','(component) date range picker','td date_range_picker (DATE-1)'),
(r'^Remove item|^Item details|^Get the mobile app','(component) shared dialog','—'),
(r'^Add a test$','/lab/orders/:id/tests/new','LabOrderLive.Show :add_test'),
(r'^Add a result field','/lab/tests/new (result fields)','LabTestLive.Index'),
(r'^Error · 403','403','ErrorHTML'),(r'^Error · 404','404','ErrorHTML'),(r'^Error · 500','500','ErrorHTML'),
(r'^Auth · Log in','/login','SessionController :new'),
(r'^Auth · Reset|Auth · Choose a new password','/reset-password[/:token]','PasswordResetController'),
(r'^Auth · Choose a site','/login → site picker','SessionController (verify)'),
(r'^Auth · Confirm|Auth · Confirmation resent','/confirm-email','ConfirmEmailLive'),
(r'^Auth · (Accept|Invalid) invite','/invites/:token','AcceptInviteLive'),
(r'^Sign up','/signup','SignupLive (SIGNUP-1, GS1 key only)'),
(r'^Onboarding','/onboarding','OnboardingLive'),
# pharmacy
(r'Pharmacy · Dashboard','/pharmacy','PharmacyDashboardLive'),
(r'Pharmacy · Quick sale','/pharmacy/quick-sale','QuickSaleLive'),
(r'Pharmacy · New prescription','/pharmacy/prescriptions/new','PrescriptionLive.Index :new'),
(r'Pharmacy · Prescription receipt','/pharmacy/prescriptions/:id/receipt','PrescriptionLive.Show :receipt'),
(r'Pharmacy · Record payment','/pharmacy/prescriptions/:id/payments/new','PrescriptionLive.Show :new_payment'),
(r'Pharmacy · (Prescription detail|Dispense item)','/pharmacy/prescriptions/:id','PrescriptionLive.Show'),
(r'Pharmacy · Prescriptions','/pharmacy/prescriptions','PrescriptionLive.Index'),
(r'(Pharmacy|Pharma-lab) · Patient detail','/pharmacy/patients/:id','PatientLive.Show'),
(r'(Pharmacy|Pharma-lab) · Patients','/pharmacy/patients','PatientLive.Index'),
(r'(Pharmacy|Pharma-lab) · Stock product detail','/pharmacy/stock/products/:id','PharmacyStockProductLive'),
(r'(Pharmacy|Pharma-lab) · Stock batch detail','/pharmacy/stock/batches/:id','PharmacyStockBatchLive'),
(r'(Pharmacy|Pharma-lab) · (Stock ·|Stock row actions|Print Data Matrix)','/pharmacy/stock','PharmacyStockLive'),
(r'(Pharmacy|Pharma-lab) · Receive','/pharmacy/receive-stock[/:id/receive]','ReceiveStockLive'),
(r'(Pharmacy|Pharma-lab) · New requisition','/pharmacy/requisitions/new','RequisitionLive.Index :new'),
(r'(Pharmacy|Pharma-lab) · Requisition detail','/pharmacy/requisitions/:id','RequisitionLive.Show'),
(r'(Pharmacy|Pharma-lab) · Requ','/pharmacy/requisitions','RequisitionLive.Index'),
(r'(Pharmacy|Pharma-lab) · Scan lookup','/pharmacy/scan','PharmacyScanLive'),
(r'(Pharmacy|Pharma-lab) · (Transaction detail|Transaction actions|Refund payment|Payment receipt|Transactions)','/pharmacy/transactions','EarningsLive :pharmacy'),
(r'Pharmacy · (Start |Submit )?[Ss]tock take','/pharmacy/stock-takes[/new|/:id]','StockTakeLive'),
(r'Pharmacy · (Start |Submit )?([Dd]isposal|[Ss]upplier return)','/pharmacy/disposals[/new|/:id]','DisposalLive'),
(r'Pharma-lab · Site dashboard','/pharmacy (combined site)','PharmacyDashboardLive'),
# lab
(r'Lab · Dashboard','/lab','LabDashboardLive'),
(r'Lab · New lab order','/lab/orders/new','LabOrderLive.Index :new'),
(r'Lab · (Lab orders|Orders ·)','/lab/orders','LabOrderLive.Index'),
(r'Lab · Add test','/lab/orders/:id/tests/new','LabOrderLive.Show :add_test'),
(r'Lab · Collect specimen','/lab/orders/:id/collect','LabOrderLive.Show :collect_specimen'),
(r'Lab · Print(ed)? specimen label','/lab/orders/:id/specimens/:sid/label','LabOrderLive.Show · SpecimenLabelComponent'),
(r'Lab · (Enter test results|Amend result)','/lab/orders/:id/results/:rid/edit','LabOrderLive.Show :edit_result'),
(r'Lab · Record consumable','/lab/orders/:id/consumables/new','LabOrderLive.Show :record_consumable'),
(r'Lab · Print(ed)? (results|lab report)','/lab/orders/:id/report','LabOrderLive.Show · LabReportComponent'),
(r'Lab · Record payment','/lab/orders/:id/payments/new','LabOrderLive.Show :new_payment'),
(r'Lab · Order detail','/lab/orders/:id','LabOrderLive.Show'),
(r'Lab · Patient detail','/lab/patients/:id','LabPatientLive.Show'),
(r'Lab · Patients','/lab/patients','LabPatientLive.Index'),
(r'Lab · (New|Edit) test','/lab/tests/new | /lab/tests/:id/edit','LabTestLive.Index'),
(r'Lab · Test','/lab/tests','LabTestLive.Index'),
(r'Lab · Stock product detail','/lab/stock/products/:id','LabStockProductLive'),
(r'Lab · Stock batch detail','/lab/stock/batches/:id','LabStockBatchLive'),
(r'Lab · (Lab stock|Stock row actions|Print Data Matrix)','/lab/stock','LabStockLive'),
(r'Lab · Receive','/lab/receive-stock[/:id/receive]','LabReceiveStockLive'),
(r'Lab · New requisition','/lab/requisitions/new','LabRequisitionLive.Index :new'),
(r'Lab · Requisition detail','/lab/requisitions/:id','LabRequisitionLive.Show'),
(r'Lab · Requ','/lab/requisitions','LabRequisitionLive.Index'),
(r'Lab · Scan consumable','/lab/scan','LabScanLive'),
(r'Lab · (Transaction detail)','/lab/transactions/:id','EarningsLive :lab_show'),
(r'Lab · Payment receipt','/lab/transactions/:id/receipt','EarningsLive :lab_receipt'),
(r'Lab · (Transaction actions|Refund payment|Transactions)','/lab/transactions','EarningsLive :lab'),
(r'Lab · (Start |Submit )?[Ss]tock take','/lab/stock-takes[/new|/:id]','LabStockTakeLive'),
(r'Lab · (Start |Submit )?([Dd]isposal|[Ss]upplier return)','/lab/disposals[/new|/:id]','LabDisposalLive'),
# distributor
(r'Distributor · Dashboard','/distributor','DistributorDashboardLive'),
(r'Distributor · Choose a serialisation plan','/distributor/billing/options','DistributorBillingLive.Options'),
(r'Distributor · New shipment','/distributor/shipments/new','DistributorShipmentLive.Form'),
(r'Distributor · Print SSCC labels','/distributor/shipments/:id (labels)','DistributorShipmentLive.Show'),
(r'Distributor · Delivery note','/distributor/shipments/:id/delivery-note','DistributorShipmentLive delivery note'),
(r'Distributor · (Shipment ·|Approve shipment|Reject shipment)','/distributor/shipments/:id[/edit]','DistributorShipmentLive.Show/Form'),
(r'Distributor · Shipments','/distributor/shipments','DistributorShipmentLive.Index'),
(r'Distributor · Goods receipt','/distributor/receiving/:id','DistributorGoodsReceiptLive'),
(r'Distributor · (Receive inventory|Add item)','/distributor/receiving/new','DistributorReceivingLive :distributor_new'),
(r'Distributor · Receiving','/distributor/receiving','DistributorReceivingLive'),
(r'Distributor · (Stock|Move stock|Change status)','/distributor/stock','DistributorStockLive.Index'),
(r'Distributor · Product detail','/distributor/products/:id','DistributorProductLive.Show'),
(r'Distributor · Batch detail','/distributor/batches/:id','DistributorBatchLive'),
(r'Distributor · (Products|Add product)','/distributor/products[/new]','DistributorProductLive.Index'),
(r'Distributor · Invoice','/distributor/billing/invoices/:id','DistributorBillingLive.Invoice'),
(r'Distributor · (Buy serials|Settle usage)','/distributor/billing/payment | /postpay-payment','DistributorBillingLive.Payment'),
(r'Distributor · Billing','/distributor/billing','DistributorBillingLive.Index'),
(r'Distributor · .*[Mm]obile user','/distributor/mobile-users[/new|/:id/edit]','DistributorMobileUserLive.Index'),
(r'Distributor · TNT','/distributor/epcis','DistributorEpcisLive'),
(r'Distributor · Org settings','/distributor/settings','OrganizationSettingsLive'),
(r'Distributor · (Sites|Add site|Site row)','/org/sites[/new]','SiteLive.Index'),
(r'Distributor · .*[Cc]ustomer return','/distributor/customer-returns[/new|/:id]','DistributorCustomerReturnLive.Index'),
(r'Distributor · .*[Cc]ustomer','/distributor/customers[/new|/:id/edit]','DistributorCustomerLive.Index'),
(r'Distributor · .*[Ss]upplier return|Distributor · Returns','/distributor/returns[/new|/:id]','DistributorSupplierReturnLive / DistributorDisposalLive.Show'),
(r'Distributor · Break case','/distributor/cases/:id','DistributorCaseLive'),
# manufacturer
(r'Manufacturer · Dashboard','/manufacturer','ManufacturerDashboardLive'),
(r'Manufacturer · Product SSCCs','/manufacturer/products/:gtin/ssccs','ManufacturerProductLive.Ssccs'),
(r'Manufacturer · SSCC serials','/manufacturer/sscc/:id/serials','ManufacturerSsccLive.Serials'),
(r'Manufacturer · Case label','/manufacturer/sscc/:id/label','ManufacturerSsccLive.Label'),
(r'Manufacturer · (Generate serials|Serials issued)','/manufacturer/products/:gtin/serials/new','ManufacturerProductLive serials wizard'),
(r'Manufacturer · Product detail','/manufacturer/products/:id','ManufacturerProductLive.Show'),
(r'Manufacturer · (Products|Add product)','/manufacturer/products[/new]','ManufacturerProductLive.Index'),
(r'Manufacturer · Inventory','/manufacturer/inventory','ManufacturerInventoryLive'),
(r'Manufacturer · New shipment','/manufacturer/shipments/new','ManufacturerShipmentLive.Form'),
(r'Manufacturer · Packing list','/manufacturer/shipments/:id/packing-list','ManufacturerShipmentLive.Review'),
(r'Manufacturer · Shipment review','/manufacturer/shipments/:id','ManufacturerShipmentLive.Review'),
(r'Manufacturer · Shipments','/manufacturer/shipments','ManufacturerShipmentLive.List'),
(r'Manufacturer · New aggregation','/manufacturer/aggregations/new','ManufacturerAggregationLive.Wizard (AGG-1, released 23 Nov)'),
(r'Manufacturer · (Aggregation review|Reject aggregation)','/manufacturer/aggregations/:id','ManufacturerAggregationLive.Review (AGG-1, released 23 Nov)'),
(r'Manufacturer · Aggregation','/manufacturer/aggregations','ManufacturerAggregationLive.Dashboard (AGG-1, released 23 Nov)'),
(r'Manufacturer · .*[Mm]obile user','/manufacturer/mobile-users[/new|/:id/edit]','ManufacturerMobileUserLive.Index'),
(r'Manufacturer · (TNT|.*TNT)|^TNT ·','/manufacturer/epcis (+ /org/epcis, /distributor/epcis)','ManufacturerEpcisLive / DistributorEpcisLive'),
(r'Manufacturer · API keys','/manufacturer/api-keys','ApiKeysLive (APIKEYS-1, released)'),
(r'Manufacturer · Org settings','/manufacturer/settings','OrganizationSettingsLive'),
# org / platform
(r'Org · Admin dashboard|Org · Filters and date range','/org/dashboard','OrgDashboardLive'),
(r'Org · Site dashboard','/org/sites/:id','SiteLive.Show'),
(r'Org · (Sites|Add site|Site row)','/org/sites[/new|/:id/edit]','SiteLive.Index'),
(r'Org · Product detail|Org · Add to stock|Org · Dispatch batch','/org/products/:id[/batches/new|/dispatch]','ProductLive.Show'),
(r'Org · Batch detail','/org/batches/:id','BatchLive.Show'),
(r'Org · Print Data Matrix','/org/batches/:id (print)','BatchLive.Show'),
(r'Org · Import products','/org/products/import','ProductLive.Import'),
(r'Org · (Products|Add product|Product row)','/org/products[/new|/:id/edit]','ProductLive.Index'),
(r'Org · (Suppliers|Add supplier|Supplier row)','/org/suppliers[/new|/:id/edit]','SupplierLive.Index'),
(r'Org · (Team|Invite staff|Edit team member|Deactivate confirm)','/org/team[/new|/:id/edit]','TeamLive.Index'),
(r'Org · Requisition detail','/org/requisitions/:id','RequisitionQueueLive.Show'),
(r'Org · (Requisition|Review requisition|Reject requisition|Fulfill requisition|Requested between)','/org/requisitions[/:id/review|reject|fulfill]','RequisitionQueueLive.Index'),
(r'Org · (Receiving|Receive inventory|Goods receipt|Add item)','/org/receiving[/new|/:id]','DistributorReceivingLive / DistributorGoodsReceiptLive (:org_*)'),
(r'Org · Stock takes','/org/stock-takes','StockTakeQueueLive.Index'),
(r'Org · Disposals','/org/disposals','InventoryDisposalQueueLive.Index'),
(r'Org · (Transaction|Refund payment|Payment receipt)','/org/earnings','EarningsLive :index'),
(r'Org · TNT','/org/epcis','DistributorEpcisLive (org portal)'),
(r'Org · Organization settings','/org/settings','OrganizationSettingsLive'),
(r'Platform · Dashboard','/platform','PlatformDashboardLive'),
(r'Platform · Audit','/platform/audit','PlatformAuditLive'),
(r'Platform · Recalls','/platform/recalls','PlatformRecallLive'),
(r'Platform · Organization','/platform/organizations[/:id]','PlatformOrganizationsLive'),
]
def route(n):
    for rx,r,lv in R:
        if re.search(rx,n): return r,lv
    return 'MISSING','MISSING — unmapped'
rows=[]; counts=collections.Counter()
order=['Web · Shared','Web · Pharmacy flows','Web · Lab flows','Web · Distributor flows','Web · Manufacturer flows','Web · Organization and platform flows']
web=[f for f in c['frames'] if pages[f['pageId']] in order]
web.sort(key=lambda f:(order.index(pages[f['pageId']]),f['y'],f['x']))
L=['# Frame ledger — Doop canvas LQFIZlhE35','',
'Generated from get_canvas + get_prototype. Status: todo / in progress / done / hold / archived. "done" means rebuilt against the frame on branch `sean/td-web-design-system` (uncommitted).',
'Flows list each frame\'s own buttons: `overlay → X` opens X as a modal/menu, `navigate → X` routes to X, `close` closes the overlay. Sidebar nav and shell overlays (search, ⌘K, notifications, tour, account menu) are left out of each row and listed once under Shell.','',
'COUNTS_PLACEHOLDER','',
'## Working order','',
'1. `_VFeE7v1Z3` Lab stock and its flow (all batches, product detail, batch detail, row actions, Print Data Matrix, Export CSV, filter menus) — done 23 Nov.',
'2. The same stock flow on Pharmacy (`puMtQXqNOq`…`87EK_g6B4h`) and Pharma-lab (`c3EiqRelu0`…`NoAAUBFYIM`), reusing `ThamaniDawaWeb.SiteStock` — done 23 Nov (row actions menu now pinned to the viewport and flips upward on the last rows).',
'2b. Released by Bau 23 Nov, next: SHELL-ACCOUNT (`y4OlKMJCvP` + per-portal copies), SHELL-COLLAPSED (`LToUOeDNer`), SIGNUP-1 (`CLsksg2sae`…), AGG-1 (`nooman_e0w`, review, wizard, reject), TEAM-1 (`yPDN9VJLDO`).',
'3. TNT reporting (manufacturer, org, distributor, event details, confirms) — frames read and mapped, build next.',
'4. Pharmacy dashboard `q2Wvk4Umn8` on `<.td_dashboard>` — done 23 Nov (Chart.js tables dropped; empty-account state covered).',
'5. Lab orders §5 and payment §6 — done 23 Nov (`3GldJbxDi_`, `7ibhYgNGj7`, new-order steps, order detail, `15D90zhEQF`, `Pef-1fqHs4`). New order stays a 3-step wizard (Patient / Tests / Details and payment); existing vs new patient are variants of step 1, not a fourth step.',
'6. DATE-1 — lab orders custom range modal uses the TD DatePicker (`y11_7Bfo8B`, Period menu `5I9pJoGa6G`). Calendar view menu `UwAiusb5oG` and the remaining pharmacy/org/pharma-lab range frames are still open. No native date inputs.',
'7. NAV-1 / NAV-2 sidebars, EMPTY-1 disposal and return empty states with `return_to`, org receiving (`2CQZtx0m1X`), platform organizations (`OPeL_8IxLl`, `5o7nNuRzYl`), notifications (`TzQlEuhO6H`, empty feed), and the manufacturer command menu `MvYOMauO8O` (not in the frozen canvas export; built from the live Doop frame).',
'8. Then the rest of each Web page top to bottom: Lab, Pharmacy, Pharma-lab, Distributor, Manufacturer, Org and platform, Shared (auth, onboarding, shell).',
'',
'Holds: none on frames (APIKEYS-1 released 23 Nov 17:11). Dark card border token on hold until Bau sends a value. Flagship manufacturer flows and Bau\'s held gap frames are not started. Flagship distributor is in progress (see frame-ledger.md section 12).',
'',
'## Shell overlays (every portal)','',
'Search (`… · Search`, `… · Search · results`), ⌘K command menu (manufacturer: `MvYOMauO8O` palette; other portals still focus global search), Notifications `TzQlEuhO6H` (empty feed; no backend yet), Product tour `pRWh641rg7` → `sHEmCo_9oR` → `F-mzfB-j8y`, account menu (SHELL-ACCOUNT), site switcher (`l3PRkMH9kA`, `IJAc4XSYTP`, `QwOww6J_-C`, `CUy1Ue75h-`, `xKjyrzVPWd`), Log out confirm `cwUKNlhijG`. Each page row below leaves these out of its flow column.','']
cur=None
for f in web:
    pg=pages[f['pageId']]
    if pg!=cur:
        cur=pg; L+=['',f'## {pg}','','| # | Frame id | Frame name | Route | LiveView / component | Status | Flow (buttons → target) |','|---|---|---|---|---|---|---|']; n=0
    n+=1
    r,lv=route(f['name'])
    st=status.get(f['id'])
    if not st:
        st='archived' if lv.startswith('archived') else ('hold' if 'HOLD' in lv else 'todo')
    counts[st]+=1
    fl=[]
    for a,t in flows.get(f['id'],[]):
        if shellish(t) or t=='close-overlay':
            if t=='close-overlay': fl.append('close')
            continue
        fl.append(f'{a} → {t}')
    fl=sorted(set(fl))
    L.append(f"| {n} | `{f['id']}` | {f['name']} | {r} | {lv} | {st} | {'; '.join(fl) or '—'} |")
# other pages summary
L+=['','## Not web app screens (listed by page, not mapped to routes)','']
oth=collections.Counter(pages[f['pageId']] for f in c['frames'] if pages[f['pageId']] not in order)
for k,v in oth.items(): L.append(f'- {k}: {v} frames (mobile, design system, marketing, explore or archive — out of scope for the web build)')
cs=', '.join(f'{k}: {v}' for k,v in sorted(counts.items()))
txt='\n'.join(L).replace('COUNTS_PLACEHOLDER',f'**Web frames: {sum(counts.values())}** — {cs}')
open('/workspace/thamani/lab-compliance/frame-ledger.md','w').write(txt)
print(cs)
miss=[l for l in L if '| MISSING' in l]
print(len(miss)); print('\n'.join(m[:160] for m in miss))
