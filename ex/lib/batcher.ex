defmodule WarehouseEx.Batcher do
  @moduledoc """
  Batching cache is an Etso repo, `WarehouseEx.Repo`, and stores all events to be sent to the Logflare service.

  There are 2 states that an event can be in:
  - pending
  - inflight

  If an event is inflight, it will have an `:inflight_at` timestamp stored on the struct.
  """
  use GenServer

  import Ecto.Query
  alias WarehouseEx.BatchedEvent
  alias WarehouseEx.BatcherRegistry
  alias WarehouseEx.Client
  alias WarehouseEx.Repo

  # API

  @doc """
  Creates an event in the batching cache. This event will be considered as pending if it does not have an `:inflight_at` value set.

  An event should only be created after all payload manipulations has been performed. The payload will be stored on the `:body` key.

  All timestamp fields internally on the struct are NaiveDateTime.

  Required fields:
  - :body
  - :source_token or :source_name
  """
  @spec create_event(map()) :: {:ok, BatchedEvent.t()}
  def create_event(attrs) do
    %BatchedEvent{created_at: NaiveDateTime.utc_now()}
    |> BatchedEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists all events within the cache. All arguments provided are considered additive filters.

  ### Example
  ```elixir
  list_events_by(:pending)
  list_events_by(:all)
  list_events_by(:inflight)
  list_events_by(:all, source_token: "...")
  list_events_by(:all, source_name: "...")
  list_events_by(:all, source_name: "...", limit: 5)
  ```

  ### Limitations

  Etso does not support the Ecto.Query `:limit` option, hence filtering is done post result fetch.
  """
  @typep list_opts :: [
           {:source_name, String.t()}
           | {:source_token, String.t()}
           | {:limit, non_neg_integer()}
         ]
  @typep status_filter :: :all | :pending | :inflight
  @spec list_events_by(status_filter(), list_opts()) :: [BatchedEvent.t()]
  def list_events_by(type, opts \\ []) when type in [:all, :pending, :inflight] do
    opts =
      Enum.into(opts, %{
        source_name: nil,
        source_token: nil,
        limit: nil
      })

    from(e in BatchedEvent)
    |> then(fn
      q when type == :pending -> where(q, [e], is_nil(e.inflight_at))
      q when type == :inflight -> where(q, [e], not is_nil(e.inflight_at))
      q -> q
    end)
    |> then(fn
      q when opts.source_token != nil -> where(q, [e], e.source_token == ^opts.source_token)
      q when opts.source_name != nil -> where(q, [e], e.source_name == ^opts.source_name)
      q -> q
    end)
    |> Repo.all()
    |> then(fn
      data when opts.limit != nil ->
        Enum.take(data, opts.limit)

      data ->
        data
    end)
  end

  @doc """
  Updates the event within the batching cache.
  """
  @spec update_event(BatchedEvent.t(), map()) :: {:ok, BatchedEvent.t()}
  def update_event(event, attrs) do
    event
    |> BatchedEvent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes all events in the cache, regardless of the status.
  """
  @spec delete_all_events() :: :ok
  def delete_all_events do
    Repo.delete_all(BatchedEvent)
    :ok
  end

  @doc """
  Performs a flush for the given source.

  Accepts the following filters: `:source_name` or `:source_token`

  Flush is performed asyncronously.
  """
  @typep kw_filter :: [{:source_name, String.t()} | {:source_token, String.t()}]
  @spec flush(kw_filter()) :: :ok
  def flush(%Client{source_name: source_name}), do: flush(source_name: source_name)
  def flush(%Client{source_token: source_token}), do: flush(source_token: source_token)

  def flush(kw) do
    kw
    |> via()
    |> GenServer.cast(:flush)
  end

  @doc """
  Deletes a single event in the cache.

  ### Example

  ```elixir
  iex> delete_event(event)
  {:ok, %BatchedEvent{...}}
  ```
  """
  @spec delete_event(BatchedEvent.t()) :: {:ok, BatchedEvent.t()}
  def delete_event(%BatchedEvent{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns the via for each partitioned Batcher. Accepts a `source_token` or `source_name` filter or a `%WarehouseEx.Client{}` struct.

  ### Example

  ```elixir
  via(source_name: "my source")
  via(source_token: "some-uuid")
  via(%WarehouseEx.Client{...})
  ```
  """
  @spec via(Client.t() | kw_filter()) :: identifier()
  def via(%Client{source_token: "" <> token}), do: via(source_token: token)
  def via(%Client{source_name: "" <> name}), do: via(source_name: name)
  def via(source_name: name), do: {:via, Registry, {BatcherRegistry, {:source_name, name}}}
  def via(source_token: token), do: {:via, Registry, {BatcherRegistry, {:source_token, token}}}

  # GenServer

  def start_link(opts) when is_list(opts) do
    opts
    |> Client.new()
    |> start_link()
  end

  def start_link(%Client{} = client) do
    GenServer.start_link(__MODULE__, client, name: via(client))
  end

  @impl GenServer
  def init(%Client{source_name: name, source_token: token} = client) do
    partition_key =
      cond do
        token != nil -> {:source_token, token}
        name != nil -> {:source_name, name}
        true -> nil
      end

    state = %{
      client: client,
      key: partition_key
    }

    schedule_flush(state)
    {:ok, state}
  end

  @impl GenServer
  def handle_cast(:flush, state) do
    flush_events(state)
    {:noreply, state}
  end

  # Flushes the cache of all items matching the Batcher's key.
  @impl GenServer
  def handle_info(:flush, state) do
    flush_events(state)
    schedule_flush(state)
    {:noreply, state}
  end

  defp flush_events(state) do
    events =
      case state.key do
        {:source_name, name} ->
          list_events_by(:pending, source_name: name, limit: state.client.batch_size)

        {:source_token, token} ->
          list_events_by(:pending, source_token: token, limit: state.client.batch_size)
      end

    event_ids = for e <- events, do: e.id

    batch =
      for event <- events do
        {:ok, e} = update_event(event, %{inflight_at: NaiveDateTime.utc_now()})
        e.body
      end

    # Task to send batch
    Task.start_link(fn ->
      WarehouseEx.send_events(state.client, batch)
      Repo.delete_all(from(e in BatchedEvent, where: e.id in ^event_ids))
    end)

    :ok
  end

  defp schedule_flush(%{client: %{auto_flush: false}} = state), do: state

  defp schedule_flush(state) do
    Process.send_after(self(), :flush, state.client.flush_interval)
    state
  end
end
