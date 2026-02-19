defmodule OpenPlaatoKeg.HttpRouter do
  use Plug.Router
  alias OpenPlaatoKeg.KegCommander
  alias OpenPlaatoKeg.Models.KegData

  plug(Plug.Static,
    at: "/",
    from: :open_plaato_keg
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["application/json"],
    json_decoder: Poison
  )

  plug(:match)
  plug(:dispatch)

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

    case KegCommander.set_temperature_offset(keg_id, value) do
      :ok ->
        json_response(conn, 200, %{status: "ok", command: "temperature_offset", value: value})

      {:error, reason} ->
        json_response(conn, 503, %{error: reason})
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

  post "api/kegs/:id/set-empty-keg-value" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    case KegCommander.set_empty_keg_value(keg_id, value) do
      :ok -> json_response(conn, 200, %{status: "ok", command: "set_empty_keg_value", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
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
  # Settings Commands
  # ============================================

  post "api/kegs/:id/unit" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    result =
      case value do
        "metric" -> KegCommander.set_unit_metric(keg_id)
        "1" -> KegCommander.set_unit_metric(keg_id)
        "us" -> KegCommander.set_unit_us(keg_id)
        "2" -> KegCommander.set_unit_us(keg_id)
        _ -> {:error, :invalid_value}
      end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "unit", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/measure-unit" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    result =
      case value do
        "weight" -> KegCommander.set_measure_unit_weight(keg_id)
        "1" -> KegCommander.set_measure_unit_weight(keg_id)
        "volume" -> KegCommander.set_measure_unit_volume(keg_id)
        "2" -> KegCommander.set_measure_unit_volume(keg_id)
        _ -> {:error, :invalid_value}
      end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "measure_unit", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
    end
  end

  post "api/kegs/:id/keg-mode" do
    keg_id = conn.params["id"]
    %{"value" => value} = conn.body_params

    result =
      case value do
        "beer" -> KegCommander.set_keg_mode_beer(keg_id)
        "1" -> KegCommander.set_keg_mode_beer(keg_id)
        "co2" -> KegCommander.set_keg_mode_co2(keg_id)
        "2" -> KegCommander.set_keg_mode_co2(keg_id)
        _ -> {:error, :invalid_value}
      end

    case result do
      :ok -> json_response(conn, 200, %{status: "ok", command: "keg_mode", value: value})
      {:error, reason} -> json_response(conn, 503, %{error: reason})
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
    send_resp(conn, 200, "1")
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
end
