defmodule OpenPlaatoKeg.AppConfig do
  require Logger

  @defaults %{
    airlock_enabled: true,
    brewfather_user_id: "",
    brewfather_api_key: "",
    watchtower_url: "",
    watchtower_token: "",
    theme: %{},
    home_page: "taplist",
    time_format: "12h"
  }

  @doc "Load persisted config from disk into Application env. Call once at startup."
  def load do
    case File.read(config_path()) do
      {:ok, content} ->
        case Poison.decode(content) do
          {:ok, map} ->
            # Explicitly map known string keys to atoms (Poison 6 does not support keys: :atoms)
            loaded = %{
              airlock_enabled: Map.get(map, "airlock_enabled", @defaults.airlock_enabled),
              brewfather_user_id: Map.get(map, "brewfather_user_id", @defaults.brewfather_user_id),
              brewfather_api_key: Map.get(map, "brewfather_api_key", @defaults.brewfather_api_key),
              watchtower_url: Map.get(map, "watchtower_url", @defaults.watchtower_url),
              watchtower_token: Map.get(map, "watchtower_token", @defaults.watchtower_token),
              theme: Map.get(map, "theme", @defaults.theme),
              home_page: Map.get(map, "home_page", @defaults.home_page),
              time_format: Map.get(map, "time_format", @defaults.time_format)
            }
            Application.put_env(:open_plaato_keg, :app_config, Map.merge(@defaults, loaded))

          _ ->
            Application.put_env(:open_plaato_keg, :app_config, @defaults)
        end

      _ ->
        Application.put_env(:open_plaato_keg, :app_config, @defaults)
    end

    :ok
  end

  def get(key, default \\ nil) do
    Application.get_env(:open_plaato_keg, :app_config, @defaults)
    |> Map.get(key, default)
  end

  def put(key, value) do
    current = Application.get_env(:open_plaato_keg, :app_config, @defaults)
    updated = Map.put(current, key, value)
    Application.put_env(:open_plaato_keg, :app_config, updated)

    case save(updated) do
      :ok -> :ok
      {:ok} -> :ok
      {:error, reason} -> {:error, reason}
      _ -> {:error, :save_failed}
    end
  end

  def all do
    Application.get_env(:open_plaato_keg, :app_config, @defaults)
  end

  defp config_path do
    db_file = Application.get_env(:open_plaato_keg, :db)[:file_path]
    Path.join(Path.dirname(db_file), "app_config.json")
  end

  defp save(config) do
    case Poison.encode(config) do
      {:ok, json} -> File.write(config_path(), json)
      {:error, reason} -> {:error, reason}
      _ -> {:error, :encode_failed}
    end
  end
end
