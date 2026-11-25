# Production readiness TODO

> Historical planning draft. Its completion marks and release notes do not match the checked-out implementation. See the README section “Changes from upstream” for implemented features.


Fork of `surrealdb.elixir` hardened for long-running WebSocket services.
Order is priority. Items marked `[x]` are implemented in this fork; the rest are
deliberately out of scope for the first production cut.

## P0 — correctness and availability (must have)

- [x] Route RPC replies by pending id before treating a message as a live notification.
      Previously any single-object reply containing an `action` field (`run`, `info`)
      was swallowed as a live event and the caller timed out.
- [x] Request timeouts owned by the connection: a timed-out call is removed from
      `pending` instead of leaking until a reply that may never arrive.
- [x] Reconnect with exponential backoff and jitter for `ws`/`wss` (and HTTP).
- [x] Session restore after reconnect: namespace/database, `let` variables, token
      (`authenticate`, falling back to `signin` with the connect-time auth).
- [x] Heartbeat (`ping` RPC) with a timeout, so half-open sockets are detected and
      replaced instead of silently black-holing calls.
- [x] Live query lifecycle:
  - managed `live/3` subscriptions are restored on reconnect and keep their
    user-facing id (`{:surrealdb, :live, original_id, ...}` keeps matching);
  - `{:surrealdb, :live_reconnected, old_id, new_id}` and
    `{:surrealdb, :live_lost, id, reason}` events;
  - subscriber `:DOWN` removes the subscription and kills it server-side;
  - `KILLED` notifications are delivered once and clean the registry;
  - `kill/2` accepts the original id across reconnects.
- [x] Permanent failures (bad credentials, missing namespace/database) put the
      connection into `:failed` instead of reconnecting forever; `reconnect/1`
      retries manually.
- [x] Fail fast with `kind: :connection` while reconnecting/restoring; no silent
      queuing of writes.
- [x] Optional telemetry events for RPC, connection state, and live queries.
- [x] No atom creation from server-provided action strings.
- [x] Integration bootstrap for SurrealDB 4.x (`DEFINE NAMESPACE/DATABASE/TABLE`),
      works on a fresh server.
- [x] WS load, live fan-out, and reconnect soak scripts (`bench/`).
- [x] CI runs the integration suite against a pinned SurrealDB service.

## P1 — feature parity with the current server (should have)

- [ ] `begin`/`commit`/`cancel` interactive transactions and the request `txn` field.
- [ ] `query` options (`read_only`, `trace`) and `query_stream`/`query_cancel`.
- [ ] `ping`, `reset` (implemented as RPC helpers), `mysql`, `pgsql`.
- [ ] CBOR v2 negotiation (`cbor.2`): sized numbers 180–188, date/time/timestamp/
      interval/bigdecimal/regex tags 100, 189–193.
- [ ] `File` (tag 55), `Set` (tag 56), shaped results (tag 57).
- [ ] Correct `Future` (tag 15) round-trip: the server expects an object wrapping the
      uncomputed query; current code sends `nil`.
- [ ] `export` options (`POST /export` body), `kvexport`, TLS/base-path options for
      the REST helpers.
- [ ] Refresh-token / cookie authentication.
- [ ] Multiple sessions and connection pooling (one OS process per session today).

## P2 — operations and DX (nice to have)

- [ ] Async connect (`start_link` succeeds while the server is down) and readiness
      state separate from connection status.
- [ ] Bounded request queue while reconnecting, with per-call deadlines.
- [ ] Protocol/capabilities handshake (`GetCapabilities`) and message-size limits.
- [ ] gRPC and embedded engines.
- [ ] Structured logging and optional OpenTelemetry spans.
- [ ] Hex release (package rename/ownership decision) and docs deployment.
- [ ] Dialyzer and a transport-level property test suite.

## Verification

- `mix test` — hermetic unit tests (mock engine).
- `podman compose up -d --wait && mix test --include integration` — real server.
- `mix run bench/ws_load.exs` — WS throughput, latency percentiles, live fan-out.
- `mix run bench/soak.exs` — reconnect/status timeline; stop and start the server
  while it runs.

## Known limits (documented, accepted)

- Changes made while the socket is down are lost; live queries have no replay.
- A live query started with `LIVE SELECT` is unmanaged: it is not restored and is
  reported as `:live_lost` on reconnect.
- One connection owns one namespace/database/token tuple.
- The HTTP engine restores transport only; there is no server-side session to restore.
