defmodule OpenPlaatoKeg.Models.KegData do
  defstruct id: nil,
            weight_raw: nil,
            weight_raw_unit: nil,
            temperature_raw: nil,
            temperature_raw_unit: nil

  def get(id) do
    case :ets.lookup(:keg_data, id) do
      [{_, model}] -> model
      [] -> nil
    end
  end

  def keys do
    :keg_data
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _} -> is_binary(key) end)
    |> Enum.map(&elem(&1, 0))
  end

  def insert(%__MODULE__{} = model) do
    :ets.insert(:keg_data, {model.id, model})
  end
end