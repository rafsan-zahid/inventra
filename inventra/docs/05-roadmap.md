# Build roadmap

Sizing assumes 2–3 developers and a designer. The prototype in `prototype/`
already defines every screen and rule, so most of the work is backend.

| Phase | Weeks | Scope | Done when |
|---|---|---|---|
| 0. Foundations | 1–3 | Repo, CI, auth + invitations, 2FA, tenancy + RLS, RBAC, audit framework, org/brand/location setup, design system | Users log in and see only their scope |
| 1. Catalog & engine | 4–7 | Products, units, conversions, suppliers, **inventory engine** (lots, FEFO/FIFO, ledger, balances), opening balances | Engine passes concurrency and reconciliation tests |
| 2. Buying & receiving | 8–11 | POs, approvals, receiving with/without PO, price history, attachments | Real deliveries received at Central |
| 3. Branch supply | 12–16 | Requests with needed-by date, Owner approval, distribution grid, dispatch, in-transit, receipt, shortages, **invoices + PDF** | A full week of supply runs end to end |
| 4. Control | 17–20 | Waste, counts, adjustments, expiry jobs, notifications | Variance visible and explained |
| 5. Visibility | 21–23 | Dashboards, charts, reports, exports, global search, audit viewer | Owner uses it daily |
| 6. Rollout | 24–26 | All branches live, data migration, training, hardening, restore drill | Paper/sheets retired |
| Phase 2 | later | Recipes, production, POS integration, theoretical vs actual, food cost, reorder forecasting, barcode scanning, WhatsApp alerts | |

**Advice:** pilot at one branch after phase 3 rather than building everything
first. Receiving and counting in a real kitchen reshape the UI more than any
specification.
