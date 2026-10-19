defmodule Goatbot.VelocityControllerTest do
  use ExUnit.Case, async: true

  alias Goatbot.VelocityController

  @degree :math.pi() / 180

  # Defaults from `Goatbot.Robot`'s `:velocity` parameters, balancing and
  # standing still with nobody driving.
  defp state(overrides) do
    Map.merge(
      %{
        mode: :balancing,
        settled?: true,
        sum: 0.0,
        count: 0,
        average: 0.0,
        velocity: 0.0,
        offset: 0.0,
        trim: 0.0,
        target_speed: 0.0,
        speed_ref: 0.0,
        gain: 0.0,
        filter: 0.2,
        limit: 5 * @degree,
        ceiling: 50.0,
        trim_gain: 0.001,
        trim_window: 10.0,
        trim_limit: 2 * @degree,
        damping: 0.0043,
        drive_accel: 1.0,
        drive_decel: 2.0,
        wheel_radius: 0.0215
      },
      Map.new(overrides)
    )
  end

  # `seconds` of 50 Hz ticks with the wheels commanded at `command` throughout.
  defp hold(state, command, seconds) do
    Enum.reduce(1..round(seconds * 50), state, fn _, state ->
      VelocityController.tick(%{state | sum: command, count: 1}, 0.02)
    end)
  end

  describe "trim" do
    # 1.5° off the balance point crawls at 1.5° / damping, about 6 rad/s, which
    # the old 3 rad/s window never learned from.
    test "learns from the crawl a 1.5° error makes" do
      crawl = 1.5 * @degree / 0.0043
      state = hold(state(average: crawl), crawl, 1.0)

      assert state.trim < -0.005
    end

    test "doesn't learn from a shove faster than the window" do
      state = hold(state(average: 15.0), 15.0, 1.0)
      assert state.trim == 0.0
    end
  end

  describe "limit" do
    # Around the trim, so a trim at +2° still leaves ±5° for braking and driving
    # rather than 3° one way and 7° the other.
    test "applies to braking and driving, either side of the trim" do
      trim = 2 * @degree

      forward = hold(state(trim: trim, average: 30.0, settled?: false), 30.0, 0.1)
      backward = hold(state(trim: trim, average: -30.0, settled?: false), -30.0, 0.1)

      assert_in_delta forward.offset, trim - 5 * @degree, 1.0e-9
      assert_in_delta backward.offset, trim + 5 * @degree, 1.0e-9
    end
  end
end
