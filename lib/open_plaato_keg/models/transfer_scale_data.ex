defmodule OpenPlaatoKeg.Models.TransferScaleData do
  @moduledoc """
  Storage for transfer scale devices. A transfer scale is placed under an empty keg
  during transfers from fermenter, posting weight readings to track fill level.
  Fields: id, label, raw_weight (grams), empty_keg_weight (grams), target_weight (grams),
  fill_percent (calculated), last_updated (unix timestamp).
  """

  def all do
    Enum.map(devices(), &get/1)
  end

  def get(id) do
    query = {{id, :"$1"}, :"$2"}

    raw =
      :transfer_scale_data
      |> :dets.match(query)
      |> Enum.map(fn [key, value] -> {key, value} end)
      |> Map.new()
      |> Map.put(:id, id)

    raw_weight = Map.get(raw, :raw_weight)
    empty_keg_weight = Map.get(raw, :empty_keg_weight)
    target_weight = Map.get(raw, :target_weight)

    fill_percent =
      if is_number(raw_weight) and is_number(empty_keg_weight) and is_number(target_weight) and
           target_weight - empty_keg_weight != 0 do
        pct = (raw_weight - empty_keg_weight) / (target_weight - empty_keg_weight) * 100.0
        pct |> max(0.0) |> min(100.0)
      else
        0.0
      end

    Map.put(raw, :fill_percent, fill_percent)
  end

  def devices do
    query = {{:_, :id}, :"$1"}

    :transfer_scale_data
    |> :dets.match(query)
    |> List.flatten()
  end

  def publish(id, data) do
    # Ensure we have an :id entry so this scale appears in devices()
    data = [{:id, id} | Enum.reject(data, fn {k, _} -> k == :id end)]

    Enum.each(data, fn {key, value} ->
      :dets.insert(:transfer_scale_data, {{id, key}, value})
    end)
  end
end
