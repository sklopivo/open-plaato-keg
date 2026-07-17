defmodule OpenPlaatoKeg.BarHelper do
  use GenServer
  require Logger

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def publish(id, data) do
    GenServer.cast(__MODULE__, {:keg_data, id, data})
  end

  def handle_cast({:keg_data, id, data}, state) do
    keg_monitor_id = state.config[:configuration][id]

    if keg_monitor_id != nil && data[:amount_left] do
      send_data_to_barhelper(data[:amount_left], keg_monitor_id, state.config)
    end

    {:noreply, state}
  end

  defp send_data_to_barhelper(volume, keg_monitor_id, config) do
    # https://docs.barhelper.app/english/settings/custom-keg-monitor

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "#{config[:api_key]}"}
    ]

    body = %{
      name: keg_monitor_id,
      volume: volume,
      type: config[:unit]
    }

    case Req.post(config[:host], json: body, headers: headers) do
      {:ok, %{body: "Wrong auth" <> _ = response_body, status: status}} ->
        Logger.error(
          "Error when sending data to BarHelper. Status: #{status}. Response: #{inspect(response_body)}"
        )

      {:ok, %{status: status, body: response_body}} ->
        if String.contains?(response_body, "\"success\": true") do
          Logger.info(
            "Successfully sent data to BarHelper. Status: #{status}. Response: #{inspect(response_body)}"
          )
        end

      error ->
        Logger.error("Failed to send data to BarHelper. Response: #{inspect(error)}")
    end
  end
end
