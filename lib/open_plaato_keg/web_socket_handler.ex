defmodule OpenPlaatoKeg.WebSocketHandler do
  alias OpenPlaatoKeg.Models.AirlockData
  alias OpenPlaatoKeg.Models.KegData
  alias OpenPlaatoKeg.Models.TransferScaleData

  def init(state) do
    Registry.register(OpenPlaatoKeg.WebSocketConnectionRegistry, "websocket_clients", self())
    {:ok, state}
  end

  def handle_info({:broadcast, message}, state) do
    {:reply, :ok, {:text, message}, state}
  end

  def terminate(_reason, _state) do
    Registry.unregister(OpenPlaatoKeg.WebSocketConnectionRegistry, "websocket_clients")
    :ok
  end

  def publish(id, _data) do
    keg_all_data = KegData.get(id)

    Registry.dispatch(
      OpenPlaatoKeg.WebSocketConnectionRegistry,
      "websocket_clients",
      fn entries ->
        for {pid, _} <- entries do
          send(pid, {:broadcast, Poison.encode!(keg_all_data)})
        end
      end
    )
  end

  def publish_airlock(id, _data) do
    airlock_data = AirlockData.get(id)
    message = Poison.encode!(%{type: "airlock", data: airlock_data})

    Registry.dispatch(
      OpenPlaatoKeg.WebSocketConnectionRegistry,
      "websocket_clients",
      fn entries ->
        for {pid, _} <- entries do
          send(pid, {:broadcast, message})
        end
      end
    )
  end

  def publish_transfer_scale(id) do
    scale_data = TransferScaleData.get(id)
    message = Poison.encode!(%{type: "transfer_scale", data: scale_data})
    Registry.dispatch(
      OpenPlaatoKeg.WebSocketConnectionRegistry,
      "websocket_clients",
      fn entries ->
        for {pid, _} <- entries do
          send(pid, {:broadcast, message})
        end
      end
    )
  end
end
