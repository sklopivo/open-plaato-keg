defmodule Journeys.SettingsTest do
  use ExUnit.Case
  import AssertValue

  alias OpenPlaatoKeg.PlaatoData
  alias OpenPlaatoKeg.PlaatoProtocol

  test "set units to metric" do
    cmd = {:hardware, 26206, 7, <<118, 119, 0, 55, 49, 0, 49>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [plaato_decoded: {:hardware, "vw", "71", "1"}, plaato_data_decoded: {:unit, "1"}]
    )
  end

  test "set units to us" do
    cmd = {:hardware, 30662, 7, <<118, 119, 0, 55, 49, 0, 50>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [plaato_decoded: {:hardware, "vw", "71", "2"}, plaato_data_decoded: {:unit, "2"}]
    )
  end

  test "set kegmode to volume" do
    cmd = {:hardware, 26206, 7, <<118, 119, 0, 55, 53, 0, 50>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "75", "2"},
        plaato_data_decoded: {:measure_unit, "2"}
      ]
    )

    # keg responded
    cmd = {:property, 265, 13, <<53, 49, 0, 109, 97, 120, 0, 49, 57, 46, 54, 54, 54>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:property, "51", "max", "19.666"},
        plaato_data_decoded: {:max_keg_volume, "19.666"}
      ]
    )
  end

  test "set kegmode to weight" do
    cmd = {:hardware, 4286, 7, <<118, 119, 0, 55, 53, 0, 49>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "75", "1"},
        plaato_data_decoded: {:measure_unit, "1"}
      ]
    )

    # keg responded
    cmd = {:property, 299, 13, <<53, 49, 0, 109, 97, 120, 0, 49, 57, 46, 54, 54, 54>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:property, "51", "max", "19.666"},
        plaato_data_decoded: {:max_keg_volume, "19.666"}
      ]
    )
  end

  test "set kegmode to beer" do
    cmd = {:hardware, 27706, 7, <<118, 119, 0, 56, 56, 0, 49>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "88", "1"},
        plaato_data_decoded: {:keg_mode_c02_beer, "1"}
      ]
    )

    # keg responded
    cmd =
      {:property, 587, 18,
       <<52, 55, 0, 108, 97, 98, 101, 108, 0, 76, 97, 115, 116, 32, 112, 111, 117, 114>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:property, "47", "label", "Last pour"},
        plaato_data_decoded: nil
      ]
    )
  end

  test "set kegmode to co2" do
    cmd = {:hardware, 20409, 7, <<118, 119, 0, 56, 56, 0, 50>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "88", "2"},
        plaato_data_decoded: {:keg_mode_c02_beer, "2"}
      ]
    )

    # keg responded
    cmd =
      {:hardware, 675, 7, <<118, 119, 0, 52, 55, 0, 32>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "47", " "},
        plaato_data_decoded: {:last_pour_string, " "}
      ]
    )

    # keg responded (2)
    cmd =
      {:property, 676, 10, <<52, 55, 0, 108, 97, 98, 101, 108, 0, 32>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [plaato_decoded: {:property, "47", "label", " "}, plaato_data_decoded: nil]
    )
  end

  test "set scale sensitivity to very low" do
    cmd = {:hardware, 27292, 7, <<118, 119, 0, 56, 57, 0, 49>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "89", "1"},
        plaato_data_decoded: {:sensitivity, "1"}
      ]
    )
  end

  test "set scale sensitivity to low" do
    cmd = {:hardware, 787, 7, <<118, 119, 0, 56, 57, 0, 50>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "89", "2"},
        plaato_data_decoded: {:sensitivity, "2"}
      ]
    )
  end

  test "set scale sensitivity to medium" do
    cmd = {:hardware, 11020, 7, <<118, 119, 0, 56, 57, 0, 51>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "89", "3"},
        plaato_data_decoded: {:sensitivity, "3"}
      ]
    )
  end

  test "set scale sensitivity to high" do
    cmd = {:hardware, 15756, 7, <<118, 119, 0, 56, 57, 0, 52>>}

    decoded = decode(cmd)

    assert_value(
      decoded == [
        plaato_decoded: {:hardware, "vw", "89", "4"},
        plaato_data_decoded: {:sensitivity, "4"}
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
