defmodule OpenPlaatoKeg.OtaRouter do
  @moduledoc """
  Wrapper plug that serves ESP32 firmware test images before handing all other
  traffic to the normal HTTP router.
  """

  @behaviour Plug
  import Plug.Conn
  require Logger

  @firmware_path "/download32.php"
  @firmware_api_path "/api/firmwares"
  @setup_path "/setup.html"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: method, request_path: @firmware_path} = conn, _opts)
      when method in ["GET", "HEAD"] do
    conn = fetch_query_params(conn)
    serve_firmware(conn, method)
  end

  def call(%Plug.Conn{method: "GET", request_path: @firmware_api_path} = conn, _opts) do
    list_firmwares(conn)
  end

  def call(%Plug.Conn{method: "GET", request_path: @setup_path} = conn, _opts) do
    serve_setup_page(conn)
  end

  def call(conn, opts) do
    OpenPlaatoKeg.HttpRouter.call(conn, OpenPlaatoKeg.HttpRouter.init(opts))
  end

  defp serve_firmware(conn, method) do
    path = selected_firmware_path(conn)

    case File.read(path) do
      {:ok, firmware} ->
        size = byte_size(firmware)
        md5 = firmware |> :crypto.hash(:md5) |> Base.encode16(case: :lower)
        version = configured_version()

        Logger.info("Serving ESP32 firmware #{path} size=#{size} md5=#{md5} version=#{version}")

        conn =
          conn
          |> put_resp_content_type("application/octet-stream")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("content-disposition", ~s(inline; filename="#{Path.basename(path)}"))
          |> put_resp_header("content-length", Integer.to_string(size))
          |> put_resp_header("x-ESP32-sketch-md5", md5)
          |> put_resp_header("x-ESP32-sketch-size", Integer.to_string(size))
          |> put_resp_header("x-ESP32-version", version)

        if method == "HEAD" do
          send_resp(conn, 200, "")
        else
          send_resp(conn, 200, firmware)
        end

      {:error, reason} ->
        Logger.warning("ESP32 firmware file not available at #{path}: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          404,
          Poison.encode!(%{error: "firmware_not_found", file: Path.basename(path)})
        )
    end
  end

  defp list_firmwares(conn) do
    firmwares =
      firmware_files()
      |> Enum.map(fn path ->
        stat = File.stat!(path)

        %{
          name: Path.basename(path),
          size: stat.size,
          path: "/download32.php?file=#{URI.encode_www_form(Path.basename(path))}"
        }
      end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Poison.encode!(%{firmwares: firmwares}))
  end

  defp serve_setup_page(conn) do
    setup_path = Path.join(:code.priv_dir(:open_plaato_keg), "static/setup.html")

    case File.read(setup_path) do
      {:ok, html} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, add_firmware_selector(html))

      {:error, reason} ->
        Logger.warning("Could not read setup page at #{setup_path}: #{inspect(reason)}")
        OpenPlaatoKeg.HttpRouter.call(conn, OpenPlaatoKeg.HttpRouter.init([]))
    end
  end

  defp add_firmware_selector(html) do
    if String.contains?(html, "otaFirmwareSelect") do
      html
    else
      add_legacy_firmware_selector(html)
    end
  end

  defp add_legacy_firmware_selector(html) do
    html
    |> String.replace(
      "onclick=\"triggerOtaUpdate()\">\n                        Send OTA",
      "onclick=\"triggerSelectedFirmwareOta()\">\n                        🔥 Update Firmware"
    )
    |> String.replace(
      ~r/<input class="input" type="text" id="otaFirmwarePath"[\s\S]*?<\/div>\s*<div class="control">/,
      firmware_select_html()
    )
    |> add_firmware_selector_js()
  end

  defp firmware_select_html do
    """
                    <div class="control is-expanded">
                      <div class="select is-fullwidth">
                        <select id="otaFirmwareSelect">
                          <option value="/download32.php">Default firmware</option>
                        </select>
                      </div>
                    </div>
                    <div class="control">
    """
  end

  defp add_firmware_selector_js(html) do
    if String.contains?(html, "function triggerSelectedFirmwareOta()") do
      html
    else
      String.replace(html, "</script>", firmware_selector_js() <> "\n    </script>",
        global: false
      )
    end
  end

  defp firmware_selector_js do
    """

      function loadOtaFirmwareOptions() {
        fetch('/api/firmwares')
          .then((response) => response.json())
          .then((data) => {
            const select = document.getElementById('otaFirmwareSelect');
            if (!select || !data.firmwares) return;

            select.innerHTML = '';
            data.firmwares.forEach((firmware) => {
              const option = document.createElement('option');
              option.value = firmware.path;
              option.textContent = `${firmware.name} (${Math.round(firmware.size / 1024)} KB)`;
              select.appendChild(option);
            });
          })
          .catch(() => {});
      }

      function triggerSelectedFirmwareOta() {
        const kegId = getSelectedKeg();
        if (!kegId) return;

        const select = document.getElementById('otaFirmwareSelect');
        const firmwarePath = select && select.value ? select.value : '/download32.php';
        const firmwareName = select && select.selectedOptions[0] ? select.selectedOptions[0].textContent : firmwarePath;

        if (!confirm(`Start firmware update using ${firmwareName}?`)) {
          return;
        }

        fetch(`/api/kegs/${kegId}/ota`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: firmwarePath })
        })
          .then((response) => response.json())
          .then((data) => {
            if (data.status === "ok") {
              showToast("Firmware update command sent", "success");
            } else {
              showToast(`Error: ${data.error}`, "danger");
            }
          })
          .catch((err) => {
            showToast(`Error: ${err.message}`, "danger");
          });
      }

      setTimeout(loadOtaFirmwareOptions, 250);
    """
  end

  defp selected_firmware_path(conn) do
    case Map.get(conn.query_params, "file") do
      file when is_binary(file) and file != "" ->
        safe_firmware_path(file)

      _ ->
        configured_firmware_path()
    end
  end

  defp safe_firmware_path(file) do
    file
    |> Path.basename()
    |> then(&Path.join(ota_dir(), &1))
  end

  defp configured_firmware_path do
    configured =
      Application.get_env(:open_plaato_keg, :ota, [])
      |> Keyword.get(:firmware_path, "priv/ota/firmware.bin")

    default_firmware = Path.join(ota_dir(), "plaatoV2.11b.bin")

    cond do
      File.exists?(configured) -> configured
      File.exists?(default_firmware) -> default_firmware
      true -> first_file_in_ota_folder(configured)
    end
  end

  defp first_file_in_ota_folder(default_path) do
    case firmware_files() do
      [first | _] -> first
      [] -> default_path
    end
  end

  defp firmware_files do
    Path.wildcard(Path.join(ota_dir(), "*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  defp ota_dir do
    Path.join(:code.priv_dir(:open_plaato_keg), "ota")
  end

  defp configured_version do
    Application.get_env(:open_plaato_keg, :ota, [])
    |> Keyword.get(:version, "test")
  end
end
