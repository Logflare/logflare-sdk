defmodule LogflareEx do
  alias LogflareEx.Client
  alias LogflareEx.Batcher
  alias LogflareEx.BatchedEvent
  alias LogflareEx.Repo
  alias LogflareEx.BatcherSup

  @moduledoc """
  Documentation for `LogflareEx`.
  """

  @doc """
  Creates a client for interacting with Logflare.

  See `LogflareEx.Client`.
  """

  defdelegate client(opts), to: __MODULE__.Client, as: :new

  @doc """
  Send a singular event to Logflare.

  See `send_events/2`

  No local caching is performed. This is less efficient than batching events.
  """
  @spec send_event(Client.t(), map()) :: {:ok, map()} | {:error, Tesla.Env.t()}
  def send_event(client, %{} = event) do
    send_events(client, [event])
  end

  @doc """
  Sends events directly to the Logflare API without local caching. All batching configurations on the client will be ignored.

  It is advised to use `send_batched_events/2` instead to spread out API requests.

  ### Example

  ```elixir
  iex> client = LogflareEx.client()
  %LogflareEx.Client{...}

  # singular event
  iex> LogflareEx.send_event(client, %{my: "event"})
  {:ok, %{"message"=> "Logged!}}

  # multiple events
  iex> LogflareEx.send_events(client, [%{my: "event"}, ...])
  {:ok, %{"message"=> "Logged!}}

  # a tesla result will be returned on error
  iex> client |> LogflareEx.send_event(%{my: "event"})
  {:error, %Tesla.Env{...}}

  ```
  """
  @spec send_events(Client.t(), [map()]) :: {:ok, map()} | {:error, Tesla.Env.t()}
  def send_events(_client, []), do: {:error, :no_events}

  def send_events(%Client{source_token: nil, source_name: nil}, _batch), do: {:error, :no_source}

  def send_events(client, [%{} | _] = batch) do
    body = Bertex.encode(%{"batch" => batch, "source" => client.source_token})

    case Tesla.post(client.tesla_client, "/api/logs", body) do
      {:ok, %Tesla.Env{status: status, body: body}} when status < 300 ->
        {:ok, Jason.decode!(body)}

      {_result, %Tesla.Env{} = result} ->
        # on_error callback
        case Map.get(client, :on_error) do
          {m, f, 1} -> apply(m, f, [result])
          cb when is_function(cb) -> cb.(result)
          _ -> :noop
        end

        {:error, result}
    end
  end

  @doc """
  Sends a batched event.

  See `send_batched_events/2`
  """
  @spec send_batched_events(Client.t(), [map()]) :: :ok
  def send_batched_event(client, %{} = event), do: send_batched_events(client, [event])

  @doc """
  Sends events in batches. Configuration of the batching is dependent on the provided client.

  Batched events are cached locally and flushed at regular intervals.

  ### Example

  ```elixir
  # create a client
  iex> client = LogflareEx.client()
  %LogflareEx.Client{...}

  # singular event
  iex> LogflareEx.send_batched_event(client, %{...})
  :ok

  # list of events
  iex> LogflareEx.send_batched_event(client, [%{...}, ...])
  :ok
  ```
  """
  @spec send_batched_events(Client.t(), [map()]) :: :ok
  def send_batched_events(_client, []), do: :ok

  def send_batched_events(client, events) when is_list(events) do
    BatcherSup.ensure_started(client)

    for event <- events do
      client
      |> Map.take([:source_token, :source_name])
      |> Map.put(:body, event)
      |> Batcher.create_event()
    end

    :ok
  end

  @doc """
  Returns a count of all queued events.
  """
  @spec count_queued_events() :: non_neg_integer()
  def count_queued_events() do
    Repo.all(BatchedEvent)
    |> length()
  end

  @doc """
  Performs a flush for a given client. Attempts to clear the queue of events for the given client.
  """
  @spec flush(Client.t()) :: :ok
  def flush(client) do
    BatcherSup.ensure_started(client)
    Batcher.flush(client)
  end
end
