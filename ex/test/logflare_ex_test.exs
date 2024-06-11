defmodule LogflareExTest do
  use LogflareEx.BatcherCase
  use Mimic
  alias LogflareEx.BatcherSup

  test "send_event/2" do
    Tesla
    |> expect(:post, 2, fn _client, _path, _body ->
      {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
    end)

    # send with source token
    client = LogflareEx.client(api_key: "123", source_token: "12313")
    assert %LogflareEx.Client{api_key: "123"} = client

    assert {:ok, %{"message" => "server msg"}} = LogflareEx.send_event(client, %{some: "event"})

    # send with source name
    client = LogflareEx.client(api_key: "123", source_name: "12313")
    assert %LogflareEx.Client{api_key: "123"} = client

    assert {:ok, %{"message" => "server msg"}} = LogflareEx.send_event(client, %{some: "event"})

    Tesla
    |> expect(:post, fn _client, _path, _body ->
      {:ok, %Tesla.Env{status: 500, body: "server err"}}
    end)

    assert {:error, %Tesla.Env{}} = LogflareEx.send_event(client, %{some: "event"})
  end

  test "send_events/2" do
    Tesla
    |> expect(:post, fn _client, _path, _body ->
      {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
    end)

    client = LogflareEx.client(api_key: "123", source_token: "123")
    assert %LogflareEx.Client{api_key: "123"} = client

    assert {:ok, %{"message" => "server msg"}} =
             LogflareEx.send_events(client, [%{some: "event"}])

    assert {:error, :no_events} = LogflareEx.send_events(client, [])

    assert {:error, :no_source} =
             LogflareEx.client(api_key: "123") |> LogflareEx.send_events([%{some: "event"}])
  end

  describe "on_error" do
    test "triggers on_error mfa if non-201 status is encountered" do
      Tesla
      |> expect(:post, 2, fn _client, _path, _body ->
        {:ok, %Tesla.Env{status: 500, body: "some server error"}}
      end)

      LogflareEx.TestUtils
      |> expect(:stub_function, 2, fn %{status: 500} -> :ok end)

      for cb <- [
            {LogflareEx.TestUtils, :stub_function, 1},
            &LogflareEx.TestUtils.stub_function/1
          ] do
        client = LogflareEx.client(api_key: "123", source_token: "123", on_error: cb)
        assert {:error, %Tesla.Env{}} = LogflareEx.send_events(client, [%{some: "event"}])
      end
    end

    test "triggers on_error mfa on tesla client error" do
      Tesla
      |> expect(:post, 2, fn _client, _path, _body ->
        {:error, %Tesla.Env{status: 500, body: "some server error"}}
      end)

      LogflareEx.TestUtils
      |> expect(:stub_function, 2, fn %{status: 500} -> :ok end)

      for cb <- [
            {LogflareEx.TestUtils, :stub_function, 1},
            &LogflareEx.TestUtils.stub_function/1
          ] do
        client = LogflareEx.client(api_key: "123", source_token: "123", on_error: cb)
        assert {:error, %Tesla.Env{}} = LogflareEx.send_events(client, [%{some: "event"}])
      end
    end
  end

  describe "on_prepare_payload" do
    test "triggered before payload is sent" do
      pid = self()

      Tesla
      |> expect(:post, 3, fn _client, _path, body ->
        %{"batch" => [event]} = Bertex.decode(body)
        send(pid, {event.ref, event})
        {:ok, %Tesla.Env{status: 500, body: "some server error"}}
      end)

      LogflareEx.TestUtils
      |> expect(:stub_function, 2, fn data ->
        %{different: "value", ref: data.ref}
      end)

      for cb <- [
            {LogflareEx.TestUtils, :stub_function, 1},
            &LogflareEx.TestUtils.stub_function/1,
            fn data -> %{different: "value", ref: data.ref} end
          ] do
        client = LogflareEx.client(api_key: "123", source_token: "123", on_prepare_payload: cb)
        ref = make_ref()

        assert {:error, %Tesla.Env{}} =
                 LogflareEx.send_events(client, [%{some: "event", ref: ref}])

        assert_receive {^ref, %{different: "value", ref: _}}
      end
    end
  end

  describe "batching" do
    setup do
      pid = start_supervised!(BatcherSup)
      {:ok, pid: pid}
    end

    test "send_batched_events/2 queues events to be batched" do
      reject(Tesla, :post, 2)

      client = LogflareEx.client(api_key: "123", source_token: "12313", auto_flush: false)

      assert :ok =
               LogflareEx.send_batched_events(client, [%{some: "event"}, %{some_other: "event"}])

      assert BatcherSup.count_batchers() == 1
      assert LogflareEx.count_queued_events() == 2
    end
  end

  @tag :benchmark
  # Bertex is way faster

  test "benchmark Jason vs Bertex" do
    large_sample = %{
      "batch" =>
        for(
          i <- 1..10_000,
          do: %{"some" => "events", "other" => i, "nested" => [%{"again" => "i_#{i}"}]}
        )
    }

    json_encoded = Jason.encode!(large_sample)
    bert_encoded = Bertex.encode(large_sample)

    Benchee.run(%{
      "bertex encode large" => fn ->
        Bertex.encode(large_sample)
      end,
      "jason encode large" => fn ->
        Jason.encode!(large_sample)
      end,
      "bertex decode large" => fn ->
        Bertex.decode(bert_encoded)
      end,
      "jason decode large" => fn ->
        Jason.decode!(json_encoded)
      end
    })
  end

  @tag :benchmark
  # Bertex is way faster
  describe "async benchmark" do
    setup :set_mimic_global

    setup do
      start_supervised!(BatcherSup)
      start_supervised!(BencheeAsync.Reporter)
      :ok
    end

    test "api request rate" do
      Tesla
      |> stub(:post, fn _client, _path, body ->
        %{"batch" => batch} = Bertex.decode(body)
        BencheeAsync.Reporter.record(length(batch))
        {:ok, %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}}
      end)

      event = %{"some" => "events", "other" => "something", "nested" => [%{"again" => "value"}]}

      BencheeAsync.run(
        %{
          "no batching" => fn ->
            LogflareEx.client(source_name: "somename")
            |> LogflareEx.send_event(event)
          end,
          "batching" => fn ->
            LogflareEx.client(source_name: "some-batched-name", flush_interval: 500)
            |> LogflareEx.send_batched_event(event)
          end
        },
        time: 2,
        warmup: 1,
        # use extended_statistics to view units of work done
        formatters: [{Benchee.Formatters.Console, extended_statistics: true}]
      )
    end
  end
end
