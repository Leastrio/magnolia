defmodule MagnoliaTest do
  use ExUnit.Case
  doctest Magnolia

  test "greets the world" do
    assert Magnolia.hello() == :world
  end
end
