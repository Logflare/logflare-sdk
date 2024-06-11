{:ok, _} = Application.ensure_all_started(:ex_machina)

Mimic.copy(Tesla)
Mimic.copy(WarehouseEx.TestUtils)
ExUnit.start(exclude: [:benchmark])
