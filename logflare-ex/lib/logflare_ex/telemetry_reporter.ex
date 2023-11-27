defmodule LogflareEx.TelemetryReporter do
  @moduledoc """
  A TelemetryReporter for attaching to metrics created from `:telemetry_metrics`.
  Telemetry events are sent to the Logflare API as is.

  ### Usage

  Add the following to your `mix.exs`
  ```elixir
  def deps do
    [
        {:telemetry, "~> 1.0"},
        {:telemetry_metrics, "~> 0.6.1"},
    ]
  end
  ```

  Thereafter, add the `LogflareEx.TelemetryReporter` to your supervision tree:

  ```elixir
    # application.ex
    children = [
      {LogflareEx.TelemetryReporter, metrics: [
        last_value("some.event.stop.duration")
      ]}
    ]
    ...
  ```

  The `LogflareEx.TelemetryReporter` will attach to all provided metrics.

  ### Configuration

  There are 2 levels of configuration available, and these are listed in priority order:

  1. Module level configuration via `config.exs`, such as `config :logflare_ex, #{__MODULE__}, source_token: ...`
  2. Application level configuration via `config.exs`, such as`config :logflare_ex, source_token: ...`

  Client options will then be merged together, with each level overriding the previous.

  """
  use GenServer
  require Logger

  @doc """
  `:telemetry.attach/4` callback for allowing attaching to telemetry events.
  Telemetry events attached this way are batched to Logflare.
  """
  @spec handle_attach(list(), map(), map(), nil | list()) :: :ok
  def handle_attach(event, measurements, metadata, nil),
    do: handle_attach(event, measurements, metadata, [])

  def handle_attach(event, measurements, metadata, config) when is_list(config) do
    # merge configuration
    config_file_opts = (Application.get_env(:logflare_ex, __MODULE__) || []) |> Map.new()
    opts = Enum.into(config, config_file_opts)

    # split handler paths
    event_str = Enum.map_join(event, ".", &Atom.to_string(&1))

    measurements_str =
      Enum.map_join(measurements, " ", fn {k, v} ->
        "#{inspect(k)}=#{inspect(v)}"
      end)

    message = "#{event_str} | #{measurements_str}"
    client = LogflareEx.client(opts)

    LogflareEx.send_batched_event(client, %{
      message: message,
      event: event_str,
      metadata: metadata,
      measurements: measurements
    })

    :ok
  end

  def start_link(opts) do
    server_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @impl true
  def init(config) do
    Process.flag(:trap_exit, true)
    {metrics, client_opts} = Keyword.pop(config, :metrics)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, _metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &__MODULE__.handle_attach/4, client_opts)
    end

    {:ok, Map.keys(groups)}
  end

  @impl true
  def terminate(_, events) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end
end
