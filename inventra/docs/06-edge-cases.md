# Edge cases and how the system handles them

| Situation | Handling |
|---|---|
| Partial receiving | PO lines track cumulative received; status auto-updates; remaining can be received later or short-closed with a reason |
| Damaged / rejected delivery | Recorded on the receipt but never enters stock; feeds supplier performance |
| Duplicate receiving | Unique constraint on supplier + invoice number; idempotency key on confirm; over-receipt beyond 5% tolerance blocked |
| Invoice price ≠ PO price | Accepted at invoice price, variance flagged, price history records the actual |
| Expired stock | Status job marks it; excluded from allocation; must be written off or quarantined by an authorised user |
| Negative stock | Blocked by default; if allowed per item/location, reconciled against the next receipt's cost |
| Partial transfers | Dispatched and received quantities tracked separately; differences need a reason and approval |
| Transfer cancellation | Free before dispatch; after dispatch it becomes a return transfer |
| Wrong stock count | Recount before approval; after approval, correct with a new adjustment referencing the count |
| Count during trading | Snapshot at start + movements during the window, so variance stays correct |
| Backdated transactions | Only within open fiscal periods and with permission; the engine re-runs allocation for that item/location and posts cost corrections |
| Supplier price changes | Never overwritten; new price row with an effective date; lots keep their own cost |
| Unit conversion errors | Stock stored in the base unit only; conversion preview on every entry; changing a conversion affects future entries only and is audited |
| Rounding | 4-decimal precision; residual lot quantities below tolerance auto-closed with a rounding transaction |
| Recipe changes | Recipes versioned with effective dates; sales use the version active at sale time |
| Deleted products | No hard delete once transactions exist; archived instead |
| Branch closure | `closing` blocks new supply; stock must be transferred or written off; then `closed` and read-only |
| Concurrent users | Row-level locks in the engine; optimistic `version` on documents so two editors get a conflict, not a silent overwrite |
| Offline operation | Mobile queues counts, waste and receiving drafts with idempotency keys; the server is the authority; conflicts surface for review |
| POS sale for an unmapped item | Held in an exceptions queue, never dropped |
| Balance drift | Nightly reconciliation; mismatch alerts the Owner and blocks period locking |
| Tenant isolation | Row-level security on every table plus organization_id in every query; automated cross-tenant access tests |
