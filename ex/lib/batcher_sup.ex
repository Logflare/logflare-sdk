defmodule WarehouseEx.BatcherSup do
  # Automatically defines child_spec/1
  use DynamicSupervisor
  alias WarehouseEx.Batcher
  alias WarehouseEx.Client
  require Logger

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def count_batchers do
    %{workers: count} = DynamicSupervisor.count_children(__MODULE__)
    count
  end

  def ensure_started(%Client{} = client) do
    client
    |> start_batcher()
    |> then(fn
      {:error, {:already_started, _pid}} ->
        :ok

      {:ok, _pid} ->
        :ok

      err ->
        Logger.error("Could not ensure that batcher was started, error: #{inspect(err)}")
        {:error, :not_started}
    end)
  end

  def start_batcher(opts) when is_list(opts) do
    client = Client.new(opts)
    start_batcher(client)
  end

  def start_batcher(%Client{} = client) do
    DynamicSupervisor.start_child(__MODULE__, {Batcher, client})
  end

  def terminate_batchers do
    for {_id, pid, _, _args} <- DynamicSupervisor.which_children(__MODULE__) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end

    :ok
  end
end
