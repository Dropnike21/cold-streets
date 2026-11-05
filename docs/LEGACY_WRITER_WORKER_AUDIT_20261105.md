# Legacy Writer / Worker Collision Audit — 2026-11-05

## Scope

This stabilization pass reviewed backend code that can modify authoritative
gameplay state outside normal request handlers.

The goal was to distinguish:

- intended persisted workers;
- dormant legacy writers;
- destructive/manual scripts;
- duplicate mutation paths;
- cross-domain lock-order hazards.

No gameplay/runtime/build/concurrency tests and no deployment were performed.

## Intended background writers

Two background workers remain active only when `ENABLE_GAMEPLAY_API=true`.

### Crew crime worker

`workers/crewCrimeWorker.js`

Properties:

- persisted schedule table;
- due-row claim uses `FOR UPDATE SKIP LOCKED`;
- one due assignment is settled per transaction;
- secure randomness uses `node:crypto.randomInt`;
- settlement writes crew state, owner Dirty Cash, events, and next schedule;
- row ownership/source catalog are revalidated before settlement.

Shared lock order:

`crew_crime_assignments -> user_crew -> users -> inventory`

The corresponding Syndicate and company crew-transfer routes use the same
schedule/crew/user ordering before shared state is modified.

No static lock-order cycle was found between:

- crew crime settlement;
- Syndicate assign/unassign;
- company NPC assign/recall.

### State duration worker

`workers/stateDurationWorker.js`

Properties:

- persisted `user_state_episodes`;
- due-row claim uses `FOR UPDATE SKIP LOCKED`;
- closes one episode transactionally;
- refreshes state-duration achievements in the same transaction.

The worker does not acquire a later `users FOR UPDATE` lock after locking an
episode, so the user->episode ordering used by request paths does not form a
reverse-lock cycle.

## Legacy server timers retired

The previous opt-in non-production timer block could perform:

- cooldown deletion;
- global Energy/Nerve/HP regeneration;
- random market stock restocking.

These operations were not persisted jobs, were replica-unsafe, and the market
restock used `Math.random` with unreconciled stock semantics.

The timer implementation has been removed from `server.js`.

If a stale deployment sets:

`ENABLE_UNSAFE_LEGACY_TIMERS=true`

startup now fails loudly instead of reactivating legacy writers.

The environment template marks this flag permanently retired.

Final static readback:

- `server.js` setInterval calls: 0;
- `server.js` SQL mutation statements: 0.

## Destructive Gym seeder retired

`seed_gyms.js` previously:

- truncated `gyms_master` with CASCADE;
- reset identity state;
- generated a synthetic 40-Gym catalog from formulas;
- wrote catalog data outside the recovered source/migration pipeline.

It is not a package startup script, but direct `node seed_gyms.js` execution
was enough to overwrite authoritative catalog state.

The file now contains no database import and no SQL. It exits by throwing a
clear retired-script error.

Source history remains available through Git if historical comparison is needed.

## Legacy Casino child engines retired

Dormant files:

- `routes/casino/perya.js`;
- `routes/casino/slots.js`;
- `routes/casino/highlow.js`;
- `utils/casinoEconomy.js`.

The canonical `routes/casino.js` already exposed only read-only token status
and blocked all game mutations, but the child modules still contained live
settlement code.

That code mixed Casino Tokens with Dirty/Clean Cash and embedded unreconciled
paytables, jackpot rules, and High-Low multipliers. A future accidental
`require()`/mount could therefore have reopened an obsolete economy path.

All three child routers are now explicit 503 fail-closed modules.

The old wager helper now always raises a 503 ActionError.

Static readback for all four retired modules:

- database imports: 0;
- SQL mutation statements: 0;
- timer loops: 0.

## Package/startup surface

`cold_streets_backend/package.json` currently contains dependencies only and
defines no npm scripts that invoke a legacy seeder or secondary server.

No alternate backend entrypoint was found in the backend tree.

## Worker polling inventory

After retirement of server timers, polling responsibility is limited to:

- `startCrewCrimeWorker`;
- `startStateDurationWorker`.

Those workers start only from `server.js` after:

- gameplay is explicitly enabled;
- required server configuration is present;
- the database connection succeeds.

## Remaining cautions

This static pass does not prove absence of runtime deadlocks under load.

Before public launch, an explicitly authorized concurrency test should still
exercise:

- crew worker vs Syndicate recall;
- crew worker vs company transfer;
- state expiry vs revive/new penalty;
- duplicate worker replicas.

No such runtime test was run in this pass.

## Result

The backend no longer contains a reachable opt-in legacy timer writer, a
destructive runnable Gym seeder, or dormant Casino settlement modules capable of
performing SQL writes.

The remaining background mutation loops are the two persisted workers designed
for multi-replica row claiming.
