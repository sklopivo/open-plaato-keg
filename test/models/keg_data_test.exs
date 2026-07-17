defmodule OpenPlaatoKeg.Models.KegDataTest do
  use ExUnit.Case

  alias OpenPlaatoKeg.Models.AirlockData
  alias OpenPlaatoKeg.Models.KegData

  setup do
    :dets.close(:keg_data)
    :dets.close(:airlock_data)

    unique = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "open_plaato_keg_test_#{unique}")
    File.mkdir_p!(dir)

    {:ok, _} = :dets.open_file(:keg_data, file: String.to_charlist(Path.join(dir, "kegs.dets")))

    {:ok, _} =
      :dets.open_file(:airlock_data, file: String.to_charlist(Path.join(dir, "airlocks.dets")))

    on_exit(fn ->
      :dets.close(:keg_data)
      :dets.close(:airlock_data)
      File.rm_rf(dir)
    end)

    :ok
  end

  test "devices excludes ids that are known airlocks" do
    KegData.publish("real-keg", id: "real-keg", amount_left: "12.3")
    KegData.publish("airlock-token", id: "airlock-token", amount_left: "0.0")
    AirlockData.publish("airlock-token", temperature: "20.5")

    assert KegData.devices() == ["real-keg"]
    assert KegData.all() == [%{id: "real-keg", amount_left: "12.3"}]
    assert KegData.get("airlock-token") == %{}
  end
end
