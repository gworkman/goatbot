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
  anything can ask the wheels to move.

  `disarm/1` runs from the safety system, possibly after this process has died.
  A line can only be open once, so while this process is alive and holding PE6,
  `disarm/1` asks it to drive the pin low; once it has died the line is free,
  and `disarm/1` opens it and drives it low itself.
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
        # So `disarm/1` can find it without any state.
        Process.register(self(), __MODULE__)
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
  def handle_call(:off, _from, state), do: {:reply, :ok, set(state, false)}

  @impl BB.Controller
  def handle_info({:bb, [:state_machine], %Message{payload: %Transition{}}}, state) do
    {:noreply, set(state, BB.Safety.armed?(state.robot))}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl BB.Controller
  def disarm(opts) do
    case GPIO.open(Keyword.fetch!(opts, :pin), :output, initial_value: 0) do
      {:ok, gpio} ->
        GPIO.write(gpio, 0)
        GPIO.close(gpio)

      {:error, _held} ->
        GenServer.call(__MODULE__, :off, 1_000)
    end

    :ok
  catch
    :exit, reason ->
      Logger.error("Could not switch the boost converter off: #{inspect(reason)}")
      {:error, reason}
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
