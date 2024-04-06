defmodule Magnolia.Shard do
  use GenServer
  require Logger
  alias Magnolia.Cluster.Sharder

  @gateway_query "/?v=10&encoding=etf&compress=zlib-stream"
  @properties %{
    "os" => "BEAM",
    "browser" => "DiscordBot",
    "device" => "Magnolia"
  }

  @ws_timeout 10_000

  defstruct [:zlib, :seq, :token, :heartbeat_ack, :heartbeat_ref, :shard, :bot_id, :conn, :stream, :gateway]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init([opts, shard, total_shards]) do
    zlib = :zlib.open()
    :zlib.inflateInit(zlib)
    state = %__MODULE__{zlib: zlib, seq: nil, token: opts.token, heartbeat_ack: true, shard: [shard, total_shards], bot_id: opts.id, gateway: opts.gateway["url"]}
    {:ok, state, {:continue, {:connect, opts.gateway["url"]}}}
  end

  def handle_continue({:connect, "wss://" <> gateway}, %__MODULE__{shard: [shard, _]} = state) do
    Sharder.block_connect(state.bot_id)
    {:ok, worker} = :gun.open(:binary.bin_to_list(gateway), 443, %{protocols: [:http], tls_opts: gun_tls_opts()})
    {:ok, :http} = :gun.await_up(worker, @ws_timeout)
    stream = :gun.ws_upgrade(worker, @gateway_query)
    {:upgrade, ["websocket"], _} = :gun.await(worker, stream, @ws_timeout)

    Logger.debug("Shard #{shard} connected!")
    {:noreply, %__MODULE__{state | conn: worker, stream: stream}}
  end

  def handle_info({:gun_ws, _worker, stream, {:binary, frame}}, state) do
    payload = :zlib.inflate(state.zlib, frame)
      |> :erlang.iolist_to_binary()
      |> :erlang.binary_to_term()

    state = %__MODULE__{state | seq: payload.s || state.seq}

    case handle_payload(payload, state) do
      :ok -> {:noreply, state}
      {:state, new_state} -> {:noreply, new_state}
      {reply, new_state} ->
        :ok = :gun.ws_send(state.conn, stream, {:binary, reply})
        {:noreply, new_state}
    end
  end
 
  def handle_info({:gun_ws, _conn, _stream, :close}, %__MODULE__{shard: [shard, _]} = state) do
    Logger.info("Shard #{shard} closed for unknown reason!")
    {:noreply, state}
  end

  def handle_info({:gun_ws, _conn, _stream, {:close, errno, reason}}, %__MODULE__{shard: [shard, _]} = state) do
    Logger.info("Shard #{shard} closed! errno #{errno} -- reason #{inspect reason}")
    {:noreply, state}
  end

  def handle_info({:gun_down, _conn, _proto, _reason, _streams}, state) do
    :timer.cancel(state.heartbeat_ref)
    {:noreply, state}
  end

  def handle_info({:gun_up, worker, _proto}, %__MODULE__{shard: [shard, _]} = state) do
    :zlib.inflateReset(state.zlib)
    stream = :gun.ws_upgrade(worker, @gateway_query)
    {:upgrade, ["websocket"], _} = :gun.await(worker, stream, @ws_timeout)
    Logger.warning("Reconnected shard #{shard}!")
    {:noreply, %__MODULE__{state | heartbeat_ack: true}}
  end

  def handle_info(:heartbeat, state) do
    if state.heartbeat_ack do
      Logger.debug("HEARTBEAT SEND")
      resp = :erlang.term_to_binary(%{"op" => 1, "d" => state.seq})
      :gun.ws_send(state.conn, state.stream, {:binary, resp})
      {:noreply, %__MODULE__{state | heartbeat_ack: false}}
    else
      Logger.debug("No ACK returned, disconnecting.")
      {:ok, :cancel} = :timer.cancel(state.heartbeat_ref)
      :gun.ws_send(state.conn, state.stream, :close)
      {:stop, :disconnected, state}
    end
  end

  def handle_payload(%{op: 10, d: %{heartbeat_interval: interval}}, state) do
    {:ok, ref} = :timer.apply_interval(interval, Kernel, :send, [self(), :heartbeat])
    resp = :erlang.term_to_binary(%{"op" => 2, "d" => %{"token" => state.token, "properties" => @properties, "compress" => true, "intents" => 33280, "shard" => state.shard}})
    {resp, %__MODULE__{state | heartbeat_ref: ref}}
  end

  def handle_payload(%{op: 11}, state) do
    Logger.debug("HEARTBEAT ACK")
    {:state, %__MODULE__{state | heartbeat_ack: true}}
  end

  def handle_payload(payload, _) do
    Logger.debug(inspect payload)
    :ok
  end

  def gun_tls_opts(), do: [
      verify: :verify_peer,
      cacerts: :certifi.cacerts(),
      depth: 2,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
end
