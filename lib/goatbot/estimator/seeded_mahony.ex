defmodule Goatbot.Estimator.SeededMahony do
  @moduledoc """
  `BB.Estimator.Ahrs.Mahony`, started from the attitude the accelerometer
  reports rather than from identity.

  ## Why

  The filter starts at the identity quaternion, but the chip is mounted at pitch
  90°, yaw -90°, so at boot the estimate is a right angle out. At this robot's
  `kp` 0.2 and `ki` 0.005 that takes minutes to settle: replayed through the
  real `Mahony.step/4`, the lean was still 9° off 10 s after boot, 3.3° at 60 s
  and 1° at 100 s, and the robot drifted 0.9° between 93 s and 206 s while
  sitting still on its charger. Worse, the error is learned into the integral
  as a bogus gyro bias of about -1.7°/s, which then has to be unlearned.

  Stood up inside that window the balancer holds a lean degrees away from the
  balance point, and the velocity loop turns every degree into about 9 cm/s of
  crawl, which is the robot driving across the room at zero throttle.

  ## What it does

  The first `seed_samples` accelerometer readings within `accel_threshold` of
  1 g are averaged, and the orientation is set to the smallest rotation taking
  their direction to straight up: the tilt the robot is actually at, with an
  arbitrary yaw, which nothing reads. The integral starts at zero, so no bias
  is learned from a start-up error. From then on it is plain Mahony.

  Readings away from 1 g are someone moving the robot, so they aren't counted;
  a robot carried about at boot seeds once it is put down.
  """

  use BB.Estimator,
    options_schema: [
      kp: [type: :float, default: 2.0, doc: "Proportional gain"],
      ki: [type: :float, default: 0.0, doc: "Integral gain"],
      accel_threshold: [
        type: :float,
        default: 0.1,
        doc: "Maximum fractional deviation of accelerometer magnitude from 1 g"
      ],
      e_int_limit: [
        type: :float,
        default: 100.0,
        doc: "Anti-windup clamp on the integral term"
      ],
      seed_samples: [
        type: :pos_integer,
        default: 20,
        doc: "Accelerometer readings averaged for the starting attitude"
      ]
    ]

  alias BB.Estimator.Ahrs.Mahony
  alias BB.Estimator.Ahrs.Math, as: AhrsMath
  alias BB.Math.Quaternion
  alias BB.Math.Vec3
  alias BB.Message
  alias BB.Message.Sensor.Imu

  @impl BB.Estimator
  def init(opts) do
    {:ok, mahony} = Mahony.init(opts)

    {:ok,
     %{
       mahony: mahony,
       seed_samples: Keyword.fetch!(opts, :seed_samples),
       seed: {0.0, 0.0, 0.0},
       seeded: 0
     }}
  end

  @impl BB.Estimator
  def handle_options(opts, state) do
    {:ok, mahony} = Mahony.handle_options(opts, state.mahony)
    {:ok, %{state | mahony: mahony, seed_samples: Keyword.fetch!(opts, :seed_samples)}}
  end

  @impl BB.Estimator
  def handle_input(%Message{} = message, %{seeded: seeded, seed_samples: n} = state)
      when seeded >= n do
    case Mahony.handle_input(message, state.mahony) do
      {:reply, outputs, mahony} -> {:reply, outputs, %{state | mahony: mahony}}
      {:noreply, mahony} -> {:noreply, %{state | mahony: mahony}}
    end
  end

  def handle_input(%Message{payload: %Imu{} = imu} = message, state) do
    state = seed(state, imu.linear_acceleration, message.monotonic_time)

    {:ok, out} =
      Imu.new(message.frame_id,
        orientation: state.mahony.q,
        angular_velocity: imu.angular_velocity,
        linear_acceleration: imu.linear_acceleration
      )

    {:reply, [out: out], state}
  end

  def handle_input(_other, state), do: {:noreply, state}

  # Each reading near 1 g goes into the average, and the attitude is set from
  # the average so far, so the output is the best guess there is from the first
  # sample on. The timestamp is kept so the first proper step has a sane dt.
  defp seed(state, accel, at) do
    {ax, ay, az} = {Vec3.x(accel), Vec3.y(accel), Vec3.z(accel)}
    norm = :math.sqrt(ax * ax + ay * ay + az * az)
    mahony = %{state.mahony | last_monotonic_time: at}

    if norm > 0.0 and abs(norm / AhrsMath.gravity() - 1.0) <= mahony.accel_threshold do
      {sx, sy, sz} = state.seed
      seed = {sx + ax / norm, sy + ay / norm, sz + az / norm}

      %{
        state
        | seed: seed,
          seeded: state.seeded + 1,
          mahony: %{mahony | q: tilt(seed), e_int: {0.0, 0.0, 0.0}}
      }
    else
      %{state | mahony: mahony}
    end
  end

  @doc """
  The smallest rotation taking `up`, a direction in the sensor's frame, to the
  world's +Z: the orientation of a sensor at rest that reads `up` as the
  direction of its accelerometer's 1 g. `up` needn't be normalised.

  Mahony's quaternion takes the sensor frame into the world, so this is the one
  whose inverse carries +Z back to `up`.
  """
  @spec tilt({float, float, float}) :: Quaternion.t()
  def tilt({x, y, z}) do
    norm = :math.sqrt(x * x + y * y + z * z)
    {x, y, z} = {x / norm, y / norm, z / norm}

    # Half-way quaternion: w = 1 + up·Z, vector part = up × Z. Upside down
    # there's no unique axis, so take a half turn about X.
    if z < -0.999_999,
      do: Quaternion.new(0.0, 1.0, 0.0, 0.0),
      else: Quaternion.new(1.0 + z, y, -x, 0.0)
  end
end
