defmodule LogflareEx.LoggerBackendTest do
  use LogflareEx.BatcherCase
  use Mimic
  setup :set_mimic_global
  alias LogflareEx.BatcherSup
  alias LogflareEx.LoggerBackend
  require Logger
  import ExUnit.CaptureLog
  import ExUnit.CaptureIO
  use ExUnitProperties

  describe "telemtry" do
    setup do
      Tesla
      |> stub(:post, fn _client, _path, _body ->
        %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}
      end)

      start_supervised!(BatcherSup)

      capture_log(fn ->
        {:ok, _pid} = Logger.add_backend(LoggerBackend)

        :ok =
          Logger.configure_backend(LoggerBackend, source_token: "some-token", flush_interval: 200)

        Logger.put_module_level(__MODULE__, :all)
        Logger.flush()
        :timer.sleep(300)
      end)

      on_exit(fn ->
        Logger.remove_backend(LoggerBackend)
      end)
    end

    test "log levels" do
      Tesla
      |> expect(:post, 1, fn _client, _path, body ->
        batch = Bertex.decode(body)["batch"]
        assert length(batch) == 10
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      assert LogflareEx.count_queued_events() == 0

      capture_log(fn ->
        Logger.emergency("a log event")
        Logger.alert("a log event")
        Logger.critical("a log event")
        Logger.error("a log event")
        Logger.warning("a log event")
        Logger.notice("a log event")
        Logger.info("a log event")
        Logger.debug("a log event")
        Logger.bare_log(:info, "a log event")
        Logger.bare_log(:info, fn -> "a log event" end)
        Process.sleep(80)
      end) =~ "a log event"

      assert LogflareEx.count_queued_events() == 10
      Process.sleep(300)
      # should clear cache
      assert LogflareEx.count_queued_events() == 0
    end

    test "exception and stacktrace" do
      pid = self()

      Tesla
      |> expect(:post, 1, fn _client, _path, body ->
        batch = Bertex.decode(body)["batch"]

        for e <- batch do
          assert %{
                   "message" => _,
                   "metadata" => %{
                     "level" => "error",
                     "context" => %{"pid" => _},
                     "stacktrace" => [
                       %{
                         "arity" => _,
                         "args" => _,
                         "file" => _,
                         "line" => _,
                         "function" => _,
                         "module" => _
                       }
                       | _
                     ]
                   },
                   "timestamp" => _
                 } = e
        end

        send(pid, :ok)
        %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}
      end)

      assert capture_log(fn ->
               spawn(fn -> 3.14 / 0 end)
               spawn(fn -> Enum.find(nil, & &1) end)
               Process.sleep(300)
             end) =~ "Protocol.UndefinedError"

      assert_receive :ok
    end
  end

  describe "Logger level" do
    setup [:send_batch_to_self, :start_batcher_sup, :add_backend]

    test "metadata.level gets set" do
      Logger.put_module_level(__MODULE__, :info)
      capture_log(fn -> Logger.info("info") end)
      assert_receive [%{"metadata" => %{"level" => "info"}}]
    end

    test "don't send events with lower log level" do
      Logger.put_module_level(__MODULE__, :info)
      capture_log(fn -> Logger.debug("debug") end)
      refute_receive [%{"metadata" => %{"level" => "debug"}}]
    end
  end

  describe "context and metadata merging" do
    setup [:send_batch_to_self, :start_batcher_sup, :add_backend]

    test "system vm gets set on metadata" do
      log_data(true)

      assert_receive [
        %{
          "metadata" => %{
            "context" => %{
              "vm" => _
            }
          }
        }
      ]
    end

    test "Logger.metadata gets merged into the log event" do
      Logger.metadata(test: 123)
      log_data(true)
      assert_receive [%{"metadata" => %{"test" => 123}}]
    end

    test "Logger.metadata context gets merged into the context key" do
      Logger.metadata(context: [data: 123])
      log_data(true)
      assert_receive [%{"metadata" => %{"context" => %{"data" => 123}}}]
    end
  end

  describe "formatter" do
    setup [:send_batch_to_self, :start_batcher_sup, :add_backend]

    test "tuples to list" do
      log_data({1, 2})
      assert_receive [%{"metadata" => %{"data" => [1, 2]}}]
    end

    test "structs to maps" do
      log_data(%Plug.Conn{})
      assert_receive [%{"metadata" => %{"data" => %{"adapter" => _}}}]
    end

    test "atom to string" do
      log_data(:value)

      assert_receive [
        %{"metadata" => %{"data" => "value"}}
      ]
    end

    test "charlist to string" do
      log_data(~c"some event", ~c"some event")

      assert_receive [
        %{
          "message" => "some event",
          "metadata" => %{"data" => "some event"}
        }
      ]
    end

    test "keywords to map" do
      log_data(some: "value")

      assert_receive [
        %{
          "metadata" => %{
            "data" => %{
              "some" => "value"
            }
          }
        }
      ]
    end

    test "pid to string" do
      log_data(self())

      assert_receive [
        %{
          "metadata" => %{"data" => "<" <> _}
        }
      ]
    end

    test "booleans" do
      log_data(true)

      assert_receive [
        %{
          "metadata" => %{"data" => true}
        }
      ]
    end

    test "function to string" do
      log_data(&String.to_atom/1)
      assert_receive [%{"metadata" => %{"data" => "&String.to_" <> _}}]
    end

    test "observer_backend.sys_info()" do
      log_data(:observer_backend.sys_info())
      assert_receive [%{"metadata" => %{"data" => data}}]

      assert ["instance", "0", "" <> _] =
               hd(data["alloc_info"]["binary_alloc"])
    end

    # property "nested list should be stringified" do
    #   check all nested_list <- list_of(list_of(term()), min_length: 1) do
    #     log_data(nested_list)
    #     assert_receive [ %{ "metadata" => %{"data" => "" <> _} } ]
    #   end
    # end
    test "NaiveDateTime to String.Chars protocol" do
      ndt = NaiveDateTime.new!(1337, 4, 19, 0, 0, 0)
      log_data(ndt)
      assert_receive [%{"metadata" => %{"data" => "1337-04-19 00:00:00"}}]
    end

    test "DateTime to String.Chars protocol" do
      ndt = NaiveDateTime.new!(1337, 4, 19, 0, 0, 0)
      dt = DateTime.from_naive!(ndt, "Etc/UTC")
      log_data(dt)
      assert_receive [%{"metadata" => %{"data" => "1337-04-19 00:00:00Z"}}]
    end

    test "iso timestamps with millisecond" do
      utc = %{NaiveDateTime.utc_now() | microsecond: {314_000, 6}}
      log_data(utc)
      assert_receive [%{"metadata" => %{"data" => ts_string}}]
      assert ts_string =~ ".314000"
    end

    test "nested list - Plug.Conn" do
      log_data([
        "Elixir.Plug.Cowboy.Conn",
        %{"peer" => [[127, 0, 0, 1], 60164]}
      ])

      assert_receive [
        %{
          "metadata" => %{
            "data" => [
              "Elixir.Plug.Cowboy.Conn",
              "" <> _
            ]
          }
        }
      ]
    end
  end

  describe "Configuration" do
    setup do
      env = Application.get_env(:logflare_ex, LoggerBackend)
      Application.put_env(:logflare_ex, LoggerBackend, api_url: "http://custom-url.com")

      on_exit(fn ->
        Application.put_env(:logflare_ex, LoggerBackend, env)
      end)

      :ok
    end

    setup [:start_batcher_sup, :add_backend]

    test "LoggerBackend level configuration" do
      pid = self()

      Tesla
      |> expect(:post, 1, fn client, _path, _body ->
        assert inspect(client.pre) =~ "http://custom-url.com"
        send(pid, :ok)
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      log_data(:ok)

      assert_receive :ok
    end
  end

  defp start_batcher_sup(_ctx) do
    start_supervised!(BatcherSup)
    :ok
  end

  defp send_batch_to_self(_ctx) do
    pid = self()

    Tesla
    |> stub(:post, fn _client, _path, body ->
      batch = Bertex.decode(body)["batch"]
      send(pid, batch)
      {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
    end)

    :ok
  end

  defp add_backend(_ctx) do
    capture_log(fn ->
      {:ok, _pid} = Logger.add_backend(LoggerBackend)

      :ok =
        Logger.configure_backend(LoggerBackend, source_token: "some-token", flush_interval: 50)

      Logger.put_module_level(__MODULE__, :all)
      Logger.flush()
      :timer.sleep(200)
    end)

    # clear the test process inbox
    capture_io(fn -> :c.flush() end)
    :timer.sleep(300)

    on_exit(fn ->
      Logger.remove_backend(LoggerBackend)
    end)

    :ok
  end

  defp log_data(data, text \\ "some event") do
    capture_log(fn ->
      Logger.info(text, data: data)
    end)
  end
end
