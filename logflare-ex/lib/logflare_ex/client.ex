defmodule LogflareEx.Client do
  @moduledoc false
  @default_tesla_adapter {Tesla.Adapter.Finch, name: LogflareEx.Finch, receive_timeout: 30_000}
  use TypedStruct

  typedstruct do
    @typedoc "Logflare client"

    field(:tesla_client, Tesla.Client.t(), enforce: true)
    field(:api_key, String.t(), enforce: true)
    field(:api_url, String.t(), default: "https://api.logflare.app")
    field(:source_token, String.t())
    field(:on_error, list() | mfa(), default: nil)
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
        tesla_client: nil,
        on_error: get_config_value(:on_error)
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
end
