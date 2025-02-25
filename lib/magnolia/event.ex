defmodule Magnolia.Event do
  require Logger

  def handle(%{op: 0, d: payload, t: event_name}, data) do
    payload = Magnolia.Utils.to_atom_keys(payload)
    
    {event_name, payload}
    |> Magnolia.Payload.cast_payload()
    |> Magnolia.Payload.dispatch_event(data)

    if event_name == :READY do
      %{data | resume_gateway_url: payload.resume_gateway_url, session_id: payload.session_id}
    else
      data
    end
  end

  def handle(%{op: 1}, data) do
    Logger.debug("Heartbeat ping")
    resp = %{"op" => 1, "d" => data.seq}
    {data, resp}
  end 

  def handle(%{op: 7}, data) do
    Logger.info("Asked to reconnect session")
    {data, :reconnect}
  end

  def handle(%{op: 9, d: resumable?}, data) do
    if resumable? do
      Logger.info("Invalid Session, resuming")
      {data, :reconnect}
    else
      Logger.info("Invalid Session, disconnecting")
      {data, :close}
    end
  end

  def handle(%{op: 10, d: %{heartbeat_interval: interval}}, data) do
    data = %{data | heartbeat_interval: interval}
    Process.send_after(self(), :heartbeat, trunc(:rand.uniform() * interval))
    if not is_nil(data.session_id) do
      Logger.info("Resuming session #{data.session_id}")
      {data, resume_payload(data)}
    else
      Logger.debug("Identifying session")
      {data, identify_payload(data)}
    end
  end

  def handle(%{op: 11}, data) do
    Logger.debug("Heartbeat ACK")
    %{data | heartbeat_ack: true}
  end

  def handle(payload, data) do
    data
  end


  defp identify_payload(data) do
    %{
      "op" => 2, 
      "d" => %{
        "token" => data.bot_state.token, 
        "properties" => %{
          "os" => "BEAM",
          "browser" => "DiscordBot",
          "device" => "Magnolia"
        },
        "compress" => true,
        "intents" => 33280,
        "shard" => [data.bot_state.shard_id, data.bot_state.total_shards]
      }
    }
  end

  defp resume_payload(data) do
    %{
      "op" => 6,
      "d" => %{
        "token" => data.bot_state.token,
        "session_id" => data.session_id,
        "seq" => data.seq
      }
    }
  end
end
