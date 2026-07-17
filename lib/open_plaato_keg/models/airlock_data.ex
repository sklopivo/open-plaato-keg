defmodule OpenPlaatoKeg.Models.AirlockData do
  @moduledoc """
  Storage for airlock (fermentation) devices. Airlocks are separate from keg scales;
  each has an id, optional label, temperature, and bubbles_per_min.
  """

  def all do
    Enum.map(devices(), &get/1)
  end

  def get(id) do
    query = {{id, :"$1"}, :"$2"}

    :airlock_data
    |> :dets.match(query)
    |> Enum.map(fn [key, value] -> {key, value} end)
    |> Map.new()
    |> Map.put(:id, id)
  end

  def devices do
    query = {{:_, :id}, :"$1"}

    :airlock_data
    |> :dets.match(query)
    |> List.flatten()
  end

  def publish(id, data) do
    # Ensure we have an :id entry so this airlock appears in devices()
    data = [{:id, id} | Enum.reject(data, fn {k, _} -> k == :id end)]

    Enum.each(data, fn {key, value} ->
      :dets.insert(:airlock_data, {{id, key}, value})
    end)
  end
end
