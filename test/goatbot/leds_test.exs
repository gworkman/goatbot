defmodule Goatbot.LedsTest do
  use ExUnit.Case, async: true

  alias Goatbot.Leds

  test "fallen fades slowly rather than flashing" do
    assert Leds.pattern(:fallen) == {{255, 0, 180}, :fade}
  end

  test "everything else pulses" do
    assert {_colour, :pulse} = Leds.pattern(:balancing)
    assert {_colour, :pulse} = Leds.pattern(:disarmed)
  end
end
