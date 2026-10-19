defmodule Goatbot.Balancer do
  @moduledoc """
  A minimal PID balance loop.

  Ticks on every sample the `:lean_angle` sensor publishes (a `JointState` with
  the lean in radians and the gyro's lean rate in rad/s), and drives both wheels
  at the same velocity:

      target  = setpoint + offset
      command = kp * error + ki * ∫error dt + kd * rate,  error = lean - target

  It only drives while the robot is `:balancing`. Arm the robot and hold it
  upright and still for `stand_hold` seconds, and it stands by itself; or run
  `Goatbot.Robot.stand/0` to hand it over at once. If the lean error passes
  `fall_angle`, it brakes the wheels and runs `Goatbot.Robot.fall/0`.

  ## Standing by itself

  While armed and not balancing (`:idle` after arming, or `:fallen`), every
  sample that would pass the catch below counts towards `stand_hold`; one that
  wouldn't starts the count again. Held there for the whole time, it runs
  `Goatbot.Robot.stand/0`. A robot lying on its side, or being carried about,
  never gets there.

  ## Catching

  A stand doesn't drive the wheels straight away. It waits until the lean is
  within `catch_angle` of the target and turning slower than `catch_rate`,
  then takes over, as the stock `bb_nsk` balancer did. Without that, a stand
  given while the robot was tilted 10°, or still swinging in the hand, started
  at kp * 0.17 = 17 rad/s with the integral climbing, and lurched off further
  than the velocity loop could bring it back.

  ## Why the integral is large

  The wheels behave like a speed servo: torque goes with the command minus the
  speed they're already turning at. Holding the body at a lean means
  accelerating, which means a command that keeps growing while the lean
  persists, and only the integral does that. With P and D alone the robot ran
  away within seconds on every attempt; with `ki` 400 it holds the lean it's
  given, and the command tracks the wheel speed, which is what
  `Goatbot.VelocityController` relies on.

  The price is that a wrong setpoint means accelerating for as long as it's
  held, so the velocity loop is not optional.

  ## Turning

  The latest `Goatbot.Message.Differential` on `[:yaw]`, from
  `Goatbot.YawController`, is mixed in: left gets `command + differential`,
  right `command - differential`, so a positive differential turns the robot
  left.

  That's the opposite of the stock `bb_nsk` mixing, whose comments say its signs
  were confirmed on hardware. On this robot they weren't: with the stock mixing
  the yaw loop asked for a right turn while the gyro showed it turning left at
  88°/s, harder and harder. Either the actuators named left and right are on
  the other sides, or one turn sense is reversed somewhere; this mixing is what
  the robot actually does. Balance comes first, so the differential is
  cut back to whatever headroom is left under `max_wheel_speed`, and one older
  than `offset_timeout` counts as zero.

  `offset` is the latest `Goatbot.Message.LeanOffset` on `[:lean_offset]`, sent
  by `Goatbot.VelocityController`. One older than `offset_timeout` counts as
  zero, so if that controller stops, this is a plain PID loop again.
  """

  import BB.Unit

  use BB.Controller,
    options_schema: [
      setpoint: [
        type: BB.Unit.Option.unit_type(compatible: :degree),
        required: true,
        doc: "The lean to hold. Negative leans back"
      ],
      kp: [type: :float, required: true, doc: "Wheel rad/s per radian of lean error"],
      ki: [type: :float, default: 0.0, doc: "Wheel rad/s per radian-second of lean error"],
      kd: [type: :float, required: true, doc: "Wheel rad/s per rad/s of lean rate"],
      integral_limit: [
        type: :float,
        default: 0.1,
        doc: "Clamp on the integral, in radian-seconds, so it can't wind up"
      ],
      fall_angle: [
        type: BB.Unit.Option.unit_type(compatible: :degree),
        required: true,
        doc: "Lean error past which it gives up"
      ],
      catch_angle: [
        type: BB.Unit.Option.unit_type(compatible: :degree),
        default: ~u(2 degree),
        doc: "Lean error within which a stand takes over"
      ],
      catch_rate: [
        type: BB.Unit.Option.unit_type(compatible: :degree_per_second),
        default: ~u(4 degree_per_second),
        doc: "Lean rate below which a stand takes over"
      ],
      stand_hold: [
        type: :float,
        default: 3.0,
        doc: "Seconds an armed robot must be held upright and still before it stands by itself"
      ],
      max_wheel_speed: [
        type: :float,
        default: 31.4,
        doc: "The motors' top speed, in rad/s: the most a wheel can be asked for"
      ],
      offset_timeout: [
        type: :pos_integer,
        default: 500,
        doc: "Milliseconds a lean offset stays good for"
      ],
      left_wheel: [type: :atom, default: :left_wheel],
      right_wheel: [type: :atom, default: :right_wheel]
    ]

  require Logger

  alias BB.Message
  alias BB.Message.Sensor.JointState
  alias BB.Robot.Units
  alias BB.StateMachine.Transition
  alias Goatbot.Message.Differential
  alias Goatbot.Message.LeanOffset

  @impl BB.Controller
  def init(opts) do
    %{robot: robot} = Keyword.fetch!(opts, :bb)

    # Built from the topology rather than written out, so it's the same path the
    # supervisors gave the sensor: [:sensor, :world, :ground, :ground_contact, :lean, :lean_angle].
    {:ok, lean_joint_path} = BB.Robot.path_to(robot.robot(), :lean)
    lean_path = [:sensor | lean_joint_path] ++ [:lean_angle]

    {:ok, _} = BB.PubSub.subscribe(robot, [:state_machine])
    {:ok, _} = BB.PubSub.subscribe(robot, lean_path, message_types: [JointState])

    {:ok, _} =
      BB.PubSub.subscribe(robot, Goatbot.VelocityController.path(), message_types: [LeanOffset])

    {:ok, _} =
      BB.PubSub.subscribe(robot, Goatbot.YawController.path(), message_types: [Differential])

    state = %{
      robot: robot,
      mode: BB.Robot.Runtime.state(robot),
      integral: 0.0,
      last: nil,
      last_command: 0.0,
      offset: 0.0,
      offset_at: nil,
      differential: 0.0,
      differential_at: nil,
      target: nil,
      caught?: false,
      upright_since: nil
    }

    {:ok, configure(opts, state)}
  end

  # Fired when a param([...]) referenced in the DSL changes, e.g.
  # BB.Parameter.set(Goatbot.Robot, [:balance, :proportional_gain], 150.0)
  @impl BB.Controller
  def handle_options(opts, state), do: {:ok, configure(opts, state)}

  @impl BB.Controller
  def handle_call(:inspect, _from, state), do: {:reply, state, state}

  @impl BB.Controller
  def handle_info({:bb, [:state_machine], %Message{payload: %Transition{to: to}}}, state) do
    # Start every attempt from a clean slate: no stale integral, no huge dt,
    # no offset left over from last time, and nothing driven until it's caught.
    {:noreply,
     %{
       state
       | mode: to,
         integral: 0.0,
         last: nil,
         last_command: 0.0,
         offset: 0.0,
         offset_at: nil,
         differential: 0.0,
         differential_at: nil,
         target: nil,
         caught?: false,
         upright_since: nil
     }}
  end

  def handle_info({:bb, _path, %Message{payload: %LeanOffset{offset: offset}} = msg}, state) do
    {:noreply, %{state | offset: offset, offset_at: msg.monotonic_time}}
  end

  def handle_info({:bb, _path, %Message{payload: %Differential{differential: d}} = msg}, state) do
    {:noreply, %{state | differential: d, differential_at: msg.monotonic_time}}
  end

  def handle_info(
        {:bb, _path, %Message{payload: %JointState{positions: [lean], velocities: [rate]}} = msg},
        %{mode: :balancing} = state
      ) do
    {:noreply, step(state, lean, rate, msg.monotonic_time)}
  end

  def handle_info(
        {:bb, _path, %Message{payload: %JointState{positions: [lean], velocities: [rate]}} = msg},
        %{mode: mode} = state
      )
      when mode in [:idle, :fallen] do
    {:noreply, wait_to_stand(state, lean, rate, msg.monotonic_time)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # No offset outside `:balancing`: the velocity loop only publishes one while
  # balancing, and the transition cleared the last.
  defp wait_to_stand(state, lean, rate, now) do
    upright? = catchable?(lean - state.setpoint, rate, state.catch_angle, state.catch_rate)

    case hold(state.upright_since, upright?, now, state.stand_hold) do
      {:stand, since} ->
        case state.robot.stand() do
          {:ok, _pid} ->
            Logger.info("Held upright for #{state.stand_hold} s: standing")

          {:error, reason} ->
            Logger.warning("Held upright, but stand refused: #{inspect(reason)}")
        end

        # Restarted rather than cleared, so the samples that arrive before the
        # transition comes back don't each ask again.
        %{state | upright_since: since}

      {:wait, since} ->
        %{state | upright_since: since}
    end
  end

  @doc """
  Whether a robot that has been upright since `since` (nil: it isn't) should
  stand now, given whether this sample at `now` (ns) is upright. `:stand` once
  it has been upright for `hold` seconds, with the count restarted; `:wait`
  otherwise, with the count to carry on with.
  """
  @spec hold(integer | nil, boolean, integer, float) :: {:stand | :wait, integer | nil}
  def hold(_since, false, _now, _hold), do: {:wait, nil}
  def hold(nil, true, now, _hold), do: {:wait, now}

  def hold(since, true, now, hold) do
    if now - since >= hold * 1_000_000_000, do: {:stand, now}, else: {:wait, since}
  end

  defp step(state, lean, rate, now) do
    target = state.setpoint + current_offset(state, now)
    error = lean - target

    cond do
      abs(error) > state.fall_angle ->
        fall(state)

      state.caught? or catchable?(error, rate, state.catch_angle, state.catch_rate) ->
        balance(%{state | caught?: true}, error, rate, target, now)

      # Not still enough yet: leave the wheels alone, and keep `last` unset so
      # the first step after the catch doesn't integrate the wait.
      true ->
        %{state | target: target}
    end
  end

  @doc """
  Whether a robot `error` radians off its target and leaning at `rate` rad/s is
  near enough and still enough to take over.
  """
  @spec catchable?(float, float, float, float) :: boolean
  def catchable?(error, rate, catch_angle, catch_rate),
    do: abs(error) <= catch_angle and abs(rate) <= catch_rate

  defp balance(state, error, rate, target, now) do
    dt = if state.last, do: (now - state.last) / 1_000_000_000, else: 0.0

    integral =
      (state.integral + error * dt)
      |> max(-state.integral_limit)
      |> min(state.integral_limit)

    # The gyro's rate rather than a differentiated error: it's measured
    # directly, so it's far less noisy.
    command = state.kp * error + state.ki * integral + state.kd * rate

    # Leaning forward is positive, and the fix is to drive forward under it,
    # so both wheels take the command's sign; turning runs one faster than the
    # other, with whatever headroom balancing leaves.
    headroom = max(state.max_wheel_speed - abs(command), 0.0)
    differential = current_differential(state, now) |> max(-headroom) |> min(headroom)

    BB.Actuator.set_velocity(state.robot, state.left_wheel, command + differential)
    BB.Actuator.set_velocity(state.robot, state.right_wheel, command - differential)

    %{state | integral: integral, last: now, last_command: command, target: target}
  end

  defp current_differential(%{differential_at: nil}, _now), do: 0.0

  defp current_differential(state, now) do
    if now - state.differential_at <= state.offset_timeout * 1_000_000,
      do: state.differential,
      else: 0.0
  end

  defp current_offset(%{offset_at: nil}, _now), do: 0.0

  defp current_offset(state, now) do
    if now - state.offset_at <= state.offset_timeout * 1_000_000, do: state.offset, else: 0.0
  end

  defp fall(state) do
    BB.Actuator.hold(state.robot, state.left_wheel)
    BB.Actuator.hold(state.robot, state.right_wheel)
    state.robot.fall()

    # Set locally rather than waiting for the transition to come back through
    # pubsub, or the samples arriving in the meantime would drive the wheels again.
    %{state | mode: :fallen, last: nil}
  end

  defp configure(opts, state) do
    Map.merge(state, %{
      setpoint: Units.to_radians(Keyword.fetch!(opts, :setpoint)),
      kp: Keyword.fetch!(opts, :kp),
      ki: Keyword.fetch!(opts, :ki),
      kd: Keyword.fetch!(opts, :kd),
      integral_limit: Keyword.fetch!(opts, :integral_limit),
      fall_angle: Units.to_radians(Keyword.fetch!(opts, :fall_angle)),
      catch_angle: Units.to_radians(Keyword.fetch!(opts, :catch_angle)),
      catch_rate: Units.to_radians_per_second(Keyword.fetch!(opts, :catch_rate)),
      stand_hold: Keyword.fetch!(opts, :stand_hold),
      offset_timeout: Keyword.fetch!(opts, :offset_timeout),
      max_wheel_speed: Keyword.fetch!(opts, :max_wheel_speed),
      left_wheel: Keyword.fetch!(opts, :left_wheel),
      right_wheel: Keyword.fetch!(opts, :right_wheel)
    })
  end
end
