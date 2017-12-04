defmodule TwitterServerTest do
  use ExUnit.Case
  doctest TwitterServer

  test "greets the world" do
    assert TwitterServer.hello() == :world
  end
end
