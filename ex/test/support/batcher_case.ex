defmodule WarehouseEx.BatcherCase do
  use ExUnit.CaseTemplate, async: false
  alias WarehouseEx.Batcher

  using do
    quote do
      use Mimic
      import WarehouseEx.Factory
      setup :set_mimic_global
      setup :verify_on_exit!
    end
  end

  # batcher cleanup
  setup do
    on_exit(fn ->
      Batcher.delete_all_events()
    end)
  end
end
