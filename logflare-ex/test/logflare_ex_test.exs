defmodule LogflareExTest do
  use ExUnit.Case, async: false
  use Mimic
  alias LogflareEx.BatcherSup

  test "send_event/2" do
    Tesla
    |> expect(:post, 2, fn _client, _path, _body ->
      %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}
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
    |> expect(:post, fn _client, _path, _body -> %Tesla.Env{status: 500, body: "server err"} end)

    assert {:error, %Tesla.Env{}} = LogflareEx.send_event(client, %{some: "event"})
  end

  test "send_events/2" do
    Tesla
    |> expect(:post, fn _client, _path, _body ->
      %Tesla.Env{status: 201, body: Jason.encode!(%{"message" => "server msg"})}
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
        %Tesla.Env{status: 500, body: "some server error"}
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
end
