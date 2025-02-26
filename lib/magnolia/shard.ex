defmodule Magnolia.Shard do
  require Logger
  alias Magnolia.Event
  alias Magnolia.Struct.BotState
  use TypedStruct

  @behaviour :gen_statem

  typedstruct do
    field :bot_state, BotState
    field :gateway_url, String.t()
    field :conn, Mint.HTTP1.t()
    field :websocket, Mint.WebSocket.t()
    field :request_ref, Mint.Types.request_ref()
    field :zlib, :zlib.zstream()
    field :seq, non_neg_integer()
    field :heartbeat_interval, non_neg_integer()
    field :heartbeat_ack, boolean(), default: true
    field :resume_gateway_url, String.t()
    field :session_id, String.t()
    field :consumer_module, module()
    field :timer_ref, reference()
  end

  def start_link(config) do
    :gen_statem.start_link(__MODULE__, config, [])
  end

  def callback_mode(), do: :state_functions

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 500
    }
  end

  def init(data) do
    {:ok, :disconnected, data, {:next_event, :internal, :connect}}
  end

  def disconnected(:internal, :connect, data) do
    uri = URI.parse(data.gateway_url)

    path = "/?v=10&encoding=etf&compress=zlib-stream" 

    mint_opts = [
      protocols: [:http1]
    ]

    with {:ok, conn} <- Mint.HTTP.connect(:https, uri.host, uri.port, mint_opts),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(:wss, conn, path, []) do
      Logger.debug("WS successfully connected")
      zlib = :zlib.open()
      :zlib.inflateInit(zlib)

      data = %{data | zlib: zlib, conn: conn, request_ref: ref}
      {:next_state, :connected, data}
    else
      {:error, reason} -> 
        Logger.error("Connecting to gateway HTTP failed: #{inspect(reason)}")
        {:stop, :http_connect_error}
      {:error, _conn, reason} -> 
        Logger.error("Upgrading to WS failed: #{inspect(reason)}")
        {:stop, :ws_upgrade_error}
    end
  end

  def disconnected(:internal, :reconnect, data) do
    disconnected(:internal, :connect, %{data | gateway_url: data.resume_gateway_url})
  end

  def connected(:info, :heartbeat, data) do
    if data.heartbeat_ack do
      Logger.debug("Heartbeat Send")
      resp = :erlang.term_to_binary(%{"op" => 1, "d" => data.seq})
      data = send_frame(data, {:binary, resp})
      timer_ref = Process.send_after(self(), :heartbeat, data.heartbeat_interval)
      {:keep_state, %{data | heartbeat_ack: false, timer_ref: timer_ref}}
    else
      Logger.debug("No ACK returned, disconnecting.")
      close(data, :heartbeat_ack_false)
    end
  end

  def connected(:info, msg, data) do
    case Mint.WebSocket.stream(data.conn, msg) do
      {:ok, conn, tcp_msg} -> 
        handle_tcp_message(tcp_msg, %{data | conn: conn})

      {:error, conn, reason, _responses} -> 
        Logger.error("WS streaming failed: #{inspect(reason)}")
        {:keep_state, %{data | conn: conn}}

      :unknown -> 
        :keep_state_and_data
    end
  end

  def connected(:cast, :close, data) do
    send_frame(data, {:close, 1002, ""})
    Mint.HTTP.close(data.conn)

    data = %__MODULE__{
      bot_state: data.bot_state,
      gateway_url: data.gateway_url,
      seq: data.seq,
      resume_gateway_url: data.resume_gateway_url,
      session_id: data.session_id,
      consumer_module: data.consumer_module,
      timer_ref: data.timer_ref
    }

    {:next_state, :disconnected, data, {:next_event, :internal, :reconnect}}
  end

  defp handle_tcp_message([{:status, ref, status}, {:headers, ref, headers} | frames], %{request_ref: ref} = data) do
    case Mint.WebSocket.new(data.conn, ref, status, headers) do
      {:ok, conn, websocket} ->
        data = %{data | conn: conn, websocket: websocket}
        data_frame = Enum.find(frames, fn 
          {:data, ^ref, _data} = frame -> frame
          _ -> nil
        end)

        if data_frame do
          handle_tcp_message([data_frame], data)
        else
          {:keep_state, data}
        end
      {:error, _conn, reason} -> 
        Logger.error("Error finalizing WS connection: #{inspect(reason)}")
        {:stop, :ws_upgrade_error}
    end
  end

  defp handle_tcp_message([{:data, ref, frame_data}], %{request_ref: ref} = data) do
    with {:ok, websocket, [frame]} <- Mint.WebSocket.decode(data.websocket, frame_data) do
      handle_frame(frame, %{data | websocket: websocket})
    end
  end

  defp handle_frame({:binary, frame}, data) do
    payload = :zlib.inflate(data.zlib, frame)
    |> :erlang.iolist_to_binary()
    |> :erlang.binary_to_term()

    data = %{data | seq: payload.s || data.seq}

    case Event.handle(payload, data) do
      {new_data, :reconnect} -> 
        reconnect(new_data)
      {new_data, {:close, reason}} -> 
        close(new_data, reason)
      {new_data, reply} ->
        new_data = send_frame(new_data, {:binary, :erlang.term_to_binary(reply)})
        {:keep_state, new_data}
      new_data -> 
        {:keep_state, new_data}
    end
  end

  defp handle_frame({:close, code, reason}, data) do
    Logger.error("WS connection closed Code: #{code} Reason: #{inspect(reason)}")
    if code in [4000, 4001, 4002, 4003, 4005, 4007, 4008, 4009] do
      reconnect(data)
    else
      close(data, :connection_closed)
    end
  end

  defp handle_frame(_frame, data), do: {:keep_state, data}

  defp send_frame(data, frame) do
    with {:ok, websocket, frame_data} <- Mint.WebSocket.encode(data.websocket, frame),
         data = %{data | websocket: websocket},
         {:ok, conn} <- Mint.WebSocket.stream_request_body(data.conn, data.request_ref, frame_data) do
      %{data | conn: conn}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        Logger.error("Encoding WS frame failed: #{inspect(reason)}")
        %{data | websocket: websocket}
      {:error, conn, reason} -> 
        Logger.error("Casting WS frame failed: #{inspect(reason)}")
        %{data | conn: conn}
    end
  end

  defp reconnect(data) do
    close(data)

    data = %__MODULE__{
      bot_state: data.bot_state,
      gateway_url: data.gateway_url,
      seq: data.seq,
      resume_gateway_url: data.resume_gateway_url,
      session_id: data.session_id,
      consumer_module: data.consumer_module,
      timer_ref: data.timer_ref
    }

    {:next_state, :disconnected, data, {:next_event, :internal, :reconnect}}
  end

  defp close(data, reason \\ :normal) do
    send_frame(data, {:close, 1000, ""})
    Mint.HTTP.close(data.conn)
    {:stop, reason}
  end

end
