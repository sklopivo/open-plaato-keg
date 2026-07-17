# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Plaato Keg is an Elixir application that reverse-engineers the Blynk protocol used by Plaato Keg homebrew devices, allowing local operation without the discontinued Plaato cloud service. It acts as a local Blynk server replacement, decoding TCP data from keg hardware and exposing it via HTTP REST API, WebSocket, MQTT, and BarHelper integrations.

## Build & Development Commands

```bash
# Install dependencies
mix deps.get

# Run the application locally
mix run --no-halt

# Run all tests (alias runs with --no-start)
mix test

# Run a single test file
mix test test/decoder_test.exs

# Run a specific test by line number
mix test test/decoder_test.exs:42

# Lint with Credo
mix credo

# Build a Docker image
docker build -t open-plaato-keg .

# Build an Elixir release
mix release
```

## Required Toolchain

Defined in `.tool-versions` (for asdf): Elixir 1.16.2-otp-26, Erlang 26.2.5.

## Architecture

### Data Flow

Raw TCP bytes from Plaato Keg hardware go through a three-stage decoding pipeline:

1. **BlynkProtocol** (`blynk_protocol.ex`) — Decodes/encodes the binary Blynk wire protocol (command type, message ID, length, body). Also provides `encode_command/3` for sending commands back to the keg.
2. **PlaatoProtocol** (`plaato_protocol.ex`) — Interprets Blynk commands into Plaato-specific operations (login with auth token, hardware pin writes, internal metadata).
3. **PlaatoData** (`plaato_data.ex`) — Maps Plaato virtual pin numbers to meaningful keg properties (amount_left, temperature, firmware_version, etc.).

### Connection Handling

- **KegConnectionHandler** — ThousandIsland TCP handler; one per keg connection. Spawns a per-connection `KegDataProcessor` GenServer (not globally named, to support multiple kegs). Registers sockets in `KegSocketRegistry` for bi-directional communication.
- **KegDataProcessor** — Per-connection GenServer that decodes incoming data and fans out to all publishers (KegData store, WebSocket, Metrics, MQTT, BarHelper) based on configuration.
- **KegCommander** (`keg_commander.ex`) — Sends commands back to connected kegs via `KegSocketRegistry` (tare, calibrate, set OG/FG, etc.).

### Storage

- Uses Erlang `:dets` for persistence. Two tables are opened at startup:
  - `:keg_data` — keg scale state, stored at `DATABASE_FILE_PATH`.
  - `:airlock_data` — airlock/fermentation device state, stored as `airlock_data.bin` in the same directory.
- **KegData** model (`models/keg_data.ex`) — Reads/writes keg state to `:keg_data` DETS; merges incoming property updates.
- **AirlockData** model (`models/airlock_data.ex`) — Reads/writes airlock state (temperature, bubbles_per_min, label, Grainfather settings) to `:airlock_data` DETS. Airlocks are identified by a caller-chosen string ID (not a Blynk token).

### HTTP Layer

- **HttpRouter** (`http_router.ex`) — Plug/Bandit router serving:
  - REST API for kegs: `/api/kegs`, `/api/kegs/devices`, `/api/kegs/connected`, `/api/kegs/:id`, and command endpoints `/api/kegs/:id/*` (tare, calibrate, beer-style, og, fg, abv, unit, keg-mode, sensitivity, etc.).
  - REST API for airlocks: `/api/airlocks`, `/api/airlocks/:id`, `/api/airlocks/:id/data` (POST temperature/bubbles_per_min), `/api/airlocks/:id/label`, `/api/airlocks/:id/grainfather`.
  - `/api/metrics` (Prometheus), `/api/alive`, `/ws` (WebSocket upgrade), static files.
- **WebSocketHandler** — Broadcasts updates to browser clients via `WebSocketConnectionRegistry`. Keg updates send raw keg JSON; airlock updates send `%{type: "airlock", data: ...}`.

### Airlock & Grainfather Integration

- **AirlockData** devices are external (not Blynk hardware); clients POST data directly to `/api/airlocks/:id/data`.
- **Grainfather** (`grainfather.ex`) — On each airlock data submission, optionally forwards temperature, bubbles-per-minute, and specific gravity to the Grainfather community API. Throttled to at most once per 15 minutes per airlock (persisted via `grainfather_last_sent_at` in DETS). Per-airlock Grainfather settings (`grainfather_enabled`, `grainfather_unit`, `grainfather_specific_gravity`) are configured via `/api/airlocks/:id/grainfather`.

### Supervision Tree

`OpenPlaatoKeg.Supervisor` starts (conditionally): MQTT client (Tortoise), BarHelper GenServer, WebSocket connection registry, Keg socket registry, TCP listener (ThousandIsland), HTTP server (Bandit).

### Configuration

All runtime config is in `config/runtime.exs` via environment variables. The `ConfigTools` module (`config_tools.ex`) provides typed env var parsing (`:boolean`, `:integer`, `:string`, `:key_value_csv`). See README for the full environment variable reference.

## Testing

Tests use `--no-start` (the application is not started during tests). Journey tests in `test/journeys/` cover end-to-end scenarios. The `assert_value` library is available for snapshot-style assertions.

## Key Conventions

- Keg IDs are 32-character hex strings (the Blynk auth token).
- Keg properties flow as keyword lists through the decode pipeline.
- User-defined fields (beer style, OG, FG, ABV, keg date) are prefixed with `my_` and stored only in the local DETS database.
- The app version is read from `.release/version` at compile time.
