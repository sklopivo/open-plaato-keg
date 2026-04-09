defmodule OpenPlaatoKeg.KegConnectionHandler do
  use ThousandIsland.Handler
  require Logger

  alias OpenPlaatoKeg.BlynkProtocol
  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  @takeover_retry_ms 100

  def handle_connection(_socket, _state) do
    {:ok, pid} = OpenPlaatoKeg.KegDataProcessor.start_link(%{})
    state = %{keg_data_processor: pid, keg_id: nil}
    {:continue, state}
  end

  def handle_data(data, socket, state) do
    # Acknowledge Blynk-style packets, echoing the msg_id from the incoming frame.
    # Old firmware (e.g. Plaato Airlock NodeMCU) validates that the response msg_id
    # matches the request before firing BLYNK_CONNECTED. If we always respond with
    # msg_id=1 (the default), the login ack is never recognised when internal info
    # was sent first (as msg_id=1), causing BLYNK_CONNECTED to never fire.
    ack =
      case data do
        <<_cmd::8, msg_id::16, _rest::binary>> -> BlynkProtocol.response_success(msg_id)
        _ -> BlynkProtocol.response_success()
      end

    ThousandIsland.Socket.send(socket, ack)

    # Process/publish decoded data
    GenServer.cast(state.keg_data_processor, {:keg_data, data})

    # Extract keg ID from the data and register socket
    state = maybe_register_socket(data, socket, state)

    {:continue, state}
  end

  def handle_close(_socket, state) do
    if state.keg_id do
      Logger.info("Keg #{state.keg_id} disconnected")

      # Unregister the socket (only affects this process's registration)
      Registry.unregister(OpenPlaatoKeg.KegSocketRegistry, state.keg_id)

      # Only push the disconnect update for kegs (not airlocks).
      # Airlocks don't have is_pouring and their ID won't be in KegData.
      if state.keg_id in OpenPlaatoKeg.Models.KegData.devices() do
        # Prevent phantom "pouring" UI by pushing a disconnect update.
        # Plaato values are typically stringy, so "0" is safest.
        disconnect_update = [is_pouring: "0"]
        OpenPlaatoKeg.Models.KegData.publish(state.keg_id, disconnect_update)
        OpenPlaatoKeg.WebSocketHandler.publish(state.keg_id, disconnect_update)
      end
    end

    :ok
  end

  defp maybe_register_socket(data, socket, %{keg_id: nil} = state) do
    case extract_keg_id(data) do
      nil ->
        state

      keg_id ->
        Logger.info("Registering socket for keg #{keg_id}")

        case Registry.register(OpenPlaatoKeg.KegSocketRegistry, keg_id, socket) do
          {:ok, _} ->
            %{state | keg_id: keg_id}

          {:error, {:already_registered, old_pid}} ->
            Logger.warning(
              "Keg #{keg_id} already registered by #{inspect(old_pid)}; taking over"
            )

            # Kill stale handler holding the unique key so we can take over immediately.
            if old_pid != self(), do: Process.exit(old_pid, :kill)

            Process.sleep(@takeover_retry_ms)

            case Registry.register(OpenPlaatoKeg.KegSocketRegistry, keg_id, socket) do
              {:ok, _} ->
                %{state | keg_id: keg_id}

              {:error, reason} ->
                Logger.warning(
                  "Failed to register keg #{keg_id} after takeover: #{inspect(reason)}"
                )

                state
            end

          {:error, reason} ->
            Logger.warning("Failed to register keg #{keg_id}: #{inspect(reason)}")
            state
        end
    end
  end

  defp maybe_register_socket(_data, _socket, state), do: state

  defp extract_keg_id(data) do
    decoded =
      data
      |> BlynkProtocol.decode()
      |> PlaatoProtocol.decode()
      |> PlaatoData.decode()

    case Keyword.get(decoded, :id) do
      nil -> nil
      id -> id
    end
  rescue
    _ -> nil
  end
end
