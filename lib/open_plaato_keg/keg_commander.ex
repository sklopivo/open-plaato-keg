defmodule OpenPlaatoKeg.KegCommander do
  @moduledoc """
  Module for sending commands to connected keg devices.
  Commands are based on the Blynk protocol used by Plaato Keg.
  """
  require Logger
  alias OpenPlaatoKeg.BlynkProtocol

  # Pin mappings from PlaatoData
  @pins %{
    temperature_offset: "52",
    known_weight_calibrate: "61",
    tare: "60",
    empty_keg_weight: "62",
    max_keg_volume: "76",
    beer_style: "64",
    date: "67",
    unit: "71",
    measure_unit: "75",
    keg_mode_co2_beer: "88",
    sensitivity: "89"
  }

  @doc """
  Sends a command to a specific keg device.
  Returns :ok on success, {:error, reason} on failure.
  """
  def send_command(keg_id, command, value) do
    case do_send(keg_id, encode_command(command, value)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lookup the socket for a given keg ID from the registry.
  """
  def lookup_socket(keg_id) do
    case Registry.lookup(OpenPlaatoKeg.KegSocketRegistry, keg_id) do
      [{_pid, socket}] -> {:ok, socket}
      [] -> {:error, :not_connected}
    end
  end

  @doc """
  Get list of connected keg IDs.
  """
  def connected_kegs do
    Registry.select(OpenPlaatoKeg.KegSocketRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  @doc """
  Encodes a command for the Plaato Keg using Blynk protocol.
  """
  def encode_command(command, value) when is_atom(command) do
    pin = Map.get(@pins, command)
    encode_hardware_write(pin, to_string(value))
  end

  def encode_command(pin, value) when is_binary(pin) do
    encode_hardware_write(pin, to_string(value))
  end

  @doc """
  Send a manual OTA command to a keg.

  This sends a BLYNK_INTERNAL \"ota\" command with body
  \"ota\\0<firmware_url>\", which the stock Plaato firmware
  interprets as an HTTP URL to download and flash.

  WARNING: Using an incompatible firmware URL can brick the device.
  """
  def send_internal_ota(keg_id, firmware_url) when is_binary(firmware_url) do
    body = "ota\0" <> firmware_url
    msg_id = :rand.uniform(65_535)
    encoded = BlynkProtocol.encode_command(:internal, msg_id, body)
    do_send(keg_id, encoded)
  end

  # Debug commands
  def set_temperature_offset(keg_id, offset),
    do: send_command(keg_id, :temperature_offset, offset)

  def calibrate_with_known_weight(keg_id, weight),
    do: send_command(keg_id, :known_weight_calibrate, weight)

  # Keg Setup commands
  def tare(keg_id), do: send_command(keg_id, :tare, "1")
  def tare_release(keg_id), do: send_command(keg_id, :tare, "0")
  def set_empty_keg(keg_id), do: send_command(keg_id, :empty_keg_weight, "1")
  def set_empty_keg_release(keg_id), do: send_command(keg_id, :empty_keg_weight, "0")

  def set_empty_keg_weight_value(keg_id, value),
    do: send_command(keg_id, :empty_keg_weight, value)
  def set_max_keg_volume(keg_id, volume), do: send_command(keg_id, :max_keg_volume, volume)

  # Monitor commands
  # NOTE: Updating hardware pins for beer_style (64) and date (67) works,
  # but there is no read feedback from the keg for these pins.
  # The values are stored in our local database as my_beer_style and my_keg_date.
  def set_beer_style(keg_id, style), do: send_command(keg_id, :beer_style, " #{style}")
  def set_date(keg_id, date), do: send_command(keg_id, :date, " #{date}")

  # Settings commands
  def set_unit_metric(keg_id), do: send_command(keg_id, :unit, "1")
  def set_unit_us(keg_id), do: send_command(keg_id, :unit, "2")
  def set_measure_unit_weight(keg_id), do: send_command(keg_id, :measure_unit, "1")
  def set_measure_unit_volume(keg_id), do: send_command(keg_id, :measure_unit, "2")
  def set_keg_mode_beer(keg_id), do: send_command(keg_id, :keg_mode_co2_beer, "1")
  def set_keg_mode_co2(keg_id), do: send_command(keg_id, :keg_mode_co2_beer, "2")

  def set_sensitivity(keg_id, level) when level in 1..4,
    do: send_command(keg_id, :sensitivity, to_string(level))

  # ============================================
  # Sync Commands (request values from device)
  # ============================================

  # All known pins that we want to sync
  @sync_pins [
    # last_pour_string
    "47",
    # percent_of_beer_left
    "48",
    # is_pouring
    "49",
    # amount_left
    "51",
    # keg_temperature
    "56",
    # last_pour
    "59",
    # beer_style
    "64",
    # date
    "67",
    # calculated_abv
    "68",
    # keg_temperature_string
    "69",
    # calculated_alcohol_string
    "70",
    # unit
    "71",
    # beer_left_unit
    "74",
    # measure_unit
    "75",
    # max_keg_volume
    "76",
    # temperature_unit
    "80",
    # keg_mode_c02_beer
    "88",
    # sensitivity
    "89"
  ]

  @doc """
  Request all known pin values from the keg device.
  Uses hardware_sync command to request values.
  """
  def sync_all(keg_id) do
    sync_pins(keg_id, @sync_pins)
  end

  @doc """
  Request specific pin values from the keg device.
  """
  def sync_pins(keg_id, pins) when is_list(pins) do
    case lookup_socket(keg_id) do
      {:ok, socket} ->
        encoded = encode_hardware_sync(pins)
        Logger.info("Requesting sync for keg #{keg_id}, pins: #{inspect(pins)}")
        ThousandIsland.Socket.send(socket, encoded)

      {:error, reason} ->
        Logger.warning("Failed to sync keg #{keg_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Request a single pin value from the keg device.
  """
  def sync_pin(keg_id, pin) when is_binary(pin) do
    sync_pins(keg_id, [pin])
  end

  defp encode_hardware_write(pin, value) do
    # Format: "vw\0<pin>\0<value>"
    body = "vw\0#{pin}\0#{value}"
    msg_id = :rand.uniform(65535)
    BlynkProtocol.encode_command(:hardware, msg_id, body)
  end

  defp encode_hardware_sync(pins) do
    # Format: "vr\0<pin1>\0<pin2>\0..."
    body = Enum.join(["vr" | pins], "\0")
    msg_id = :rand.uniform(65535)
    BlynkProtocol.encode_command(:hardware_sync, msg_id, body)
  end

  @doc """
  Sends a raw Blynk command binary to a specific keg device.
  Intended for advanced flows like OTA where we need to use
  non-hardware commands (e.g. BLYNK_INTERNAL).
  """
  defp do_send(keg_id, encoded) do
    case lookup_socket(keg_id) do
      {:ok, socket} ->
        Logger.info("Sending command to keg #{keg_id}")
        ThousandIsland.Socket.send(socket, encoded)

      {:error, reason} ->
        Logger.warning("Failed to send command to keg #{keg_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
