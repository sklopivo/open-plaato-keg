defmodule OpenPlaatoKeg.MqttHandler do
  require Logger
  alias OpenPlaatoKeg.Models.KegData

  def init(args) do
    Logger.info("", data: inspect(args))
    {:ok, args}
  end

  def connection(status, state) do
    Logger.info("", data: inspect(%{status: status, state: state}))
    {:ok, state}
  end

  def handle_message(topic, payload, state) do
    Logger.debug(
      "Received message on topic #{inspect(topic)}, playload #{payload}, state: #{inspect(state)}"
    )

    {:ok, state}
  end

  def subscription(status, topic_filter, state) do
    Logger.info("", data: inspect(%{status: status, topic_filter: topic_filter, state: state}))
    {:ok, state}
  end

  def terminate(reason, state) do
    Logger.info("", data: inspect(%{reason: reason, state: state}))
    :ok
  end

  def publish(id, data) do
    if OpenPlaatoKeg.mqtt_config()[:json_output] do
      keg_all_data = KegData.get(id)

      Tortoise.publish(
        OpenPlaatoKeg.mqtt_config()[:client],
        "#{OpenPlaatoKeg.mqtt_config()[:topic]}/#{id}",
        Poison.encode!(keg_all_data),
        qos: 0,
        retain: true
      )
    end

    if OpenPlaatoKeg.mqtt_config()[:property_output] do
      Enum.each(data, fn {key, value} ->
        publish_value =
          case value do
            value when is_binary(value) ->
              value

            value when is_map(value) ->
              Poison.encode!(value)
          end

        Tortoise.publish(
          OpenPlaatoKeg.mqtt_config()[:client],
          "#{OpenPlaatoKeg.mqtt_config()[:topic]}/#{id}/#{key}",
          publish_value,
          qos: 0,
          retain: true
        )
      end)
    end
  end
end
