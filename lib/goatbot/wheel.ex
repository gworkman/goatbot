defmodule Goatbot.Wheel do
  @moduledoc """
  Drives one wheel through its H-bridge's two PWM inputs: `BB.NSK.Wheel`
  without the sleep pin.

  `BB.NSK.Wheel` expects a bridge with a sleep pin, and takes a GPIO line for
  it. This board's bridges have none: what it was given as the left wheel's,
  PE6, is the boost converter's enable, which the driver then switched on and
  off with that one wheel's state. The boost is `Goatbot.Boost`'s now, on for as
  long as the robot is armed, and this drives the inputs and nothing else.

  Everything else is `BB.NSK.Wheel`'s, and its docs are the reference: open
  loop, a velocity turned into a duty cycle against `max_velocity` with the
  deadband skipped over (`BB.NSK.Wheel.drive_ratio/2` and
  `BB.NSK.Wheel.compensate/2`, used as they are), slow or fast decay, `Stop`
  coasting and `Hold` braking, and a watchdog that coasts a wheel nobody has
  commanded for `command_timeout`.

  ## Changing between brake and drive

  The sleep pin was how `BB.NSK.Wheel` changed the inputs without a glitch:
  asleep, the outputs are high impedance whatever the inputs do. Without it the
  inputs change one write after the other, so the order is chosen to keep the
  in-between state harmless. Driving into a brake raises the input that is
  pulsing, since the held one is already high; from a brake into driving the
  held input is already high and the other drops to its duty. Only braking from
  a coast, or coasting from a brake, passes through a full-duty state, for the
  length of one sysfs write: tens of microseconds, against a motor whose current
  takes milliseconds to build.

  ## Disarm

  `disarm/1` writes zero duty to both channels from outside the process, and
  `Goatbot.Boost` takes the motor supply away as well.
  """

  use BB.Actuator,
    options_schema: [
      forward_pwm: [
        type: :non_neg_integer,
        required: true,
        doc: "PWM channel that turns the wheel forwards"
      ],
      reverse_pwm: [
        type: :non_neg_integer,
        required: true,
        doc: "PWM channel that turns the wheel backwards"
      ],
      frequency: [
        type: :pos_integer,
        default: 20_000,
        doc: "PWM frequency in hertz. Above hearing, so the motors don't whine"
      ],
      max_velocity: [
        type: :float,
        default: 31.4,
        doc: "Wheel speed in rad/s at full duty, from the motor's rating"
      ],
      decay: [
        type: {:in, [:slow, :fast]},
        default: :slow,
        doc: "What the bridge does between pulses. `:slow` recirculates, `:fast` coasts"
      ],
      deadband: [
        type: :float,
        default: 0.01,
        doc: "Duty below which the motor doesn't turn, skipped over so no command is wasted"
      ],
      command_timeout: [
        type: :non_neg_integer,
        default: 250,
        doc: "Milliseconds of silence after which the wheel coasts. Zero to never give up"
      ]
    ]

  alias BB.Message
  alias BB.Message.Actuator.Command
  alias BB.NSK.PWM
  alias BB.NSK.Wheel

  require Logger

  @pwm "/sys/class/pwm/pwmchip0"

  @impl BB.Actuator
  def command_payloads(_opts), do: [Command.Hold, Command.Stop, Command.Velocity]

  @impl BB.Actuator
  def init(opts) do
    frequency = Keyword.fetch!(opts, :frequency)
    timeout = Keyword.fetch!(opts, :command_timeout)

    if timeout > 0, do: :timer.send_interval(max(div(timeout, 4), 10), :watchdog)

    with {:ok, forward} <- PWM.open(Keyword.fetch!(opts, :forward_pwm), frequency),
         {:ok, reverse} <- PWM.open(Keyword.fetch!(opts, :reverse_pwm), frequency) do
      {:ok,
       %{
         forward: forward,
         reverse: reverse,
         mode: :coast,
         decay: Keyword.fetch!(opts, :decay),
         deadband: Keyword.fetch!(opts, :deadband),
         max_velocity: Keyword.fetch!(opts, :max_velocity),
         command_timeout: timeout,
         commanded_at: nil
       }}
    else
      {:error, reason} ->
        Logger.info(
          "Could not claim the hardware for #{inspect(__MODULE__)} " <>
            "(#{inspect(reason)}), so it is not starting."
        )

        :ignore
    end
  end

  @impl BB.Actuator
  def handle_command(%Message{payload: %Command.Hold{}}, state) do
    {:noreply, brake(commanded(state))}
  end

  def handle_command(%Message{payload: %Command.Stop{}}, state) do
    {:noreply, coast(commanded(state))}
  end

  def handle_command(%Message{payload: %Command.Velocity{velocity: velocity}}, state) do
    ratio =
      velocity
      |> Wheel.drive_ratio(state.max_velocity)
      |> Wheel.compensate(state.deadband)

    {:noreply, drive(commanded(state), ratio)}
  end

  @impl BB.Actuator
  def handle_info(:watchdog, state) do
    {:noreply, watchdog(state, System.monotonic_time(:millisecond))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl BB.Actuator
  def handle_options(opts, state) do
    {:ok,
     %{
       state
       | decay: Keyword.fetch!(opts, :decay),
         deadband: Keyword.fetch!(opts, :deadband),
         max_velocity: Keyword.fetch!(opts, :max_velocity)
     }}
  end

  # Runs when things may already have gone wrong, possibly after this process
  # has died, so it writes to sysfs directly rather than through any state.
  @impl BB.Actuator
  def disarm(opts) do
    for channel <- [Keyword.fetch!(opts, :forward_pwm), Keyword.fetch!(opts, :reverse_pwm)] do
      File.write(Path.join([@pwm, "pwm#{channel}", "duty_cycle"]), "0")
    end

    :ok
  end

  @doc false
  def watchdog(%{commanded_at: nil} = state, _now), do: state
  def watchdog(%{mode: mode} = state, _now) when mode in [:coast, :brake], do: state

  def watchdog(state, now) do
    if now - state.commanded_at >= state.command_timeout do
      Logger.warning(
        "No command for #{state.command_timeout}ms while driving, so coasting. " <>
          "Something upstream has stopped talking."
      )

      coast(state)
    else
      state
    end
  end

  defp commanded(state), do: %{state | commanded_at: System.monotonic_time(:millisecond)}

  defp drive(state, ratio) when ratio > 0.0, do: turn(state, :forward, :reverse, ratio)
  defp drive(state, ratio) when ratio < 0.0, do: turn(state, :reverse, :forward, abs(ratio))
  defp drive(state, _stopped), do: coast(state)

  # As in `BB.NSK.Wheel`: in fast decay the idle input sits low and the driving
  # one is pulsed; in slow decay the driving input is held high and the idle one
  # pulsed with the complement. The held-high input is written first, so coming
  # out of a brake (both high) goes straight to driving, and changing direction
  # passes through the brake rather than a pulse the wrong way.
  defp turn(%{decay: :fast} = state, driving, idle, ratio) do
    state
    |> Map.put(idle, PWM.off(Map.fetch!(state, idle)))
    |> Map.put(driving, PWM.set_duty(Map.fetch!(state, driving), ratio))
    |> Map.put(:mode, driving)
  end

  defp turn(state, driving, idle, ratio) do
    state
    |> Map.put(driving, PWM.set_duty(Map.fetch!(state, driving), 1.0))
    |> Map.put(idle, PWM.set_duty(Map.fetch!(state, idle), 1.0 - ratio))
    |> Map.put(:mode, driving)
  end

  # Whichever input is already high goes first: in slow decay the one held for
  # the direction it was driving, so the other rising completes the brake.
  defp brake(%{mode: :reverse} = state) do
    reverse = PWM.set_duty(state.reverse, 1.0)
    %{state | reverse: reverse, forward: PWM.set_duty(state.forward, 1.0), mode: :brake}
  end

  defp brake(state) do
    forward = PWM.set_duty(state.forward, 1.0)
    %{state | forward: forward, reverse: PWM.set_duty(state.reverse, 1.0), mode: :brake}
  end

  defp coast(state) do
    %{state | forward: PWM.off(state.forward), reverse: PWM.off(state.reverse), mode: :coast}
  end
end
