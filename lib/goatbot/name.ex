defmodule Goatbot.Name do
  @moduledoc """
  The robot's name: the mDNS host it answers to (`<name>.local`) and the name
  the phone controller shows. With two robots on one network, each needs its
  own, or `goatbot.local` answers from whichever spoke last.

  The name comes from, in order:

    1. **Runtime**, set with `set/1` on the robot. Kept in the U-Boot
       environment (`goatbot_name`), so it survives reboots and firmware
       updates, and takes effect at once.
    2. **Build time**, from `GOATBOT_NAME` when the firmware was built:
       `GOATBOT_NAME=goat2 mix firmware`.
    3. `"goatbot"`.

  Each robot also keeps the unique `nerves-<serial>.local` that Nerves gives it.

      iex> Goatbot.Name.set("goat2")
      :ok
      iex> Goatbot.Name.get()
      "goat2"
      iex> Goatbot.Name.clear()   # back to the build-time name
      :ok
  """

  require Logger

  @key "goatbot_name"

  @doc "The robot's name."
  @spec get() :: String.t()
  def get do
    case stored() do
      name when is_binary(name) and name != "" -> name
      _ -> default()
    end
  end

  @doc "The name the firmware was built with: `GOATBOT_NAME`, or `\"goatbot\"`."
  @spec default() :: String.t()
  def default, do: Application.get_env(:goatbot, :name, "goatbot")

  @doc """
  Name the robot `name`, from now on and across reboots and firmware updates.

  A host name label: lowercase letters, digits and hyphens, not starting or
  ending with a hyphen, at most 63 characters.
  """
  @spec set(String.t()) :: :ok | {:error, :invalid_name | term}
  def set(name) when is_binary(name) do
    if valid?(name) do
      with :ok <- Nerves.Runtime.KV.put(@key, name), do: apply_name()
    else
      {:error, :invalid_name}
    end
  end

  @doc "Forget the runtime name, going back to the one the firmware was built with."
  @spec clear() :: :ok | {:error, term}
  def clear do
    with :ok <- Nerves.Runtime.KV.put(@key, ""), do: apply_name()
  end

  @doc "Whether `name` can be a host name label."
  @spec valid?(term) :: boolean
  def valid?(name) when is_binary(name),
    do: name =~ ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

  def valid?(_name), do: false

  @doc """
  Advertise the current name over mDNS. Run at boot, and by `set/1` and
  `clear/0`.
  """
  @spec apply_name() :: :ok
  def apply_name do
    name = get()

    # `mdns_lite` comes with `nerves_pack`, which is target-only.
    if Code.ensure_loaded?(MdnsLite) do
      apply(MdnsLite, :set_hosts, [[:hostname, name]])
      Logger.info("Answering to #{name}.local")
    end

    :ok
  end

  defp stored do
    Nerves.Runtime.KV.get(@key)
  rescue
    _ -> nil
  end
end
