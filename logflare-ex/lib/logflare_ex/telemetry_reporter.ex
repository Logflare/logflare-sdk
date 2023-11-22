defmodule LogflareEx.TelemetryReporter do
  @moduledoc """
  A TelemetryReporter for attaching to metrics created from `:telemetry_metrics`.
  Telemetry events are sent to the Logflare API as is.

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
    event_str = Enum.map_join(event, ".", &Atom.to_string(&1))

    measurements_str =
      Enum.map_join(measurements, " ", fn {k, v} ->
        "#{inspect(k)}=#{inspect(v)}"
      end)

    message = "#{event_str} | #{measurements_str}"
    client = LogflareEx.client(config)

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
