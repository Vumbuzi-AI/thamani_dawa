# Pharmacy Interface Design Document

## 1. Purpose

This document captures the visual language, layout, navigation, components, and interaction patterns used by the current GHC Excellence pharmacy interface. It is intended to be the design reference for another system that should feel closely related without copying pharmacy-specific content blindly.

The design should communicate:

- calm, dependable, clinical software;
- high information density without visual clutter;
- fast scanning of stock, dispensing, compliance, and patient work;
- clear separation between navigation, filtering, analysis, and action;
- predictable behaviour on desktop, tablet, and mobile.

This is a source-based specification of the current application. Where the current pharmacy pages use both newer dashboard styling and older compact list-page styling, this document identifies both and recommends how to unify them in the next system.

---

## 2. Design character

The interface is a light, indigo-led operational dashboard. It uses a white sidebar, a very light slate page canvas, rounded white content surfaces, subtle cool-gray borders, low-contrast shadows, and outlined icons. Colour is mainly reserved for active navigation, primary actions, metrics, and status.

Key qualities:

- **Light and spacious:** large neutral areas and consistent gaps make dense data easier to scan.
- **Soft, not decorative:** corners and shadows soften the interface, but content remains utilitarian.
- **Indigo as the anchor:** the same indigo family connects brand, active navigation, buttons, links, headings, values, and focus rings.
- **Semantic colour only when useful:** green means healthy/completed, amber means attention/pending, red or rose means danger/out of stock, and gray means neutral or unavailable.
- **Role-oriented:** the sidebar names the user's workspace and groups tasks around real operational workflows.

---

## 3. Overall application shell

### 3.1 Desktop layout

The application is a two-column shell:

```text
+----------------------------+----------------------------------------------+
|                            |                                              |
|  Fixed role sidebar        |  Scrollable page content                     |
|  18rem / 288px             |  Flexible width                              |
|                            |  max content width: 1600px                    |
|  Brand                     |  page padding: 16px mobile / 32px desktop     |
|  Account                   |                                              |
|  Navigation                |  Pharmacy screen                             |
|                            |                                              |
|  Utilities                 |                                              |
|                            |                                              |
+----------------------------+----------------------------------------------+
```

- The sidebar is fixed to the left, full viewport height, and `18rem` (`288px`) wide.
- The content area has a matching left margin and fills the remaining width.
- Main content is constrained to `1600px` and centred.
- The shell background is a light slate/gray (`slate-50` / `gray-50`).
- Page content uses `16px` horizontal padding on small screens and `32px` from medium screens upward.
- Wide tables may scroll horizontally; the main content flex child must use `min-width: 0`.

### 3.2 Collapsed desktop layout

At viewport widths of `1024px` and above, the sidebar can collapse from `288px` to `72px`.

- Only navigation icons and the brand mark remain visible.
- Labels, account card, and brand copy are hidden.
- Icons are centred in the rail.
- Hover or keyboard focus reveals a dark-indigo tooltip to the right.
- The chevron rotates `180deg` to show that the rail can expand.
- Content margin animates from `288px` to `72px` with the sidebar.
- The user's preference is persisted locally and applied before first paint to avoid layout flash.
- Width and margin transitions use `250ms ease-in-out`.

### 3.3 Mobile and tablet layout

Below `1024px`, the sidebar becomes an off-canvas drawer.

- It starts translated outside the left edge.
- A mobile menu control opens it.
- A page backdrop becomes visible behind the drawer.
- Selecting the backdrop or pressing `Escape` closes it.
- Body scrolling is locked while the drawer is open.
- The content area has no permanent left margin.

The sidebar must remain keyboard accessible. Interactive controls require visible focus rings, meaningful `aria-label` values, and `aria-current="page"` on the active destination.

---

## 4. Sidebar specification

### 4.1 Sidebar container

| Property         | Current value                                                     |
| ---------------- | ----------------------------------------------------------------- |
| Position         | Fixed, top-left                                                   |
| Layer            | `z-index: 40`                                                     |
| Width            | `288px` expanded; `72px` collapsed                                |
| Height           | `100vh`                                                           |
| Background       | `#FFFFFF`                                                         |
| Right border     | `#EDF0F8`                                                         |
| Internal padding | `20px` horizontal, `24px` vertical                                |
| Layout           | Vertical flex column                                              |
| Overflow         | Vertical scrolling, horizontal clipping while expanded/collapsing |

The sidebar has three zones: brand/account, primary navigation, and utilities.

### 4.2 Brand row

The brand row contains:

- a `44px × 44px` rounded-square mark;
- `GHC` in `13px` bold indigo text;
- the product name `GHC Excellence` in `17px` bold indigo;
- the workspace label `Pharmacist's Panel` in `13px` medium gray;
- a `36px × 36px` bordered collapse button with a left chevron.

Brand mark styling:

- background: `#F0F0FF`;
- border: `#CFD1FF`;
- text: `#373896`;
- radius: `12px`.

Collapse control:

- white background;
- border `#E2E6F0`;
- indigo icon;
- `12px` radius;
- pale-indigo hover;
- `2px` indigo focus ring with offset.

### 4.3 Account card

The account card sits below the brand row.

- Surface: `#FBFBFF`.
- Border: `#E8EBF3`.
- Radius: `16px`.
- Padding: `16px` horizontal and `14px` vertical.
- Avatar: `44px` circle, indigo fill, white `15px` bold initials; use a cover-cropped image when available.
- Name: `15px` bold, `#1F2433`, truncated if necessary.
- Supporting text: `13px` medium, `#687083`, currently “Signed-in account”.

The entire account card is hidden in collapsed mode.

### 4.4 Primary navigation

The pharmacy sidebar starts with **Dashboard** as a standalone link. The remaining links are grouped into collapsible workflow sections.

Current information architecture:

```text
Dashboard

Drug Management (4)
├── Scan Patient
├── Drugs
├── Drug Allocations
└── Pending Drugs

Analytics & Compliance (3)
├── Consumption Analysis
├── Temp & Humidity Logs
└── Dangerous Drug Register

Admin (4)
├── Duty Rota
├── Requisitions
├── Todos
└── Shift Handover
```

Each group row shows an outlined icon, group label, number of child pages, and a chevron. The active group is expanded by default and its chevron is rotated. Inactive groups start closed.

Navigation item specification:

| Property       | Value                                                                 |
| -------------- | --------------------------------------------------------------------- |
| Minimum height | `48px`                                                                |
| Padding        | `16px` horizontal, `12px` vertical                                    |
| Gap            | `12px`                                                                |
| Radius         | `12px`                                                                |
| Label          | `15px`, semibold                                                      |
| Icon           | `20px`, outline, approximately `2px` stroke                           |
| Default        | text/icon `#687083`                                                   |
| Hover          | background `#F0F0FF`, text/icon `#373896`                             |
| Active         | background `#E7E7FF`, text/icon `#373896`, border-like ring `#D2D3FF` |
| Focus          | `2px` ring `#6667AB` with offset                                      |

Nested items are indented with a `#EDF0F8` vertical guide line. Group transitions use a short `150ms` opacity/max-height animation.

Optional count badges use:

- dark indigo `#373896` background;
- white `11px` bold text;
- full-pill shape;
- `8px` horizontal and `2px` vertical padding.

### 4.5 Utility navigation

The bottom zone is separated by a `#E8EBF3` top border and contains:

- Settings;
- SOPs;
- Help & Support;
- Telephone Directory;
- Sign Out.

Utility links use the same size and rhythm as primary links. Sign Out is the exception: it uses danger red `#C21F17` and a pale-red hover state.

### 4.6 Collapsed tooltips

Collapsed navigation labels appear as tooltips on hover and focus:

- positioned just beyond the sidebar's right edge;
- background `#373896`;
- white `12px` semibold text;
- `12px` radius;
- padding `8px 12px`;
- shadow `0 12px 24px rgba(55, 56, 150, 0.18)`;
- fade/slide transition of roughly `180ms`.

---

## 5. Pharmacy dashboard

The pharmacy dashboard is the clearest expression of the newer visual system and should be the main reference for the new system.

### 5.1 Page frame

- Light gray page background.
- Inner content width is `95%`, centred.
- Vertical rhythm between major blocks is `24px`.
- On small screens, page padding is `16px`; from small breakpoints upward it becomes `24px` within the dashboard frame.

Screen order:

```text
Dashboard header / control card
Summary metric grid
Analytics section
Recent activity card
```

### 5.2 Dashboard header card

The first card combines identity and controls rather than using a separate top bar.

- White surface.
- Radius: `32px`.
- Border: `#E6EDF8`.
- Shadow: `0 20px 42px rgba(15, 23, 42, 0.06)`.
- Padding: `20px` mobile, `28px` from small screens upward.

Content:

- Title: “Pharmacy Dashboard”, `24px` mobile / `30px` desktop, bold, near-black.
- Subtitle: `14px` gray, with the selected reporting date range.
- Search: expands to fill available width, minimum `220px`.
- Filters: `40px` high primary indigo button on the dashboard.
- Date shortcuts: This Month, Last Month, Last 30 Days, This Year, All Time.

On mobile, title/actions stack vertically. Controls wrap rather than overflow.

### 5.3 Search and filters

Canonical search input:

- height `40px`;
- full width;
- `6px` radius;
- gray border;
- `12px` horizontal padding;
- `14px` text;
- indigo focus border;
- `300ms` debounce for live search.

The filter control opens a dropdown-style panel anchored below the trigger, not a full-page navigation change.

Filter panel:

- maximum width `672px`;
- maximum height constrained to the viewport;
- white surface, `12px` radius, subtle border, large shadow;
- groups use uppercase `12px` semibold gray labels;
- fields are a one-column grid on mobile and two columns from small screens upward;
- footer provides Clear filters and Apply filters;
- `Escape` and click-away close the panel.

When filters are active, show the count in an indigo circular badge and render removable pale-indigo chips below the toolbar. Always offer “Clear all”.

### 5.4 Summary metrics

The current pharmacy dashboard can show up to eight metrics:

- Drugs in Catalog;
- Stock on Hand;
- Current Stock Value;
- Drug Allocations;
- Units Dispensed;
- Dispensed Value;
- Pending Drug Allocations;
- Low Stock Items.

Grid behaviour:

- one column by default;
- two columns from the small breakpoint;
- four columns on extra-large screens;
- `20px` gap.

Metric card:

- minimum height `128px`;
- white surface;
- radius `26px`;
- border `#E7EDF8`;
- shadow `0 12px 28px rgba(15, 23, 42, 0.045)`;
- padding `20px` mobile / `24px` desktop;
- circular outlined icon badge;
- uppercase `12px` gray label;
- `24px` bold indigo value;
- `14px` gray helper text.

Metric icon accent colours rotate across indigo, blue, emerald, amber, violet, teal, cyan, and rose. The colour identifies categories without changing the card surface or the main value colour.

### 5.5 Analytics

The analytics container is a large white section:

- radius `30px`;
- border `#E6EDF8`;
- shadow `0 18px 38px rgba(15, 23, 42, 0.055)`;
- padding `20–24px`.

It contains six pharmacy charts:

1. Daily Units Dispensed.
2. Top Drugs by Usage.
3. Dispensed Value by Drug.
4. Current Stock Value by Drug.
5. Allocation Status.
6. Low Stock Pressure.

Charts use a single column by default and a two-column layout at extra-large widths, with `24px` gaps. Each chart panel is a nested white card with a `26px` radius, soft border and shadow, `20–24px` padding, and a `320px` chart area.

Chart headings are `18px` semibold near-black; subtitles are `14px` gray with relaxed line height. Charts should preserve semantic colour use and avoid large rainbow palettes.

### 5.6 Recent activity

The recent allocations card uses the same rounded dashboard surface language.

- Radius `28px`.
- `24px` padding.
- `20px` semibold heading.
- Each row is a `22px` rounded, lightly bordered container with `16px` padding.
- Row hover changes to a very pale blue-gray.
- Primary text is `14px` semibold; supporting text is `14px` muted gray.
- A compact status badge sits at the end when available.
- Empty state is centred, concise, and vertically padded.

---

## 6. Pharmacy operational pages

Operational list and detail screens are more compact than the dashboard. They retain the same sidebar and palette, but use smaller radii and denser tables.

Representative pages include Drugs, Drug Allocations, Pending Drugs, Consumption Analysis, Temperature & Humidity Logs, Dangerous Drug Register, and patient-specific dispensing.

### 6.1 Standard list page structure

```text
+------------------------------------------------------------------+
| Icon  Page title                                      Actions     |
|       One-line description                                        |
|------------------------------------------------------------------|
| Search.............................................. | Filters |  |
| [active filter chips]                                            |
|                                                                  |
| Responsive data table                                            |
|                                                                  |
| Showing x-y of z                 Previous  Page n of n  Next      |
+------------------------------------------------------------------+
```

Current list container:

- white surface;
- `8px` radius;
- subtle gray border and shadow;
- `16px` padding.

The page header uses:

- `40px` pale-indigo rounded-square icon badge;
- `20px` indigo outlined icon;
- `18px` semibold near-black title;
- optional `14px` gray subtitle;
- bottom border and `16px` vertical separation;
- optional page actions aligned right.

For the new system, preserve the compact density but increase the outer list container radius to `20–24px` so it belongs more clearly to the dashboard family.

### 6.2 Data tables

Table shell:

- `12px` radius;
- slate `#E2E8F0` border;
- fixed table layout;
- pale-slate header;
- headers use `14px` semibold slate text;
- cells use `14px` text and `24px` horizontal / `12px` vertical padding;
- rows have subtle dividers and pale-slate hover.

Responsive behaviour:

- The most important first four columns remain visible by default.
- Less important columns move into an expandable row-details panel.
- A chevron button opens the details row.
- Details use a one-, two-, or three-column definition list depending on width.
- Tables may use horizontal scrolling where necessary, but hiding secondary fields behind row details is preferred.

Pharmacy table content should prioritise:

1. entity identity, such as patient or drug;
2. current operational state;
3. quantity/value;
4. date or batch identity;
5. responsible staff;
6. actions.

### 6.3 Status badges

Use small, high-contrast pills and never rely on colour alone. Include a text label and, where useful, a status dot.

| Meaning                                 | Treatment                                        |
| --------------------------------------- | ------------------------------------------------ |
| Healthy / given / in stock              | pale green background, dark green text           |
| Pending / low stock / needs attention   | pale amber or orange background, dark amber text |
| Error / out of stock / critical         | pale red background, dark red text               |
| Informational / linked record           | pale indigo background, indigo text              |
| Neutral / not assigned / not applicable | pale gray background, slate text                 |

Typical badge text is `12px` medium, with `8–10px` horizontal and `2–4px` vertical padding. Use a full pill for status and a small rounded rectangle for metadata such as a date, payment type, or staff name.

Examples from the pharmacy interface:

- `Given` with green dot;
- `Pending` with amber dot;
- `Out of Stock` in red;
- `12 units (Low Stock)` in orange;
- `OTC` in green and `Non-OTC` in gray;
- `In DDA` in orange and `Not in DDA` in gray;
- batch count in pale indigo;
- drug-and-quantity tags in pale indigo.

### 6.4 Empty states

An empty result is a designed state, not a blank table.

- Pale-gray background.
- Dashed gray border.
- `8px` radius.
- `48px` muted outline icon.
- `14px` medium title.
- `14px` muted description explaining whether there is no data or no filter match.
- A small “Clear filters” action when filters caused the empty result.

For tables where column context matters, keep the headers visible and render a placeholder row using dashes and disabled controls.

### 6.5 Pagination

- Separated from results by a slate top border.
- Shows “Showing x–y of z”.
- Shows “Page n of n”.
- Previous and Next buttons have a minimum width of `120px`.
- Disabled buttons use pale gray and cannot receive an action.
- On mobile, information and buttons stack; on wider screens they align horizontally.

### 6.6 Environmental log cards

The Temperature & Humidity Logs landing page uses a responsive card grid: one column mobile, two columns medium, three columns large.

Each card uses a pale-indigo gradient, indigo title, right chevron, one-line description, and smaller normal-range text. Hover slightly deepens the gradient and shadow. This is a useful pattern for choosing among a small set of operational modules, but it should not replace tables for record-heavy pages.

---

## 7. Pharmacy workflows to preserve

The new system may use different domain language, but it should preserve the current workflow hierarchy:

### 7.1 Patient-to-dispensing flow

```text
Scan or find patient
        ↓
Open prescription / drug allocation
        ↓
Review patient, medicine, payment, and status
        ↓
Select batch and quantity
        ↓
Confirm dispensing
        ↓
Update allocation status and stock
        ↓
Print or review dispensing record
```

The interface should make the current step, patient identity, medicine identity, and completion state visible throughout the flow.

### 7.2 Stock flow

```text
Drug catalogue → Drug detail → Available batches → Requisition / issue
                              ↘ Expiry and low-stock warnings
```

Stock quantity, batch identity, expiry, and reorder pressure should be visually prominent. Destructive or irreversible stock actions require explicit confirmation.

### 7.3 Compliance flow

Consumption analysis, environmental logs, and dangerous-drug records belong under one clearly labelled compliance/analytics group. These pages should favour dated records, auditability, responsible staff, and clear normal/exception states.

---

## 8. Design tokens

### 8.1 Core colours

| Token         | Hex                   | Use                                                    |
| ------------- | --------------------- | ------------------------------------------------------ |
| `primary-700` | `#373896`             | Brand, active text, primary buttons, key metric values |
| `primary-500` | `#6667AB`             | Secondary links, icons, focus borders                  |
| `primary-100` | `#E7E7FF`             | Active navigation, filter chips, icon surfaces         |
| `primary-50`  | `#F0F0FF`             | Hover states and subtle tinted backgrounds             |
| `text-900`    | `#1F2433`             | Strong body and account text                           |
| `text-700`    | `#374151`             | Main body text                                         |
| `text-500`    | `#687083`             | Navigation defaults and supporting copy                |
| `canvas`      | `#F8FAFC` / `#F9FAFB` | Application/page background                            |
| `surface`     | `#FFFFFF`             | Cards, sidebar, tables, panels                         |
| `border-soft` | `#E6EDF8`             | Dashboard card borders                                 |
| `border-nav`  | `#EDF0F8`             | Sidebar and nested navigation guides                   |

Semantic accents:

| Role               | Representative colour  |
| ------------------ | ---------------------- |
| Success            | `#12B586` / emerald    |
| Warning            | `#D79B2B` / amber      |
| Danger             | `#E85D75` or `#C21F17` |
| Information        | `#2C66E4` / blue       |
| Secondary category | `#7C58E8` / violet     |
| Teal category      | `#14B8A6`              |
| Cyan category      | `#2AA8BD`              |

All semantic colours must be paired with text or an icon and must meet accessible contrast requirements.

### 8.2 Typography

The interface uses a system sans-serif stack:

```css
ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
"Segoe UI", Roboto, Helvetica, Arial, sans-serif
```

Suggested type scale:

| Role                    | Size / weight                      |
| ----------------------- | ---------------------------------- |
| Dashboard page title    | `24–30px`, bold                    |
| Section title           | `20px`, semibold                   |
| Card/chart title        | `18px`, semibold                   |
| Sidebar brand           | `17px`, bold                       |
| Navigation/account name | `15px`, semibold/bold              |
| Body/supporting text    | `14px`, regular/medium             |
| Eyebrow/metric label    | `12px`, medium, uppercase, tracked |
| Badge/count             | `11–12px`, medium/bold             |

Avoid using more than three weights on one screen. Use tabular numerals for currency and important quantities.

### 8.3 Spacing

Use a `4px` base grid.

- `4px`: tiny internal separation.
- `8px`: compact icon/text and control gaps.
- `12px`: standard navigation gap.
- `16px`: compact card padding and toolbar rhythm.
- `20px`: dashboard grid gap and mobile card padding.
- `24px`: major section gap and desktop card padding.
- `28–32px`: spacious dashboard header padding.

### 8.4 Radius

| Element                              | Radius           |
| ------------------------------------ | ---------------- |
| Input / compact button               | `6px`            |
| Small card / menu panel              | `8–12px`         |
| Navigation item                      | `12px`           |
| Account card                         | `16px`           |
| Recommended operational page surface | `20–24px`        |
| Dashboard metric/chart card          | `26–28px`        |
| Dashboard section/header             | `30–32px`        |
| Status/avatar                        | Full circle/pill |

### 8.5 Elevation

Use cool, low-opacity shadows. Borders do most of the structural work.

```css
--shadow-card: 0 12px 28px rgba(15, 23, 42, 0.045);
--shadow-panel: 0 18px 38px rgba(15, 23, 42, 0.055);
--shadow-hero: 0 20px 42px rgba(15, 23, 42, 0.06);
--shadow-tooltip: 0 12px 24px rgba(55, 56, 150, 0.18);
```

Do not use heavy black drop shadows.

### 8.6 Icons

- Use one consistent outline icon family; the current system uses Heroicons.
- Navigation icons are `20px` with about a `2px` stroke.
- Dashboard metric icons are `28px` inside circular badges.
- Icons support labels; they should not replace labels except in the collapsed rail or universally understood controls.
- Any icon-only button must have a tooltip and accessible name.

---

## 9. Responsive rules

| Width      | Behaviour                                                                             |
| ---------- | ------------------------------------------------------------------------------------- |
| `< 640px`  | Single-column cards, stacked headers/actions, full-width controls, stacked pagination |
| `≥ 640px`  | Two-column metric cards and filter fields where space allows                          |
| `≥ 768px`  | Environmental log grid may use two columns; content padding increases                 |
| `< 1024px` | Sidebar is off-canvas                                                                 |
| `≥ 1024px` | Fixed sidebar; environmental log grid may use three columns                           |
| `≥ 1280px` | Four-column metrics and two-column analytics charts                                   |

Touch targets should be at least `40px`, with `44–48px` preferred for primary navigation.

---

## 10. Interaction and accessibility

- Every actionable element must have visible hover, focus, active, disabled, and loading states.
- Use a `2px` indigo focus ring with sufficient offset.
- Preserve `aria-current="page"` on the active navigation item.
- The mobile drawer closes with `Escape` and backdrop selection.
- Filter panels close with `Escape` and click-away.
- Do not encode clinical or stock state by colour alone.
- Announce validation and save results through accessible status/alert messages.
- Place the most important action first in keyboard order.
- Confirm destructive changes such as deleting records or irreversible stock updates.
- Keep labels visible; placeholders are examples, not replacements for field labels.
- Use sentence case for navigation, headings, buttons, filters, and statuses.
- Use clear verbs: “Apply filters”, “Clear filters”, “View batches”, “Confirm dispensing”.

---

## 11. Reuse guidance for the new system

### Keep unchanged

- application shell proportions;
- expandable/collapsible role sidebar;
- sidebar brand, account, grouped navigation, and bottom utilities;
- indigo/white/slate colour relationship;
- system font and outlined icon style;
- dashboard card hierarchy and responsive grids;
- search + filter drawer + active-chip pattern;
- semantic badges and responsive row details;
- soft borders and restrained elevation.

### Replace with the new system's content

- product and organisation name;
- role/workspace title;
- group names and navigation labels;
- pharmacy metrics and chart subjects;
- table columns, statuses, currency, and workflows;
- compliance vocabulary and required audit fields.

### Recommended visual normalization

The current application has two surface generations:

1. a newer dashboard language with `26–32px` radii and layered soft shadows;
2. older list pages with `8px` outer cards and minimal shadow.

For a new implementation, use a single family:

- `28–32px` only for hero/header and major analytics containers;
- `20–26px` for metrics, chart cards, list pages, and detail panels;
- `12px` for tables, navigation items, menus, and nested controls;
- `6–8px` for inputs and compact buttons.

This keeps the recognisable pharmacy look while making navigation, dashboard, and operational screens feel like one product.

---

## 12. Acceptance checklist

The new system matches this design direction when:

- [ ] Desktop sidebar is `288px`, collapses to `72px`, and content follows it without jumping.
- [ ] Mobile sidebar is off-canvas, has a backdrop, locks body scroll, and closes with `Escape`.
- [ ] Active, hover, focus, disabled, and danger navigation states are implemented.
- [ ] Navigation is grouped by real user workflows and automatically exposes the active group.
- [ ] Page canvas is light slate and primary surfaces are white with cool-gray borders.
- [ ] Indigo `#373896` is the main brand/action colour.
- [ ] Dashboard order is header/controls, metrics, analytics, and recent activity.
- [ ] Metric grid changes from one to two to four columns responsively.
- [ ] Search and filters work together and active filters appear as removable chips.
- [ ] Tables prioritise essential columns and move secondary data into responsive details.
- [ ] Empty, loading, error, and no-filter-match states are explicitly designed.
- [ ] Statuses include text and do not rely only on colour.
- [ ] All icon-only controls have accessible names and tooltips.
- [ ] Page titles, card titles, body copy, badges, and numeric values follow the type scale.
- [ ] Borders and low-opacity shadows are used consistently; there are no heavy shadows.

---

## 13. Current implementation references

These files are the source of truth for the present design:

- `lib/medic_web/components/sidebar_components.ex` — pharmacy sidebar, grouped navigation, account card, utility links.
- `lib/medic_web/components/layouts/pharmacist.html.heex` — pharmacy application shell and content sizing.
- `assets/css/app.css` — sidebar collapse, mobile drawer, tooltip, scrollbar, and content-margin behaviour.
- `assets/js/app.js` — persistence and keyboard/backdrop interactions for the sidebar.
- `lib/medic_web/live/pharmacist_pages/pharmacist_dashboard_live/index.ex` — dashboard composition and pharmacy-specific content.
- `lib/medic_web/components/dashboard_components.ex` — header, metric, analytics, chart, and recent-item cards.
- `lib/medic_web/components/core_components.ex` — page headers, search, filters, chips, tables, empty states, and pagination.
- `lib/medic_web/live/pharmacists_pages/drug_live/index.ex` — representative stock list page.
- `lib/medic_web/live/pharmacists_pages/drug_allocation_live/index.ex` — representative dispensing/allocation table.
- `lib/medic_web/live/pharmacists_pages/pharmacy_log_live/index.ex` — module-selection card grid.
