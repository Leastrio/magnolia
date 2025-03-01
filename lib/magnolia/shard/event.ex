defmodule Magnolia.Shard.Event do
  require Logger
  alias Magnolia.Shard.Payload
  alias Magnolia.Utils

  def handle(%{op: 0, d: payload, t: event_name}, data) do
    payload = Magnolia.Utils.to_atom_keys(payload)
    
    {event_name, payload}
    |> Payload.cast_payload()
    |> dispatch_event(data)

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
      {data, {:close, :invalid_session}}
    end
  end

  def handle(%{op: 10, d: %{heartbeat_interval: interval}}, data) do
    if data.timer_ref do
      Process.cancel_timer(data.timer_ref)
    end
    timer_ref = Process.send_after(self(), :heartbeat, trunc(:rand.uniform() * interval))
    data = %{data | heartbeat_interval: interval, timer_ref: timer_ref}
    if not is_nil(data.session_id) do
      Logger.debug("Resuming session #{data.session_id}")
      {data, Payload.resume_payload(data)}
    else
      Logger.debug("Identifying session")
      {data, Payload.identify_payload(data)}
    end
  end

  def handle(%{op: 11}, data) do
    Logger.debug("Heartbeat ACK")
    %{data | heartbeat_ack: true}
  end

  def handle(payload, data) do
    Logger.warning("Unhandled event #{inspect(payload)}")
    data
  end

  defp dispatch_event(event, %{bot_ctx: bot_ctx} = state) do
    name = Utils.to_via({Magnolia.TaskSupervisors, bot_ctx.bot_id})
    {:ok, _pid} = Task.Supervisor.start_child(
      {:via, PartitionSupervisor, {name, state.seq}},
      fn -> 
        try do
          state.consumer_module.handle_event(event, bot_ctx)
        rescue
          e -> Logger.error("Error in event handler: #{Exception.format(:error, e, __STACKTRACE__)}")
        end
      end
    )
  end
end
