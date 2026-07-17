defmodule OpenPlaatoKeg.PlaatoProtocol do
  require Logger

  def decode(commands) when is_list(commands) do
    Enum.map(commands, &decode/1)
  end

  def decode({:internal, _, _, message}) do
    internal_props =
      message
      |> String.split("\0", trim: true)
      |> Enum.chunk_every(2)
      |> Enum.map(fn [key, value] -> {key, value} end)
      |> Enum.into(%{})

    {:internal, :not_relevant, :not_relevant, internal_props}
  end

  def decode({:notify, _, _, notify}), do: {:notify, notify}
  def decode({:ping, sequence, _, _}), do: {:ping, sequence}

  def decode({type, _, _, message}) do
    case String.split(message, "\0", trim: true) do
      [data] ->
        {type, :not_relevant, :not_relevant, data}

      [kind, id, data] ->
        {type, kind, id, data}

      data ->
        {type, :not_relevant, :not_relevant, data}
    end
  end
end
