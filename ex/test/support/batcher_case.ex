defmodule LogflareEx.BatcherCase do
  use ExUnit.CaseTemplate, async: false
  alias LogflareEx.Batcher

  using do
    quote do
      use Mimic
      import LogflareEx.Factory
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
