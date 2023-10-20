defmodule LogflareEx.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LogflareEx.Repo,
      {PartitionSupervisor, child_spec: LogflareEx.Batcher, name: LogflareEx.BatcherSup},
      {Finch, name: LogflareEx.Finch}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LogflareEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
