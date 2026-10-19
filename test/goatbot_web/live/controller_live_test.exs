defmodule GoatbotWeb.ControllerLiveTest do
  # Not async: these drive the one robot the application starts, and listen on
  # its `[:drive]` topic.
  use GoatbotWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BB.NSK.Drive
  alias BB.NSK.Message.Drive, as: DriveMessage

  @robot Goatbot.Robot

  setup do
    BB.PubSub.subscribe(@robot, Drive.path(), message_types: [DriveMessage])
    :ok
  end

  defp drive_message do
    assert_receive {:bb, _path, %BB.Message{payload: %DriveMessage{} = drive}}
    {drive.throttle, drive.turn}
  end

  describe "while disarmed" do
    test "offers arm and power off, not stand", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      assert has_element?(lv, "#arm", "Arm")
      assert has_element?(lv, "#stand[disabled]")
      assert has_element?(lv, "#poweroff:not([disabled])")
      assert has_element?(lv, "#stick[phx-hook=Stick]")
    end

    test "a stand asked for anyway is refused and shown", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_hook(lv, "stand", %{})

      assert has_element?(lv, ".error", "stand")
    end
  end

  describe "the stick" do
    test "up is forwards", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_hook(lv, "drive", %{"x" => 0.0, "y" => -1.0})

      assert drive_message() == {1.0, 0.0}
    end

    test "right turns right, at the full turn rate", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      turn_rate = BB.Parameter.get!(@robot, [:yaw, :turn_rate])

      render_hook(lv, "drive", %{"x" => 1.0, "y" => 0.0})

      {throttle, turn} = drive_message()
      assert throttle == 0.0
      assert_in_delta turn, -turn_rate, 1.0e-9
    end

    test "near the centre is the deadzone", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_hook(lv, "drive", %{"x" => 0.03, "y" => -0.05})

      assert drive_message() == {0.0, 0.0}
    end

    test "letting go stops the robot", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_hook(lv, "drive", %{"x" => 0.0, "y" => -1.0})
      assert drive_message() == {1.0, 0.0}

      render_hook(lv, "release", %{})
      assert drive_message() == {0.0, 0.0}
    end

    test "a malformed position is ignored, not acted on", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_hook(lv, "drive", %{"x" => "fast", "y" => nil})

      refute_receive {:bb, _path, %BB.Message{payload: %DriveMessage{}}}, 50
      assert render(lv) =~ "throttle 0.00"
    end
  end
end
