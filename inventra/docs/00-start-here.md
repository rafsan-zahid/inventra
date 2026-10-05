# Start here

Read in this order:

1. `01-architecture.md` — the shape of the system and the recommended stack.
2. `02-fifo-engine.md` — the inventory engine. **Build and test this first.**
3. `03-roles-permissions.md` — who can do what; Owner-only approvals; invitations.
4. `04-workflows.md` — buying, branch requests, daily distribution, waste, counts.
5. `06-edge-cases.md` — the situations that corrupt stock data if ignored.
6. `05-roadmap.md` — phases and sizing.
7. `../db/schema.sql` — the database. `../api/endpoints.md` — the API surface.
8. `../prototype/inventra.html` — open it in a browser; it is the working
   reference for every screen and rule described above.

## If you are handing this to a developer

The prototype is a complete, working specification. The quickest route is:

1. Run `db/schema.sql` on a fresh PostgreSQL database.
2. Implement the engine from `02-fifo-engine.md` with tests for: FEFO order,
   expired lots excluded, insufficient stock, concurrent consumption of the last
   unit, transfer lineage, reversal.
3. Build the API in `api/endpoints.md` module by module.
4. Rebuild the screens from the prototype against the API.

## If you are using an AI coding tool

Give it `docs/`, `db/schema.sql`, `api/endpoints.md` and the prototype, and ask
it to generate one module at a time, starting with the engine. Keep the business
rules in the README as its acceptance criteria.
