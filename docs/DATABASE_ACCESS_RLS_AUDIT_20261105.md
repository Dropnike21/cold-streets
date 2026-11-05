# Database Access / RLS Audit — 2026-11-05

## Scope

This audit covers the development Supabase project's public gameplay schema and
the server-authoritative access model used by Cold Streets.

No gameplay/runtime/build tests and no deployment were performed.

## Intended access model

Cold Streets currently uses:

- Supabase Auth to authenticate the player;
- the Node backend to verify the Supabase access token;
- a private direct PostgreSQL connection for authoritative gameplay reads/writes;
- no client-authoritative Data API mutations.

Therefore `anon` and `authenticated` do not need direct gameplay table,
sequence, or RPC access.

## Current object inventory

Development readback after hardening:

- public tables: 74;
- public sequences: 43;
- public functions: 2;
- public views/materialized views: 0.

All current public tables, sequences and functions are owned by `postgres`.

## RLS state

All 74 public tables have RLS enabled.

There are no public RLS policies. This is intentional for the current
server-only Data API boundary: no policy means RLS denies rows, and the client
roles also have no table grants.

The Supabase Security Advisor reports `rls_enabled_no_policy` as INFO for these
tables. This is expected under the current deny-all direct-access model; it is
not an instruction to add permissive client policies.

## Table grants

After readback:

- `anon`: zero public table grants;
- `authenticated`: zero public table grants.

The `service_role` retains administrative/server grants. That role is a secret
server capability and must never be shipped to Flutter.

## Sequence exposure fixed

Before this audit, all 43 public sequences exposed `USAGE`/`SELECT` to
`anon` and `authenticated` through legacy Supabase defaults.

The development project now revokes client access from all current public
sequences.

Post-fix readback:

- anon sequence access: 0;
- authenticated sequence access: 0.

## Function/RPC exposure

The only public functions are:

- `prevent_casino_token_spend_mutation()`;
- `record_user_item_discovery()`.

Both are:

- `SECURITY INVOKER`;
- configured with an empty search path;
- not executable by `anon`;
- not executable by `authenticated`;
- not executable through the PostgreSQL `PUBLIC` grant.

No public `SECURITY DEFINER` RPC surface exists.

## Default privilege exposure fixed for postgres-owned objects

The project still carried legacy Supabase default ACLs that would automatically
grant newly created public tables/functions/sequences to client roles.

The development project now removes those future grants for objects created by
`postgres`:

- no table SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN;
- no sequence USAGE/SELECT/UPDATE;
- no function EXECUTE;
- no PostgreSQL PUBLIC function EXECUTE.

This includes the PostgreSQL 17 `MAINTAIN` table privilege, which was visible
in the first post-change readback and was then explicitly revoked.

## supabase_admin default ACL caveat

The platform-owned `supabase_admin` role still has Supabase's legacy default
ACL entries. The project `postgres` role is not permitted to alter another
role's default privileges, and an attempted cross-owner change correctly failed
with PostgreSQL permission denial.

This was not bypassed or worked around.

Risk is currently bounded because every Cold Streets public gameplay object is
owned by `postgres`; none is owned by `supabase_admin`.

Operational rule:

- create future gameplay schema objects through reviewed postgres-owned
  migrations;
- do not create gameplay tables/functions under `supabase_admin`;
- if the platform later exposes a supported project setting/owner-level action
  to revoke that default ACL, apply it separately.

## Migration

Git now contains:

`20261105093500_data_api_privilege_hardening_20261105.sql`

It reproduces the successful hardening:

- revoke direct client table access;
- revoke direct client sequence access;
- revoke public/client function execution;
- harden future postgres-owned default privileges.

The SQL was applied directly to the development project for verification. Its
migration-history entry was not fabricated manually; the file remains pending
for the next authorized normal migration-history reconciliation pass.

## Security Advisor

After hardening, the remaining security advisor output is the expected
`rls_enabled_no_policy` INFO class for server-only tables.

No public SECURITY DEFINER function exposure or RLS-disabled public table was
found.

## Verification performed

Read-only verification included:

- RLS flags for every public table;
- table grants;
- sequence privileges;
- function security mode and EXECUTE privileges;
- object ownership;
- default ACLs;
- public policies;
- public views;
- Security Advisor output.

No runtime client request was executed.
