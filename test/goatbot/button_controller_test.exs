defmodule Goatbot.ButtonControllerTest do
  use ExUnit.Case, async: true

  import Goatbot.ButtonController, only: [command: 3]

  @buttons [arm_toggle: 1, poweroff: 3]

  test "the arm button toggles" do
    assert command(1, false, @buttons) == :arm
    assert command(1, true, @buttons) == :disarm
  end

  # Whether it's allowed is the command system's call: poweroff only runs from
  # `:disarmed`.
  test "the third button powers off" do
    assert command(3, false, @buttons) == :poweroff
    assert command(3, true, @buttons) == :poweroff
  end

  test "the middle button does nothing yet" do
    assert command(2, false, @buttons) == nil
    assert command(2, true, @buttons) == nil
  end
end
