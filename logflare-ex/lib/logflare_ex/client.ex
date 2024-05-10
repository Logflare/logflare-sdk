defmodule LogflareEx.Client do
  @moduledoc """
  A `LogflareEx.Client` contains all configuration used for making API requests, whether batched or not.

  ### Application-level Configuration

  Application-wide configuration can be set in `config.exs`:

  ```elixir
  config :logflare_ex,
    api_key: "...",
    source_token: "..."
  ```

  ### Runtime Configuration

  All configuration options can be overridden at runtime. This is through the use of the `LogflareEx.Client` struct.

  To create a new client with a custom configuration, use `LogflareEx.client/1`:

  ```elixir
  # To create a client from the application-level configuration.
  iex> default_client = LogflareEx.client()
  %LogflareEx.Client{...}

  # To create a client with runtime overrides
  iex> client = LogflareEx.client(source_token: "...")
  %LogflareEx.Client{...}

  # use the runtime client
  iex> LogflareEx.send_batched_event(client, %{...})
  :ok
  ```

  ### Options

  For every configuration, either `:source_token` or `:source_name` must be provided.

  - `:api_key`: **Required**. Public API key.
  - `:api_url`: Custom Logflare endpoint, for self-hosting. Defaults to `https//api.logflare.app`.
  - `:source_token`: Source UUID. Mutually exclusive with `:source_name`
  - `:source_name`: Source name. Mutually exclusive with `:source_token`
  - `:on_error`: mfa callback for handling API errors. Must be 1 arity.
  - `:auto_flush`: Used for batching. Enables automatic flushing. If disabled, `LogflareEx.flush/1` must be called.
  - `:flush_interval`: Used for batching. Flushes cached events at the provided interval.
  - `:batch_size`: Used for batching. It is the maximum number of events send per API request.

  """
  @default_tesla_adapter {Tesla.Adapter.Finch, name: LogflareEx.Finch, receive_timeout: 30_000}
  @default_batch_size 100
  @default_flush_interval 1_500

  use TypedStruct

  typedstruct do
    @typedoc "Logflare client"

    field(:tesla_client, Tesla.Client.t(), enforce: true)
    field(:api_key, String.t(), enforce: true)
    field(:api_url, String.t(), default: "https://api.logflare.app")
    field(:source_token, String.t())
    field(:source_name, String.t())
    field(:on_error, list() | mfa(), default: nil)
    # batching
    field(:auto_flush, :boolean, default: true)
    field(:flush_interval, non_neg_integer(), default: @default_flush_interval)
    field(:batch_size, non_neg_integer(), default: @default_batch_size)
  end

  @typep opts :: [api_key: String.t(), api_url: String.t(), tesla_client: Tesla.Client.t()]
  @spec new(opts) :: t()
  def new(opts \\ []) do
    opts =
      Enum.into(opts, %{
        api_url: get_config_value(:api_url) || "https://api.logflare.app",
        api_key: get_config_value(:api_key),
        adapter: get_config_value(:adapter) || @default_tesla_adapter,
        source_token: get_config_value(:source_token),
        source_name: get_config_value(:source_name),
        tesla_client: nil,
        on_error: get_config_value(:on_error),
        flush_interval: get_config_value(:flush_interval) || @default_flush_interval,
        batch_size: get_config_value(:batch_size) || @default_batch_size
      })

    tesla_client =
      make_tesla_client(
        opts.api_url,
        opts.api_key,
        opts.adapter
      )

    struct(__MODULE__, %{opts | tesla_client: tesla_client})
  end

  defp make_tesla_client(
         api_url,
         api_key,
         adapter
       ) do
    middlewares = [
      Tesla.Middleware.FollowRedirects,
      {Tesla.Middleware.Headers,
       [
         {"x-api-key", api_key},
         {"content-type", "application/bert"}
       ]},
      {Tesla.Middleware.BaseUrl, api_url},
      {Tesla.Middleware.Compression, format: "gzip"}
    ]

    Tesla.client(middlewares, adapter)
  end

  def get_config_value(key) do
    Application.get_env(:logflare_ex, key)
  end

  def validate_client(%__MODULE__{source_name: nil, source_token: nil}),
    do: {:error, :invalid_config}

  def validate_client(%__MODULE__{api_key: nil}), do: {:error, :invalid_config}
  def validate_client(%__MODULE__{flush_interval: i}) when i < 0, do: {:error, :invalid_config}
  def validate_client(%__MODULE__{batch_size: i}) when i < 0, do: {:error, :invalid_config}
  def validate_client(%__MODULE__{}), do: :ok
  def validate_client(_), do: {:error, :invalid_config}
end
