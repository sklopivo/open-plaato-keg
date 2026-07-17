defmodule OpenPlaatoKeg.Models.KegData do
  require Logger

  alias OpenPlaatoKeg.Models.AirlockData

  def all do
    Enum.map(devices(), &get/1)
  end

  def get(id) do
    if id in airlock_devices() do
      %{}
    else
      get_keg(id)
    end
  end

  def devices do
    query = {{:_, :id}, :"$1"}
    airlock_ids = MapSet.new(airlock_devices())

    :keg_data
    |> :dets.match(query)
    |> List.flatten()
    |> Enum.reject(&MapSet.member?(airlock_ids, &1))
  end

  def publish(id, data) do
    Enum.each(data, fn {key, value} ->
      :dets.insert(:keg_data, {{id, key}, value})
    end)
  end

  def delete(id) do
    # Find all keys stored for this id, then delete each record individually.
    :keg_data
    |> :dets.match({{id, :"$1"}, :_})
    |> List.flatten()
    |> Enum.each(fn key -> :dets.delete(:keg_data, {id, key}) end)
  end

  defp get_keg(id) do
    query = {{id, :"$1"}, :"$2"}

    data =
      :keg_data
      |> :dets.match(query)
      |> Enum.map(fn [key, value] -> {key, value} end)
      |> Enum.reject(fn {key, _value} -> key == :calibration end)
      |> Map.new()
      |> Map.put(:id, id)

    # Always derive beer_left_unit from unit + measure_unit whenever unit is known.
    # This ensures the displayed unit label is always consistent with the configured
    # mode, regardless of what the hardware sends on V74.
    unit = to_string(data[:unit] || "")

    if unit in ["1", "2"] do
      measure = to_string(data[:measure_unit] || "")
      keg_mode = to_string(data[:keg_mode_c02_beer] || "1")
      Map.put(data, :beer_left_unit, derive_beer_left_unit(unit, measure, keg_mode))
    else
      data
    end
  end

  defp airlock_devices do
    AirlockData.devices()
  catch
    :exit, _ -> []
  end

  # unit "1" = metric, "2" = US; measure_unit "1" = weight; keg_mode "2" = CO2
  # CO2 mode: always weight-based regardless of measure_unit setting
  defp derive_beer_left_unit("1", _, "2"), do: "kg CO\u2082"
  defp derive_beer_left_unit("2", _, "2"), do: "lbs CO\u2082"
  # Beer mode: unit + measure_unit
  defp derive_beer_left_unit("1", "1", _), do: "kg"
  defp derive_beer_left_unit("1", _, _), do: "litre"
  defp derive_beer_left_unit("2", "1", _), do: "lbs"
  defp derive_beer_left_unit("2", _, _), do: "gal"
  defp derive_beer_left_unit(_, _, _), do: "litre"
end
