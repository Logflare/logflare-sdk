defmodule LogflareEx do
  @moduledoc """
  Documentation for `LogflareEx`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> client  =  LogflareEx.client("some url")
      iex> match?(%Tesla.Client{}, client)
      true

  """
  alias Tesla

  def client(url, api_key, opts \\ []) do
    opts = Enum.into(opts, %{
      api_url: url || get_config_value(:api_url) || "https://api.logflare.app",
      api_key: api_key  || get_config_value(:api_key),
      adapter:   get_config_value(:adapter) || {Tesla.Adapter.Finch, name: LogflareEx.Finch, receive_timeout: 30_000}
    })

    middlewares = [
      Tesla.Middleware.FollowRedirects,
      {Tesla.Middleware.Headers,
       [
         {"x-api-key", opts.api_key},
         {"content-type", "application/bert"}
       ]},
      {Tesla.Middleware.BaseUrl, opts.api_url},
      {Tesla.Middleware.Compression, format: "gzip"}
    ]

    Tesla.client( middlewares, opts.adapter)
  end


  def send_events(_client, _source_token, []), do: {:error, :no_events}
  def send_events(client, source_token, [ %{} | _ ] = batch) do
    body = Bertex.encode(%{"batch" => batch, "source" => source_token})

    Tesla.post(client, "/api/logs", body)
  end


  defp get_config_value(key) do
    Application.get_env(:logflare_ex, key)
  end

end
