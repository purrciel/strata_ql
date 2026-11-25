# Use MIX_ENV=test for the in-memory transport, or set SURREALDB_URL for a server.
count = String.to_integer(System.get_env("REQUESTS", "20000"))
concurrency = String.to_integer(System.get_env("CONCURRENCY", "64"))
if min(count, concurrency) < 1, do: raise("REQUESTS and CONCURRENCY must be positive")

{mode, opts} =
  case System.get_env("SURREALDB_URL") do
    nil ->
      {"mock",
       [
         url: "ws://mock/rpc",
         engine: SurrealDB.Engine.Mock,
         responder: fn "query", [_, %{"n" => n}] ->
           {:ok, [%{"status" => "OK", "result" => n}]}
         end
       ]}

    url ->
      auth =
        case System.get_env("SURREALDB_USER") do
          nil -> nil
          user -> %SurrealDB.Auth.Root{user: user, pass: System.fetch_env!("SURREALDB_PASS")}
        end

      {"server",
       [
         url: url,
         namespace: System.get_env("SURREALDB_NS"),
         database: System.get_env("SURREALDB_DB"),
         auth: auth
       ]}
  end

{:ok, db} = SurrealDB.start_link(opts)
started = System.monotonic_time(:microsecond)

samples =
  Task.async_stream(
    1..count,
    fn n ->
      {elapsed, reply} = :timer.tc(fn -> SurrealDB.query(db, "RETURN $n", %{n: n}) end)
      if reply == {:ok, [n]}, do: {:latency, elapsed}, else: :failed
    end, max_concurrency: concurrency, ordered: false, timeout: 35_000, on_timeout: :kill_task)
  |> Enum.to_list()

elapsed = System.monotonic_time(:microsecond) - started
latencies = for {:ok, {:latency, us}} <- samples, do: us
sorted = Enum.sort(latencies)
success = length(sorted)

IO.inspect(%{
  mode: mode,
  requests: count,
  concurrency: concurrency,
  errors: count - success,
  successful_rps: round(success * 1_000_000 / elapsed),
  latency_us:
    for(p <- [50, 95, 99], into: %{}, do: {p, Enum.at(sorted, ceil(success * p / 100) - 1)})
})

SurrealDB.close(db)
if success != count, do: System.halt(1)
