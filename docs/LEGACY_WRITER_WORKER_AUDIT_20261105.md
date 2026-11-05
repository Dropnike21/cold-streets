# Legacy Writer / Worker Collision Audit — 2026-11-05

## Final state

No gameplay/runtime/build/concurrency test or deployment was performed.

The final runtime writer inventory is deliberately small.

### Enabled background worker

`workers/stateDurationWorker.js`

- persisted `user_state_episodes`;
- due-row claim uses `FOR UPDATE SKIP LOCKED`;
- transactional close/achievement refresh;
- structured worker health/error telemetry;
- the only polling `setInterval` in runtime backend code.

### Crew crime worker

Crew crime settlement was originally hardened as a persisted multi-replica worker, but the final source pass found a conflict:

- Recruits Canvas: fixed 60-second loop + flat 1% mortality;
- `crimes_master`: per-crime automation cooldown + casualty risk.

It is therefore no longer started by `server.js`, is not required by readiness, and `workers/crewCrimeWorker.js` now throws an explicit fail-closed error if invoked.

Existing persisted assignments can be recalled through the safe recall path; no automated payout settlement runs.

## Retired single-process writers

Permanently retired:

- cooldown/Vital regeneration timer;
- random market restock timer;
- destructive `seed_gyms.js`;
- legacy Casino Perya/Slots/High-Low settlement modules;
- legacy mixed Casino wager helper;
- dormant Pickpocket client-activity settlement;
- dormant company pricing writer;
- dormant company advertising writer;
- legacy recruit generator implementation.

`ENABLE_UNSAFE_LEGACY_TIMERS=true` causes startup failure rather than restoring the old timer engine.

## Runtime source scan

Final static scan:

- runtime `Math.random`: 0;
- runtime ad-hoc `console.*`: 0;
- server-level mutation timers: 0;
- enabled polling workers: 1 (State Duration).

The release-preflight CLI intentionally uses console output and is not server runtime logging.

## Collision conclusion

With crew automation paused, the former cross-domain crew-worker settlement collision surface is removed from runtime.

Company NPC assignment/recall and Syndicate crew recall still use transactional row locking for their own persisted state changes.

Runtime/concurrency testing remains required before release; this document establishes only the final static writer ownership model.
