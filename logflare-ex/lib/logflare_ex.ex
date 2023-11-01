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

  Options:

  - `:api_key`, required - api key obtained from dashboard
  - `:api_url`, optional - Logflare instance url, defaults to Logflare service at https://api.logflare.app
  - `:source_token`, required for ingest - A source uuid obtained from dashboard
  - `:adapter`, optional - Tesla client adapter

  ## Examples

      iex> LogflareEx.client(%{...})
      %LogflareEx.Client{...}

  """

  defdelegate client(opts), to: __MODULE__.Client, as: :new

  @doc """
  Send a singular event to Logflare.


  ### Example
  Pipe the client into the desired function
      iex> client |> LogflareEx.send_event(%{my: "event"})
      {:ok, %{"message"=> "Logged!}}

      If an error is encountered, the tesla result will be returned
      iex> client |> LogflareEx.send_event(%{my: "event"})
      {:error, %Tesla.Env{...}}


  """
  @spec send_event(Client.t(), map()) :: {:ok, map()} | {:error, Tesla.Env.t()}
  def send_event(client, %{} = event) do
    send_events(client, [event])
  end

  @spec send_events(Client.t(), [map()]) :: {:ok, map()} | {:error, Tesla.Env.t()}
  def send_events(_client, []), do: {:error, :no_events}

  def send_events(%Client{source_token: nil}, _batch), do: {:error, :no_source}

  def send_events(client, [%{} | _] = batch) do
    body = Bertex.encode(%{"batch" => batch, "source" => client.source_token})

    case Tesla.post(client.tesla_client, "/api/logs", body) do
      %Tesla.Env{status: 201, body: body} ->
        {:ok, Jason.decode!(body)}

      %Tesla.Env{} = result ->
        # on_error callback
        case Map.get(client, :on_error) do
          {m, f, 1} -> apply(m, f, [result])
          cb when is_function(cb) -> cb.(result)
          _ -> :noop
        end

        {:error, result}
    end
  end

  @spec send_batched_events(Client.t(), [map()]) :: :ok
  def send_batched_event(client, %{} = event), do: send_batched_events(client, [event])

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

  def count_queued_events() do
    Repo.all(BatchedEvent)
    |> length()
  end
end
