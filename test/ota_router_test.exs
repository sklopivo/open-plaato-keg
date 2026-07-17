defmodule OpenPlaatoKeg.OtaRouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias OpenPlaatoKeg.OtaRouter

  test "lists firmware files from the application priv ota directory" do
    conn =
      conn(:get, "/api/firmwares")
      |> OtaRouter.call([])

    assert conn.status == 200

    body = Poison.decode!(conn.resp_body)
    firmware_names = Enum.map(body["firmwares"], & &1["name"])

    assert "plaatoV2.11b.bin" in firmware_names
  end
end
