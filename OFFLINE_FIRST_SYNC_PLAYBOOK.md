# Offline-First Sync Playbook (PC Hub + Phone Clients)

Audience: an AI coding agent (or engineer) that must add offline-first sync to a different app.
Origin: distilled from a working, tested proof of concept (Flutter/Dart, Drift/SQLite, Shelf HTTP server on a Windows PC, Android phones as clients). The domain of the PoC is intentionally omitted; everything below is domain-agnostic. Wherever this document says **record**, substitute your own entity (order, task, inspection, contact, ...).

How to use this document: read sections 1-3 to understand the design, implement sections 4-9 in order, then use section 10 (tests) and section 12 (adaptation checklist) to verify you reproduced it. "MUST" items are invariants the design depends on; breaking one reintroduces data loss or false conflicts.

---

## 1. Goals, non-goals, and the shape of the system

### Goals
- App is **fully usable offline** on every device. The UI reads/writes only the local database, never the network.
- When devices share a network, the user presses **Sync** and both sides converge to identical data.
- Edits to *different* fields of the same record on different devices **auto-merge**.
- Edits to the *same* field, or delete-vs-edit, are real **conflicts** that the user resolves explicitly.
- **No silent data loss**, ever. Any failure leaves both sides consistent and retryable.

### Non-goals (deliberately out of scope; adding them changes the design)
Cloud backend, accounts, internet sync, background/auto sync, push notifications, TLS/E2E encryption (plain HTTP on trusted LAN), phone-to-phone sync, multiple hubs, purging of deleted records, rich-text/CRDT merging inside a single field.

### Topology (the key simplifying decision)
```
 Phone A (client) ──┐
 Phone B (client) ──┼── HTTP/JSON over LAN ──►  PC (hub = the only server, source of truth ordering)
 Phone C (client) ──┘
```
- **One hub (PC), many clients (phones).** A client pairs with exactly one hub at a time.
- **Clients initiate everything.** The hub is passive: it runs an HTTP server and answers. The hub never calls a phone (phones are behind NAT/sleep, have no stable address).
- Same codebase and same DB schema on both roles; the role is chosen by platform. Columns that matter to one role stay unused on the other.
- Sync is **manual (user presses a button)**. No background sync. This keeps conflict UI possible (a user is present) and removes a large class of lifecycle problems.

---

## 2. Core design decisions (and why)

| Decision | Why |
|---|---|
| **Never compare clocks between devices.** Change detection uses a hub revision counter + a client dirty set. | Device clocks drift/are changed manually; timestamp-based "last write wins" produces missed changes and false conflicts. Timestamps are kept **for display only** (e.g. "edited 14:32" in the conflict UI). |
| **Field-level change tracking**, not record-level. | Lets edits to different fields of the same record auto-merge; only genuinely contested fields become conflicts. |
| **Global monotonically increasing `revision` on the hub**; every field stores the revision at which it last changed (`<field>_rev`). | A client only needs to remember one integer (`last_synced_revision`, "R0") to ask "what changed since I last synced?". |
| **Client keeps a per-record `dirty_fields` set.** | The client knows exactly which fields it edited since the last successful sync without any clock. |
| **Soft delete (tombstone) via a synced `deleted` field.** | A delete is just another field change, so it syncs and merges like any other. Rows are never hard-deleted (purging is a non-goal). |
| **Client-generated UUID v4 primary keys.** | Records can be created offline on any device with no id collision and no server round trip. |
| **Pull -> merge locally -> (resolve) -> push -> commit locally**, with the *client* doing the merge. | Hub stays dumb and simple (store values + revisions). Conflict UI lives where the user is. |
| **Optimistic concurrency on push via `baseRevision`**; hub answers `409 stale_revision` if it changed since the pull; client re-pulls and retries (max 3). | Makes pull+push behave like one atomic operation without long-held locks. Handles "PC user edited" and "another phone synced" mid-sync identically. |
| **Phone applies nothing locally until the hub confirmed the push; hub applies a push all-or-nothing in one transaction.** | Any failure (network drop, crash, cancel) leaves both sides unchanged. |
| **Pure-Dart (no Flutter/DB imports) merge and conflict-resolution modules.** | Trivially unit-testable; the most bug-prone logic gets the most tests. |
| **Pairing via QR code + single-use short-lived token -> long-lived per-device secret.** | Zero typing, no accounts, per-device revocation. |
| **Idempotent push** (values equal to hub's current value are ignored, no revision bump). | Retrying after a lost response is harmless. |

---

## 3. Data model

### 3.1 Per synced record (same table on both roles)

```
id            TEXT PK         -- UUID v4, generated on the creating device
<field_1..n>  ...             -- the user-editable synced fields
deleted       BOOL            -- tombstone; itself a synced field
created_at    INT             -- UTC ms, set once, never changes
updated_at    INT             -- UTC ms of last local edit of any field (list ordering AND the
                              --   client's "version" stamp, see 6.5)
<field>_at    INT   (per synced field, incl. deleted) -- UTC ms of last edit. DISPLAY ONLY.
<field>_rev   INT   (per synced field, incl. deleted) -- HUB ONLY: hub revision when field last changed. default 0
dirty_fields  TEXT            -- CLIENT ONLY: comma-separated field names edited since last successful sync
```

Rules:
- A "synced field" is any field that is merged independently. Choose the granularity deliberately: finer = fewer conflicts but more columns. Whole-blob fields (e.g. a long text body) are merged atomically: concurrent edits to the same blob are a conflict, not a text-merge.
- `deleted` MUST be a synced field with its own `_at`/`_rev`/dirty bit.
- A brand-new record on a client has **all fields dirty** (so it is pushed in full).

### 3.2 Meta / state tables

```
meta(key PK, value)                   -- hub: 'revision' (int as text, default 0), 'server_id' (UUID).
                                      -- client: 'device_id' (UUID), 'last_server_id'
paired_devices (HUB)                  -- device_id PK, name, secret_hash (SHA-256 hex; secret itself never stored),
                                      --   paired_at, last_sync_at?, revoked BOOL
server_pairing (CLIENT, single row id=1) -- server_id, server_name, host, port, device_secret,
                                      --   paired_at, last_synced_revision (R0, default 0), last_sync_at?
sync_log (BOTH)                       -- id autoinc, started_at, finished_at, peer_name, outcome(success|cancelled|failed),
                                      --   notes_in, notes_out, auto_merged*, conflicts_resolved*, error?   (*client only)
                                      --   keep newest 200 rows; failure to write the log MUST NEVER affect the sync
```
- The hub's `server_id` is stored **in the same DB as the data**. If the DB is reset, the id changes, and clients detect "this is a different hub" (see 5.4). This is intentional.
- `revision` MUST be updated in the same transaction as the data change it accounts for.

### 3.3 Where change tracking happens: the repository (single choke point)

All edits go through one repository class so the UI can never forget tracking. On every write:
1. For each field whose value **actually changed**: set `<field>_at = now`.
2. **Hub:** `revision += 1` (once per write), set `<field>_rev = revision` for each changed field.
3. **Client:** add changed field names to `dirty_fields`.
4. If nothing changed -> no-op (no revision bump, no dirty marking).
5. Delete = set `deleted=true` (soft), same tracking as any field.
6. `update(id, edited, base)`: when `base` (the values the editor opened with) is given, **write only fields the user changed relative to `base`**; untouched fields keep their *current stored* value. This is the **editor-safety rule**: a stale open editor must never overwrite changes that arrived from a sync meanwhile. The editor should also refresh untouched fields live from the DB stream and close if its record gets deleted by a sync.

---

## 4. Wire protocol

HTTP/1.1 + JSON, versioned: `/api/v1/...`. Shared Dart DTOs are used by both server and client (single source of truth for the contract). Constants: `protocolVersion = 1`, default port `8765` (fall back to any free port if busy; the QR carries the real port).

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /info` | none | `{serverId, serverName, protocolVersion}` |
| `POST /pair` | none (needs pairing token) | body `{pairingToken, deviceId, deviceName}` -> `{deviceSecret, server}`. `403 invalid_pairing_token` if expired/used/replaced; `400` if malformed (token NOT consumed) |
| `GET /ping` | Bearer | `{server, revision}`; proves pairing still valid (`401` = revoked) |
| `POST /sync/pull` | Bearer | body `{since: R0}` -> `{revision: R1, <records>: [...]}` = every record with **any** field `_rev > since`, **all fields** of each such record, each field as `{value, at, rev}` |
| `POST /sync/push` | Bearer | body `{baseRevision: R1, changes: [...]}` -> `{revision}` or `409 {error:"stale_revision", revision}` |

Auth: `Authorization: Bearer <deviceSecret>` on every non-public route; hub hashes (SHA-256) and looks up a non-revoked device. Missing/unknown/revoked -> `401 unauthorized`.

Errors are always `{"error": "<machine_code>", "message": "<human text>"}`. Machine codes: `bad_request`, `invalid_pairing_token`, `unauthorized`, `stale_revision`.

DTO shapes:
```
Field   { value, at, rev? }            -- rev present in pull responses, absent in pushes
Record  { id, createdAt, fields: { <fieldName>: Field } }
Pull    req { since }                  resp { revision, records[] }   -- pull always carries ALL fields per record
Push    req { baseRevision, changes[] }                              -- changes carry ONLY the pushed (dirty) fields,
                                                                     --   except NEW records which MUST carry all fields
```
Validation: both sides parse values with a per-field type check (`parseWireValue`) and throw a format error on anything unexpected; the hub answers `400` and applies nothing; the client reports "the PC sent data this app cannot read". Unknown field names are rejected. Enums travel by **name**, not index.

Client-side HTTP rules: 6 s timeout; timeout / socket / client exceptions all map to one *Unreachable* error whose message tells the user the likely causes (hub not sharing, different network, firewall). Map `401 -> Unauthorized`, `409 stale_revision -> Stale`, other `>=400 -> Rejected(message)`. All exceptions extend one `SyncException` whose `message` is already written for end users.

---

## 5. Pairing & trust

### 5.1 Hub side
1. User turns **Sharing** on. Hub starts the HTTP server on `0.0.0.0` (all IPv4 interfaces) and shows: LAN IPv4 address(es), port, and a QR code.
2. LAN address discovery: enumerate IPv4 interfaces (no loopback/link-local); keep private ranges (10/8, 172.16/12, 192.168/16); **rank real adapters first and likely-virtual ones last** (regex on interface name: vethernet, virtual, vmware, vbox, hyper-v, wsl, docker, vpn, tap, tun, loopback, bluetooth); within those prefer `192.168.x`. Re-read the list every time the sharing screen opens (network may change). Let the user pick if there are several.
3. QR payload (JSON): `{ "v":1, "host":"192.168.x.x", "port":8765, "serverId":"<uuid>", "pairingToken":"<token>" }`. Decoder MUST validate version, host non-empty, port 1-65535, non-empty strings, and throw a format error ("Not a pairing code") otherwise.
4. **Pairing token**: 16 random bytes (secure RNG, base64url, no padding), **single-use, expires in 5 min, only one valid at a time** (issuing a new one invalidates the old). `consume()` returns true once. After a successful pair the hub immediately issues a fresh token/QR for the next phone. Provide "Show new QR code".
5. On valid `/pair`: store device `{deviceId, name, SHA-256(secret)}`, return a **32-byte random secret**. Pairing again with the same `deviceId` **replaces** the record (old secret dies; revoked phones can come back by re-scanning).
6. Hub UI: list of active paired devices (name, last sync) with **Revoke**. Revoked device gets `401` on next call.

### 5.2 Client side
- Generates and persists a `device_id` (UUID) once. Device name defaults to manufacturer + model.
- Scan QR -> `POST /pair` -> verify `response.server.serverId == qr.serverId` (else reject: "different identity than the QR code") -> store pairing in one transaction.

### 5.3 Re-pairing semantics (important)
- **Same hub again** (new IP, or after revoke): keep `last_synced_revision` and `last_sync_at`; only host/port/secret change.
- **Different hub** (`serverId` differs from `last_server_id`): reset `last_synced_revision = 0`, **mark every record fully dirty** (full push to the new hub), remember the new `last_server_id` — all in the same transaction.
- `unpair()` just deletes the pairing row; data stays on the phone.

### 5.4 Pre-flight before every sync
Client calls `GET /ping` first. Fail early and clearly (before reading or sending anything) when: unreachable, `401` (revoked: "scan the QR code again"), or `ping.server.serverId != pairing.serverId` (different/reset hub).

### 5.5 Security level (accepted for the PoC — state it, don't hide it)
Plain HTTP on a trusted LAN; the bearer secret only stops casual access, not eavesdropping. Android needs `usesCleartextTraffic="true"`. If you need more, add TLS (self-signed cert pinned via the QR payload) — that is an extension, not part of this design.

---

## 6. The sync algorithm

Client-driven, one user-pressed button. Terms: `R0` = `last_synced_revision`; `R1` = hub revision returned by pull; `local` = phone's record; `remote` = hub's record.

### 6.1 Flow (client orchestrator)
```
run(resolver?):
  pairing = load; if none -> error "not paired"
  preflight ping (5.4)
  remembered = {}                                  # conflict choices kept across retries
  for attempt in 1..3:
    pull    = POST /sync/pull {since: R0}          # R1 = pull.revision
    remotes = parse+validate(pull)                 # reject malformed
    locals  = load ALL local records (incl. tombstones)
    plan    = planSync(locals, remotes, since=R0)  # pure function (section 7)
    if plan.hasConflicts:
        choices = decide(plan.conflicts, remembered, resolver)   # may throw Cancelled / ConflictsPending
        plan    = resolveConflicts(plan, choices, since=R0)      # pure function (section 8)
    push = POST /sync/push {baseRevision: R1, changes: buildChanges(plan)}   # ALWAYS sent, even if empty
    on 409 stale_revision: continue                # hub changed meanwhile -> pull again
    commit(plan, locals, newRevision = push.revision)            # ONE local transaction (6.4)
    return summary
  fail "hub kept changing, try again"
every outcome (success/cancelled/failed) is written to sync_log (errors writing the log are swallowed)
```
Key properties:
- **The push is always sent, even when empty.** The hub checks `baseRevision` either way and records `last_sync_at` for that device in the same transaction; this also makes "received-only" syncs consistent and verifies nothing changed during the sync.
- Only one sync at a time (controller flag); the UI blocks editing and navigation while a sync runs.
- If conflicts exist and **no resolver is supplied**, the sync stops with "N conflicts found, nothing changed" (useful for headless/tests).
- Cancel in the resolver = abort the whole sync; **nothing** is applied on either side; the same conflicts re-appear next time.
- Retry memory: a conflict choice is reused on retry only if the conflict's **signature** (the local+remote values it was decided on) is unchanged; otherwise the user is asked again.

### 6.2 Hub: pull
Single read transaction: select records where `any(<field>_rev > since)`; return them with **all** fields + their `rev`, plus current `revision` (R1). Because the snapshot and R1 are read in one transaction, they are consistent.

### 6.3 Hub: push (all-or-nothing, one DB transaction)
```
current = revision
if current != request.baseRevision: return STALE(current)        # -> HTTP 409
new = current + 1
changed = false
for each change:
    values = parse+validate each field (type check, known name)   # FormatException -> 400, whole tx rolled back
    existing = get(id)
    if none:  require ALL fields present (else 400); insert with every field's rev = new; changed = true
    else:     for each field: if value == stored value: skip       # idempotency
                              else write value, at, rev = new; changed = true
if changed: revision = new                                         # ONE bump per push, however many records
mark device last_sync_at = now                                     # even when nothing changed
return APPLIED(changed ? new : current)
```
- Hub never trusts the client's merge decision beyond "these values are final"; it only does equality-skip + revision stamping.
- The hub records a sync-log entry only when a push is **applied**. A stale (409) push is not a finished sync. Log-write errors are swallowed.

### 6.4 Client: commit (one local transaction, only after hub accepted the push)
```
verify nothing was edited since `locals` was read:
    for each planned record: row.updated_at must still equal local.version  else throw SyncInterrupted
        (the hub already has the pushed values; next sync sees them identical on both sides -> nothing lost)
for each record plan:
    isNew  -> insert from remote (all adopted fields)
    else   -> write adopted fields (value+at), clear dirty_fields if plan.clearsDirty
              (adopting does NOT set dirty, and does NOT touch rev columns on the client)
set server_pairing.last_synced_revision = push.revision, last_sync_at = now
```
Note `newRevision = push.revision`: after our own push the hub is at R1+1 and every field we pushed has `rev = R1+1`. Setting R0 = R1+1 means the next pull will not echo our own changes back. If the push changed nothing, `push.revision = R1`.

### 6.5 Concurrency/consistency invariants (MUST hold)
1. Client mutates its DB **only** in `commit`, **after** the hub accepted the push. Network failure at any earlier point = nothing changed anywhere.
2. Hub applies a push in a single transaction. `revision` bump and data writes commit together.
3. A lost push response is safe: next sync pulls the client's own already-applied changes; "both sides changed to the same value" is **not** a conflict (section 7), and re-pushing equal values is ignored.
4. The client version stamp (`updated_at` per record) detects local edits made during the sync. Because the UI is also locked during sync this is defense in depth. *Hardening idea if reused:* use a monotonic per-row counter instead of a millisecond timestamp so two edits in the same millisecond can't look identical.
5. Hub-local edits (user typing on the PC) go through the same repository and bump `revision`; that is exactly what makes a concurrent phone push return `409` and retry.

---

## 7. Merge rules (pure function `planSync`)

Inputs: `locals` (all phone records, with `dirty` sets), `remotes` (only records the hub says changed since R0, each with per-field `rev`), `since = R0`. Output: a `SyncPlan` = list of per-record plans. Define for each field `f` of a record present on both sides:

- `remoteChanged(f) = remote.f.rev > since`
- `localChanged(f)  = f in local.dirty`

Per-record plan fields: `isNew`, `adopt` (field -> value to take from hub), `push` (set of fields to send), `conflicts`, `clearsDirty`, `resolvedConflicts`.

| Situation | Outcome |
|---|---|
| Record only on hub (no local row) | Insert on phone (`isNew`, adopt all fields) — also covers "deleted on hub before this phone ever saw it" |
| Record only on phone, or not reported by hub, and has dirty fields | `push` its dirty fields (new record: all fields), `clearsDirty` |
| Field changed only on hub | `adopt` hub value (skip if already equal) |
| Field changed only on phone | `push` |
| Field changed on both, **equal** values | nothing (no conflict) |
| Field changed on both, **different** values | **FieldConflict** (field is in neither adopt nor push until resolved) |
| Different fields changed on each side | auto-merge: adopt some, push others; counted as `autoMerged` |
| Deleted on both sides | no decision; converge on hub's copy for fields that changed there; clear dirty |
| Deleted on one side, **not edited** on the other | deletion propagates through the ordinary per-field rules (`deleted` is a field) |
| Deleted on one side (this sync), **edited** (any non-`deleted` field changed) on the other | **DeleteEditConflict** (whole-record decision), takes precedence over per-field handling for that record |

Details that matter:
- "Edited" means any *content* field changed, excluding `deleted`.
- `remoteJustDeleted = remote.deleted && remoteChanged(deleted) && !local.deleted` and the mirror for local. Use "just" (changed in this window) so an old tombstone doesn't create a conflict.
- Only compare **values** when both changed; identical outcomes are never conflicts. This is what makes lost-response retries and "both users made the same edit" safe.
- Records not reported by the hub and not dirty -> no plan entry (empty plans are filtered out).
- No clocks anywhere in this function.

Data types (keep them in a separate pure-Dart `merge_models` file): `LocalRecord{id,createdAt,version,fields,dirty}`, `RemoteRecord{id,createdAt,fields(value,at,rev)}`, `FieldState(value, at)`, sealed `Conflict` with `FieldConflict` / `DeleteEditConflict`, `ConflictChoice {keepPhone, keepPc, keepRecord, deleteRecord}`, `RecordPlan`, `SyncPlan` (computed counters: pulled, pushed, autoMerged, resolved).

Each `Conflict` exposes: `key` (`"<id>/<field>"` or `"<id>/record"`), `phoneSide`/`pcSide` choices, `accepts(choice)`, and a `signature` string over the involved local+remote values (used to decide whether an earlier answer is still valid on retry).

---

## 8. Conflict resolution (pure function `resolveConflicts` + UI)

`resolveConflicts(plan, choices, since)` returns a conflict-free plan; every conflict MUST have a valid choice or it throws (`ArgumentError`).

**FieldConflict**
- `keepPhone` -> add field to `push` (hub still has the other value; it will be overwritten).
- `keepPc` -> `adopt[field] = remote value`.

**DeleteEditConflict** — after *either* choice both devices end up with byte-identical records:
- `deleteRecord`: adopt hub's value for every content field that differs (discarded edits leave no difference); if hub isn't deleted, `push deleted=true`; else if phone isn't deleted, adopt hub's `deleted`.
- `keepRecord`: restore the record. Per content field: changed only on hub -> adopt (if differs); changed only on phone -> push; changed on both and differs -> **the side that edited (not the side that deleted) wins**. Then `deleted`: if phone has it deleted, adopt hub's `deleted=false`; else `push deleted=false`.
- "Mine" (`phoneSide`) = whatever the phone did (deleted -> `deleteRecord`; edited -> `keepRecord`); "PC's" is the opposite.

Resolved plans always set `clearsDirty = true` and `resolvedConflicts = n`.

**UI requirements (phone):** list of records in conflict with a count; per-conflict side-by-side **Phone value vs PC value** with each side's last-edit time (this is the only place `_at` is used); per-record and global "Keep all mine / Keep all PC's"; **Apply** enabled only when every conflict has a choice; **Cancel sync** aborts with no changes. Delete-vs-edit shows the edited version with *Keep / Delete* actions. The resolver is injected into the sync client as a callback (`Future<Map<key,choice>?> Function(groups)`, `null` = cancelled), so the client has no UI dependency.

---

## 9. Supporting concerns

**Sync log / history (both roles):** one row per finished attempt with peer name, outcome, counts in/out, `autoMerged` and `conflictsResolved` (phone only — the hub cannot know), error text; prune to the newest 200; log failures never propagate. Hub remembers per device how many records it just served (in-memory map) so the push that completes the sync can log `notesOut`.

**Sync summary after success (phone):** "N pulled, M pushed, K auto-merged, C conflicts resolved", or "nothing changed".

**Status UI:**
- Phone: banner with paired hub name, last sync time, count of unsynced records; per-record badge **Synced / Modified** (`dirty_fields` non-empty).
- Hub: banner showing sharing on/off and number of paired phones; paired list with last-sync times and Revoke.

**Platform requirements:**
- Android: `INTERNET`, `CAMERA` (QR scan), `usesCleartextTraffic=true`.
- Windows hub: first server start triggers the Windows Firewall prompt — user must allow **Private networks** (installer does not add a rule). Phones and PC must be on the same subnet; guest networks / AP "client isolation" block sync; a phone hotspot with the PC joined also works.
- The hub app must be running with Sharing on for any sync to work (accepted limitation).

**Dependency stack used (swap freely; the design is stack-agnostic):** Flutter/Dart; `drift` (+ sqlite) for local DB with schema migrations (`createTable` per version bump); `flutter_riverpod` state; `shelf` + `shelf_router` server; `http` client; `qr_flutter` / `mobile_scanner`; `uuid`; `crypto` (SHA-256); `device_info_plus` (device name); `dart:io` `NetworkInterface`.

**Code layout (feature-first, sync isolated):**
```
lib/core/db/            schema (Drift), migrations, enums
lib/features/<domain>/  repository (the choke point for change tracking), UI
lib/sync/protocol/      protocol.dart (paths, error codes, info/pair/ping DTOs), sync_dtos.dart, pairing_qr.dart
lib/sync/merge/         merge_models.dart, merge.dart (planSync), resolve.dart (resolveConflicts)   <- PURE
lib/sync/<codec>.dart   record <-> wire DTO <-> merge-model conversions, field parse/validation, writeField
lib/sync/server/        hub_server.dart (shelf routes + auth middleware), hub_sync_service.dart (pull/push),
                        device_registry.dart, pairing_tokens.dart, hub_identity.dart, lan_addresses.dart, providers
lib/sync/client/        hub_api.dart (HTTP + exception types), pairing_service.dart, sync_store.dart (local DB ops),
                        sync_client.dart (orchestrator), providers (SyncController with "running" flag)
lib/sync/sync_log.dart  history repository
```
Testability seams worth copying: `HubServer.handler` is a plain shelf `Handler` testable without a socket (`start()` only binds it); clocks are injectable (`clock:` params) in repositories, token store, registry, store; `SyncClient` takes an injectable `http.Client` and a `beforePush` test hook (to simulate a concurrent edit between merge and push); the conflict resolver is a callback.

---

## 10. Test plan (reproduce these)

Automated (unit/integration, no real network needed):
1. **Merge (pure):** record new on each side; unchanged on both; same field edited on both with different values (conflict) and equal values (no conflict); different fields edited (auto-merge); delete vs untouched (propagates); delete vs edit both directions (conflict); delete on both; enum/bool fields as conflicts too; hub deleted a record phone never saw.
2. **Resolve (pure):** every choice for field conflicts; all four delete/edit combinations -> both sides end identical; invalid/missing choice throws.
3. **Idempotency:** applying the same sync twice yields the same result; re-pushing equal values changes nothing and does not bump `revision`.
4. **Hub service:** push with stale `baseRevision` -> stale and nothing applied; malformed push (unknown field, wrong type, new record missing fields) -> 400 and **nothing applied (rollback)**; one revision bump per push regardless of record count; empty push still updates device `last_sync_at`.
5. **Server routes (via `handler`, no socket):** public vs authed routes; missing/wrong/revoked bearer -> 401; pairing token single-use, expiry, replacement; re-pair same device id replaces secret.
6. **Pairing flow:** QR encode/decode validation; serverId mismatch rejected; re-pair same hub keeps R0; different hub resets R0 and marks all dirty.
7. **Full client<->hub sync flow** (two in-memory DBs, real HTTP client against `handler`): union after first sync; auto-merge; conflict resolved each way converges both DBs to equal; cancel leaves both DBs unchanged; concurrent hub edit between pull and push (use `beforePush`) triggers retry and converges; retries exhausted -> clean failure; local edit during sync -> `SyncInterrupted`, no loss.
8. **Repository:** only changed fields get `_at`/`_rev`/dirty; no-op edit does nothing; editor `base` rule (stale editor doesn't clobber); `markAllDirty`.
9. **DB migration:** upgrade from each prior schema version.
10. **Sync log:** pruning to 200; log failure doesn't break sync.

Manual acceptance scenarios:
1. Create data on both devices offline, pair, sync -> both show the union.
2. Edit field A on phone and field B on PC of the same record -> both kept, no conflict.
3. Edit same field on both -> conflict UI; try each option; devices end equal.
4. Delete on phone, edit on PC (and reverse) -> delete-vs-edit conflict.
5. Cancel in conflict UI -> nothing changed anywhere; next sync shows same conflicts.
6. Two phones: A syncs, then B -> B gets A's changes via the PC.
7. Edit on PC while a phone is mid-sync -> phone retries, result consistent.
8. Revoke a phone -> its next sync says pairing revoked.
9. Disable Wi-Fi mid-sync -> clean failure, no partial data.
10. Reset the hub DB -> phone detects different `serverId`, forces re-pair + full push.

---

## 11. Known limitations & pitfalls (carry these forward knowingly)

- Tombstones are never purged (DB grows). Purging safely needs per-client acknowledgment; out of scope.
- Editing is blocked on the phone during a sync (simple, safe). Removing the lock relies entirely on the `version` check in commit.
- A single synced field is atomic: two concurrent edits to one long text are a conflict, not a text merge. If you need merging inside text, that is a CRDT/OT project — do not bolt it on here.
- Plain HTTP; trusted network only.
- Pull returns whole records (all fields) for any changed record, and the client loads all local records into memory for planning: fine for thousands of records, revisit (pagination, indexed dirty lookup) for hundreds of thousands. Pull is a single response; large initial syncs / attachments/binary data are **not** handled (add chunked pull and a separate blob channel keyed by content hash if needed).
- Hub must be running and reachable; there is no queueing on the hub side.
- Hub `revision` is a single global counter => hub-local edits and pushes serialize through it. Fine for a single-PC, few-phones topology.
- Windows Firewall prompt and Wi-Fi client isolation are the #1 real-world "sync doesn't work" causes — surface them in the unreachable-error message (already done in `HubUnreachable`).
- A client that has been offline long needs no special handling: R0 is just an integer; the pull returns everything since.
- Don't use device time to decide anything. If you ever find yourself comparing `_at` values to choose a winner, you are breaking the core design.

---

## 12. Adaptation checklist for a new app

1. **Define the synced entities and their fields.** For each entity decide field granularity (what merges independently). Include `deleted`. Give every entity a UUID id, `created_at`, `updated_at`, and per-field `_at` (+ `_rev` on hub, + `dirty_fields` on client). Multiple entity types: either one revision counter shared across all (recommended: still a single R0) with each table carrying `_rev` columns, and the pull/push DTOs carrying a `type` discriminator; or a generic `(entity, id, field)` store.
2. **Relationships between entities:** reference by UUID. Decide per relationship what happens to children of a deleted parent (cascade by tombstoning children as ordinary field changes so they sync) and how a child referencing a not-yet-synced parent is ordered (push parents first, or tolerate dangling ids until the parent arrives; the hub applying a push in one transaction removes ordering problems within a single push).
3. **Put all writes through one repository** that implements 3.3 for both roles. Make it impossible for UI code to write tables directly.
4. **Copy the protocol (section 4) as-is**; replace the record DTO and `note_codec` equivalents (per-field type validation, `writeField`, wire-name enums) for your fields.
5. **Port the pure modules** `merge_models`, `planSync`, `resolveConflicts` with your field list. Keep them free of Flutter/DB imports. Update the "content fields" list (everything except `deleted`).
6. **Implement hub** (server, auth middleware, pairing tokens, device registry, identity, LAN addresses, sync service) and **client** (HTTP wrapper with user-readable exceptions, pairing service, sync store, sync client) exactly per sections 5-6.
7. **UI:** Sharing screen (hub): on/off, address picker, QR, new-QR, paired devices + revoke. Sync screen (phone): pair/scan, test connection, Sync button with progress, summary, error text. Conflict screen per section 8. Status banner and per-record Synced/Modified badge. Sync history screen.
8. **Platform setup:** Android permissions + cleartext; document the firewall prompt; same-subnet requirement.
9. **Write the tests in section 10 before declaring done**, especially the end-to-end flow tests with `beforePush` concurrency injection and the rollback-on-malformed-push test.
10. **Verify the invariants in 6.5** by review: client writes only in commit; hub push is one transaction including the revision bump; no clock comparisons; push always sent; stale -> retry <= 3.

### Minimal pseudo-API surface to build (names are suggestions)
```
Repository.create/update(id, edited, base?)/delete(id)/markAllDirty()/currentRevision()
planSync(locals, remotes, since) -> SyncPlan
resolveConflicts(plan, choices, since) -> SyncPlan
HubSyncService.pull(since, deviceId) / push(deviceId, PushRequest) -> Applied|Stale|Invalid
HubServer(identity, registry, tokens, currentRevision, sync, onPaired).handler / start / stop
DeviceRegistry.addDevice/authenticate/revoke/markSynced/watchActive
PairingTokens.issue/consume/clear
HubApi.info/pair/ping/pull/push           // throws SyncException subclasses
PairingService.pair(qr)/unpair/checkConnection/current
SyncStore.loadAll/buildChanges(plan, locals)/commit(plan, locals, newRevision)
SyncClient.run(resolver?) -> SyncSummary
```
