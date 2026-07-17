defmodule Journeys.KegSetupTest do
  use ExUnit.Case
  import AssertValue

  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  test "tare" do
    cmd = {:hardware, 19392, 7, <<118, 119, 0, 54, 48, 0, 49>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [plaato_decoded: {:hardware, "vw", "60", "1"}, plaato_data_decoded: {:tare, "1"}]
    )

    cmd = {:hardware, 9043, 7, <<118, 119, 0, 54, 48, 0, 48>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [plaato_decoded: {:hardware, "vw", "60", "0"}, plaato_data_decoded: {:tare, "0"}]
    )
  end

  test "empty keg" do
    cmd = {:hardware, 13671, 7, <<118, 119, 0, 54, 50, 0, 49>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "62", "1"},
        plaato_data_decoded: {:empty_keg_weight, "1"}
      ]
    )

    cmd = {:hardware, 13671, 7, <<118, 119, 0, 54, 50, 0, 48>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "62", "0"},
        plaato_data_decoded: {:empty_keg_weight, "0"}
      ]
    )
  end

  test "max keg volume to 19.66" do
    cmd = {:hardware, 31460, 11, <<118, 119, 0, 55, 54, 0, 49, 57, 46, 54, 54>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "76", "19.66"},
        plaato_data_decoded: {:max_keg_volume, "19.66"}
      ]
    )
  end

  test "og to 1055" do
    cmd = {:hardware, 9289, 10, <<118, 119, 0, 54, 53, 0, 49, 48, 53, 53>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "65", "1055"},
        plaato_data_decoded: {:og, "1055"}
      ]
    )
  end

  test "fg to 1015" do
    cmd = {:hardware, 19303, 10, <<118, 119, 0, 54, 54, 0, 49, 48, 49, 53>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "66", "1015"},
        plaato_data_decoded: {:fg, "1015"}
      ]
    )
  end

  test "calculate" do
    cmd = {:hardware, 22383, 7, <<118, 119, 0, 55, 50, 0, 49>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "72", "1"},
        plaato_data_decoded: {:calculate, "1"}
      ]
    )

    cmd = {:hardware, 32027, 7, <<118, 119, 0, 55, 50, 0, 48>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "72", "0"},
        plaato_data_decoded: {:calculate, "0"}
      ]
    )

    ## keg responds
    cmd = {:hardware, 22383, 11, <<118, 119, 0, 54, 56, 0, 53, 46, 52, 48, 51>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "68", "5.403"},
        plaato_data_decoded: {:calculated_abv, "5.403"}
      ]
    )

    cmd = {:hardware, 22383, 11, <<118, 119, 0, 55, 48, 0, 53, 46, 52, 48, 37>>}
    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "70", "5.40%"},
        plaato_data_decoded: {:calculated_alcohol_string, "5.40%"}
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
