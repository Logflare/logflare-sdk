defmodule LogflareEx.TelemetryReporterTest do
  use LogflareEx.BatcherCase
  use Mimic
  alias LogflareEx.BatcherSup
  alias LogflareEx.TelemetryReporter
  import Telemetry.Metrics

  describe "telemtry" do
    setup do
      start_supervised!(BatcherSup)
      source_name = Application.get_env(:logflare_ex, :source_name)
      Application.put_env(:logflare_ex, :source_name, "some name")

      on_exit(fn ->
        :telemetry.detach("my-id")
        Application.put_env(:logflare_ex, :source_name, source_name)
      end)
    end

    test "handle_attach/4" do
      Tesla
      |> expect(:post, fn _client, _path, _body ->
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      :telemetry.attach("my-id", [:some, :event], &TelemetryReporter.handle_attach/4,
        auto_flush: true,
        flush_interval: 50
      )

      :telemetry.execute([:some, :event], %{latency: 123}, %{some: "metadata"})

      Process.sleep(300)
      # should clear cache
      assert LogflareEx.count_queued_events() == 0
    end
  end

  # reporter
  describe "TelemtryReporter genserver" do
    setup do
      pid = start_supervised!(BatcherSup)
      {:ok, pid: pid}
    end

    test "metrics opt" do
      Tesla
      |> expect(:post, fn _client, _path, _body ->
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      start_supervised!(
        {TelemetryReporter,
         metrics: [
           last_value("some.event.stop.duration")
         ],
         source_name: "speed_test",
         auto_flush: true,
         flush_interval: 100}
      )

      Process.sleep(300)

      :telemetry.span([:some, :event], %{some: "metadata"}, fn ->
        {:ok, %{some: "stop metadata"}}
      end)

      Process.sleep(300)
    end
  end

  describe "Configuration" do
    setup do
      start_supervised!(BatcherSup)
      env = Application.get_env(:logflare_ex, TelemetryReporter)
      Application.put_env(:logflare_ex, TelemetryReporter, api_url: "http://custom-url.com")

      on_exit(fn ->
        Application.put_env(:logflare_ex, TelemetryReporter, env)
        :telemetry.detach("my-id")
      end)

      :ok
    end

    test "LoggerBackend level configuration" do
      pid = self()

      Tesla
      |> expect(:post, fn client, _path, _body ->
        assert inspect(client.pre) =~ "custom-url.com"
        assert inspect(client.pre) =~ "some-key"
        send(pid, :ok)
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      start_supervised!(
        {TelemetryReporter,
         metrics: [
           last_value("some.event.latency")
         ],
         source_name: "some-source",
         api_key: "some-key",
         auto_flush: true,
         flush_interval: 100}
      )

      Process.sleep(300)

      :telemetry.execute([:some, :event], %{latency: 123})

      assert_receive :ok, 1_000
    end
  end
end
