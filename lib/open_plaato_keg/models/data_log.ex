defmodule OpenPlaatoKeg.Models.DataLog do
  @moduledoc """
  Time-series log of keg and airlock sensor readings, backed by a DETS table.

  Entries are keyed by {device_type, device_id, unix_timestamp_seconds} so they
  can be range-queried by device. A per-device ETS throttle prevents logging
  more than once per minute for kegs (which send continuous data); airlocks
  naturally transmit every ~290 seconds so no throttle is applied.
  """

  @table :data_log
  @throttle_table :data_log_throttle
  @min_keg_interval_seconds 60

  # Called once at app startup to create the in-memory throttle table.
  def init_throttle do
    :ets.new(@throttle_table, [:named_table, :set, :public])
  end

  @doc """
  Log a data point for `device_type` (`:keg` or `:airlock`) and `device_id`.
  `data` must be a string-keyed map. Returns `:ok` (skipped if throttled).
  """
  def log(device_type, device_id, data) when is_map(data) and map_size(data) > 0 do
    now = System.system_time(:second)

    if should_log?(device_type, device_id, now) do
      :ets.insert(@throttle_table, {{device_type, device_id}, now})
      :dets.insert(@table, {{device_type, device_id, now}, data})
    end

    :ok
  end

  def log(_device_type, _device_id, _data), do: :ok

  @doc """
  Return all log entries for `device_type`/`device_id` between two Unix
  timestamps (inclusive). Entries are sorted ascending by timestamp and each
  entry has a `"timestamp"` key added.
  """
  def get(device_type, device_id, from_ts, to_ts) do
    matchspec = [
      {
        {{device_type, device_id, :"$1"}, :"$2"},
        [{:>=, :"$1", from_ts}, {:"=<", :"$1", to_ts}],
        [{{:"$1", :"$2"}}]
      }
    ]

    case :dets.select(@table, matchspec) do
      {:error, _} ->
        []

      results ->
        results
        |> Enum.sort_by(fn {ts, _} -> ts end)
        |> Enum.map(fn {ts, data} -> Map.put(data, "timestamp", ts) end)
    end
  end

  @doc """
  Serialise `entries` (as returned by `get/4`) to a CSV string.
  """
  def to_csv(:keg, entries) do
    headers = ["timestamp", "amount_left", "keg_temperature", "percent_of_beer_left", "is_pouring"]
    rows_to_csv(headers, entries)
  end

  def to_csv(:airlock, entries) do
    headers = ["timestamp", "temperature", "bubbles_per_min"]
    rows_to_csv(headers, entries)
  end

  @doc """
  Delete all log entries older than `days_to_keep` days (default 90).
  """
  def prune(days_to_keep \\ 90) do
    cutoff = System.system_time(:second) - days_to_keep * 86_400

    matchspec = [
      {
        {{:"$1", :"$2", :"$3"}, :"_"},
        [{:<, :"$3", cutoff}],
        [{{:"$1", :"$2", :"$3"}}]
      }
    ]

    case :dets.select(@table, matchspec) do
      {:error, _} ->
        :ok

      keys ->
        Enum.each(keys, fn {type, id, ts} ->
          :dets.delete(@table, {type, id, ts})
        end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp should_log?(:keg, device_id, now) do
    case :ets.lookup(@throttle_table, {:keg, device_id}) do
      [{{:keg, ^device_id}, last_ts}] -> now - last_ts >= @min_keg_interval_seconds
      [] -> true
    end
  end

  defp should_log?(_device_type, _device_id, _now), do: true

  defp rows_to_csv(headers, entries) do
    rows =
      Enum.map(entries, fn entry ->
        Enum.map(headers, &(Map.get(entry, &1) || ""))
      end)

    [headers | rows]
    |> Enum.map_join("\n", &Enum.join(&1, ","))
  end
end
