defmodule Journeys.MonitorTest do
  use ExUnit.Case
  import AssertValue

  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  test "set style to 'my style'" do
    cmd =
      {:hardware, 3800, 15, <<118, 119, 0, 54, 52, 0, 32, 109, 121, 32, 115, 116, 121, 108, 101>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "64", " my style"},
        plaato_data_decoded: {:beer_style, " my style"}
      ]
    )
  end

  test "set keg date to '12.01.2025'" do
    cmd =
      {:hardware, 17522, 17,
       <<118, 119, 0, 54, 55, 0, 32, 49, 50, 46, 48, 49, 46, 50, 48, 50, 53>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "67", " 12.01.2025"},
        plaato_data_decoded: {:date, " 12.01.2025"}
      ]
    )
  end

  defp decode(blynk_cmd) do
    plaato_decoded = PlaatoProtocol.decode(blynk_cmd)
    plaato_data_decoded = PlaatoData.decode(plaato_decoded)

    [
      plaato_decoded: plaato_decoded,
      plaato_data_decoded: plaato_data_decoded
    ]
  end
end
