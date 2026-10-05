# Architecture

## Shape

A modular monolith, API-first, multi-tenant with a shared database and
row-level isolation by `organization_id`. Microservices are unnecessary at this
scale and would slow the build down.

```
Clients:  Web (HQ desktop) · PWA (phones & tablets for ops) · future POS / integrations
                                  |
                          API layer (REST, OpenAPI)
                 auth · tenant resolution · RBAC · rate limiting
                                  |
 +------------------- Domain modules (one codebase) ---------------------+
 | Org & locations | Catalog | Suppliers | Purchasing | Receiving        |
 | INVENTORY ENGINE (lots, ledger, allocation, balances)                 |
 | Requests & distribution | Transfers | Invoices | Counts | Waste       |
 | Adjustments | Consumption | Approvals | Audit | Notifications | Reports|
 +------------------------------------------------------------------------+
                                  |
   PostgreSQL (RLS) · Redis (cache, queues, locks) · S3 (PDFs, photos)
   Workers: expiry scan, alerts, reconciliation, PDF generation, POS ingestion
```

**Rule:** only the inventory engine writes to `inventory_lots`,
`inventory_transactions`, `lot_allocations` and `inventory_balances`. Every other
module calls the engine's commands. This is what keeps stock correct.

## Hierarchy

```
Organization
 └── Brands
      └── Branches            (supplied only by Central)
 └── Central Warehouse        (the only location that buys from vendors)
      └── Storage areas
```

## Recommended stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Next.js + React + Tailwind | Fast, responsive, PWA-capable |
| API | NestJS (TypeScript) or Laravel (PHP) | Structured modules, mature |
| Database | PostgreSQL | RLS, `SELECT … FOR UPDATE`, numeric precision, JSONB |
| ORM | Prisma or Drizzle + raw SQL for the engine | The engine needs hand-tuned locking |
| Jobs | BullMQ (Redis) | Expiry scans, notifications, PDFs |
| Search | Postgres full-text + trigram first | Avoid extra infrastructure early |
| Auth | Own auth (argon2 + TOTP) or a provider | Invitations by email |
| Hosting | Managed Postgres with PITR backups, Singapore region | Close to Dhaka |

## Security

Authentication, RBAC with location scoping, session management, optional 2FA,
immutable inventory transactions and audit logs, approval workflows, soft
deletion where appropriate, device/IP capture, and a tested backup/restore plan.
Inventory transactions that affect historical balances are never deleted.
