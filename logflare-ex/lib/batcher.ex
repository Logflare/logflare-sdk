defmodule LogflareEx.Batcher do
  @moduledoc """
  Batching cache is an Etso repo, `LogflareEx.Repo`, and stores all events to be sent to the Logflare service.

  There are 2 states that an event can be in:
  - pending
  - inflight

  If an event is inflight, it will have an `:inflight_at` timestamp stored on the struct.
  """
  use GenServer

  import Ecto.Query
  alias LogflareEx.BatchedEvent
  alias LogflareEx.Repo

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
  Deletes all events in the cache, regardless of the status.
  """
  @spec delete_all_events() :: :ok
  def delete_all_events do
    Repo.delete_all(BatchedEvent)
    :ok
  end

  @doc """
  Deletes a single event in the cache.

  ### Example

  ```elixir
  iex> delete_event(event)
  {:ok, %BatchedEvent{...}}
  ```
  """
  def delete_event(%BatchedEvent{} = event) do
    Repo.delete(event)
  end

  # GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_) do
    {:ok, %{}}
  end

  # # GenServer
  # @impl true
  # def handle_call(:pop, _from, [head | tail]) do
  #   {:reply, head, tail}
  # end

  # @impl true
  # def handle_cast({:push, element}, state) do
  #   {:noreply, [element | state]}
  # end
end
