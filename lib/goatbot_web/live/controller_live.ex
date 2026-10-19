defmodule GoatbotWeb.ControllerLive do
  @moduledoc """
  A phone controller for the robot, in place of the badge.

  Three buttons, arm/disarm, stand and power off, and an analog stick: drag
  the knob from the centre and the robot drives, let go and it springs back and
  the robot stops. Up is forwards, right turns right.

  The stick goes through `Goatbot.Remote.command/4`, the same as the badge, so
  it gets the same `[:drive, :remote_deadzone]` and `[:yaw, :turn_rate]`, and
  then to `BB.NSK.Drive.command/3`.

  ## What stops the robot

  The controllers forget a drive request after `drive_timeout` (300 ms), so the
  stick hook (`assets/js/stick.js`) resends the stick's position every 100 ms
  while it's held, not just when it moves. That keeps a held stick driving, and
  makes the phone the dead man: a tab sent to the background, a closed browser
  or a lost connection stops sending, and the robot stops within 300 ms.
  Letting go sends a stop at once, and so does this LiveView going down.

  Power off is only allowed once disarmed, as from the board's button, and asks
  for confirmation first.
  """

  use GoatbotWeb, :live_view

  alias BB.NSK.Drive
  alias BB.StateMachine.Transition

  @robot Goatbot.Robot

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # So `terminate/2` runs, and a page going away stops the robot.
      Process.flag(:trap_exit, true)
      BB.PubSub.subscribe(@robot, [:state_machine])
    end

    {:ok,
     assign(socket,
       page_title: "Goatbot",
       state: robot_state(),
       armed?: armed?(),
       throttle: 0.0,
       turn: 0.0,
       error: nil
     )}
  end

  @impl true
  def handle_event("toggle_arm", _params, socket) do
    if armed?() do
      Drive.stop(@robot)
      {:noreply, command(socket, :disarm)}
    else
      {:noreply, command(socket, :arm)}
    end
  end

  def handle_event("stand", _params, socket), do: {:noreply, command(socket, :stand)}
  def handle_event("poweroff", _params, socket), do: {:noreply, command(socket, :poweroff)}

  # The stick's x is right and y is down, both -1 to 1. Forwards is up the
  # screen, and a positive turn is to the robot's left.
  def handle_event("drive", %{"x" => x, "y" => y}, socket)
      when is_number(x) and is_number(y) do
    {throttle, turn} = Goatbot.Remote.command(-y, -x, turn_rate(), deadzone())
    Drive.command(@robot, throttle, turn)

    {:noreply, assign(socket, throttle: throttle, turn: turn)}
  end

  # The socket is a public interface: anything else is ignored rather than
  # crashing the page, and the robot's drive timeout stops it.
  def handle_event("drive", _params, socket), do: {:noreply, socket}

  def handle_event("release", _params, socket) do
    Drive.stop(@robot)
    {:noreply, assign(socket, throttle: 0.0, turn: 0.0)}
  end

  @impl true
  def handle_info({:bb, [:state_machine], %BB.Message{payload: %Transition{to: to}}}, socket) do
    {:noreply, assign(socket, state: to, armed?: armed?())}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, _socket) do
    Drive.stop(@robot)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="controller">
      <header class="status">
        <span class="robot">Goatbot</span>
        <span class={["state", "state-#{@state}"]}>{@state}</span>
      </header>

      <p :if={@error} class="error" role="alert">{@error}</p>

      <section class="buttons">
        <button
          id="arm"
          class={["button", if(@armed?, do: "disarm", else: "arm")]}
          phx-click="toggle_arm"
        >
          {if @armed?, do: "Disarm", else: "Arm"}
        </button>
        <button
          id="stand"
          class="button stand"
          phx-click="stand"
          disabled={@state not in [:idle, :fallen]}
        >
          Stand
        </button>
        <button
          id="poweroff"
          class="button poweroff"
          phx-click="poweroff"
          data-confirm="Power the robot off?"
          disabled={@state != :disarmed}
        >
          Power off
        </button>
      </section>

      <section class="drive">
        <div id="stick" class="stick" phx-hook="Stick" phx-update="ignore">
          <div class="stick-ring"></div>
          <div class="stick-knob"></div>
        </div>
        <p class="readout">
          throttle {format(@throttle)} · turn {format(@turn)} rad/s
        </p>
      </section>
    </main>
    """
  end

  defp command(socket, name) do
    case apply(@robot, name, []) do
      {:ok, _pid} -> assign(socket, error: nil)
      {:error, reason} -> assign(socket, error: "#{name}: #{describe(reason)}")
    end
  end

  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(reason), do: inspect(reason)

  defp format(value), do: :erlang.float_to_binary(value * 1.0, decimals: 2)

  defp turn_rate, do: param([:yaw, :turn_rate], 1.0)
  defp deadzone, do: param([:drive, :remote_deadzone], 0.0)

  defp param(path, default) do
    BB.Parameter.get!(@robot, path)
  rescue
    _ -> default
  end

  # The rescues are for a page served while the robot isn't running.
  defp robot_state do
    BB.Robot.Runtime.state(@robot)
  rescue
    _ -> :unknown
  end

  defp armed? do
    BB.Safety.armed?(@robot)
  rescue
    _ -> false
  end
end
