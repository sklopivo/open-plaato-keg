defmodule OpenPlaatoKeg.Models.BeverageDB do
  @table :beverages

  def all do
    @table
    |> :dets.match({{:beverage, :"$1"}, :"$2"})
    |> Enum.map(fn [id, data] -> Map.put(data, :id, id) end)
    |> Enum.sort_by(&(Map.get(&1, :name, "") |> String.downcase()))
  end

  def get(id) do
    case :dets.lookup(@table, {:beverage, id}) do
      [{{:beverage, _}, data}] -> Map.put(data, :id, id)
      _ -> nil
    end
  end

  def put(id, data), do: :dets.insert(@table, {{:beverage, id}, data})
  def delete(id), do: :dets.delete(@table, {:beverage, id})

  def generate_id do
    :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  end
end
