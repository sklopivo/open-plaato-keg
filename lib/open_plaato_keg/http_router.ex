defmodule OpenPlaatoKeg.HttpRouter do
  use Plug.Router
  require Logger
  alias OpenPlaatoKeg.KegCommander
  alias OpenPlaatoKeg.Metrics
  alias OpenPlaatoKeg.Models.AirlockData
  alias OpenPlaatoKeg.Models.BeerDB
  alias OpenPlaatoKeg.Models.BeverageDB
  alias OpenPlaatoKeg.Models.KegData
  alias OpenPlaatoKeg.Models.TransferScaleData
  alias OpenPlaatoKeg.MqttHandler
  alias OpenPlaatoKeg.WebSocketHandler

  plug(Plug.Static,
    at: "/",
    from: :open_plaato_keg
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json, :multipart],
    pass: ["*/*"],
    json_decoder: Poison,
    length: 10_000_000
  )

  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_header("location", "/index.html")
    |> send_resp(302, "")
  end

  # ============================================
  # Global App Config
  # ============================================

  get "api/config" do
    json_response(conn, 200, OpenPlaatoKeg.AppConfig.all())
  end

  post "api/config/airlock-enabled" do
    params = conn.body_params || %{}
    enabled = params["enabled"] in [true, "true", "1"]

    case OpenPlaatoKeg.AppConfig.put(:airlock_enabled, enabled) do
      :ok ->
        Logger.info("Airlock support #{if enabled, do: "enabled", else: "disabled"}", [])
        json_response(conn, 200, %{status: "ok", airlock_enabled: enabled, persisted: true})

      {:error, reason} ->
        # In-memory config is already updated; only the on-disk save failed.
        Logger.error("Failed to persist app config: #{inspect(reason)}", [])

        # Still report success to the client so the toggle works at runtime.
        json_response(conn, 200, %{
          status: "ok",
          airlock_enabled: enabled,
          persisted: false
        })
    end
  end

  # ============================================
  # Keg Data Endpoints
  # ============================================

  get "api/kegs/devices" do
    data = KegData.devices()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/kegs/connected" do
    data = KegCommander.connected_kegs()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/kegs" do
    data = KegData.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/kegs/:id" do
    case KegData.get(conn.params["id"]) do
      %{} = data when map_size(data) > 0 ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Poison.encode!(data))

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Poison.encode!(%{error: "not_found"}))
    end
  end

  # ============================================
  # Debug Commands
  # ============================================

  post "api/kegs/:id/temperature-offset" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    # Save to our local database so it persists across reconnects
    KegData.publish(keg_id, [{:temperature_offset, value}])

    case KegCommander.set_temperature_offset(keg_id, value) do
      :ok ->
        json_response(conn, 200, %{status: "ok", command: "temperature_offset", value: value})

      {:error, reason} ->
        json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/ota" do
    keg_id = conn.params["id"]
    params = conn.body_params || %{}

    url_param = Map.get(params, "url")
    path_param = Map.get(params, "path")

    url =
      cond do
        is_binary(url_param) and url_param != "" ->
          url_param

        is_binary(path_param) and path_param != "" ->
          scheme = if conn.scheme == :https, do: "https", else: "http"
          host = conn.host
          port = conn.port
          port_str = if port in [80, 443], do: "", else: ":#{port}"
          path =
            if String.starts_with?(path_param, "/"),
              do: path_param,
              else: "/" <> path_param

          "#{scheme}://#{host}#{port_str}#{path}"

        true ->
          nil
      end

    if is_nil(url) do
      json_response(conn, 400, %{error: "missing_url_or_path"})
    else
      # Manual OTA only. We just send the OTA command; device will decide
      # whether to download/flash. Wrong firmware can brick the scale.
      case KegCommander.send_internal_ota(keg_id, url) do
        :ok ->
          json_response(conn, 200, %{status: "ok"})

        {:error, reason} ->
          json_response(conn, 400, %{error: to_string(reason)})
      end
    end
  end

  post "api/kegs/:id/calibrate-known-weight" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    case KegCommander.calibrate_with_known_weight(keg_id, value) do
      :ok ->
        json_response(conn, 200, %{status: "ok", command: "known_weight_calibrate", value: value})

      {:error, reason} ->
        json_response(conn, 503, %{error: reason})
    end
  end

  # ============================================
  # Keg Setup Commands
  # ============================================

  post "api/kegs/:id/tare" do
    keg_id = conn.params["id"]

    case KegCommander.tare(keg_id) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "tare"})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/tare-release" do
    keg_id = conn.params["id"]

    case KegCommander.tare_release(keg_id) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "tare_release"})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/empty-keg" do
    keg_id = conn.params["id"]

    case KegCommander.set_empty_keg(keg_id) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "empty_keg"})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/empty-keg-release" do
    keg_id = conn.params["id"]

    case KegCommander.set_empty_keg_release(keg_id) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "empty_keg_release"})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/reset-last-pour" do
    keg_id = conn.params["id"]

    KegData.publish(keg_id, [{:last_pour, "0"}])
    WebSocketHandler.publish(keg_id, [])

    json_response(conn, 200, %{status: "ok", command: "reset_last_pour"})
  end

  post "api/kegs/:id/empty-keg-weight" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    KegData.publish(keg_id, [{:empty_keg_weight, value}])

    case KegCommander.set_empty_keg_weight_value(keg_id, value) do
      :ok ->
        json_response(conn, 200, %{status: "ok", command: "empty_keg_weight", value: value})

      {:error, reason} ->
        json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/max-keg-volume" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    case KegCommander.set_max_keg_volume(keg_id, value) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "max_keg_volume", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/label" do
    keg_id = conn.params["id"]
    value = (conn.body_params || %{})["value"] |> Kernel.to_string() |> String.trim()

    KegData.publish(keg_id, [{:my_label, value}])
    WebSocketHandler.publish(keg_id, [])

    json_response(conn, 200, %{status: "ok", command: "label", value: value})
  end

  # ============================================
  # Monitor Commands
  # ============================================

  # NOTE: Beer style and keg date are saved to custom properties (my_beer_style, my_keg_date)
  # in our local database. The hardware pins (64, 67) are also updated on the keg,
  # but there is no read feedback from those pins, so we store our own copy.

  post "api/kegs/:id/beer-style" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    # Save to our local database
    KegData.publish(keg_id, [{:my_beer_style, value}])

    # Also send to keg hardware pin (no read feedback available)
    KegCommander.set_beer_style(keg_id, value)

    json_response(conn, 200, %{status: "ok", command: "beer_style", value: value})
  end

  post "api/kegs/:id/date" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    # Save to our local database
    KegData.publish(keg_id, [{:my_keg_date, value}])

    # Also send to keg hardware pin (no read feedback available)
    KegCommander.set_date(keg_id, value)

    json_response(conn, 200, %{status: "ok", command: "date", value: value})
  end

  post "api/kegs/:id/og" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    # Save to our local database only (no hardware pin for this)
    KegData.publish(keg_id, [{:my_og, value}])

    json_response(conn, 200, %{status: "ok", command: "og", value: value})
  end

  post "api/kegs/:id/fg" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    # Save to our local database only (no hardware pin for this)
    KegData.publish(keg_id, [{:my_fg, value}])

    json_response(conn, 200, %{status: "ok", command: "fg", value: value})
  end

  post "api/kegs/:id/abv" do
    keg_id = conn.params["id"]
    %{"og" => og_str, "fg" => fg_str} = conn.body_params

    with {og, ""} <- Float.parse(og_str),
         {fg, ""} <- Float.parse(fg_str) do
      # Standard homebrewing ABV formula: (OG - FG) × 131.25
      abv = (og - fg) * 131.25
      abv_rounded = Float.round(abv, 2)

      # Save to our local database only (no hardware pin for this)
      KegData.publish(keg_id, [{:my_abv, "#{abv_rounded}"}])

      json_response(conn, 200, %{abv: abv_rounded})
    else
      _ ->
        json_response(conn, 400, %{error: "Invalid OG or FG format"})
    end
  end

  # ============================================
  # Delete a keg and all its stored data from DETS (e.g. decommissioned or phantom kegs).
  post "api/kegs/:id/delete" do
    keg_id = conn.params["id"]
    KegData.delete(keg_id)
    Logger.info("Deleted keg #{keg_id} from DETS")
    json_response(conn, 200, %{status: "ok", deleted: keg_id})
  end

  # Airlock (fermentation) devices – separate from keg scales
  # ============================================

  get "api/airlocks" do
    data = AirlockData.all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(data))
  end

  get "api/airlocks/:id" do
    id = conn.params["id"]
    data = AirlockData.get(id)

    if id in AirlockData.devices() do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Poison.encode!(data))
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, Poison.encode!(%{error: "not_found"}))
    end
  end

  # Submit temperature and/or bubbles per minute from an airlock device (id chosen by device/user).
  post "api/airlocks/:id/data" do
    airlock_id = conn.params["id"]
    params = conn.body_params || %{}

    temperature = parse_airlock_value(params["temperature"])
    bubbles_per_min = parse_airlock_value(params["bubbles_per_min"])

    cond do
      temperature == nil and bubbles_per_min == nil ->
        json_response(conn, 400, %{error: "At least one of temperature or bubbles_per_min is required"})

      true ->
        data =
          []
          |> maybe_append(:temperature, temperature)
          |> maybe_append(:bubbles_per_min, bubbles_per_min)

        AirlockData.publish(airlock_id, data)
        WebSocketHandler.publish_airlock(airlock_id, data)

        # Send to Grainfather/Brewfather if enabled (throttled to every 15 min by each module)
        OpenPlaatoKeg.Grainfather.maybe_send(airlock_id, temperature, bubbles_per_min)
        OpenPlaatoKeg.Brewfather.maybe_send(airlock_id, temperature, bubbles_per_min)

        response =
          %{status: "ok", command: "airlock_data"}
          |> maybe_put_response("temperature", temperature)
          |> maybe_put_response("bubbles_per_min", bubbles_per_min)

        json_response(conn, 200, response)
    end
  end

  # Set airlock label (e.g. "Primary", "Secondary"). Configurable from setup page.
  post "api/airlocks/:id/label" do
    airlock_id = conn.params["id"]
    value = (conn.body_params || %{})["value"] |> Kernel.to_string() |> String.trim()

    AirlockData.publish(airlock_id, [{:label, value}])
    WebSocketHandler.publish_airlock(airlock_id, [{:label, value}])

    json_response(conn, 200, %{status: "ok", command: "airlock_label", value: value})
  end

  # Grainfather: enable/disable and options for sending this airlock's data to Grainfather web app (max every 15 min).
  post "api/airlocks/:id/grainfather" do
    airlock_id = conn.params["id"]
    params = conn.body_params || %{}

    enabled = params["enabled"] in [true, "true", "1"]
    unit = case params["unit"] do
      "fahrenheit" -> "fahrenheit"
      _ -> "celsius"
    end
    sg = params["specific_gravity"] |> parse_airlock_value() |> Kernel.||("1.0")
    url = (params["url"] || "") |> to_string() |> String.trim()

    data = [
      {:grainfather_enabled, to_string(enabled)},
      {:grainfather_unit, unit},
      {:grainfather_specific_gravity, sg},
      {:grainfather_url, url}
    ]

    AirlockData.publish(airlock_id, data)
    WebSocketHandler.publish_airlock(airlock_id, data)

    json_response(conn, 200, %{
      status: "ok",
      command: "grainfather",
      grainfather_enabled: enabled,
      grainfather_unit: unit,
      grainfather_specific_gravity: sg,
      grainfather_url: url
    })
  end

  # Brewfather: enable/disable and options for sending this airlock's data to Brewfather custom stream (max every 15 min).
  post "api/airlocks/:id/brewfather" do
    airlock_id = conn.params["id"]
    params = conn.body_params || %{}

    enabled = params["enabled"] in [true, "true", "1"]
    unit = case params["unit"] do
      "fahrenheit" -> "fahrenheit"
      _ -> "celsius"
    end
    sg = params["specific_gravity"] |> parse_airlock_value() |> Kernel.||("1.0")
    og = params["og"] |> parse_airlock_value()
    batch_volume = params["batch_volume"] |> parse_airlock_value()
    url = (params["url"] || "") |> to_string() |> String.trim()

    data =
      [
        {:brewfather_enabled, to_string(enabled)},
        {:brewfather_temp_unit, unit},
        {:brewfather_sg, sg},
        {:brewfather_url, url}
      ]
      |> then(fn d -> if og, do: [{:brewfather_og, og} | d], else: d end)
      |> then(fn d -> if batch_volume, do: [{:brewfather_batch_volume, batch_volume} | d], else: d end)

    AirlockData.publish(airlock_id, data)
    WebSocketHandler.publish_airlock(airlock_id, data)

    json_response(conn, 200, %{
      status: "ok",
      command: "brewfather",
      brewfather_enabled: enabled,
      brewfather_temp_unit: unit,
      brewfather_sg: sg,
      brewfather_og: og,
      brewfather_batch_volume: batch_volume,
      brewfather_url: url
    })
  end

  # ============================================
  # Settings Commands
  # ============================================

  post "api/kegs/:id/unit" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    unit_pin =
      case value do
        v when v in ["metric", "1"] -> "1"
        v when v in ["us", "2"] -> "2"
        _ -> nil
      end

    result =
      case unit_pin do
        "1" -> KegCommander.set_unit_metric(keg_id)
        "2" -> KegCommander.set_unit_us(keg_id)
        nil -> {:error, :invalid_value}
      end

    if unit_pin do
      current = KegData.get(keg_id)
      measure_unit = to_string(current[:measure_unit] || "2")
      keg_mode = to_string(current[:keg_mode_c02_beer] || "1")

      KegData.publish(keg_id, [
        {:unit, unit_pin},
        {:beer_left_unit, derive_beer_left_unit(unit_pin, measure_unit, keg_mode)},
        {:temperature_unit, derive_temperature_unit(unit_pin)}
      ])

      WebSocketHandler.publish(keg_id, [])
    end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "unit", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/measure-unit" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    measure_pin =
      case value do
        v when v in ["weight", "1"] -> "1"
        v when v in ["volume", "2"] -> "2"
        _ -> nil
      end

    result =
      case measure_pin do
        "1" -> KegCommander.set_measure_unit_weight(keg_id)
        "2" -> KegCommander.set_measure_unit_volume(keg_id)
        nil -> {:error, :invalid_value}
      end

    if measure_pin do
      current = KegData.get(keg_id)
      unit = to_string(current[:unit] || "1")
      keg_mode = to_string(current[:keg_mode_c02_beer] || "1")

      KegData.publish(keg_id, [
        {:measure_unit, measure_pin},
        {:beer_left_unit, derive_beer_left_unit(unit, measure_pin, keg_mode)}
      ])

      WebSocketHandler.publish(keg_id, [])
    end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "measure_unit", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/keg-mode" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    {result, mode_pin} =
      case value do
        v when v in ["beer", "1"] -> {KegCommander.set_keg_mode_beer(keg_id), "1"}
        v when v in ["co2", "2"]  -> {KegCommander.set_keg_mode_co2(keg_id), "2"}
        _ -> {{:error, :invalid_value}, nil}
      end

    if mode_pin do
      current = KegData.get(keg_id)
      unit = to_string(current[:unit] || "1")
      measure_unit = to_string(current[:measure_unit] || "2")

      KegData.publish(keg_id, [
        {:keg_mode_c02_beer, mode_pin},
        {:beer_left_unit, derive_beer_left_unit(unit, measure_unit, mode_pin)}
      ])

      WebSocketHandler.publish(keg_id, [])
    end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "keg_mode", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/co2-capacity" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    capacity =
      cond do
        is_number(value) -> to_string(value)
        is_binary(value) ->
          case Float.parse(value) do
            {_, ""} -> value
            _ -> nil
          end
        true -> nil
      end

    if capacity do
      KegData.publish(keg_id, [{:my_co2_capacity, capacity}])
      json_response(conn, 200, %{status: "ok", co2_capacity: capacity})
    else
      json_response(conn, 400, %{error: "value must be a number"})
    end
  end

  post "api/kegs/:id/sensitivity" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    level =
      case value do
        "very_low" -> 1
        "low" -> 2
        "medium" -> 3
        "high" -> 4
        v when is_binary(v) -> String.to_integer(v)
        v when is_integer(v) -> v
      end

    case KegCommander.set_sensitivity(keg_id, level) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "sensitivity", value: level})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  # ============================================
  # Tap List (beer.db)
  # ============================================

  get "api/taps" do
    json_response(conn, 200, BeerDB.all_taps())
  end

  get "api/taps/:id" do
    case BeerDB.get_tap(conn.params["id"]) do
      nil -> json_response(conn, 404, %{error: "not_found"})
      tap -> json_response(conn, 200, tap)
    end
  end

  post "api/taps/:id" do
    id = conn.params["id"]
    p = conn.body_params || %{}

    raw_device_id = to_string(p["device_id"] || "") |> String.trim() |> String.slice(0, 6)

    data = %{
      tap_number: parse_int_or_nil(p["tap_number"]),
      name: to_string(p["name"] || ""),
      brewery: to_string(p["brewery"] || ""),
      style: to_string(p["style"] || ""),
      abv: to_string(p["abv"] || ""),
      ibu: to_string(p["ibu"] || ""),
      color: to_string(p["color"] || "#c9a849"),
      description: to_string(p["description"] || ""),
      tasting_notes: to_string(p["tasting_notes"] || ""),
      keg_id: nilify_empty(p["keg_id"]),
      handle_image: nilify_empty(p["handle_image"]),
      device_id: nilify_empty(raw_device_id)
    }

    BeerDB.put_tap(id, data)
    json_response(conn, 200, %{status: "ok", id: id})
  end

  post "api/taps/:id/delete" do
    BeerDB.delete_tap(conn.params["id"])
    json_response(conn, 200, %{status: "ok"})
  end

  # ============================================
  # open-tap ESP32 endpoint
  # GET /get_keg/:device_id
  # Returns tap + live keg data in open-tap JSON format.
  # Weights are in KG (floats); logo_url points to the handle image.
  # device_id is up to 6 chars (configured in ESP32 NVS).
  # ============================================

  get "get_keg/:device_id" do
    device_id = conn.params["device_id"]

    tap =
      BeerDB.all_taps()
      |> Enum.find(fn t ->
        did = Map.get(t, :device_id) || Map.get(t, "device_id")
        did && String.downcase(to_string(did)) == String.downcase(device_id)
      end)

    case tap do
      nil ->
        json_response(conn, 404, %{error: "no tap configured for device_id '#{device_id}'"})

      tap ->
        keg_id = Map.get(tap, :keg_id) || Map.get(tap, "keg_id")
        keg = if keg_id, do: KegData.get(keg_id), else: %{}
        keg = keg || %{}

        # max_keg_volume is the total full weight in kg (Plaato pin 76)
        keg_capacity_kg =
          case keg[:max_keg_volume] || keg["max_keg_volume"] do
            nil -> nil
            v -> parse_float_or_nil(v)
          end

        # empty_keg_weight is the tare/empty weight in kg (Plaato pin 62)
        empty_keg_weight_kg =
          case keg[:empty_keg_weight] || keg["empty_keg_weight"] do
            nil -> nil
            v -> parse_float_or_nil(v)
          end

        # current_weight: always total weight in kg so open-tap can compute beer left =
        # current_weight - empty_keg_weight. Uses weight_raw when valid (then + empty to get
        # total, since scale often reports net); else fallback = empty + amount_left in kg.
        current_weight_kg =
          compute_get_keg_current_weight(
            keg[:weight_raw] || keg["weight_raw"],
            keg,
            empty_keg_weight_kg
          )

        handle_image = Map.get(tap, :handle_image) || Map.get(tap, "handle_image")

        logo_url =
          if handle_image && handle_image != "" do
            scheme = if conn.scheme == :https, do: "https", else: "http"
            host = conn.host
            port = conn.port
            port_str = if port in [80, 443], do: "", else: ":#{port}"
            "#{scheme}://#{host}#{port_str}/uploads/tap-handles/#{URI.encode(handle_image)}"
          else
            nil
          end

        beer_name = Map.get(tap, :name) || Map.get(tap, "name") || ""
        brewery = Map.get(tap, :brewery) || Map.get(tap, "brewery") || ""

        description =
          [Map.get(tap, :description) || Map.get(tap, "description"),
           Map.get(tap, :tasting_notes) || Map.get(tap, "tasting_notes")]
          |> Enum.reject(&(is_nil(&1) || &1 == ""))
          |> Enum.join(" | ")

        full_name = if brewery != "", do: "#{beer_name} - #{brewery}", else: beer_name

        json_response(conn, 200, %{
          id: device_id,
          name: full_name,
          description: description,
          logo_url: logo_url,
          keg_capacity: round_kg(keg_capacity_kg),
          empty_keg_weight: round_kg(empty_keg_weight_kg),
          current_weight: round_kg(current_weight_kg),
          keg_id: keg_id
        })
    end
  end

  # ============================================
  # Tap Handle Images
  # ============================================

  get "api/tap-handles" do
    json_response(conn, 200, BeerDB.all_handles())
  end

  # Serve uploaded handle images from the persistent data directory
  get "uploads/tap-handles/:filename" do
    filename = conn.params["filename"]

    if Regex.match?(~r/^[a-zA-Z0-9_\-]+\.jpg$/i, filename) do
      path = Path.join(OpenPlaatoKeg.tap_handle_dir(), filename)

      if File.exists?(path) do
        conn
        |> put_resp_content_type("image/jpeg")
        |> send_resp(200, File.read!(path))
      else
        json_response(conn, 404, %{error: "not_found"})
      end
    else
      json_response(conn, 400, %{error: "invalid_filename"})
    end
  end

  post "api/tap-handles/upload" do
    case conn.params["image"] do
      %Plug.Upload{filename: original_name, path: temp_path} ->
        fname_lower = String.downcase(original_name)

        cond do
          not String.ends_with?(fname_lower, ".jpg") ->
            json_response(conn, 400, %{error: "Only .jpg files are allowed"})

          true ->
            content = File.read!(temp_path)

            case jpeg_dimensions(content) do
              {200, 200} ->
                safe_name = sanitize_filename(fname_lower)
                dest = Path.join(OpenPlaatoKeg.tap_handle_dir(), safe_name)
                File.cp!(temp_path, dest)
                BeerDB.put_handle(safe_name, %{uploaded_at: DateTime.utc_now() |> to_string()})
                json_response(conn, 200, %{status: "ok", filename: safe_name})

              {w, h} ->
                json_response(conn, 400, %{error: "Image must be exactly 200×200 px (got #{w}×#{h})"})

              nil ->
                json_response(conn, 400, %{error: "Could not read JPEG dimensions — ensure file is a valid JPEG"})
            end
        end

      _ ->
        json_response(conn, 400, %{error: "No image file provided (field name must be 'image')"})
    end
  end

  post "api/tap-handles/:filename/delete" do
    filename = conn.params["filename"]

    if Regex.match?(~r/^[a-zA-Z0-9_\-]+\.jpg$/i, filename) do
      File.rm(Path.join(OpenPlaatoKeg.tap_handle_dir(), filename))
      BeerDB.delete_handle(filename)
      json_response(conn, 200, %{status: "ok"})
    else
      json_response(conn, 400, %{error: "invalid_filename"})
    end
  end

  # ============================================
  # Beverage Library
  # ============================================

  get "api/beverages" do
    json_response(conn, 200, BeverageDB.all())
  end

  get "api/beverages/:id" do
    case BeverageDB.get(conn.params["id"]) do
      nil -> json_response(conn, 404, %{error: "not_found"})
      bev -> json_response(conn, 200, bev)
    end
  end

  post "api/beverages/:id" do
    id = conn.params["id"]
    p = conn.body_params || %{}

    og_str = to_string(p["og"] || "") |> String.trim()
    fg_str = to_string(p["fg"] || "") |> String.trim()
    sg_str = to_string(p["sg"] || "") |> String.trim()
    # Some users might provide "sg" instead of "fg" (FG = final gravity).
    fg_input_str = if fg_str != "", do: fg_str, else: sg_str

    abv_str = to_string(p["abv"] || "") |> String.trim()
    computed_abv_str =
      if String.trim(abv_str) == "" do
        with {og, ""} <- Float.parse(og_str),
             {fg, ""} <- Float.parse(fg_input_str) do
          abv = (og - fg) * 131.25
          "#{Float.round(abv, 2)}"
        else
          _ -> ""
        end
      else
        ""
      end

    data = %{
      name:                to_string(p["name"] || ""),
      brewery:             to_string(p["brewery"] || ""),
      style:               to_string(p["style"] || ""),
      abv:                 (if computed_abv_str != "", do: computed_abv_str, else: abv_str),
      ibu:                 to_string(p["ibu"] || ""),
      color:               to_string(p["color"] || "#c9a849"),
      description:         to_string(p["description"] || ""),
      tasting_notes:       to_string(p["tasting_notes"] || ""),
      og:                  og_str,
      fg:                  fg_input_str,
      srm:                 to_string(p["srm"] || ""),
      source:              to_string(p["source"] || "manual"),
      brewfather_batch_id: to_string(p["brewfather_batch_id"] || ""),
      created_at:          to_string(p["created_at"] || DateTime.utc_now())
    }

    BeverageDB.put(id, data)
    json_response(conn, 200, %{status: "ok", id: id})
  end

  post "api/beverages/:id/delete" do
    BeverageDB.delete(conn.params["id"])
    json_response(conn, 200, %{status: "ok"})
  end

  # ============================================
  # Brewfather API credentials + batch import
  # ============================================

  get "api/config/brewfather" do
    user_id = OpenPlaatoKeg.AppConfig.get(:brewfather_user_id, "")
    configured = is_binary(user_id) && user_id != ""
    json_response(conn, 200, %{configured: configured})
  end

  post "api/config/brewfather" do
    p = conn.body_params || %{}
    user_id = to_string(p["user_id"] || "") |> String.trim()
    api_key  = to_string(p["api_key"] || "") |> String.trim()

    OpenPlaatoKeg.AppConfig.put(:brewfather_user_id, user_id)
    OpenPlaatoKeg.AppConfig.put(:brewfather_api_key, api_key)

    json_response(conn, 200, %{status: "ok", configured: user_id != ""})
  end

  get "api/brewfather/batches" do
    user_id = OpenPlaatoKeg.AppConfig.get(:brewfather_user_id, "")
    api_key  = OpenPlaatoKeg.AppConfig.get(:brewfather_api_key, "")

    if user_id == "" || api_key == "" do
      json_response(conn, 400, %{error: "no_credentials"})
    else
      case OpenPlaatoKeg.BrewfatherApi.fetch_batches(user_id, api_key) do
        {:ok, batches} ->
          simplified = Enum.map(batches, fn b ->
            %{
              id:     b["_id"],
              name:   b["name"] || get_in(b, ["recipe", "name"]) || "",
              style:  get_in(b, ["recipe", "style", "name"]) || "",
              abv:    b["measuredAbv"] || b["estimatedAbv"],
              status: b["status"] || ""
            }
          end)
          json_response(conn, 200, simplified)

        {:error, reason} ->
          json_response(conn, 502, %{error: reason})
      end
    end
  end

  post "api/brewfather/import/:batch_id" do
    batch_id = conn.params["batch_id"]
    user_id  = OpenPlaatoKeg.AppConfig.get(:brewfather_user_id, "")
    api_key  = OpenPlaatoKeg.AppConfig.get(:brewfather_api_key, "")

    if user_id == "" || api_key == "" do
      json_response(conn, 400, %{error: "no_credentials"})
    else
      case OpenPlaatoKeg.BrewfatherApi.fetch_batches(user_id, api_key) do
        {:ok, batches} ->
          case Enum.find(batches, fn b -> b["_id"] == batch_id end) do
            nil ->
              json_response(conn, 404, %{error: "batch_not_found"})

            batch ->
              bev_data =
                batch
                |> OpenPlaatoKeg.BrewfatherApi.batch_to_beverage()
                |> Map.put(:created_at, to_string(DateTime.utc_now()))

              new_id = BeverageDB.generate_id()
              BeverageDB.put(new_id, bev_data)
              json_response(conn, 200, %{status: "ok", id: new_id})
          end

        {:error, reason} ->
          json_response(conn, 502, %{error: reason})
      end
    end
  end

  # ============================================
  # Other Endpoints
  # ============================================

  get "/api/metrics" do
    conn
    |> put_resp_content_type(:prometheus_text_format.content_type())
    |> send_resp(200, OpenPlaatoKeg.Metrics.scrape_data())
  end

  get "/ws" do
    conn
    |> WebSockAdapter.upgrade(OpenPlaatoKeg.WebSocketHandler, [], timeout: :infinity)
    |> halt()
  end

  get "/api/alive" do
    version = Application.spec(:open_plaato_keg, :vsn) |> to_string()
    json_response(conn, 200, %{status: "ok", version: version})
  end

  # ============================================
  # Transfer Scale Endpoints
  # ============================================

  get "api/transfer-scales" do
    data = TransferScaleData.all()
    json_response(conn, 200, data)
  end

  get "api/transfer-scales/:id" do
    id = conn.params["id"]
    data = TransferScaleData.get(id)

    if id in TransferScaleData.devices() do
      json_response(conn, 200, data)
    else
      json_response(conn, 404, %{error: "not_found"})
    end
  end

  post "api/transfer-scales/:id/data" do
    scale_id = conn.params["id"]
    params = conn.body_params || %{}

    case parse_transfer_scale_float(params["raw_weight"]) do
      nil ->
        json_response(conn, 400, %{error: "raw_weight is required and must be a number"})

      raw_weight ->
        last_updated = System.os_time(:second)

        TransferScaleData.publish(scale_id, [
          {:raw_weight, raw_weight},
          {:last_updated, last_updated}
        ])

        WebSocketHandler.publish_transfer_scale(scale_id)

        updated = TransferScaleData.get(scale_id)

        json_response(conn, 200, %{
          status: "ok",
          id: scale_id,
          raw_weight: raw_weight,
          fill_percent: updated[:fill_percent]
        })
    end
  end

  post "api/transfer-scales/:id/config" do
    scale_id = conn.params["id"]
    params = conn.body_params || %{}

    label = params["label"]
    empty_keg_weight = parse_transfer_scale_float(params["empty_keg_weight"])
    target_weight = parse_transfer_scale_float(params["target_weight"])

    data =
      []
      |> then(fn d -> if is_binary(label), do: [{:label, label} | d], else: d end)
      |> then(fn d ->
        if is_number(empty_keg_weight), do: [{:empty_keg_weight, empty_keg_weight} | d], else: d
      end)
      |> then(fn d ->
        if is_number(target_weight), do: [{:target_weight, target_weight} | d], else: d
      end)

    TransferScaleData.publish(scale_id, data)

    json_response(conn, 200, %{status: "ok", id: scale_id})
  end

  post "api/transfer-scales/:id/delete" do
    scale_id = conn.params["id"]

    :dets.match_delete(:transfer_scale_data, {{scale_id, :_}, :_})

    json_response(conn, 200, %{status: "ok", deleted: scale_id})
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  # Helper functions

  defp json_response(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Poison.encode!(data))
  end

  # Airlock: accept number or string that parses as a complete number (no trailing junk); return string for storage/metrics
  defp parse_airlock_value(nil), do: nil
  defp parse_airlock_value(v) when is_number(v), do: to_string(v)
  defp parse_airlock_value(v) when is_binary(v) do
    case Float.parse(v) do
      {_num, ""} -> v
      {_num, _rest} -> nil
      :error -> nil
    end
  end
  defp parse_airlock_value(_), do: nil

  # Transfer scale: accept number or string, return float (nil if invalid)
  defp parse_transfer_scale_float(nil), do: nil
  defp parse_transfer_scale_float(v) when is_float(v), do: v
  defp parse_transfer_scale_float(v) when is_integer(v), do: v * 1.0
  defp parse_transfer_scale_float(v) when is_binary(v) do
    case Float.parse(v) do
      {num, ""} -> num
      _ -> nil
    end
  end
  defp parse_transfer_scale_float(_), do: nil

  defp maybe_append(list, _key, nil), do: list
  defp maybe_append(list, key, value), do: [{key, value} | list] |> Enum.reverse()

  defp maybe_put_response(map, _key, nil), do: map
  defp maybe_put_response(map, key, value), do: Map.put(map, key, value)

  # unit "1" = metric, "2" = US; measure_unit "1" = weight; keg_mode "2" = CO2
  defp derive_beer_left_unit("1", _, "2"), do: "kg CO\u2082"
  defp derive_beer_left_unit("2", _, "2"), do: "lbs CO\u2082"
  defp derive_beer_left_unit("1", "1", _), do: "kg"
  defp derive_beer_left_unit("1", _, _),   do: "litre"
  defp derive_beer_left_unit("2", "1", _), do: "lbs"
  defp derive_beer_left_unit("2", _, _),   do: "gal"
  defp derive_beer_left_unit(_, _, _),     do: "litre"

  defp derive_temperature_unit("2"), do: "°F"
  defp derive_temperature_unit(_),   do: "°C"

  # Plausible net (beer) weight in kg (0–200). weight_raw outside this is ignored.
  @get_keg_weight_kg_max 200.0

  # Always return total weight (empty + beer) for open-tap so device can compute
  # beer left = current_weight - empty_keg_weight. When weight_raw is valid we treat it
  # as scale/net (beer only) and add empty_keg_weight to get total; when invalid we use
  # fallback total = empty_keg_weight + amount_left converted to kg.
  defp compute_get_keg_current_weight(weight_raw, keg, empty_keg_weight_kg) do
    fallback_total =
      (fn ->
        amount_left = parse_float_or_nil(keg[:amount_left] || keg["amount_left"])
        unit = to_string(keg[:beer_left_unit] || keg["beer_left_unit"] || "")

        beer_kg =
          cond do
            amount_left == nil -> nil
            unit in ["litre", "l", "liter"] -> amount_left * 1.0
            unit in ["lbs", "lb", "pounds"] -> amount_left * 0.453592
            unit in ["gal", "gallon", "gallons"] -> amount_left * 3.78541
            true -> amount_left
          end

        case {empty_keg_weight_kg, beer_kg} do
          {e, b} when is_float(e) and is_float(b) -> e + b
          _ -> nil
        end
      end).()

    case parse_float_or_nil(weight_raw) do
      nil ->
        fallback_total
      w when w < 0 or w > @get_keg_weight_kg_max ->
        fallback_total
      w ->
        # Scale (pin 53) typically reports net/beer weight when tare'd; add empty for total.
        case empty_keg_weight_kg do
          e when is_float(e) -> e + w
          _ -> fallback_total
        end
    end
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(v) do
    case Integer.parse(to_string(v)) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp parse_float_or_nil(nil), do: nil
  defp parse_float_or_nil(v) do
    case Float.parse(to_string(v)) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp round_kg(nil), do: nil
  defp round_kg(w) when is_number(w), do: Float.round(w, 2)

  defp nilify_empty(nil), do: nil
  defp nilify_empty(""), do: nil
  defp nilify_empty(v), do: to_string(v)

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^a-z0-9_\-\.]/, "_")
    |> String.replace(~r/_+/, "_")
  end

  # Parse JPEG image dimensions from raw binary data.
  # Returns {width, height} or nil if not a valid JPEG or SOF not found.
  defp jpeg_dimensions(<<0xFF, 0xD8, rest::binary>>), do: find_jpeg_sof(rest)
  defp jpeg_dimensions(_), do: nil

  @sof_markers [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]

  # SOF marker: precision(1) height(2) width(2)
  defp find_jpeg_sof(<<0xFF, m, _size::big-16, _prec, h::big-16, w::big-16, _::binary>>)
       when m in @sof_markers,
       do: {w, h}

  # Non-SOF segment: skip payload and recurse
  defp find_jpeg_sof(<<0xFF, _m, size::big-16, rest::binary>>) when size >= 2 do
    skip = size - 2

    if byte_size(rest) >= skip do
      <<_::binary-size(skip), next::binary>> = rest
      find_jpeg_sof(next)
    end
  end

  defp find_jpeg_sof(_), do: nil
end
