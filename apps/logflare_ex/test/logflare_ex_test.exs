defmodule LogflareExTest do
  use ExUnit.Case, async: false
  alias LogflareEx

  test "client/3" do
    assert %Tesla.Client{} = LogflareEx.client("https://localhost:4000", "some api key")
  end

  describe "with client" do
    setup do

      Tesla.Mock.mock(fn
        %{method: :post, url: "https://some-url" <> _} ->
          %Tesla.Env{status: 201, body: "hello"}
      end)


      {:ok, client: LogflareEx.client("https://some-url", "some api key", adapter: Tesla.Mock)}
    end
    test "send_events/2", %{client: client} do
      assert {:ok, %Tesla.Env{body: "hello"}} = LogflareEx.send_events(client, "some-uuid", [%{some: "event"}])
      assert {:error, :no_events} = LogflareEx.send_events(client, "some-uuid", [])
    end
  end



  @tag :benchmark
  # Bertex is way faster
  test "benchmark Jason vs Bertex" do
    large_sample = %{"batch"=> (for i <- 1..10_000, do: %{"some"=> "events", "other" => i, "nested"=> [%{"again" => "i_#{i}"}]}) }
    json_encoded = Jason.encode!(large_sample)
    bert_encoded = Bertex.encode(large_sample)
    Benchee.run(%{
      "bertex encode large" => fn() ->
        Bertex.encode(large_sample)
      end,
      "jason encode large" => fn ()->
        Jason.encode!(large_sample)
      end,

      "bertex decode large" => fn() ->
        Bertex.decode(bert_encoded)
      end,
      "jason decode large" => fn() ->
        Jason.decode!(json_encoded)
      end,
    })
  end
end
