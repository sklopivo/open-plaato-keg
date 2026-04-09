defmodule OpenPlaatoKeg.BrewfatherApi do
  @moduledoc """
  Reads batch data from the Brewfather v2 REST API.
  Separate from the Brewfather module which *sends* airlock data to Brewfather.
  """
  require Logger

  @base_url "https://api.brewfather.app/v2"

  def fetch_batches(user_id, api_key) do
    auth = Base.encode64("#{user_id}:#{api_key}")
    url = "#{@base_url}/batches?include=recipe&limit=50"

    case Req.get(url, headers: [{"authorization", "Basic #{auth}"}]) do
      {:ok, %{status: 200, body: batches}} when is_list(batches) ->
        {:ok, batches}

      {:ok, %{status: 401}} ->
        {:error, "invalid_credentials"}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("BrewfatherApi: unexpected response #{status} #{inspect(body)}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("BrewfatherApi: request failed #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  def batch_to_beverage(batch) do
    srm = batch["estimatedColor"] || get_in(batch, ["recipe", "color"])

    %{
      name: batch["name"] || get_in(batch, ["recipe", "name"]) || "",
      brewery: batch["brewer"] || "",
      style: get_in(batch, ["recipe", "style", "name"]) || "",
      abv: to_string(batch["measuredAbv"] || batch["estimatedAbv"] || ""),
      ibu: to_string(get_in(batch, ["recipe", "ibu"]) || batch["estimatedIbu"] || ""),
      color: srm_to_hex(srm),
      srm: if(srm, do: to_string(srm), else: ""),
      description: batch["batchNotes"] || "",
      tasting_notes: batch["tasteNotes"] || "",
      og: to_string(batch["measuredOg"] || batch["estimatedOg"] || ""),
      fg: to_string(batch["measuredFg"] || batch["estimatedFg"] || ""),
      source: "brewfather",
      brewfather_batch_id: batch["_id"] || ""
    }
  end

  # SRM color lookup table (standard 40-entry scale)
  @srm_colors [
    {1,  "#FFE699"}, {2,  "#FFD878"}, {3,  "#FFCA5A"}, {4,  "#FFBF42"},
    {5,  "#FBB123"}, {6,  "#F8A600"}, {7,  "#F39C00"}, {8,  "#EA8F00"},
    {9,  "#E58500"}, {10, "#DE7C00"}, {11, "#D77200"}, {12, "#CF6900"},
    {13, "#CB6200"}, {14, "#C35900"}, {15, "#BB5100"}, {16, "#B54C00"},
    {17, "#B04500"}, {18, "#A63E00"}, {19, "#A13700"}, {20, "#9B3200"},
    {21, "#952D00"}, {22, "#8E2900"}, {23, "#882300"}, {24, "#821E00"},
    {25, "#7B1A00"}, {26, "#771900"}, {27, "#701400"}, {28, "#6A0F00"},
    {29, "#640B00"}, {30, "#5E0800"}, {31, "#590600"}, {32, "#560403"},
    {33, "#530403"}, {34, "#500403"}, {35, "#4D0403"}, {36, "#4A0403"},
    {37, "#470304"}, {38, "#440304"}, {39, "#410304"}, {40, "#3D0304"}
  ]

  defp srm_to_hex(nil), do: "#c9a849"

  defp srm_to_hex(srm) when is_number(srm) do
    srm_int = srm |> round() |> max(1) |> min(40)

    case Enum.find(@srm_colors, fn {s, _} -> s == srm_int end) do
      {_, hex} -> hex
      nil -> "#c9a849"
    end
  end

  defp srm_to_hex(srm) when is_binary(srm) do
    case Float.parse(srm) do
      {f, _} -> srm_to_hex(f)
      :error -> "#c9a849"
    end
  end

  defp srm_to_hex(_), do: "#c9a849"
end
