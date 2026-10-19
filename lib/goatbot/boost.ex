defmodule Goatbot.Boost do
  @moduledoc """
  Switches the motors' boost converter (enable on PE6) on while the robot is
  armed, and off while it isn't.

  The H-bridges have no sleep pins, so the boost is what stands between the
  battery and the motors: off, a PWM channel left driving has nothing to drive
  with. It was the left wheel's "sleep pin" under `BB.NSK.Wheel`, and so went
  up and down with that one wheel's state; `Goatbot.Wheel` leaves it alone.

  Set on every state transition from `BB.Safety.armed?/1`, and on start. The
  arm command arms before it transitions, so the boost is up by the time
  anything can ask the wheels to move. `disarm/1` drives it low from outside
  the process, so a disarm takes the motor supply away even if this has died.
  """

  use BB.Controller,
    options_schema: [
      pin: [type: :string, default: "PE6", doc: "GPIO line wired to the boost converter's enable"]
    ]

  alias BB.Message
  alias BB.StateMachine.Transition
  alias Circuits.GPIO

  require Logger

  @impl BB.Controller
  def init(opts) do
    %{robot: robot} = Keyword.fetch!(opts, :bb)

    case GPIO.open(Keyword.fetch!(opts, :pin), :output, initial_value: 0) do
      {:ok, gpio} ->
        # So `terminate/2` runs, and the boost goes off with the robot.
        Process.flag(:trap_exit, true)
        {:ok, _} = BB.PubSub.subscribe(robot, [:state_machine])
        {:ok, set(%{robot: robot, gpio: gpio, on?: false}, BB.Safety.armed?(robot))}

      {:error, reason} ->
        Logger.info(
          "No boost enable (#{inspect(reason)}), so #{inspect(__MODULE__)} is not starting."
        )

        :ignore
    end
  end

  @impl BB.Controller
  def handle_call(:inspect, _from, state), do: {:reply, state, state}

  @impl BB.Controller
  def handle_info({:bb, [:state_machine], %Message{payload: %Transition{}}}, state) do
    {:noreply, set(state, BB.Safety.armed?(state.robot))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl BB.Controller
  def disarm(opts) do
    with {:ok, gpio} <- GPIO.open(Keyword.fetch!(opts, :pin), :output) do
      GPIO.write(gpio, 0)
      GPIO.close(gpio)
    end

    :ok
  end

  @impl BB.Controller
  def terminate(_reason, state) do
    GPIO.write(state.gpio, 0)
    :ok
  end

  defp set(state, on?) do
    GPIO.write(state.gpio, if(on?, do: 1, else: 0))
    if on? != state.on?, do: Logger.info("Boost converter #{if on?, do: "on", else: "off"}")

    %{state | on?: on?}
  end
end
