# Workflows

## 1. Buying (Central only)

Low-stock suggestion → PO created → auto-approved under the limit, else sent for
approval → ordered → received at Central.

**Receiving** records accepted / rejected quantities, expiry dates, supplier
batch numbers and the invoice price. Confirming it, in one database transaction:
creates lots, posts transactions, updates balances and PO quantities, records
price history, writes the audit entry and fires alerts (price increase, short
delivery). Rejected quantities never enter stock. The same supplier invoice
number cannot be received twice.

## 2. Branch restock request

Branch manager chooses **single product** or **multiple products (bulk)**, sets
a **needed-by date** and an optional note.

→ **Owner approves** (nobody else can) → a **pro-forma invoice is created
automatically and shared with the branch** → Central picks the FEFO/FIFO lots and
dispatches → stock goes **in transit** → branch confirms what arrived →
shortages are recorded as a transfer loss and go to the Owner.

The invoice keeps its number and is finalised at dispatch with the exact batches
and costs, then shows received quantities after confirmation.

## 3. Daily distribution

Central (Inventory Manager or Storekeeper) opens the distribution grid:
every product against every branch, prefilled with
**par − on hand − already in transit**, every cell editable.

→ Submit for **Owner approval** (stock does not move yet) → Owner approves →
one transfer and one invoice per branch, dispatched together → branches confirm.

## 4. Kitchen usage

Daily usage entry per location (phase 2: POS sales → recipes). Allocation is
automatic, so staff never choose a batch.

## 5. Waste

Item, quantity, reason, optional photo. Under the limit it posts immediately;
above it, stock is deducted **only after approval**.

## 6. Stock count

Create (snapshot of system quantities) → blind count by storage area → review
variance, biggest value first → approve → adjustments posted. The variance is
applied to *current* stock, so movements during the count are preserved.
Approved counts are never edited; corrections are new adjustments.

## 7. Adjustments

Reason-coded, approval above the limit. **Positive adjustments are only allowed
at Central** — branches correct upward differences through a stock count.
