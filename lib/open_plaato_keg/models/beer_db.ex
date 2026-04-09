defmodule OpenPlaatoKeg.Models.BeerDB do
  @doc "All configured taps sorted by tap_number."
  def all_taps do
    :beer_db
    |> :dets.match({{:tap, :"$1"}, :"$2"})
    |> Enum.map(fn [id, data] -> Map.put(data, :id, id) end)
    |> Enum.sort_by(&(Map.get(&1, :tap_number) || 999))
  end

  def get_tap(id) do
    case :dets.lookup(:beer_db, {:tap, id}) do
      [{{:tap, _}, data}] -> Map.put(data, :id, id)
      _ -> nil
    end
  end

  def put_tap(id, data), do: :dets.insert(:beer_db, {{:tap, id}, data})
  def delete_tap(id), do: :dets.delete(:beer_db, {:tap, id})

  @doc "All tap handle image metadata."
  def all_handles do
    :beer_db
    |> :dets.match({{:handle, :"$1"}, :"$2"})
    |> Enum.map(fn [filename, meta] -> Map.put(meta, :filename, filename) end)
    |> Enum.sort_by(&Map.get(&1, :uploaded_at, ""))
  end

  def get_handle(filename) do
    case :dets.lookup(:beer_db, {:handle, filename}) do
      [{{:handle, _}, data}] -> Map.put(data, :filename, filename)
      _ -> nil
    end
  end

  def put_handle(filename, meta), do: :dets.insert(:beer_db, {{:handle, filename}, meta})
  def delete_handle(filename), do: :dets.delete(:beer_db, {:handle, filename})
end
