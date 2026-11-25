defmodule SurrealDB.Transaction do
  @moduledoc "A transaction on one connection. Obtain a handle with SurrealDB.begin/1."
  @enforce_keys [:connection, :id]
  defstruct [:connection, :id]
  @type t :: %__MODULE__{connection: pid(), id: term()}
end
