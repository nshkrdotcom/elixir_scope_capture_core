defmodule ElixirScope.Capture.CoreTest do
  use ExUnit.Case
  doctest ElixirScope.Capture.Core

  test "greets the world" do
    assert ElixirScope.Capture.Core.hello() == :world
  end
end
