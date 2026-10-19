defmodule Goatbot.ButtonController do
  @moduledoc """
  Turns the board's buttons into robot commands.

  | button | does                                         |
  | ------ | -------------------------------------------- |
  | 1      | arm, or disarm if armed                      |
  | 2      | nothing yet: kept for a mode switch          |
  | 3      | power off, only once disarmed                |

  Acts on the press, not the release. Commands go through the robot's command
  system as they would from IEx, so a press in a state that doesn't allow the
  command is refused and logged rather than acted on. `poweroff` is only
  allowed from `:disarmed`, so button 3 can't drop a balancing robot: disarm
  with button 1 first. Nothing waits for a command to finish, so a slow one
  doesn't hold up the next press.

  The STM32 debounces the buttons (50 ms) and reports `pressed: true` for a
  press. The events reach here via `Goatbot.Sensor.Power` on `[:buttons]`, so
  on the host this never hears anything.

  Standing up needs no button: hold the armed robot upright and still and
  `Goatbot.Balancer` takes over by itself.
  """

  use BB.Controller,
    options_schema: [
      arm_toggle: [type: {:in, [1, 2, 3]}, default: 1, doc: "Button that arms and disarms"],
      poweroff: [type: {:in, [1, 2, 3]}, default: 3, doc: "Button that powers off"]
    ]

  require Logger

  alias BB.Message
  alias Goatbot.Message.Button

  @doc """
  The command a press of `button` asks for, given whether the robot is armed.
  Pure, so it can be tested without a robot.
  """
  @spec command(1..3, boolean, keyword) :: :arm | :disarm | :poweroff | nil
  def command(button, armed?, buttons) do
    cond do
      button == buttons[:arm_toggle] and armed? -> :disarm
      button == buttons[:arm_toggle] -> :arm
      button == buttons[:poweroff] -> :poweroff
      true -> nil
    end
  end

  @impl BB.Controller
  def init(opts) do
    %{robot: robot} = Keyword.fetch!(opts, :bb)

    {:ok, _} =
      BB.PubSub.subscribe(robot, Goatbot.Sensor.Power.buttons_path(), message_types: [Button])

    {:ok, %{robot: robot, buttons: Keyword.take(opts, [:arm_toggle, :poweroff])}}
  end

  @impl BB.Controller
  def handle_info({:bb, _path, %Message{payload: %Button{button: button, pressed: true}}}, state) do
    case command(button, BB.Safety.armed?(state.robot), state.buttons) do
      nil -> :ok
      name -> run(state.robot, name, button)
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run(robot, name, button) do
    case apply(robot, name, []) do
      {:ok, _pid} ->
        Logger.info("Button #{button}: #{name}")

      {:error, reason} ->
        Logger.warning("Button #{button}: #{name} refused: #{inspect(reason)}")
    end
  end
end
