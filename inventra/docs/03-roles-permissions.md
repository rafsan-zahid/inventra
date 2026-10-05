# Roles, permissions and invitations

## Access levels

| Role | What they can do |
|---|---|
| **Owner (Super Admin)** | Everything, including finance. The **only** role that approves branch restock requests and daily distributions, and the only one that invites users. |
| **Admin** | Day-to-day operations and setup: buying, receiving, products, suppliers, branches, counts, waste and adjustment approvals. Cannot invite users or approve restock/distribution. |
| **Inventory Manager** | Buying, receiving, stock, setup and operational approvals. |
| **Branch Manager** | Sees every location; acts only on their own branch: requests stock, receives deliveries, logs waste, runs counts. Sees costs. |
| **Storekeeper** | Central only: receiving, picking and dispatch, counts. No cost figures. |
| **Kitchen Manager** | Their branch: records usage and waste. No cost figures. |
| **Auditor** | Read-only, including the audit log. |
| **Viewer** | Read-only, including values. Changes nothing. |

Permissions are atomic strings (`po.approve`, `tr.dispatch`, `dist.approve`…),
roles are editable bundles, and **every assignment is scoped** to the
organization, a brand, or specific locations. A user can hold different roles at
different locations.

## Two separate scopes

- **View scope** — Owner, Admin, Inventory Manager, Branch Manager, Auditor and
  Viewer can *see* all locations.
- **Action scope** — what a user may *change* is limited to their assigned
  locations.

## Approval rules

- **Owner only:** branch restock requests, daily distribution plans.
- **Owner or Admin/Inventory Manager:** purchase orders above the limit, waste
  above the limit, adjustments above the limit, stock counts.
- **Nobody can approve their own request** (enforced in the `approvals` table).
- Limits are configurable per organization (see `.env.example`).

## Invitations (production build)

The prototype identifies people through their Claude account. In production:

1. Owner invites by email and picks the access level and locations.
2. System creates the user with `status = 'invited'` and emails a signed,
   single-use invite link (24h expiry).
3. On acceptance they set a password (and 2FA if enabled); status becomes
   `active` and `joined_at` is stamped.
4. The Owner can change anyone's level or disable them at any time. Disabling
   revokes all sessions; history stays attributed to them.
