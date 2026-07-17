defmodule OpenPlaatoKeg.Supervisor do
  use Supervisor
  require Logger

  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    children =
      [
        mqtt_spec(),
        barhelper_spec(),
        ws_registry_spec(),
        keg_socket_registry_spec(),
        tcp_listener_spec(),
        http_router_spec()
      ]
      |> Enum.reject(&is_nil/1)

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp ws_registry_spec do
    {Registry, keys: :duplicate, name: OpenPlaatoKeg.WebSocketConnectionRegistry}
  end

  defp keg_socket_registry_spec do
    {Registry, keys: :unique, name: OpenPlaatoKeg.KegSocketRegistry}
  end

  defp tcp_listener_spec do
    port = OpenPlaatoKeg.tcp_listener_config()[:port]

    Logger.info("TCP keg listener starting on port #{port}...")

    {ThousandIsland, port: port, handler_module: OpenPlaatoKeg.KegConnectionHandler}
  end

  defp http_router_spec do
    port = OpenPlaatoKeg.http_listener_config()[:port]

    # Wrap default router with OTA handler so /download32.php works
    {Bandit, scheme: :http, plug: OpenPlaatoKeg.OtaRouter, port: port}
  end

  defp mqtt_spec do
    if OpenPlaatoKeg.mqtt_config()[:enabled] do
      Tortoise.Connection.child_spec(
        client_id: OpenPlaatoKeg.mqtt_config()[:client],
        handler: {OpenPlaatoKeg.MqttHandler, []},
        server: {
          Tortoise.Transport.Tcp,
          host: OpenPlaatoKeg.mqtt_config()[:host], port: OpenPlaatoKeg.mqtt_config()[:port]
        },
        user_name: OpenPlaatoKeg.mqtt_config()[:username],
        password: OpenPlaatoKeg.mqtt_config()[:password],
        subscriptions: []
      )
    else
      Logger.info("MQTT_ENABLED is not set to 'true'. MQTT connection not starting..")
      nil
    end
  end

  defp barhelper_spec do
    if OpenPlaatoKeg.barhelper_config()[:enabled] do
      {OpenPlaatoKeg.BarHelper, %{config: OpenPlaatoKeg.barhelper_config()}}
    else
      Logger.info("BARHELPER_ENABLED is not set to 'true'. Barhelper hooks not starting..")
      nil
    end
  end
end
