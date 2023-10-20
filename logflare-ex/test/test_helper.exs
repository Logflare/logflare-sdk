{:ok, _} = Application.ensure_all_started(:ex_machina)

Mimic.copy(Tesla)
Mimic.copy(LogflareEx.TestUtils)
ExUnit.start(exclude: [:benchmark])
