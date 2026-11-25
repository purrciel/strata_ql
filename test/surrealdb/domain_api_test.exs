defmodule SurrealDB.DomainAPITest do
  use ExUnit.Case, async: true
  alias SurrealDB.Error

  defp db(responder) do
    start_supervised!(
      {SurrealDB.Connection,
       url: "ws://mock", engine: SurrealDB.Engine.Mock, responder: responder}
    )
  end

  test "read helpers validate statement shape, cardinality and later statement errors" do
    db =
      db(fn "query", [_, %{"results" => results}] ->
        {:ok,
         Enum.map(results, fn
           "failure" -> %{"status" => "ERR", "result" => "bad statement"}
           value -> %{"status" => "OK", "result" => value}
         end)}
      end)

    for rows <- [[], [nil], [%{"id" => 1}], [1, 2]] do
      assert {:ok, ^rows} = SurrealDB.all(db, "query", %{results: [rows]})

      case rows do
        [] ->
          assert :error = SurrealDB.fetch_one(db, "query", %{results: [rows]})

        [one] ->
          assert {:ok, ^one} = SurrealDB.fetch_one(db, "query", %{results: [rows]})

        _ ->
          assert {:error, %Error{kind: :cardinality, details: %{actual: 2}}} =
                   SurrealDB.fetch_one(db, "query", %{results: [rows]})
      end
    end

    for reader <- [&SurrealDB.all/3, &SurrealDB.fetch_one/3] do
      for results <- [[], [42], [[], []]] do
        assert {:error, %Error{kind: :result_shape}} = reader.(db, "query", %{results: results})
      end

      assert {:error, %Error{kind: :rpc}} = reader.(db, "query", %{results: [[], "failure"]})
    end
  end

  test "callback selects commit or cancel and preserves nonlocal exits" do
    owner = self()

    db =
      db(fn method, _ ->
        send(owner, method)
        {:ok, "tx"}
      end)

    assert {:ok, 42} =
             SurrealDB.transaction(db, fn tx ->
               assert {:error, %Error{kind: :unsupported}} =
                        SurrealDB.transaction(tx, fn _ -> flunk() end)

               {:ok, 42}
             end)

    assert_received "commit"
    assert {:error, :empty} = SurrealDB.transaction(db, fn _ -> {:error, :empty} end)
    assert_received "cancel"
    assert_raise ArgumentError, fn -> SurrealDB.transaction(db, fn _ -> :ok end) end
    assert_received "cancel"
    assert_raise RuntimeError, "bad", fn -> SurrealDB.transaction(db, fn _ -> raise "bad" end) end
    assert_received "cancel"
    assert :signal = catch_throw(SurrealDB.transaction(db, fn _ -> throw(:signal) end))
    assert_received "cancel"
    assert :signal = catch_exit(SurrealDB.transaction(db, fn _ -> exit(:signal) end))
    assert_received "cancel"
  end

  test "lost commit reply yields unknown outcome without retrying the callback" do
    owner = self()

    db =
      db(fn
        "begin", _ -> {:ok, "tx"}
        "commit", _ -> exit(:normal)
      end)

    assert {:error, %Error{kind: :transaction_unknown}} =
             SurrealDB.transaction(db, fn _ ->
               send(owner, :called)
               {:ok, :done}
             end)

    assert_received :called
    refute_received :called
  end

  test "a rejected cancel retains the domain reason and server error" do
    db =
      db(fn
        "begin", _ -> {:ok, "tx"}
        "cancel", _ -> {:error, %{"message" => "cancel failed"}}
      end)

    assert {:error,
            %Error{kind: :cancel_failed, details: %{reason: :empty, cause: %Error{kind: :rpc}}}} =
             SurrealDB.transaction(db, fn _ -> {:error, :empty} end)
  end
end
