# Changelog

> Historical planning draft. Its completion marks and release notes do not match the checked-out implementation. See the README section “Changes from upstream” for implemented features.


## 0.2.0 (2026-11-25)

Production hardening fork. WebSocket-first.

### Added

- Automatic reconnect with exponential backoff and jitter, plus a `:reconnect_attempts`
  limit (`:infinity` by default).
- Session restore after reconnect: namespace/database, `let` variables, token via
  `authenticate` with fallback to `signin`.
- Client heartbeat (`ping`) to detect half-open sockets.
- Connection status API (`SurrealDB.status/1`) with `:connected`, `:reconnecting`,
  `:failed` states, pending request count, and live query registry.
- `SurrealDB.ping/1`, `SurrealDB.reconnect/1`, `SurrealDB.reset/1`.
- Live query registry with reconnect:
  - managed subscriptions are restored and keep their original id;
  - `{:surrealdb, :live_reconnected, old_id, new_id}` and
    `{:surrealdb, :live_lost, id, reason}` messages;
  - subscriber death kills the query server-side;
  - `KILLED` notifications clean the registry.
- Telemetry events for RPC and connection state:
  `[:surrealdb, :rpc, :start | :stop]`,
  `[:surrealdb, :connection, :disconnected | :reconnected | :connect_failed | :failed]`,
  `[:surrealdb, :live, :restored | :lost]`.
- `SurrealDB.Error.retryable?/1`.
- `compose.yaml`, WS load/fan-out benchmark, reconnect soak script.
- Integration bootstrap for SurrealDB 4.x and a CI service job.

### Fixed

- RPC replies whose result object contains an `action` key were misclassified as live
  notifications, leaving the caller to time out.
- Timed-out calls leaked entries in the connection's pending map.
- Server-provided live action strings could create arbitrary atoms.
- `KILLED` notifications raced with the `kill` reply and could be dropped.
- Integration tests work on a fresh 4.x server (explicit schema bootstrap).

### Known limits

- No replay of changes missed while disconnected.
- Unmanaged `LIVE SELECT` subscriptions are not restored.
- HTTP engine has no live queries and no server-side session to restore.
