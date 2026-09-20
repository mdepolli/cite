defmodule CiteTest do
  use ExUnit.Case
  doctest Cite

  test "greets the world" do
    assert Cite.hello() == :world
  end
end
