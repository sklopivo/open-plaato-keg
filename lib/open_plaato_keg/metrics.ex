defmodule OpenPlaatoKeg.Metrics do
  use Prometheus.Metric
  require Logger

  def init do
    Summary.declare(
      name: :telemetry_scrape_duration_seconds,
      help: "Scrape duration",
      labels: ["registry"],
      registry: :default
    )

    Summary.declare(
      name: :telemetry_scrape_size_bytes,
      help: "Scrape size, uncompressed",
      labels: ["registry"],
      registry: :default
    )

    Gauge.declare(
      name: :plaato_keg,
      help: "Plaato keg metrics",
      labels: ["id", "type"],
      registry: :default
    )
  end

  def scrape_data(format \\ :prometheus_text_format, registry \\ :default) do
    scrape =
      Summary.observe_duration(
        [
          registry: registry,
          name: :telemetry_scrape_duration_seconds,
          labels: [registry]
        ],
        fn ->
          format.format(registry)
        end
      )

    Summary.observe(
      [registry: registry, name: :telemetry_scrape_size_bytes, labels: [registry]],
      :erlang.iolist_size(scrape)
    )

    scrape
  end

  def publish(id, keg_data) do
    Enum.each(keg_data, fn {key, value} ->
      record_metric(id, key, value)
    end)
  rescue
    error ->
      Logger.error("Failed to publish metrics",
        data: inspect([keg_data: keg_data, error: error], limit: :infinity)
      )
  end

  defp record_metric(id, key, value) when is_binary(value) do
    case Float.parse(value) do
      {float_value, ""} ->
        Gauge.set(
          [
            name: :plaato_keg,
            labels: [id, key]
          ],
          float_value
        )

      _ ->
        :skip
    end
  end

  defp record_metric(_id, _key, _value) do
    :skip
  end
end
