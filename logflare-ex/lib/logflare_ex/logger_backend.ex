defmodule LogflareEx.LoggerBackend do
  @moduledoc """
  Implements :gen_event behaviour, handles incoming Logger messages
  """
  alias __MODULE__.Formatter
  require Logger

  @app :logflare_ex
  @behaviour :gen_event

  @type level :: Logger.level()
  @type message :: Logger.message()
  @type metadata :: Logger.metadata()
  @type log_msg :: {level, pid, {Logger, message, term, metadata}} | :flush

  @spec init(__MODULE__) :: {:ok, map()}
  def init(__MODULE__) do
    config = build_default_config()
    maybe_start(config)
    {:ok, config}
  end

  @spec handle_event(log_msg, Config.t()) :: {:ok, Config.t()}
  def handle_event(:flush, config) do
    LogflareEx.flush(config.client)
    {:ok, config}
  end

  def handle_event({_, gl, _}, config) when node(gl) != node() do
    {:ok, config}
  end

  def handle_event(
        {_level, _gl, {_Logger, _msg, _datetime, _metadata}},
        %{client: nil} = config
      ) do
    {:ok, config}
  end

  def handle_event({level, _gl, {Logger, msg, datetime, metadata}}, config) do
    if log_level_matches?(level, config.level) do
      # TODO: add default context formatting for backwards compat
      payload = Formatter.format(level, msg, datetime, metadata)
      LogflareEx.send_batched_event(config.client, payload)
    end

    {:ok, config}
  end

  @spec handle_call({:configure, keyword()}, map()) :: {:ok, :ok, map()}
  def handle_call({:configure, options}, _config) do
    config = build_default_config(options)
    maybe_start(config)

    {:ok, :ok, config}
  end

  # for hot code reloading
  # https://www.erlang.org/doc/man/gen_event#Module:code_change-3
  def code_change(_old_vsn, config, _extra), do: {:ok, config}

  def terminate(_reason, _state), do: :ok

  defp maybe_start(config) do
    with :ok <- LogflareEx.Client.validate_client(config.client) do
      msg = "[#{__MODULE__}] v#{Application.spec(@app, :vsn)} started."
      Logger.info(msg)

      LogflareEx.send_batched_event(config.client, %{"message" => msg})
      :ok
    else
      {:error, :invalid_config} = err ->
        Logger.error("[#{__MODULE__}] Invalid client configuration on backend init")
        err
    end
  end

  @spec log_level_matches?(level, level | nil) :: boolean
  defp log_level_matches?(_lvl, nil), do: true
  # to avoid the deprecation warning log
  defp log_level_matches?(:warn, min), do: log_level_matches?(:warning, min)
  defp log_level_matches?(lvl, min), do: Logger.compare_levels(lvl, min) != :lt

  defp build_default_config(options \\ []) do
    client = LogflareEx.client(options)

    client =
      if :ok == LogflareEx.Client.validate_client(client) do
        client
      else
        nil
      end

    options
    |> Enum.into(%{
      level: :all,
      client: client
    })
  end
end
