defmodule Goatbot.NameTest do
  use ExUnit.Case, async: true

  alias Goatbot.Name

  describe "valid?/1" do
    test "takes a host name label" do
      assert Name.valid?("goatbot")
      assert Name.valid?("goat-2")
      assert Name.valid?("g")
    end

    test "refuses anything that isn't one" do
      refute Name.valid?("")
      refute Name.valid?("Goat")
      refute Name.valid?("goat.bot")
      refute Name.valid?("-goat")
      refute Name.valid?("goat-")
      refute Name.valid?(String.duplicate("g", 64))
      refute Name.valid?(:goat)
    end
  end

  describe "set/1" do
    test "refuses an invalid name without storing it" do
      assert Name.set("Goat Bot") == {:error, :invalid_name}
      assert Name.get() == Name.default()
    end
  end

  test "is the build-time name when none is set on the robot" do
    assert Name.get() == "goatbot"
  end
end
