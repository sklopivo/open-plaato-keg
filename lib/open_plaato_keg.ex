defmodule OpenPlaatoKeg do
  use Application

  def start(_type, _args) do
    OpenPlaatoKeg.Metrics.init()
    bootstrap()
    OpenPlaatoKeg.Supervisor.start_link()
  end

  def bootstrap do
    db_file_path =
      Application.get_env(:open_plaato_keg, :db)[:file_path]

    # create folder if doesn't exist
    db_folder = Path.dirname(db_file_path)
    File.mkdir_p!(db_folder)

    {:ok, _keg_table} =
      :dets.open_file(:keg_data, [
        {:file, String.to_charlist(db_file_path)}
      ])

    # Airlocks are separate from kegs; own DETS file
    airlock_path = Path.join(db_folder, "airlock_data.bin")
    {:ok, _airlock_table} =
      :dets.open_file(:airlock_data, [
        {:file, String.to_charlist(airlock_path)}
      ])

    # Transfer scales: dumb WiFi scales placed under kegs during transfers from fermenter
    transfer_scale_path = Path.join(db_folder, "transfer_scale_data.bin")
    {:ok, _transfer_scale_table} =
      :dets.open_file(:transfer_scale_data, [
        {:file, String.to_charlist(transfer_scale_path)}
      ])

    # Beer DB: tap list configuration and tap handle metadata
    beer_db_path = Path.join(db_folder, "beer_db.bin")
    {:ok, _beer_table} = :dets.open_file(:beer_db, [{:file, String.to_charlist(beer_db_path)}])

    # Beverage library: reusable beverage recipes
    beverages_path = Path.join(db_folder, "beverages.bin")
    {:ok, _} = :dets.open_file(:beverages, [{:file, String.to_charlist(beverages_path)}])

    # Time-series data log for kegs and airlocks
    data_log_path = Path.join(db_folder, "data_log.bin")
    {:ok, _} = :dets.open_file(:data_log, [{:file, String.to_charlist(data_log_path)}])
    OpenPlaatoKeg.Models.DataLog.init_throttle()

    # Ensure tap handle image directory exists (persistent volume)
    File.mkdir_p!(Path.join(db_folder, "tap-handles"))

    OpenPlaatoKeg.AppConfig.load()
  end

  def tap_handle_dir do
    db_file = Application.get_env(:open_plaato_keg, :db)[:file_path]
    Path.join(Path.dirname(db_file), "tap-handles")
  end

  def tcp_listener_config do
    Application.get_env(:open_plaato_keg, :tcp_listener)
  end

  def http_listener_config do
    Application.get_env(:open_plaato_keg, :http_listener)
  end

  def mqtt_config do
    Application.get_env(:open_plaato_keg, :mqtt)
  end

  def barhelper_config do
    Application.get_env(:open_plaato_keg, :barhelper)
  end
end
