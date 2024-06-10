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


  ### Reporter Options

  - `:include`: a list of dot paths to include in the event payload.
  """
  use GenServer
  require Logger

  @doc """
  `:telemetry.attach/4` callback for allowing attaching to telemetry events.
  Telemetry events attached this way are batched to Logflare.

  Options:
  - `:include` - dot syntax fields to be included.
  """
  @spec handle_attach(list(), map(), map(), nil | list()) :: :ok
  def handle_attach(event, measurements, metadata, nil),
    do: handle_attach(event, measurements, metadata, [])

  def handle_attach(event, measurements, metadata, config) when is_list(config) do
    # merge configuration
    config_file_opts = (Application.get_env(:logflare_ex, __MODULE__) || []) |> Map.new()
    opts = Enum.into(config, config_file_opts)

    payload = %{metadata: metadata, measurements: measurements}
    to_include = Map.get(opts, :include, [])

    filtered_payload =
      for path <- to_include,
          String.starts_with?(path, "measurements.") or String.starts_with?(path, "metadata."),
          reduce: %{} do
        acc -> put_path(acc, path, get_path(payload, path))
      end

    # split handler paths
    event_str = Enum.map_join(event, ".", &Atom.to_string(&1))

    measurements_str =
      if Map.get(filtered_payload, :measurements) do
        Enum.map_join(filtered_payload.measurements, " ", fn {k, v} ->
          "#{stringify(k)}=#{stringify(v)}"
        end)
      else
        ""
      end

    message = "#{event_str} | #{measurements_str}"
    client = LogflareEx.client(opts)

    payload =
      Map.merge(
        %{
          message: message,
          event: event_str
        },
        filtered_payload
      )

    LogflareEx.send_batched_event(client, payload)

    :ok
  end

  defp stringify(v) do
    case v do
      v when is_float(v) -> Float.to_string(v)
      v when is_integer(v) -> Integer.to_string(v)
      v when is_atom(v) -> Atom.to_string(v)
      v when is_binary(v) -> v
      v when is_map(v) -> inspect(v)
      other -> inspect(v)
    end
  end

  # puts a value at a given dot path or atom list path
  # if the path does not exist, it will fill in the key(s)
  defp put_path(nil, path, value), do: put_path(%{}, path, value)

  defp put_path(payload, [part], value) do
    Map.put(payload, part, value)
  end

  defp put_path(payload, [head | tail] = path, value) when is_list(path) do
    head_value = Map.get(payload, head)
    Map.put(payload, head, put_path(head_value, tail, value))
  end

  defp put_path(payload, path, value) when is_binary(path) do
    list_path =
      for part <- String.split(path, ".") do
        if atom_map?(payload) do
          String.to_existing_atom(part)
        else
          part
        end
      end

    put_path(payload, list_path, value)
  end

  defp atom_map?(map) do
    key = Map.keys(map) |> List.first()
    is_atom(key)
  end

  # gets a value of a map/struct at a given dot path
  defp get_path(payload, path) when is_binary(path) do
    for part <- String.split(path, "."), reduce: payload do
      %{} = data ->
        if atom_map?(data) do
          Map.get(data, String.to_existing_atom(part))
        else
          Map.get(data, part)
        end

      data when is_list(data) ->
        Enum.map(data, fn datum -> get_path(datum, part) end)

      other ->
        other
    end
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
