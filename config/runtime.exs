import Config
import OpenPlaatoKeg.Config

config :open_plaato_keg,
  include_unknown_data: get_env!("INCLUDE_UNKNOWN_DATA", :boolean, "false")

config :open_plaato_keg, :db,
  file_path: get_env("DATABASE_FILE_PATH", :string, "priv/db/keg_data.bin")

config :open_plaato_keg, :tcp_listener, port: get_env!("KEG_LISTENER_PORT", :integer, "1234")

config :open_plaato_keg, :http_listener, port: get_env!("HTTP_LISTENER_PORT", :integer, "8085")

# OTA firmware test configuration
config :open_plaato_keg, :ota,
  firmware_path: get_env("OTA_FIRMWARE_PATH", :string, "priv/ota/firmware.bin"),
  version: get_env("OTA_VERSION", :string, "test")

config :open_plaato_keg, :mqtt,
  enabled: get_env!("MQTT_ENABLED", :boolean, "false"),
  host: get_env("MQTT_HOST", :string, "localhost"),
  port: get_env("MQTT_PORT", :integer, "1883"),
  username: get_env("MQTT_USERNAME", :string, "client"),
  password: get_env("MQTT_PASSWORD", :string, "client"),
  client: get_env("MQTT_CLIENT_ID", :string, "open_plaato_keg_local"),
  topic: get_env("MQTT_TOPIC", :string, "plaato/keg"),
  json_output: get_env!("MQTT_JSON_OUTPUT", :boolean, "true"),
  property_output: get_env!("MQTT_PROPERTY_OUTPUT", :boolean, "true")

config :open_plaato_keg, :barhelper,
  enabled: get_env!("BARHELPER_ENABLED", :boolean, "false"),
  host:
    get_env(
      "BARHELPER_ENDPOINT",
      :string,
      "https://europe-west1-barhelper-app.cloudfunctions.net/api/customKegMon"
    ),
  api_key: get_env("BARHELPER_API_KEY", :string, ""),
  unit: get_env("BARHELPER_UNIT", :string, "l"),
  configuration:
    get_env(
      "BARHELPER_KEG_MONITOR_MAPPING",
      :key_value_csv,
      "plaato-auth-key:barhelper-custom-keg-monitor-id"
    )
