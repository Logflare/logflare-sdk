defmodule WarehouseEx.LoggerBackend.Formatter do
  @moduledoc false
  alias WarehouseEx.LoggerBackend.Stacktrace
  require Logger

  def format(level, message, ts, metadata) do
    # dbg({level, message, ts, metadata})

    try do
      new(level, message, ts, Map.new(metadata))
    rescue
      e ->
        %{
          "timestamp" => NaiveDateTime.to_iso8601(NaiveDateTime.utc_now(), :extended) <> "Z",
          "message" => "#{__MODULE__} error: #{inspect(e, safe: true)}",
          "metadata" => %{
            "formatter_error_params" => %{
              "metadata" =>
                inspect(metadata, safe: true, limit: :infinity, printable_limit: :infinity),
              "timestamp" => inspect(ts),
              "message" => inspect(message),
              "level" => inspect(level)
            },
            "level" => "error"
          }
        }
    end
  end

  @doc """
  Creates a LogParams struct when all fields have serializable values
  """
  def new(level, message, timestamp, metadata) do
    message = encode_message(message)
    timestamp = encode_timestamp(timestamp)
    metadata = encode_metadata(metadata)

    {stacktrace, metadata} = Map.pop(metadata, "stacktrace")

    {system_context, user_context} = Map.split(metadata, default_metadata_keys())

    context = Map.get(user_context, "context", %{})

    system_context =
      system_context
      |> enrich(:vm)

    log_params = %{
      "timestamp" => timestamp,
      "message" => message,
      "metadata" =>
        user_context
        |> Map.put("level", Atom.to_string(level))
        |> Map.put("context", Map.merge(context, system_context))
    }

    if stacktrace do
      put_in(log_params, ~w[metadata stacktrace], stacktrace)
    else
      log_params
    end
  end

  def enrich(context, :vm) do
    Map.merge(context, %{"vm" => %{"node" => "#{Node.self()}"}})
  end

  @doc """
  Encodes message, if is iodata converts to binary.
  """
  def encode_message(message) do
    to_string(message)
  end

  @doc """
  Converts erlang datetime tuple into ISO:Extended binary.
  """

  def encode_timestamp({date, {hour, minute, second}}) do
    encode_timestamp({date, {hour, minute, second, 0}})
  end

  def encode_timestamp({date, {hour, minute, second, {_micro, 6} = fractions_with_precision}}) do
    {date, {hour, minute, second}}
    |> NaiveDateTime.from_erl!(fractions_with_precision)
    |> NaiveDateTime.to_iso8601(:extended)
    |> Kernel.<>("Z")
  end

  def encode_timestamp({date, {hour, minute, second, milli}}) when is_integer(milli) do
    erldt =
      {date, {hour, minute, second}}
      |> :calendar.local_time_to_universal_time_dst()
      |> case do
        [] -> {date, {hour, minute, second}}
        [dt_utc] -> dt_utc
        [_, dt_utc] -> dt_utc
      end

    erldt
    |> NaiveDateTime.from_erl!({milli * 1000, 6})
    |> NaiveDateTime.to_iso8601(:extended)
    |> Kernel.<>("Z")
  end

  def encode_metadata(meta) when is_map(meta) do
    meta
    |> encode_crash_reason()
    |> convert_mfa()
    |> convert_initial_call()
    |> traverse_convert()
    |> Map.drop(["report_cb", "erl_level"])
  end

  @doc """
  Adds formatted stacktrace to the metadata
  """
  def encode_crash_reason(%{crash_reason: {_err, stacktrace}} = meta) do
    meta
    |> Map.drop([:crash_reason])
    |> Map.merge(%{stacktrace: Stacktrace.format(stacktrace)})
  end

  def encode_crash_reason(meta), do: meta

  def convert_initial_call(%{initial_call: {m, f, a}} = meta) when is_integer(a) do
    %{meta | initial_call: {m, f, "#{a}"}}
  end

  def convert_initial_call(meta), do: meta

  def convert_mfa(%{mfa: {m, f, a}} = meta) when is_integer(a) do
    %{meta | mfa: {m, f, "#{a}"}}
  end

  def convert_mfa(meta), do: meta

  def traverse_convert(%NaiveDateTime{} = v), do: to_string(v)
  def traverse_convert(%DateTime{} = v), do: to_string(v)

  def traverse_convert(%{__struct__: _} = v) do
    v |> Map.from_struct() |> traverse_convert()
  end

  def traverse_convert(data) when is_map(data) do
    for {k, v} <- data, into: Map.new() do
      {traverse_convert(k), traverse_convert(v)}
    end
  end

  def traverse_convert(value) when is_list(value) do
    single_type? =
      value
      |> Enum.map(&type/1)
      |> Enum.uniq()
      |> then(&(length(&1) == 1))

    cond do
      Keyword.keyword?(value) ->
        value
        |> Map.new()
        |> traverse_convert()

      length(value) > 0 and List.ascii_printable?(value) ->
        to_string(value)

      single_type? ->
        Enum.map(value, &traverse_convert/1)

      true ->
        Enum.map(value, fn
          v when is_atom(v) ->
            Atom.to_string(v)

          v when is_float(v) ->
            Float.to_string(v)

          v when is_integer(v) ->
            Integer.to_string(v)

          v when is_binary(v) ->
            v

          v ->
            try do
              Jason.encode!(v)
            rescue
              _e ->
                inspect(v)
            end
        end)
    end
  end

  def traverse_convert(x) when is_tuple(x) do
    x |> Tuple.to_list() |> traverse_convert()
  end

  @doc """
  All atoms are converted to strings for Logflare server to be able
  to safely convert binary to terms using :erlang.binary_to_term(binary, [:safe])
  """
  def traverse_convert(x) when is_boolean(x), do: x

  def traverse_convert(nil), do: nil

  def traverse_convert(x) when is_atom(x), do: Atom.to_string(x)

  def traverse_convert(x) when is_function(x), do: inspect(x)

  def traverse_convert(x) when is_pid(x) do
    x
    |> :erlang.pid_to_list()
    |> to_string()
  end

  def traverse_convert(x), do: x

  defp default_metadata_keys do
    ~w[
        application
        module
        function
        file
        line
        pid
        crash_reason
        initial_call
        registered_name
        domain
        gl
        time
        mfa
      ]
  end

  defp type(v) when is_tuple(v), do: :tuple
  defp type(v) when is_map(v), do: :map
  defp type(v) when is_list(v), do: :list
  defp type(v) when is_integer(v), do: :integer
  defp type(v) when is_float(v), do: :float
  defp type(v) when is_number(v), do: :number
  defp type(v) when is_binary(v), do: :binary
  defp type(v) when is_boolean(v), do: :boolean
  defp type(_), do: :other
end
