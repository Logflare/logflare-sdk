defmodule LogflareEx.BatcherTest do
  use LogflareEx.BatcherCase
  alias LogflareEx.Batcher
  alias LogflareEx.BatcherSup
  alias LogflareEx.BatchedEvent
  alias LogflareEx.Client
  use Mimic

  describe "BatcherSup" do
    setup do
      pid = start_supervised!(BatcherSup)
      {:ok, pid: pid}
    end

    test "count_batchers/0, terminate_batchers/0 will kill all batchers" do
      assert 0 == BatcherSup.count_batchers()
      assert {:ok, pid} = BatcherSup.start_batcher(source_name: "some name")
      assert is_pid(pid)
      assert 1 == BatcherSup.count_batchers()
      assert :ok = BatcherSup.terminate_batchers()
      assert 0 == BatcherSup.count_batchers()
    end

    test "list_batchers/0, start_batcher/1 starts a worker by name or token" do
      # use default client
      assert {:ok, pid} = BatcherSup.start_batcher(source_name: "some name", auto_flush: false)
      assert is_pid(pid)
      assert {:ok, pid} = BatcherSup.start_batcher(source_token: "some-uuid", auto_flush: false)
      assert is_pid(pid)

      # start_batcher with client
      client = Client.new(source_name: "some namer", auto_flush: false)
      assert {:ok, _pid} = BatcherSup.start_batcher(client)
      client = Client.new(source_token: "some-uuids", auto_flush: false)
      assert {:ok, _pid} = BatcherSup.start_batcher(client)
    end
  end

  describe "Batcher worker" do
    test "list_events_by/2" do
      insert(:inflight_event)
      insert(:pending_event, source_token: "some-uuid")
      insert(:pending_event, source_name: "some name")

      assert [%BatchedEvent{source_name: "some name"}] =
               Batcher.list_events_by(:pending, source_name: "some name")

      assert [%BatchedEvent{source_token: "some-uuid"}] =
               Batcher.list_events_by(:pending, source_token: "some-uuid")

      # list all of a type
      assert [_, _, _] = Batcher.list_events_by(:all)
      assert [_, _] = Batcher.list_events_by(:pending)
      assert [_] = Batcher.list_events_by(:inflight)

      # can limit the query
      assert [_] = Batcher.list_events_by(:all, limit: 1)
    end

    test "create_events/0" do
      assert {:ok, %BatchedEvent{created_at: %NaiveDateTime{}}} =
               Batcher.create_event(%{source_token: "some-uuid", body: %{"test" => "testing"}})

      assert {:ok, %BatchedEvent{}} =
               Batcher.create_event(%{source_name: "some name", body: %{"test" => "testing"}})

      # no source
      assert {:error, %Ecto.Changeset{}} = Batcher.create_event(%{body: %{"test" => "testing"}})

      # no body
      assert {:error, %Ecto.Changeset{}} = Batcher.create_event(%{source_name: "some name"})
    end

    test "update_event/2" do
      event = insert(:pending_event)
      assert [_] = Batcher.list_events_by(:pending)
      assert [] = Batcher.list_events_by(:inflight)

      assert {:ok, _updated} =
               Batcher.update_event(event, %{inflight_at: NaiveDateTime.utc_now()})

      assert [] = Batcher.list_events_by(:pending)
      assert [_] = Batcher.list_events_by(:inflight)
    end

    test "delete_all_events/0" do
      insert(:pending_event)
      insert(:inflight_event)
      assert :ok = Batcher.delete_all_events()
      assert [] = Batcher.list_events_by(:all)
    end

    test "delete_event/1" do
      event = insert(:pending_event)
      assert {:ok, %_{}} = Batcher.delete_event(event)
      assert [] = Batcher.list_events_by(:all)
    end
  end

  describe "Batcher genserver" do
    setup do
      Tesla
      |> stub(:post, fn _client, _path, _body ->
        {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
      end)

      :ok
    end

    test "manual flush by source token" do
      client = Client.new(source_token: "some-uuid", auto_flush: false)
      start_link_supervised!({Batcher, client})

      insert(:pending_event, source_token: "some-uuid")
      assert :ok = Batcher.flush(source_token: "some-uuid")
      Process.sleep(1000)
      assert [] = Batcher.list_events_by(:all)
    end

    test "manual flush by source name" do
      client = Client.new(source_name: "some name", auto_flush: false)
      start_supervised!({Batcher, client})

      insert(:pending_event, source_name: "some name")
      assert :ok = Batcher.flush(source_name: "some name")
      Process.sleep(500)
      assert [] = Batcher.list_events_by(:all)
    end

    test "auto flush" do
      client = Client.new(source_name: "some name", auto_flush: true, flush_interval: 100)
      start_supervised!({Batcher, client})

      insert(:pending_event, source_name: "some name")
      Process.sleep(500)
      assert [] = Batcher.list_events_by(:all)
    end

    test ":auto_flush disabled" do
      client = Client.new(source_name: "some name", auto_flush: false, flush_interval: 100)
      start_supervised!({Batcher, client})
      insert(:pending_event, source_name: "some name")
      Process.sleep(500)
      assert [_] = Batcher.list_events_by(:all)
    end
  end
end
