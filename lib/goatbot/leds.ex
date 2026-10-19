defmodule Goatbot.Leds do
  @moduledoc """
  Shows the robot's state on the NeoPixels, as `BB.NSK.Leds.Controller` does,
  but easier on the eyes.

  The stock controller flashes pink at 4 Hz while fallen, to ask for attention.
  Across a room that's fine; at a desk it's hard to look at. Here every state
  breathes, and fallen (the state waiting for someone) breathes slowly in
  pink: still unmistakable, since nothing else is pink, without the strobe.

  Everything else, one timer for all four pixels and phase from the monotonic
  clock, is the stock controller's, and the breath itself is
  `BB.NSK.Leds.Controller.breath/4`.
  """

  use BB.Controller,
    options_schema: [
      brightness: [
        type: :non_neg_integer,
        default: 30,
        doc: "Brightness at the top of a breath, 0 to the device's maximum (255)"
      ],
      pulse_period: [
        type: :pos_integer,
        default: 2_000,
        doc: "Milliseconds for a full breath, in and out"
      ],
      fade_period: [
        type: :pos_integer,
        default: 4_000,
        doc: "Milliseconds for a full breath while fallen"
      ],
      pulse_interval: [
        type: :pos_integer,
        default: 50,
        doc: "Milliseconds between brightness updates"
      ]
    ]

  alias BB.{Message, PubSub}
  alias BB.NSK.Leds
  alias BB.NSK.Leds.Controller
  alias BB.Robot.Runtime
  alias BB.StateMachine.Transition

  require Logger

  @patterns %{
    disarmed: {{0, 0, 255}, :pulse},
    idle: {{0, 255, 0}, :pulse},
    executing: {{0, 255, 0}, :pulse},
    balancing: {{0, 255, 0}, :pulse},
    fallen: {{255, 0, 180}, :fade},
    disarming: {{255, 120, 0}, :pulse},
    error: {{255, 0, 0}, :pulse}
  }

  @unknown {{80, 0, 80}, :pulse}

  @doc "The colour a state is shown in, and whether it pulses or fades slowly."
  @spec pattern(atom) :: {Leds.colour(), :pulse | :fade}
  def pattern(state), do: Map.get(@patterns, state, @unknown)

  @impl BB.Controller
  def init(opts) do
    %{robot: robot} = Keyword.fetch!(opts, :bb)

    case Leds.open_all() do
      [] ->
        Logger.info("No NeoPixels found, so #{inspect(__MODULE__)} is not starting.")
        :ignore

      [pixel | _] = pixels ->
        Process.flag(:trap_exit, true)
        {:ok, _subscription} = PubSub.subscribe(robot, [:state_machine])

        # Brightness is ours to drive, so make sure nothing in the kernel is
        # also driving it.
        Enum.each(pixels, &Leds.release(&1.path))
        :timer.send_interval(Keyword.fetch!(opts, :pulse_interval), :breathe)

        state = %{
          pixels: pixels,
          operational: Runtime.state(robot),
          max_brightness: Leds.max_brightness(pixel.path) || 255,
          started_at: System.monotonic_time(:millisecond)
        }

        {:ok, configure(state, opts), {:continue, :show_state}}
    end
  end

  @impl BB.Controller
  def handle_continue(:show_state, state), do: {:noreply, show(state)}

  @impl BB.Controller
  def handle_info({:bb, _path, %Message{payload: %Transition{to: to}}}, state) do
    {:noreply, show(%{state | operational: to})}
  end

  def handle_info(:breathe, state) do
    elapsed = System.monotonic_time(:millisecond) - state.started_at
    {_colour, profile} = pattern(state.operational)
    period = if profile == :fade, do: state.fade_period, else: state.pulse_period

    # Dimming to nothing would read as an LED that has gone out, so a breath
    # bottoms out at a glow.
    brightness = Controller.breath(elapsed, state.brightness, div(state.brightness, 8), period)

    {:noreply, %{state | pixels: Leds.set_brightness_all(state.pixels, brightness)}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl BB.Controller
  def handle_options(opts, state), do: {:ok, configure(state, opts)}

  # The board stays powered, so they'd stay lit with nothing behind them.
  @impl BB.Controller
  def terminate(_reason, _state) do
    Leds.off()
    :ok
  end

  defp configure(state, opts) do
    Map.merge(state, %{
      brightness: opts |> Keyword.fetch!(:brightness) |> min(state.max_brightness),
      pulse_period: Keyword.fetch!(opts, :pulse_period),
      fade_period: Keyword.fetch!(opts, :fade_period)
    })
  end

  defp show(state) do
    {colour, _profile} = pattern(state.operational)
    Leds.set_all(state.pixels, colour)

    state
  end
end
