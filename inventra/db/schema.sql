-- Inventra — PostgreSQL schema (production build)
-- Conventions: UUID ids, every tenant table carries organization_id,
-- quantities NUMERIC(18,4) in the item's BASE unit, money NUMERIC(18,4).
-- Enable row-level security on every tenant table and scope by organization_id.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ========== Tenancy & locations ==========
CREATE TABLE organizations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  currency      TEXT NOT NULL DEFAULT 'BDT',
  timezone      TEXT NOT NULL DEFAULT 'Asia/Dhaka',
  settings      JSONB NOT NULL DEFAULT '{}',   -- approval limits, near-expiry days, etc.
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE brands (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'active',
  UNIQUE (organization_id, name)
);

CREATE TYPE location_type AS ENUM ('central','branch');

CREATE TABLE locations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  brand_id        UUID REFERENCES brands(id),          -- NULL for the central warehouse
  type            location_type NOT NULL,
  name            TEXT NOT NULL,
  code            TEXT,
  address         TEXT,
  status          TEXT NOT NULL DEFAULT 'active',      -- active | closing | closed
  UNIQUE (organization_id, name)
);
-- Exactly one central warehouse per organization (relax if you add more):
CREATE UNIQUE INDEX one_central_per_org ON locations (organization_id) WHERE type = 'central';

CREATE TABLE storage_areas (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id UUID NOT NULL REFERENCES locations(id),
  name        TEXT NOT NULL,
  sort_order  INT NOT NULL DEFAULT 0
);

-- ========== Identity & access ==========
CREATE TABLE users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  email           CITEXT NOT NULL,
  password_hash   TEXT,
  totp_secret     TEXT,
  status          TEXT NOT NULL DEFAULT 'invited',     -- invited | active | disabled
  invited_by      UUID REFERENCES users(id),
  invited_at      TIMESTAMPTZ,
  joined_at       TIMESTAMPTZ,
  last_login_at   TIMESTAMPTZ,
  UNIQUE (organization_id, email)
);

CREATE TABLE roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  key             TEXT NOT NULL,   -- owner | admin | inventory_manager | branch_manager |
                                   -- storekeeper | kitchen_manager | auditor | viewer
  name            TEXT NOT NULL,
  is_system       BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (organization_id, key)
);

CREATE TABLE permissions (
  code        TEXT PRIMARY KEY,    -- e.g. po.approve, tr.dispatch, dist.approve
  description TEXT NOT NULL
);

CREATE TABLE role_permissions (
  role_id         UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_code TEXT NOT NULL REFERENCES permissions(code),
  PRIMARY KEY (role_id, permission_code)
);

-- A user may hold a role for the whole org, a brand, or specific locations.
CREATE TABLE user_role_assignments (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id     UUID NOT NULL REFERENCES roles(id),
  scope_type  TEXT NOT NULL,       -- org | brand | location
  scope_id    UUID                 -- NULL when scope_type = 'org'
);

CREATE TABLE approval_limits (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id  UUID NOT NULL REFERENCES roles(id),
  action   TEXT NOT NULL,          -- waste | adjustment | purchase_order
  max_value NUMERIC(18,4)
);

CREATE TABLE sessions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ip         INET,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ
);

-- ========== Catalog ==========
CREATE TABLE categories (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  UNIQUE (organization_id, name)
);

CREATE TABLE units (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  code            TEXT NOT NULL,            -- kg, g, L, ml, pc, pack, carton
  dimension       TEXT NOT NULL,            -- mass | volume | count
  UNIQUE (organization_id, code)
);

-- item_id NULL = global conversion (kg <-> g); item-specific: 1 carton = 24 bottles
CREATE TABLE unit_conversions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  item_id         UUID,
  from_unit_id    UUID NOT NULL REFERENCES units(id),
  to_unit_id      UUID NOT NULL REFERENCES units(id),
  factor          NUMERIC(18,6) NOT NULL CHECK (factor > 0)
);

CREATE TYPE allocation_policy AS ENUM ('FEFO','FIFO');

CREATE TABLE inventory_items (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id    UUID NOT NULL REFERENCES organizations(id),
  name               TEXT NOT NULL,
  sku                TEXT,
  category_id        UUID REFERENCES categories(id),
  base_unit_id       UUID NOT NULL REFERENCES units(id),
  purchase_unit_id   UUID REFERENCES units(id),
  preferred_supplier_id UUID,
  policy             allocation_policy NOT NULL DEFAULT 'FEFO',
  track_expiry       BOOLEAN NOT NULL DEFAULT TRUE,
  shelf_life_days    INT,
  standard_cost      NUMERIC(18,4) NOT NULL DEFAULT 0,
  extra              JSONB NOT NULL DEFAULT '{}',   -- custom product fields
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, name)
);

-- Par levels and rules per item per location (branch targets drive distribution)
CREATE TABLE item_location_settings (
  item_id          UUID NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
  location_id      UUID NOT NULL REFERENCES locations(id) ON DELETE CASCADE,
  par_level        NUMERIC(18,4) NOT NULL DEFAULT 0,
  reorder_point    NUMERIC(18,4),
  allow_negative   BOOLEAN NOT NULL DEFAULT FALSE,
  storage_area_id  UUID REFERENCES storage_areas(id),
  PRIMARY KEY (item_id, location_id)
);

-- ========== Suppliers & purchasing ==========
CREATE TABLE suppliers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  contact_person  TEXT, phone TEXT, email TEXT, address TEXT,
  vat_no          TEXT, payment_terms TEXT,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (organization_id, name)
);

CREATE TABLE supplier_price_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id UUID NOT NULL REFERENCES suppliers(id),
  item_id     UUID NOT NULL REFERENCES inventory_items(id),
  price       NUMERIC(18,4) NOT NULL,
  effective_date DATE NOT NULL,
  source_type TEXT, source_id UUID
);

CREATE TYPE po_status AS ENUM ('draft','pending','approved','partial','received','cancelled','rejected');

CREATE TABLE purchase_orders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  supplier_id     UUID NOT NULL REFERENCES suppliers(id),
  location_id     UUID NOT NULL REFERENCES locations(id),  -- must be the central warehouse
  status          po_status NOT NULL DEFAULT 'draft',
  order_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  expected_date   DATE,
  total           NUMERIC(18,4) NOT NULL DEFAULT 0,
  notes           TEXT,
  created_by      UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, number)
);

CREATE TABLE purchase_order_lines (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_order_id UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  item_id           UUID NOT NULL REFERENCES inventory_items(id),
  qty_ordered       NUMERIC(18,4) NOT NULL CHECK (qty_ordered > 0),
  unit_price        NUMERIC(18,4) NOT NULL CHECK (unit_price >= 0),
  qty_received      NUMERIC(18,4) NOT NULL DEFAULT 0,
  qty_rejected      NUMERIC(18,4) NOT NULL DEFAULT 0
);

CREATE TABLE goods_receipts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   UUID NOT NULL REFERENCES organizations(id),
  number            TEXT NOT NULL,
  purchase_order_id UUID REFERENCES purchase_orders(id),
  supplier_id       UUID NOT NULL REFERENCES suppliers(id),
  location_id       UUID NOT NULL REFERENCES locations(id),
  invoice_number    TEXT NOT NULL,
  delivery_date     DATE NOT NULL,
  value             NUMERIC(18,4) NOT NULL DEFAULT 0,
  attachment_url    TEXT,
  received_by       UUID NOT NULL REFERENCES users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, number),
  UNIQUE (supplier_id, invoice_number)          -- blocks duplicate receiving
);

CREATE TABLE goods_receipt_lines (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goods_receipt_id UUID NOT NULL REFERENCES goods_receipts(id) ON DELETE CASCADE,
  po_line_id       UUID REFERENCES purchase_order_lines(id),
  item_id          UUID NOT NULL REFERENCES inventory_items(id),
  qty_accepted     NUMERIC(18,4) NOT NULL DEFAULT 0,
  qty_rejected     NUMERIC(18,4) NOT NULL DEFAULT 0,
  unit_price       NUMERIC(18,4) NOT NULL,
  expiry_date      DATE,
  supplier_batch   TEXT,
  lot_id           UUID
);

-- ========== Inventory engine ==========
CREATE TYPE lot_status AS ENUM ('active','quarantined','depleted','disposed');

CREATE TABLE inventory_lots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  item_id         UUID NOT NULL REFERENCES inventory_items(id),
  location_id     UUID NOT NULL REFERENCES locations(id),
  code            TEXT NOT NULL,
  origin_lot_id   UUID REFERENCES inventory_lots(id),   -- lineage across transfers
  source_type     TEXT NOT NULL,            -- goods_receipt | transfer | adjustment | count | opening
  source_id       UUID,
  supplier_id     UUID REFERENCES suppliers(id),
  received_at     DATE NOT NULL,            -- FIFO key; preserved across transfers
  expiry_date     DATE,
  unit_cost       NUMERIC(18,4) NOT NULL,
  qty_original    NUMERIC(18,4) NOT NULL CHECK (qty_original > 0),
  qty_remaining   NUMERIC(18,4) NOT NULL CHECK (qty_remaining >= 0),
  status          lot_status NOT NULL DEFAULT 'active',
  storage_area_id UUID REFERENCES storage_areas(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX lots_fifo  ON inventory_lots (item_id, location_id, status, received_at)
  WHERE qty_remaining > 0;
CREATE INDEX lots_fefo  ON inventory_lots (item_id, location_id, status, expiry_date)
  WHERE qty_remaining > 0;

CREATE TYPE txn_type AS ENUM (
  'opening','purchase_receipt','purchase_return','transfer_out','transfer_in','transfer_loss',
  'consumption','production_in','production_out','waste','expired_write_off',
  'count_adjustment','stock_adjustment','reversal');

-- APPEND ONLY. Grant INSERT/SELECT only; never UPDATE or DELETE.
CREATE TABLE inventory_transactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  type            txn_type NOT NULL,
  item_id         UUID NOT NULL REFERENCES inventory_items(id),
  location_id     UUID NOT NULL REFERENCES locations(id),
  qty             NUMERIC(18,4) NOT NULL,     -- signed: + in, - out
  value           NUMERIC(18,4) NOT NULL DEFAULT 0,
  occurred_at     TIMESTAMPTZ NOT NULL,       -- business time (may be backdated)
  posted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  source_type     TEXT, source_id UUID,
  reverses_id     UUID REFERENCES inventory_transactions(id),
  reason          TEXT, notes TEXT,
  user_id         UUID NOT NULL REFERENCES users(id),
  idempotency_key TEXT UNIQUE,
  UNIQUE (organization_id, number)
);
CREATE INDEX txn_item_loc ON inventory_transactions (item_id, location_id, occurred_at);

-- Which lots each outbound transaction consumed: the FIFO/FEFO trace.
CREATE TABLE lot_allocations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID NOT NULL REFERENCES inventory_transactions(id),
  lot_id         UUID NOT NULL REFERENCES inventory_lots(id),
  qty            NUMERIC(18,4) NOT NULL CHECK (qty > 0),
  unit_cost      NUMERIC(18,4) NOT NULL
);
CREATE INDEX alloc_lot ON lot_allocations (lot_id);

-- Projection, rebuildable from transactions; reconciled nightly.
CREATE TABLE inventory_balances (
  item_id      UUID NOT NULL REFERENCES inventory_items(id),
  location_id  UUID NOT NULL REFERENCES locations(id),
  qty_on_hand  NUMERIC(18,4) NOT NULL DEFAULT 0,
  value        NUMERIC(18,4) NOT NULL DEFAULT 0,
  version      BIGINT NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (item_id, location_id)
);

-- ========== Branch supply: requests, distribution, transfers ==========
CREATE TYPE transfer_status AS ENUM
  ('requested','approved','in_transit','received','discrepancy','cancelled','rejected');

CREATE TABLE stock_transfers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  from_location_id UUID NOT NULL REFERENCES locations(id),   -- always the central warehouse
  to_location_id   UUID NOT NULL REFERENCES locations(id),   -- always a branch
  status          transfer_status NOT NULL DEFAULT 'requested',
  needed_by       DATE,
  note            TEXT,
  distribution_id UUID,
  requested_by    UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),                 -- Owner only
  dispatched_by   UUID REFERENCES users(id),
  received_by     UUID REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at   TIMESTAMPTZ, received_at TIMESTAMPTZ,
  UNIQUE (organization_id, number),
  CHECK (from_location_id <> to_location_id)
);

CREATE TABLE stock_transfer_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id UUID NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  item_id     UUID NOT NULL REFERENCES inventory_items(id),
  qty_requested  NUMERIC(18,4) NOT NULL DEFAULT 0,
  qty_approved   NUMERIC(18,4) NOT NULL DEFAULT 0,
  qty_dispatched NUMERIC(18,4) NOT NULL DEFAULT 0,
  qty_received   NUMERIC(18,4) NOT NULL DEFAULT 0,
  discrepancy_reason TEXT
);

-- Which source lot became which destination lot (keeps expiry, cost and lineage)
CREATE TABLE transfer_line_lots (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_line_id  UUID NOT NULL REFERENCES stock_transfer_lines(id) ON DELETE CASCADE,
  source_lot_id     UUID NOT NULL REFERENCES inventory_lots(id),
  destination_lot_id UUID REFERENCES inventory_lots(id),
  qty               NUMERIC(18,4) NOT NULL,
  unit_cost         NUMERIC(18,4) NOT NULL
);

-- A daily distribution plan covers many branches and needs Owner approval.
CREATE TABLE distributions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  plan_date       DATE NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',   -- pending | approved | rejected
  estimated_value NUMERIC(18,4) NOT NULL DEFAULT 0,
  submitted_by    UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at      TIMESTAMPTZ,
  UNIQUE (organization_id, number)
);

CREATE TABLE distribution_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  distribution_id UUID NOT NULL REFERENCES distributions(id) ON DELETE CASCADE,
  location_id     UUID NOT NULL REFERENCES locations(id),
  item_id         UUID NOT NULL REFERENCES inventory_items(id),
  qty             NUMERIC(18,4) NOT NULL CHECK (qty > 0)
);

-- ========== Invoices (one per delivery to a branch) ==========
CREATE TABLE invoices (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  transfer_id     UUID NOT NULL REFERENCES stock_transfers(id),
  status          TEXT NOT NULL DEFAULT 'proforma',  -- proforma | issued | received
  currency        TEXT NOT NULL DEFAULT 'BDT',
  issue_date      DATE NOT NULL DEFAULT CURRENT_DATE,
  due_date        DATE,
  payment_terms   TEXT,
  bill_to         TEXT, ship_to TEXT, from_text TEXT,
  notes           TEXT, terms TEXT,
  tax_mode        TEXT, tax_value NUMERIC(18,4) DEFAULT 0,
  discount_mode   TEXT, discount_value NUMERIC(18,4) DEFAULT 0,
  shipping        NUMERIC(18,4) DEFAULT 0,
  amount_paid     NUMERIC(18,4) DEFAULT 0,
  subtotal        NUMERIC(18,4) NOT NULL DEFAULT 0,
  total           NUMERIC(18,4) NOT NULL DEFAULT 0,
  pdf_url         TEXT,
  shared_at       TIMESTAMPTZ,
  issued_by       UUID NOT NULL REFERENCES users(id),
  UNIQUE (organization_id, number)
);

CREATE TABLE invoice_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id  UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  item_id     UUID REFERENCES inventory_items(id),   -- NULL for manual lines (delivery charge…)
  description TEXT NOT NULL,
  qty         NUMERIC(18,4) NOT NULL,
  rate        NUMERIC(18,4) NOT NULL,
  amount      NUMERIC(18,4) NOT NULL
);

-- ========== Operations: waste, counts, adjustments, consumption ==========
CREATE TABLE waste_logs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  location_id     UUID NOT NULL REFERENCES locations(id),
  item_id         UUID NOT NULL REFERENCES inventory_items(id),
  qty             NUMERIC(18,4) NOT NULL CHECK (qty > 0),
  reason          TEXT NOT NULL,
  notes           TEXT, photo_url TEXT,
  estimated_value NUMERIC(18,4), value NUMERIC(18,4),
  status          TEXT NOT NULL DEFAULT 'pending',   -- pending | posted | rejected
  logged_by       UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, number)
);

CREATE TABLE stock_counts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  location_id     UUID NOT NULL REFERENCES locations(id),
  count_type      TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'counting',  -- counting | review | applied | cancelled
  is_blind        BOOLEAN NOT NULL DEFAULT TRUE,
  snapshot_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_by      UUID NOT NULL REFERENCES users(id),
  counted_by      UUID REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  UNIQUE (organization_id, number)
);

CREATE TABLE stock_count_lines (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  count_id    UUID NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  item_id     UUID NOT NULL REFERENCES inventory_items(id),
  system_qty  NUMERIC(18,4) NOT NULL,      -- snapshot at start
  counted_qty NUMERIC(18,4),
  variance_value NUMERIC(18,4)
);

CREATE TABLE stock_adjustments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  number          TEXT NOT NULL,
  location_id     UUID NOT NULL REFERENCES locations(id),
  item_id         UUID NOT NULL REFERENCES inventory_items(id),
  qty_delta       NUMERIC(18,4) NOT NULL,   -- positive only allowed at the central warehouse
  reason          TEXT NOT NULL, notes TEXT,
  status          TEXT NOT NULL DEFAULT 'pending',
  requested_by    UUID NOT NULL REFERENCES users(id),
  approved_by     UUID REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (organization_id, number)
);

CREATE TABLE consumption_entries (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  location_id     UUID NOT NULL REFERENCES locations(id),
  business_date   DATE NOT NULL,
  source          TEXT NOT NULL DEFAULT 'manual',   -- manual | pos | count_derived
  posted_by       UUID NOT NULL REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE consumption_lines (
  id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entry_id UUID NOT NULL REFERENCES consumption_entries(id) ON DELETE CASCADE,
  item_id  UUID NOT NULL REFERENCES inventory_items(id),
  qty      NUMERIC(18,4) NOT NULL CHECK (qty > 0)
);

-- ========== Phase 2: recipes, production, POS ==========
CREATE TABLE recipes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name            TEXT NOT NULL,
  output_item_id  UUID REFERENCES inventory_items(id),
  yield_qty       NUMERIC(18,4), yield_unit_id UUID REFERENCES units(id),
  version         INT NOT NULL DEFAULT 1,
  effective_from  DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to    DATE
);

CREATE TABLE recipe_lines (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  item_id   UUID NOT NULL REFERENCES inventory_items(id),
  qty       NUMERIC(18,4) NOT NULL,
  yield_pct NUMERIC(6,2) NOT NULL DEFAULT 100
);

CREATE TABLE pos_sales (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  location_id     UUID NOT NULL REFERENCES locations(id),
  external_id     TEXT NOT NULL,              -- idempotency: never deduct twice
  sold_at         TIMESTAMPTZ NOT NULL,
  pos_item_code   TEXT NOT NULL,
  qty             NUMERIC(18,4) NOT NULL,
  recipe_id       UUID REFERENCES recipes(id),
  processed_at    TIMESTAMPTZ,
  UNIQUE (organization_id, external_id)
);

-- ========== Cross-cutting ==========
CREATE TABLE approvals (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  entity_type   TEXT NOT NULL,     -- purchase_order | transfer | distribution | waste | adjustment | count
  entity_id     UUID NOT NULL,
  requested_by  UUID NOT NULL REFERENCES users(id),
  status        TEXT NOT NULL DEFAULT 'pending',
  decided_by    UUID REFERENCES users(id),
  decided_at    TIMESTAMPTZ,
  comment       TEXT,
  rule_snapshot JSONB,
  CHECK (decided_by IS NULL OR decided_by <> requested_by)   -- no self-approval
);

-- APPEND ONLY, hash-chained per organization for tamper evidence.
CREATE TABLE audit_logs (
  id              BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_user_id   UUID REFERENCES users(id),
  action          TEXT NOT NULL,
  entity_type     TEXT, entity_id TEXT,
  location_id     UUID REFERENCES locations(id),
  before          JSONB, after JSONB,
  reason          TEXT, request_id TEXT, ip INET, user_agent TEXT,
  prev_hash       TEXT, hash TEXT
);
CREATE INDEX audit_org_time ON audit_logs (organization_id, occurred_at DESC);

CREATE TABLE notifications (
  id              BIGSERIAL PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  user_id         UUID NOT NULL REFERENCES users(id),
  type            TEXT NOT NULL,
  payload         JSONB NOT NULL,
  link_view       TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at         TIMESTAMPTZ
);
CREATE INDEX notif_user ON notifications (user_id, read_at NULLS FIRST, created_at DESC);

CREATE TABLE option_lists (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  list_key        TEXT NOT NULL,     -- unit | category | brand | waste | adjustment | shortage…
  value           TEXT NOT NULL,
  sort_order      INT NOT NULL DEFAULT 0,
  UNIQUE (organization_id, list_key, value)
);

CREATE TABLE fiscal_periods (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  start_date      DATE NOT NULL, end_date DATE NOT NULL,
  status          TEXT NOT NULL DEFAULT 'open',   -- open | locked
  locked_by       UUID REFERENCES users(id)
);

CREATE TABLE number_sequences (
  organization_id UUID NOT NULL REFERENCES organizations(id),
  doc_type        TEXT NOT NULL,     -- PO | GRN | TR | INV | WS | ADJ | CNT | DP | TXN
  prefix          TEXT NOT NULL,
  next_value      BIGINT NOT NULL DEFAULT 1,
  PRIMARY KEY (organization_id, doc_type)
);
