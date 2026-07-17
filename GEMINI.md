# open-plaato-keg

This project, `open-plaato-keg`, is an Elixir-based application designed to provide a local, self-hosted alternative to the Plaato cloud service for managing Plaato Keg devices. It bypasses the official Plaato cloud, enabling users to keep their keg data local and maintain functionality after the discontinuation of the official cloud service.

## Project Overview

The application acts as a server that communicates directly with Plaato Keg devices using a reverse-engineered Blynk protocol over TCP. It provides:

*   **TCP Listener**: For receiving data from and sending commands to Plaato Keg devices.
*   **HTTP Server (Bandit)**: Hosts a web-based user interface (`/index.html` for real-time monitoring and `/setup.html` for configuration) and a comprehensive REST API for interacting with connected kegs.
*   **WebSocket Interface**: Provides real-time updates for connected clients (e.g., the web UI).
*   **MQTT Integration (Tortoise)**: Optionally publishes keg data to an MQTT broker, allowing integration with home automation systems.
*   **BarHelper Integration**: Optionally sends keg data to BarHelper for custom keg monitor integration.
*   **Local Data Storage**: Uses Erlang's Dets database (`keg_data.bin`) for persistent storage of keg-related data and user-defined settings.
*   **Metrics**: Exposes Prometheus-compatible metrics for monitoring.

The project is built with Elixir and leverages its OTP (Open Telecom Platform) capabilities for robustness and concurrency.

## Building and Running

The `open-plaato-keg` application can be deployed using Docker or as an Elixir release. Configuration is primarily managed through environment variables.

### Docker

Docker images are available on GitHub Container Registry and support `linux/amd64` and `linux/arm64` architectures.

**To run with Docker:**

```bash
docker run --rm -it -p 1234:1234 -p 8085:8085 ghcr.io/sklopivo/open-plaato-keg:latest
```

A `docker-compose.yaml` file is also provided in the repository for a more comprehensive setup, including environment variable configurations for MQTT and BarHelper.

### Elixir Releases

For direct deployment without Docker, you can build an Elixir release. Ensure you have the correct Elixir and Erlang/OTP versions installed (recommended to use `asdf` with the `.tool-versions` file).

**General steps for building and running an Elixir release:**

1.  **Install Dependencies:**
    ```bash
    mix deps.get
    ```
2.  **Build Release:**
    ```bash
    MIX_ENV=prod mix release
    ```
    The release will be generated in `_build/prod/rel/open_plaato_keg`.
3.  **Run Release:**
    ```bash
    _build/prod/rel/open_plaato_keg/bin/open_plaato_keg start
    ```

### Configuration

The application is configured using environment variables. Key variables include:

*   `KEG_LISTENER_PORT`: TCP port for Plaato Keg connections (default: `1234`).
*   `HTTP_LISTENER_PORT`: HTTP port for web UI and API (default: `8085`).
*   `DATABASE_FILE_PATH`: Path to the persistent Dets database file (default: `priv/db/keg_data.bin`).
*   `MQTT_ENABLED`, `MQTT_HOST`, `MQTT_PORT`, `MQTT_USERNAME`, `MQTT_PASSWORD`, `MQTT_CLIENT_ID`, `MQTT_TOPIC`, `MQTT_JSON_OUTPUT`, `MQTT_PROPERTY_OUTPUT`: For MQTT integration.
*   `BARHELPER_ENABLED`, `BARHELPER_ENDPOINT`, `BARHELPER_API_KEY`, `BARHELPER_UNIT`, `BARHELPER_KEG_MONITOR_MAPPING`: For BarHelper integration.
*   `INCLUDE_UNKNOWN_DATA`: Set to `true` to include undecoded Blynk pins in output (default: `false`).

Refer to the `README.md` for a complete list and detailed descriptions of environment variables.

### Testing

Tests are written using ExUnit, Elixir's built-in testing framework.

**To run tests:**

```bash
mix test
```

The `mix.exs` file defines a `test` alias which runs `test --no-start`.

## Development Conventions

*   **Language**: Elixir
*   **Linting**: The project uses `Credo` for static code analysis. Configuration is found in `config/.credo.exs`.
    *   To run Credo: `mix credo`
*   **Formatting**: The project uses `mix format` for code formatting, configured by `.formatter.exs`.
*   **Testing**: Tests are located in the `test/` directory and use ExUnit. Journey tests are found in `test/journeys/`.
*   **Architecture**: Follows an OTP-driven design with supervisors managing various processes for listeners, handlers, and integrations.
*   **Configuration**: Prioritizes environment variables for runtime configuration.

---

This `GEMINI.md` provides an overview of the `open-plaato-keg` project, covering its purpose, architecture, how to build and run it, and development conventions. It serves as a foundational context for future interactions with the Gemini CLI.
