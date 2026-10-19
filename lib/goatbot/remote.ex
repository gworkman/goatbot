defmodule Goatbot.Remote do
  @moduledoc """
  Drive commands from another Erlang node, such as the AtomVM badge's Goatbot
  page.

  Registered as `Goatbot.Remote`, so a peer sends to `{Goatbot.Remote, node}`
  without needing a pid first:

      send({Goatbot.Remote, :"goatbot@goatbot.local"}, {:drive, self(), throttle, turn})

  `throttle` and `turn` are both fractions from -1 to 1: positive is forwards
  and to the robot's left. Both lose a `[:drive, :remote_deadzone]` around
  zero, then the throttle goes to `BB.NSK.Drive.command/3` and the turn is
  scaled by the `[:yaw, :turn_rate]` parameter, so the robot keeps its own
  limits. Each command is answered with
  `{:goatbot, state}`, the robot's state machine state, which tells the
  sender that the link is up. `{:hello, from}` gets the same answer without
  driving.

  `{:command, from, name}` runs `:arm`, `:stand` or `:disarm` on the robot,
  as `Goatbot.IExHelpers` does, and answers `{:goatbot_command, name, text}`
  once it finishes: `"ok"`, or a short reason. It runs in its own process,
  so drive commands keep flowing while the robot arms.

  There is no stop message and no watchdog here: the controllers already
  drop a drive request after `drive_timeout`, so a sender that goes quiet
  stops the robot.
  """

  use GenServer

  require Logger

  @robot Goatbot.Robot
  @commands [:arm, :stand, :disarm]

  # Reasons are clipped to fit the badge's panel.
  @reason_bytes 24

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  The throttle and turn rate, in rad/s, for a request of `throttle` and
  `turn` (both -1 to 1) at a full `turn_rate`. Anything else reads as zero.

  Within `deadzone` of zero reads as zero, and the rest is stretched so a full
  request is still a full one. The badge steers by tilting, and a hand never
  holds it level: without this a badge at rest asked for a small drive the
  whole time, and every one of those requests stopped
  `Goatbot.VelocityController` learning its trim.
  """
  @spec command(term, term, number, number) :: {float, float}
  def command(throttle, turn, turn_rate, deadzone \\ 0.0),
    do: {fraction(throttle, deadzone), fraction(turn, deadzone) * turn_rate}

  defp fraction(value, deadzone) when is_number(value) do
    value = value |> max(-1.0) |> min(1.0) |> Kernel.+(0.0)

    if abs(value) <= deadzone,
      do: 0.0,
      else: (value - deadzone * sign(value)) / (1.0 - deadzone)
  end

  defp fraction(_value, _deadzone), do: 0.0

  defp sign(value) when value < 0.0, do: -1.0
  defp sign(_value), do: 1.0

  @impl true
  def init(_opts), do: {:ok, %{peer: nil}}

  @impl true
  def handle_info({:drive, from, throttle, turn}, state) when is_pid(from) do
    {throttle, turn} = command(throttle, turn, turn_rate(), deadzone())
    safely(fn -> BB.NSK.Drive.command(@robot, throttle, turn) end)
    {:noreply, answer(from, state)}
  end

  def handle_info({:hello, from}, state) when is_pid(from), do: {:noreply, answer(from, state)}

  def handle_info({:command, from, name}, state) when is_pid(from) and name in @commands do
    Task.start(fn -> send(from, {:goatbot_command, name, run(name)}) end)
    {:noreply, greet(node(from), state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp run(name) do
    case apply(@robot, name, []) do
      {:ok, pid} when is_pid(pid) -> describe(BB.Command.await(pid, 60_000))
      other -> describe(other)
    end
  catch
    kind, reason -> describe({:error, {kind, reason}})
  end

  @doc "A command's result as the badge shows it: `\"ok\"`, or a clipped reason."
  @spec describe(term) :: binary
  def describe({:ok, _result}), do: "ok"
  def describe({:ok, _result, _opts}), do: "ok"
  def describe({:error, %{__exception__: true} = error}), do: clip(Exception.message(error))
  def describe({:error, reason}), do: clip(inspect(reason))
  def describe(other), do: clip(inspect(other))

  defp clip(text) when byte_size(text) <= @reason_bytes, do: text
  defp clip(text), do: binary_part(text, 0, @reason_bytes)

  defp answer(from, state) do
    send(from, {:goatbot, safely(fn -> BB.Robot.Runtime.state(@robot) end) || :unknown})
    greet(node(from), state)
  end

  # Logs a new driver once rather than every command.
  defp greet(peer, %{peer: peer} = state), do: state

  defp greet(peer, state) do
    Logger.info("Remote driver: #{peer}")
    %{state | peer: peer}
  end

  defp turn_rate, do: safely(fn -> BB.Parameter.get!(@robot, [:yaw, :turn_rate]) end) || 1.0

  defp deadzone,
    do: safely(fn -> BB.Parameter.get!(@robot, [:drive, :remote_deadzone]) end) || 0.0

  defp safely(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
