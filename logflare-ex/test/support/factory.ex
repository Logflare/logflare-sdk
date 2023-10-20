defmodule LogflareEx.Factory do
  # with Ecto
  use ExMachina.Ecto, repo: LogflareEx.Repo
  alias LogflareEx.BatchedEvent

  def pending_event_factory() do
    %BatchedEvent{
      source_token: random_string(),
      created_at: NaiveDateTime.utc_now(),
      body: %{"some" => "value"}
    }
  end

  def inflight_event_factory() do
    %BatchedEvent{
      source_token: random_string(),
      created_at: NaiveDateTime.utc_now(),
      inflight_at: NaiveDateTime.utc_now(),
      body: %{"some" => "value"}
    }
  end

  defp random_string(n \\ 5), do: :crypto.strong_rand_bytes(n)
end
