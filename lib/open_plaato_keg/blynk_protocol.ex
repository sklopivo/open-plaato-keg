defmodule OpenPlaatoKeg.BlynkProtocol do
  @moduledoc """
    Blynk Protocol - commands generated from https://github.com/blynkkk/blynk-library/blob/7e942d661bc54ded310bf5d00edee737d0ca44d7/src/Blynk/BlynkProtocolDefs.h
  """

  @blynk_cmds %{
    0 => :response,
    1 => :register,
    2 => :login,
    3 => :save_prof,
    4 => :load_prof,
    5 => :get_token,
    6 => :ping,
    7 => :activate,
    8 => :deactivate,
    9 => :refresh,
    10 => :get_graph_data,
    11 => :get_graph_data_response,
    12 => :tweet,
    13 => :email,
    14 => :notify,
    15 => :bridge,
    16 => :hardware_sync,
    17 => :internal,
    18 => :sms,
    19 => :property,
    20 => :hardware,
    21 => :create_dash,
    22 => :save_dash,
    23 => :delete_dash,
    24 => :load_prof_gz,
    25 => :sync,
    26 => :sharing,
    27 => :add_push_token,
    29 => :get_shared_dash,
    30 => :get_share_token,
    31 => :refresh_share_token,
    32 => :share_login,
    41 => :redirect,
    55 => :debug_print,
    64 => :event_log
  }

  @blynk_statuses %{
    200 => :success,
    1 => :quota_limit_exception,
    2 => :illegal_command,
    3 => :not_registered,
    4 => :already_registered,
    5 => :not_authenticated,
    6 => :not_allowed,
    7 => :device_not_in_network,
    8 => :no_active_dashboard,
    9 => :invalid_token,
    11 => :illegal_command_body,
    12 => :get_graph_data_exception,
    13 => :ntf_invalid_body,
    14 => :ntf_not_authorized,
    15 => :ntf_exception,
    16 => :timeout,
    17 => :no_data_exception,
    18 => :device_went_offline,
    19 => :server_exception,
    20 => :not_supported_version,
    21 => :energy_limit
  }

  @reverse_blynk_cmds Enum.into(@blynk_cmds, %{}, fn {k, v} -> {v, k} end)
  @reverse_blynk_statuses Enum.into(@blynk_statuses, %{}, fn {k, v} -> {v, k} end)

  def decode(<<cmd::8, msg_id::16, length::16, body::binary>>, result \\ []) do
    cmd_atom = Map.get(@blynk_cmds, cmd, :unknown_cmd)

    case cmd_atom do
      :response ->
        status_atom = Map.get(@blynk_statuses, length, :unknown_status)
        [{:response, msg_id, status_atom, body}]

      cmd_atom ->
        <<current_body::binary-size(length), rest::binary>> = body
        new_result = result ++ [{cmd_atom, msg_id, length, current_body}]

        if byte_size(rest) == 0 do
          new_result
        else
          decode(rest, new_result)
        end
    end
  end

  def encode_command(cmd_atom, msg_id, body) when is_atom(cmd_atom) do
    cmd = Map.get(@reverse_blynk_cmds, cmd_atom, 0)
    encode_command(cmd, msg_id, body)
  end

  def encode_command(cmd, msg_id, body) do
    length = byte_size(body)
    <<cmd::8, msg_id::16, length::16, body::binary>>
  end

  def encode_response(msg_id, status_atom, body) do
    status = Map.get(@reverse_blynk_statuses, status_atom, 0)
    length = byte_size(body)
    <<0::8, msg_id::16, status::16, length::16, body::binary>>
  end

  def response_success(num \\ 1) do
    status = @reverse_blynk_statuses[:success]
    body = ""

    <<0::8, num::16, status::16, body::binary>>
  end
end
