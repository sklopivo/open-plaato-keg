defmodule OpenPlaatoKeg.KegDataProcessor do
  use GenServer
  require Logger

  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.Models.AirlockData
  alias OpenPlaatoKeg.Models.KegData
  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  # IMPORTANT:
  # This GenServer must be per-connection, NOT globally named.
  # Otherwise the 2nd keg connection will fail with {:already_started, pid}.
  def start_link(init_arg \\ %{}) do
    GenServer.start_link(__MODULE__, init_arg)
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:keg_data, data}, state) do
    data
    |> decode()
    |> process(state)
  end

  defp process([], state), do: {:noreply, state}

  defp process(data, state) do
    # The login packet (get_shared_dash) may arrive in the same TCP frame as
    # other commands, so we always extract the id from any decoded list rather
    # than relying on a single-element [id: id] pattern.
    state =
      case Keyword.fetch(data, :id) do
        {:ok, id} -> Map.put(state, :id, id)
        :error -> state
      end

    # Detect device type from pin keys once and cache it in state.
    state =
      cond do
        state[:device_type] != nil -> state
        airlock_data?(data) -> Map.put(state, :device_type, :airlock)
        keg_data?(data) -> Map.put(state, :device_type, :keg)
        true -> state
      end

    # Strip the id before routing — it is already in state.
    payload = Keyword.delete(data, :id)

    cond do
      payload == [] ->
        {:noreply, state}

      state[:device_type] == :airlock ->
        if OpenPlaatoKeg.AppConfig.get(:airlock_enabled, true) do
          Logger.debug("Decoded airlock data", data: inspect(payload, limit: :infinity))
          # Drop internal metadata — not stored for airlocks.
          process_airlock(Keyword.delete(payload, :internal), state)
        else
          Logger.debug("Airlock support disabled — ignoring airlock packet")
          {:noreply, state}
        end

      true ->
        Logger.debug("Decoded keg data", data: inspect(payload, limit: :infinity))
        process_keg(payload, state)
    end
  end

  # A packet contains airlock data if it has any of the three airlock pins.
  defp airlock_data?(data) do
    Keyword.has_key?(data, :airlock_bubble_count) or
      Keyword.has_key?(data, :airlock_temperature) or
      Keyword.has_key?(data, :airlock_error)
  end

  # A packet contains keg data if it has any well-known keg-only pins.
  defp keg_data?(data) do
    Keyword.has_key?(data, :amount_left) or
      Keyword.has_key?(data, :keg_temperature) or
      Keyword.has_key?(data, :percent_of_beer_left) or
      Keyword.has_key?(data, :is_pouring) or
      Keyword.has_key?(data, :firmware_version)
  end

  # Valid pour range per unit. Lower bound catches near-zero scale noise;
  # upper bound catches compressor/vibration spikes (e.g. 110 lbs from a fridge compressor).
  # Equivalent to roughly 2 oz min – 48 oz max in all unit systems.
  @pour_range %{
    "lbs"   => {0.1,  3.0},
    "kg"    => {0.05, 1.4},
    "gal"   => {0.015, 0.375},
    "litre" => {0.05, 1.4}
  }

  defp filter_last_pour(data, id) do
    case Keyword.get(data, :last_pour) do
      nil -> data
      value ->
        unit = KegData.get(id)[:beer_left_unit] || "litre"
        {min, max} = Map.get(@pour_range, unit, {0.05, 1.4})

        case Float.parse(to_string(value)) do
          {v, _} when v >= min and v <= max ->
            data

          {v, _} ->
            Logger.warning("Ignoring out-of-range last_pour=#{v} #{unit} for keg #{id}")
            Keyword.delete(data, :last_pour)

          :error ->
            data
        end
    end
  end

  defp process_keg(data, state) do
    id = state[:id]
    confirmed_keg? = state[:device_type] == :keg

    # Only register the device in KegData (via the :id key) once we have
    # confirmed it is a keg, so airlock devices never appear in the keg list.
    data_with_id =
      if id && confirmed_keg?,
        do: Keyword.put_new(data, :id, id),
        else: data

    # Drop out-of-range last_pour values caused by scale vibration/noise
    # (e.g. compressor turning on). Valid pours are roughly 2–48 oz.
    data_with_id = if id, do: filter_last_pour(data_with_id, id), else: data_with_id

    amount_left_changed? =
      Enum.any?(data, fn {key, _value} -> key == :amount_left end)

    # All publishers are guarded by confirmed_keg? to prevent phantom keg entries
    # when an airlock's internal packet arrives before its V99/V100/V101 pins
    # (which is what sets device_type to :airlock).
    publish(id, data_with_id, [
      {&KegData.publish/2, fn -> confirmed_keg? end},
      {&OpenPlaatoKeg.Metrics.publish/2, fn -> confirmed_keg? end},
      {&OpenPlaatoKeg.WebSocketHandler.publish/2, fn -> confirmed_keg? end},
      {&OpenPlaatoKeg.MqttHandler.publish/2,
       fn -> confirmed_keg? and OpenPlaatoKeg.mqtt_config()[:enabled] end},
      {&OpenPlaatoKeg.BarHelper.publish/2,
       fn -> confirmed_keg? and amount_left_changed? and OpenPlaatoKeg.barhelper_config()[:enabled] end}
    ])

    {:noreply, state}
  end

  defp process_airlock(data, state) do
    id = state[:id]

    # The airlock deep-sleeps between readings, so each wake-up is a new TCP
    # connection with a fresh GenServer state. Seed the previous count/time from
    # DETS on the first packet of each connection so BPM can still be computed.
    state =
      if id != nil and state[:airlock_last_count] == nil do
        persisted = AirlockData.get(id)

        state
        |> seed_integer(:airlock_last_count, persisted[:last_bubble_count])
        |> seed_integer(:airlock_last_count_time, persisted[:last_bubble_count_time])
        |> seed_integer(:total_bubble_count, persisted[:total_bubble_count])
      else
        state
      end

    # V100 sends cumulative count since power-on. BPM = delta / elapsed_minutes.
    {bpm, new_state} =
      maybe_compute_bpm(Keyword.get(data, :airlock_bubble_count), state)

    # Accumulate lifetime bubble total across connections.
    # Hardware resets its count each power-on, so we track the delta each packet.
    {new_state, bubble_total} = accumulate_bubble_total(new_state, state[:airlock_last_count])

    # Persist the updated count/time/total so the next wake-up connection can use it.
    if id != nil and new_state[:airlock_last_count] != state[:airlock_last_count] do
      AirlockData.publish(id, [
        {:last_bubble_count, to_string(new_state[:airlock_last_count])},
        {:last_bubble_count_time, to_string(new_state[:airlock_last_count_time])},
        {:total_bubble_count, to_string(bubble_total || 0)}
      ])
    end

    airlock_fields =
      []
      |> append_field(:temperature, Keyword.get(data, :airlock_temperature))
      |> append_field(:bubbles_per_min, bpm && to_string(bpm))
      |> append_field(:error, Keyword.get(data, :airlock_error))

    if id && airlock_fields != [] do
      AirlockData.publish(id, airlock_fields)
      OpenPlaatoKeg.WebSocketHandler.publish_airlock(id, airlock_fields)
      OpenPlaatoKeg.Grainfather.maybe_send(id, Keyword.get(data, :airlock_temperature), bpm && to_string(bpm))
      OpenPlaatoKeg.Brewfather.maybe_send(id, Keyword.get(data, :airlock_temperature), bpm && to_string(bpm), bubble_total)
    end

    {:noreply, new_state}
  end

  # Computes the delta from the previous count and adds it to the lifetime total.
  # When the hardware resets (new_count < prev_count), the new_count itself is the delta.
  defp accumulate_bubble_total(state, prev_count) do
    new_count = state[:airlock_last_count]

    if new_count == nil or new_count == prev_count do
      {state, state[:total_bubble_count]}
    else
      delta =
        cond do
          prev_count == nil -> new_count
          new_count >= prev_count -> new_count - prev_count
          true -> new_count
        end

      new_total = (state[:total_bubble_count] || 0) + delta
      {Map.put(state, :total_bubble_count, new_total), new_total}
    end
  end

  defp seed_integer(state, _key, nil), do: state

  defp seed_integer(state, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> Map.put(state, key, int)
      :error -> state
    end
  end

  defp maybe_compute_bpm(nil, state), do: {nil, state}

  defp maybe_compute_bpm(count_str, state) do
    case Integer.parse(to_string(count_str)) do
      {new_count, _} ->
        now = System.system_time(:millisecond)
        prev_count = state[:airlock_last_count]
        prev_time = state[:airlock_last_count_time]

        bpm =
          if prev_count != nil and prev_time != nil do
            elapsed_min = (now - prev_time) / 60_000.0
            # Require at least 60 seconds between readings to prevent inflated
            # BPM from burst packets sent within a single wake-up cycle.
            if elapsed_min >= 1.0 do
              # Hardware resets V100 to 0 on each wake-up (new TCP connection).
              # When new_count < prev_count a reset is detected: use prev_count
              # as the delta (bubbles from the previous cycle) over elapsed time.
              delta =
                if new_count >= prev_count,
                  do: new_count - prev_count,
                  else: prev_count

              Float.round(delta / elapsed_min, 1)
            end
          end

        new_state =
          state
          |> Map.put(:airlock_last_count, new_count)
          |> Map.put(:airlock_last_count_time, now)

        {bpm, new_state}

      :error ->
        {nil, state}
    end
  end

  defp append_field(list, _key, nil), do: list
  defp append_field(list, key, value), do: [{key, value} | list]

  defp decode(data) do
    data
    |> BlynkProtocol.decode()
    |> PlaatoProtocol.decode()
    |> PlaatoData.decode()
  end

  defp publish(nil = _id, data, _publishers) do
    Logger.warning("No id found for decoded data", data: inspect(data))
    :skip
  end

  defp publish(id, data, publishers) do
    Enum.each(publishers, fn {publish_func, condition} ->
      if condition.() do
        publish_func.(id, data)
      end
    end)
  end
end
