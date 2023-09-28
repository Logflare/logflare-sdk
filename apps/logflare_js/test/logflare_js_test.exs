defmodule LogflareJsTest do
  use ExUnit.Case
  doctest LogflareJs

  test "greets the world" do
    assert LogflareJs.hello() == :world
  end
end
