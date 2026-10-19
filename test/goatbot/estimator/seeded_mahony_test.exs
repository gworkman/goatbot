defmodule Goatbot.Estimator.SeededMahonyTest do
  use ExUnit.Case, async: true

  alias BB.Estimator.Ahrs.Mahony
  alias BB.Math.Quaternion
  alias BB.Math.Vec3
  alias BB.Message
  alias BB.Message.Sensor.Imu
  alias BB.NSK.Sensor.Lean
  alias Goatbot.Estimator.SeededMahony

  @g 9.80665
  @opts [kp: 0.2, ki: 0.005, accel_threshold: 0.1, e_int_limit: 100.0, seed_samples: 20]

  defp degrees(angle), do: angle * 180 / :math.pi()
  defp radians(angle), do: angle * :math.pi() / 180

  # The robot's own mounting, from its topology: the chip at pitch 90°, yaw -90°.
  defp body_from_imu, do: Lean.body_from_imu(Goatbot.Robot, :base_link, :imu_link)

  # What the chip's accelerometer reads with the body standing still at `lean`
  # radians, positive forwards: up is (-sin, 0, cos) in the body, taken into
  # the chip's frame.
  defp accel_at(lean) do
    up = Vec3.new(-:math.sin(lean), 0.0, :math.cos(lean))

    body_from_imu()
    |> Quaternion.inverse()
    |> Quaternion.rotate_vector(up)
    |> Vec3.scale(@g)
  end

  defp sample(accel, at) do
    %Message{
      frame_id: :imu_link,
      monotonic_time: round(at * 1.0e9),
      payload: %Imu{
        orientation: Quaternion.identity(),
        angular_velocity: Vec3.new(0.0, 0.0, 0.0),
        linear_acceleration: accel
      }
    }
  end

  # Feeds `seconds` of 200 Hz samples, and returns the state and the last lean
  # the estimate gives.
  defp run(module, state, accel, seconds, from \\ 0.0) do
    Enum.reduce(0..round(seconds * 200), {state, nil}, fn i, {state, _lean} ->
      {:reply, [out: out], state} = module.handle_input(sample(accel, from + i / 200), state)
      {state, Lean.lean(out.payload.orientation, body_from_imu())}
    end)
  end

  describe "tilt/1" do
    test "carries straight up back to the direction it was given" do
      for up <- [
            {0.0, 0.0, 1.0},
            {1.0, 0.0, 0.0},
            {0.3, -0.5, 0.8},
            {0.0, -1.0, 0.0},
            {0.0, 0.0, -1.0}
          ] do
        q = SeededMahony.tilt(up)
        back = Quaternion.rotate_vector(Quaternion.inverse(q), Vec3.unit_z())
        {x, y, z} = up
        n = :math.sqrt(x * x + y * y + z * z)

        assert_in_delta Vec3.x(back), x / n, 1.0e-9
        assert_in_delta Vec3.y(back), y / n, 1.0e-9
        assert_in_delta Vec3.z(back), z / n, 1.0e-9
      end
    end
  end

  describe "handle_input/2" do
    test "reports the lean from the first sample, and holds it" do
      {:ok, state} = SeededMahony.init(@opts)
      accel = accel_at(radians(-3.4))

      {state, lean} = run(SeededMahony, state, accel, 0.0)
      assert_in_delta degrees(lean), -3.4, 0.01

      {_state, lean} = run(SeededMahony, state, accel, 10.0, 0.005)
      assert_in_delta degrees(lean), -3.4, 0.05
    end

    # What it fixes: started at identity, plain Mahony is still degrees off ten
    # seconds after boot.
    test "plain Mahony isn't settled ten seconds in" do
      {:ok, state} = Mahony.init(Keyword.delete(@opts, :seed_samples))
      {_state, lean} = run(Mahony, state, accel_at(radians(-3.4)), 10.0)

      assert abs(degrees(lean) + 3.4) > 1.0
    end

    test "doesn't seed from readings away from 1 g" do
      {:ok, state} = SeededMahony.init(@opts)

      {:reply, _, state} =
        SeededMahony.handle_input(sample(Vec3.new(0.0, 0.0, 2 * @g), 0.0), state)

      assert state.seeded == 0
      assert state.mahony.q == Quaternion.identity()
    end
  end
end
