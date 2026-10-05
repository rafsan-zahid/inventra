# API surface

All routes are tenant-scoped by the authenticated user's organization. Every
state-changing route takes an `Idempotency-Key` header. Permissions in brackets.

## Auth & users
```
POST   /auth/login                         email + password (+ TOTP)
POST   /auth/logout
GET    /me                                 profile, roles, scoped locations
POST   /users/invite                       [user.manage] email, role, locations  (Owner only)
POST   /users/accept-invite                token, password
PATCH  /users/:id                          [user.manage] role, locations, status
GET    /users
```

## Setup
```
GET/POST/PATCH  /brands                    [master]
GET/POST/PATCH  /locations                 [master]
GET/POST/PATCH  /items                     [master]
GET/POST/PATCH  /suppliers                 [master]
GET/POST/DELETE /option-lists/:key         [master]  units, categories, reasons…
```

## Buying
```
GET    /purchase-orders
POST   /purchase-orders                    [po.create]   always delivers to Central
POST   /purchase-orders/:id/approve        [po.approve]
POST   /purchase-orders/:id/cancel
POST   /goods-receipts                     [receive]     creates lots + transactions
```

## Branch supply
```
POST   /transfers                          [tr.request]  single or bulk, needed_by date
POST   /transfers/:id/approve              [tr.approve]  Owner only -> issues pro-forma invoice
POST   /transfers/:id/dispatch             [tr.dispatch] FEFO/FIFO allocation, finalises invoice
POST   /transfers/:id/receive              [tr.receive]  received quantities + shortage reasons
POST   /transfers/:id/cancel
GET    /distributions/suggestion?date=     par - on hand - in transit, per branch
POST   /distributions                      [tr.dispatch] submit plan for approval
POST   /distributions/:id/approve          [dist.approve] Owner only -> dispatches all branches
```

## Invoices
```
GET    /invoices
GET    /invoices/:id
PATCH  /invoices/:id                       [invoice.edit] rates, extra lines, tax, discount…
POST   /invoices/:id/share                 notify the branch
GET    /invoices/:id/pdf                   rendered PDF
```

## Operations
```
POST   /consumption                        [consume]
POST   /waste        POST /waste/:id/approve
POST   /counts       POST /counts/:id/submit   POST /counts/:id/approve
POST   /adjustments  POST /adjustments/:id/approve
POST   /lots/:id/quarantine | /release | /write-off   [lot.manage]
```

## Read models
```
GET /stock?location=&item=                 balances
GET /lots?location=&status=                batches, expiry
GET /ledger?item=&location=&from=&to=      transactions with lot allocations
GET /dashboard?location=&days=             KPIs and chart series
GET /reports/{valuation|movement|expiry|waste|variance|purchases}?format=csv|xlsx|pdf
GET /audit?user=&entity=&from=&to=         [audit.view]
GET /notifications                         PATCH /notifications/read
```

## Webhooks (phase 2)
```
POST /webhooks/pos/sales                   signed; idempotent on external sale id
```
