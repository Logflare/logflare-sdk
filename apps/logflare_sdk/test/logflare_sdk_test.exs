defmodule LogflareSdkTest do
  use ExUnit.Case
  doctest LogflareSdk

  test "greets the world" do
    assert LogflareSdk.hello() == :world
  end
end
