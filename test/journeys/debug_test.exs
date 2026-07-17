defmodule Journeys.DebugTest do
  use ExUnit.Case
  import AssertValue

  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  test "set temperature offset to -7,5" do
    cmd = {:hardware, 7071, 10, <<118, 119, 0, 53, 50, 0, 45, 55, 46, 53>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "52", "-7.5"},
        plaato_data_decoded: {:temperature_offset, "-7.5"}
      ]
    )
  end

  test "calibrate with known weight" do
    cmd = {:hardware, 23230, 9, <<118, 119, 0, 54, 49, 0, 48, 46, 49>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "61", "0.1"},
        plaato_data_decoded: {:known_weight_calibrate, "0.1"}
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
