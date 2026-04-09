defmodule OpenPlaatoKeg.Brewfather do
  @moduledoc """
  Sends airlock fermentation data to Brewfather via custom stream.
  POST at most every 15 minutes.
  """
  require Logger
  alias OpenPlaatoKeg.Models.AirlockData

  @throttle_minutes 15

  def maybe_send(airlock_id, temperature, bubbles_per_min, bubble_total \\ nil) do
    airlock = AirlockData.get(airlock_id)

    enabled? =
      case airlock[:brewfather_enabled] do
        "true" -> true
        true -> true
        _ -> false
      end

    url = airlock[:brewfather_url] |> to_string() |> String.trim()

    if enabled? and url != "" do
      if throttle_ok?(airlock) do
        do_send(airlock_id, airlock, url, temperature, bubbles_per_min, bubble_total)
      else
        :throttled
      end
    else
      :skip
    end
  end

  defp throttle_ok?(airlock) do
    case airlock[:brewfather_last_sent_at] do
      nil -> true
      ts when is_binary(ts) ->
        case Integer.parse(ts) do
          {ms, _} -> now_ms() - ms >= @throttle_minutes * 60 * 1000
          :error -> true
        end
      _ -> true
    end
  end

  defp now_ms, do: System.system_time(:millisecond)

  defp do_send(airlock_id, airlock, url, temperature, bubbles_per_min, bubble_total) do
    bubbles_per_min = bubbles_per_min || airlock[:bubbles_per_min]
    unit = airlock[:brewfather_temp_unit] || "celsius"
    sg = parse_float(airlock[:brewfather_sg], 1.0)
    og = parse_float(airlock[:brewfather_og], nil)
    batch_volume = parse_float(airlock[:brewfather_batch_volume], nil)

    label = (airlock[:label] || "") |> to_string() |> String.trim()
    device_name = if label == "", do: "Plaato", else: label
    temp_unit_str = if unit == "fahrenheit", do: "°F", else: "°C"

    temp_value =
      case temperature do
        nil -> nil
        t when is_binary(t) ->
          case Float.parse(t) do
            {f, _} -> temp_for_unit(f, unit)
            :error -> nil
          end
        t when is_number(t) -> temp_for_unit(t, unit)
      end

    if temp_value == nil do
      Logger.debug("Brewfather: skip (no temperature)")
      :skip
    else
      body = %{
        "device_name" => device_name,
        "temp" => temp_value,
        "temp_unit" => temp_unit_str,
        "sg" => sg
      }

      body =
        case bubbles_per_min do
          nil -> body
          b when is_binary(b) ->
            case Float.parse(b) do
              {n, _} -> Map.put(body, "bpm", round(n))
              :error -> body
            end
          b when is_number(b) -> Map.put(body, "bpm", round(b))
        end

      # bubbles, co2_volume, and abv are withheld until Brewfather patches
      # their server-side handling of small bubble counts. The lifetime total
      # is still tracked in DETS and will be sent once the fix is deployed.

      body = if og, do: Map.put(body, "og", og), else: body

      body =
        if batch_volume do
          body
          |> Map.put("batch_volume", batch_volume)
          |> Map.put("volume_unit", "L")
        else
          body
        end

      Logger.info("Brewfather: payload #{inspect(body)}")

      case Req.post(url, json: body) do
        {:ok, %{status: status}} when status in 200..299 ->
          AirlockData.publish(airlock_id, [{:brewfather_last_sent_at, to_string(now_ms())}])
          Logger.info("Brewfather: sent airlock #{airlock_id} (status #{status})")
          :ok

        {:ok, %{status: 429}} ->
          Logger.debug("Brewfather: throttled (429)")
          :throttled

        {:ok, %{status: status, body: resp_body}} ->
          Logger.warning("Brewfather: unexpected response #{status} #{inspect(resp_body)}")
          :error

        {:error, reason} ->
          Logger.error("Brewfather: request failed #{inspect(reason)}")
          :error
      end
    end
  end

  defp parse_float(nil, default), do: default
  defp parse_float(s, default) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> default
    end
  end
  defp parse_float(n, _default) when is_number(n), do: n * 1.0
  defp parse_float(_, default), do: default

  defp temp_for_unit(t, "fahrenheit"), do: t * 9 / 5 + 32
  defp temp_for_unit(t, _), do: t
end
