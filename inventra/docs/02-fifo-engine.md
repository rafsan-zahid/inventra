# The inventory engine (FEFO / FIFO)

This is the heart of the product. Everything else is screens around it.

## Model

- Every inbound movement creates a **lot** with `qty_remaining`, `unit_cost`,
  `received_at` and `expiry_date`.
- Every outbound movement creates a **transaction** plus one or more
  **lot_allocations** saying exactly which lots it consumed and at what cost.
- `inventory_balances` is a projection; the transactions are the truth.

## Allocation rules

- Policy is per item: **FEFO** (earliest expiry first) for perishables,
  **FIFO** (oldest received first) for everything else. Ties break on
  `received_at`, then `id`, so allocation is deterministic.
- Expired and quarantined lots are excluded by the query, not by the UI, so
  they can never be consumed by accident.
- A manual lot override requires permission and a reason, and is audited.

## Allocation algorithm (must run inside one DB transaction)

```sql
BEGIN;

SELECT * FROM inventory_balances
 WHERE item_id = $1 AND location_id = $2
 FOR UPDATE;                    -- serialises writes for this item+location

SELECT * FROM inventory_lots
 WHERE item_id = $1 AND location_id = $2
   AND status = 'active' AND qty_remaining > 0
   AND (expiry_date IS NULL OR expiry_date >= $as_of)
 ORDER BY
   CASE WHEN $policy = 'FEFO' THEN expiry_date END NULLS LAST,
   received_at, id
 FOR UPDATE;

-- take from each lot in order until the quantity is covered
-- insufficient stock -> ROLLBACK unless allow_negative is set for this item+location

INSERT INTO inventory_transactions (...);       -- value = sum of allocations
INSERT INTO lot_allocations (...);              -- one row per lot touched
UPDATE inventory_lots SET qty_remaining = ...;  -- depleted lots -> status 'depleted'
UPDATE inventory_balances SET qty_on_hand = ..., value = ..., version = version + 1;
INSERT INTO audit_logs (...);

COMMIT;
```

Key points:

- **Lock the balance row first.** It serialises concurrent writes for one item
  at one location (two tablets consuming the last 10 kg at the same time)
  without locking the table. Contention is naturally low.
- **Idempotency keys** on every command stop double submission from flaky
  mobile networks.
- **Reversals** re-credit the exact lots from the original allocations.
  Historic transactions are never edited.

## Transfers keep lineage

On dispatch, stock is allocated from Central's lots and moves to **in transit**.
On receipt, one destination lot is created per source lot with:

- `origin_lot_id` pointing back to the Central lot,
- the **original** `received_at`, `expiry_date` and `unit_cost`.

So the chicken received on 1 September is still the oldest stock at the branch,
and searching a lot code shows the full journey: vendor → Central → branch →
consumption or waste.

## Background jobs

- **Expiry scan** (hourly): mark near-expiry and expired lots, raise alerts.
- **Reconciliation** (nightly): for every item+location,
  `SUM(lot.qty_remaining) = balance.qty_on_hand = SUM(transactions.qty)`.
  A mismatch alerts the Owner and blocks period locking.
- **POS ingestion** (phase 2): sales → recipe → FEFO allocation, batched,
  idempotent on the POS sale id.
