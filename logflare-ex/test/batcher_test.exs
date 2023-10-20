defmodule LogflareEx.BatcherTest do
  use LogflareEx.BatcherCase
  alias LogflareEx.Batcher
  alias LogflareEx.BatchedEvent

  test "list_events_by/2" do
    insert(:inflight_event)
    insert(:pending_event, source_token: "some-uuid")
    insert(:pending_event, source_name: "some name", source_token: nil)

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
