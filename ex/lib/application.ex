defmodule WarehouseEx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    env = Application.get_env(:warehouse_ex, :env)

    children = get_children(env)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WarehouseEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_children(:test) do
    [
      WarehouseEx.Repo,
      {Registry, keys: :unique, name: WarehouseEx.BatcherRegistry},
      {Finch, name: WarehouseEx.Finch}
    ]
  end

  defp get_children(_) do
    [
      WarehouseEx.Repo,
      {DynamicSupervisor, name: WarehouseEx.BatcherSup},
      {Registry, keys: :unique, name: WarehouseEx.BatcherRegistry},
      {Finch, name: WarehouseEx.Finch}
    ]
  end
end
