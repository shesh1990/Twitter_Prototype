defmodule TwitterClientTest do
  use ExUnit.Case
  doctest TwitterClient

  test "greets the world" do
    assert TwitterClient.hello() == :world
  end
end
