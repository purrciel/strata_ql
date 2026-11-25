defmodule StrataQLTest do
  use ExUnit.Case, async: true
  alias SurrealDB.Codec.CBOR

  test "transaction scope follows the handle, including on interleaved calls" do
    responder = fn
      %{"method" => "begin"} ->
        {:ok, "tx1"}

      %{"method" => "select"} = frame ->
        {:ok, Map.get(frame, "txn", "outside")}

      %{"method" => method, "params" => ["tx1"]} = frame when method in ["commit", "cancel"] ->
        refute Map.has_key?(frame, "txn")
        {:ok, nil}

      %{"method" => "ping"} ->
        {:ok, nil}

      %{"method" => "query", "txn" => "tx1"} ->
        {:ok, [%{"status" => "ERR", "result" => "bad query"}]}

      %{"method" => "info"} ->
        {:ok, %{"action" => "normal RPC data"}}
    end

    db =
      start_supervised!(
        {SurrealDB.Connection,
         url: "ws://mock", engine: SurrealDB.Engine.Mock, responder: responder}
      )

    assert {:ok, nil} = SurrealDB.ping(db)
    assert {:ok, %{"action" => _}} = SurrealDB.info(db)
    assert {:ok, tx} = SurrealDB.begin(db)
    assert {:ok, "tx1"} = SurrealDB.select(tx, "example")
    assert {:ok, "outside"} = SurrealDB.select(db, "example")
    assert_raise SurrealDB.Error, fn -> SurrealDB.query!(tx, "invalid") end
    assert {:ok, nil} = SurrealDB.cancel(tx)
    assert {:ok, tx} = SurrealDB.begin(db)
    assert {:ok, nil} = SurrealDB.commit(tx)
  end

  test "CBOR set tag and unknown live actions" do
    set = MapSet.new([1])
    assert IO.iodata_to_binary(CBOR.encode(set)) == <<0xD8, 56, 0x81, 1>>
    assert CBOR.decode(<<0xD8, 56, 0x81, 1>>) == {:ok, set}
    assert SurrealDB.RPC.action("NEW_EVENT") == "NEW_EVENT"
  end
end
