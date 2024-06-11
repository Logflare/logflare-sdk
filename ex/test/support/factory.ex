defmodule WarehouseEx.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: WarehouseEx.Repo
  alias WarehouseEx.BatchedEvent

  def pending_event_factory(attrs) do
    %BatchedEvent{
      source_name:
        if(attrs[:source_token] != nil, do: nil, else: attrs[:source_name] || random_string()),
      source_token:
        if(attrs[:source_name] != nil, do: nil, else: attrs[:source_token] || random_string()),
      created_at: NaiveDateTime.utc_now(),
      body: %{"some" => "value"}
    }
  end

  def inflight_event_factory(attrs) do
    %BatchedEvent{
      source_name:
        if(attrs[:source_token] != nil, do: nil, else: attrs[:source_name] || random_string()),
      source_token:
        if(attrs[:source_name] != nil, do: nil, else: attrs[:source_token] || random_string()),
      created_at: NaiveDateTime.utc_now(),
      inflight_at: NaiveDateTime.utc_now(),
      body: %{"some" => "value"}
    }
  end

  defp random_string(n \\ 5), do: :crypto.strong_rand_bytes(n)
end
