defmodule LogflareEx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    env = Application.get_env(:logflare_ex, :env)

    children = get_children(env)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LogflareEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_children(:test) do
    [
      LogflareEx.Repo,
      {Registry, keys: :unique, name: LogflareEx.BatcherRegistry},
      {Finch, name: LogflareEx.Finch}
    ]
  end

  defp get_children(_) do
    [
      LogflareEx.Repo,
      {DynamicSupervisor, name: LogflareEx.BatcherSup},
      {Registry, keys: :unique, name: LogflareEx.BatcherRegistry},
      {Finch, name: LogflareEx.Finch}
    ]
  end
end
