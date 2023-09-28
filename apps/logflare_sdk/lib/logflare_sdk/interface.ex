defmodule LogflareSdk.Interface do
  @moduledoc false

  @callback gen_ingest() :: String.t()
  @callback gen_query() :: String.t()
end
