defmodule Goatbot.BalancerTest do
  use ExUnit.Case, async: true

  alias BB.Message
  alias BB.Message.Sensor.JointState
  alias Goatbot.Balancer

  @degree :math.pi() / 180

  # Just stood up: balancing, not yet caught. No robot, so driving the wheels
  # would raise, which is what makes "doesn't drive" testable.
  defp state(overrides \\ []) do
    Map.merge(
      %{
        robot: nil,
        mode: :balancing,
        caught?: false,
        setpoint: -3.4 * @degree,
        offset: 0.0,
        offset_at: nil,
        fall_angle: 30 * @degree,
        catch_angle: 2 * @degree,
        catch_rate: 4 * @degree,
        last: nil,
        target: nil
      },
      Map.new(overrides)
    )
  end

  defp lean(lean, rate) do
    payload = %JointState{names: [:lean], positions: [lean], velocities: [rate], efforts: []}
    {:bb, [:sensor, :lean_angle], %Message{payload: payload, monotonic_time: 0}}
  end

  describe "catchable?/4" do
    test "only near the target and still" do
      assert Balancer.catchable?(1 * @degree, 1 * @degree, 2 * @degree, 4 * @degree)
      refute Balancer.catchable?(3 * @degree, 0.0, 2 * @degree, 4 * @degree)
      refute Balancer.catchable?(0.0, 10 * @degree, 2 * @degree, 4 * @degree)
    end
  end

  describe "a stand" do
    test "doesn't drive while the robot is tilted" do
      {:noreply, state} = Balancer.handle_info(lean(10 * @degree, 0.0), state())

      refute state.caught?
      assert state.last == nil
    end

    test "doesn't drive while the robot is still swinging" do
      {:noreply, state} = Balancer.handle_info(lean(-3.4 * @degree, 30 * @degree), state())

      refute state.caught?
    end
  end
end
