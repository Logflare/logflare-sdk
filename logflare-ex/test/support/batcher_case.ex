defmodule LogflareEx.BatcherCase do
  use ExUnit.CaseTemplate, async: false
  use Mimic
  alias LogflareEx.Batcher

  using do
    quote do
      import LogflareEx.Factory
    end
  end

  setup :set_mimic_global
  setup :verify_on_exit!

  # batcher cleanup
  setup do
    on_exit(fn ->
      Batcher.delete_all_events()
    end)
  end
end
