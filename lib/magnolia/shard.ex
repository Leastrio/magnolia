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
    field :resp_status, Mint.Types.status()
    field :resp_headers, Mint.Types.headers()
    field :queued_resp, Mint.Types.response()
    field :zlib, :zlib.zstream()
    field :seq, non_neg_integer()
    field :heartbeat_interval, non_neg_integer()
    field :heartbeat_ack, boolean(), default: true
    field :resume_gateway_url, String.t()
    field :session_id, String.t()
    field :consumer_module, module()
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

    {http_scheme, ws_scheme} =
      case uri.scheme do
        "ws" -> {:http, :ws}
        "wss" -> {:https, :wss}
      end

    path = "/?v=10&encoding=etf&compress=zlib-stream" 

    mint_opts = [
      protocols: [:http1]
    ]

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, uri.host, uri.port, mint_opts),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      Logger.debug("WS successfully upgraded")
      zlib = :zlib.open()
      :zlib.inflateInit(zlib)

      data = %{data | zlib: zlib, conn: conn, request_ref: ref}
      {:next_state, :connected, data}
    else
      {:error, reason} ->
        Logger.error("Connecting to gateway failed: #{inspect(reason)}")
        {:stop, :http_connect_error}

      {:error, _conn, reason} -> 
        Logger.error("Upgrading to WS failed: #{inspect(reason)}")
        {:stop, :ws_upgrade_error}
    end
  end

  def disconnected(:internal, :reconnect, data) do
    disconnected(:internal, :connect, %{data | gateway_url: data.resume_gateway_url, resume_gateway_url: nil})
  end

  def connected(:info, :heartbeat, data) do
    if data.heartbeat_ack do
      Logger.debug("Heartbeat send")
      resp = :erlang.term_to_binary(%{"op" => 1, "d" => data.seq})
      data = send_frame(data, {:binary, resp})
      Process.send_after(self(), :heartbeat, data.heartbeat_interval)
      {:keep_state, %{data | heartbeat_ack: false}}
    else
      Logger.debug("No ACK returned, disconnecting.")
      close(data, :heartbeat_ack_false)
    end
  end

  def connected(:info, msg, data) do
    case Mint.WebSocket.stream(data.conn, msg) do
      {:ok, conn, responses} -> 
        Enum.reduce(responses, %{data | conn: conn}, &handle_response/2)

      {:error, conn, reason, _responses} -> 
        Logger.error("WS streaming failed: #{inspect(reason)}")
        {:keep_state, %{data | conn: conn}}

      :unknown -> 
        :keep_state_and_data
    end
  end

  defp handle_response({:status, ref, status}, %{request_ref: ref} = data) do
    %{data | resp_status: status}
  end
  
  defp handle_response({:headers, ref, headers}, %{request_ref: ref} = data) do
    %{data | resp_headers: headers}
  end

  defp handle_response({:done, ref}, %{request_ref: ref} = data) do
    case Mint.WebSocket.new(data.conn, ref, data.resp_status, data.resp_headers) do
      {:ok, conn, websocket} -> 
        data = %{data | conn: conn, websocket: websocket, resp_status: nil, resp_headers: nil}
        handle_response(data.queued_resp, data)

      {:error, conn, reason} -> 
        Logger.error("Error finalizing WS connection: #{inspect(reason)}")
        %{data | conn: conn}
    end
  end

  defp handle_response({:data, ref, frame_data} = resp, %{request_ref: ref} = data) do
    if data.websocket != nil do
      case Mint.WebSocket.decode(data.websocket, frame_data) do
        {:ok, websocket, [frame]} -> 
          handle_frame(frame, %{data | websocket: websocket})

        {:error, websocket, reason} -> 
          Logger.error("WS data decode error: #{inspect(reason)}")
          %{data | websocket: websocket}
      end
    else
      %{data | queued_resp: resp}
    end
  end

  defp handle_response(_resp, data), do: data

  defp handle_frame({:binary, frame}, data) do
    payload = :zlib.inflate(data.zlib, frame)
    |> :erlang.iolist_to_binary()
    |> :erlang.binary_to_term()

    data = %{data | seq: payload.s || data.seq}

    case Event.handle(payload, data) do
      {new_data, :reconnect} -> 
        reconnect(data)
      {new_data, :close} -> 
        close(data)
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
      close(data)
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
      session_id: data.session_id
    }

    {:next_state, :disconnected, data, {:next_event, :internal, :reconnect}}
  end

  defp close(data, reason \\ :normal) do
    if reason == :normal do
      send_frame(data, {:close, 1000, ""})
    end
    Mint.HTTP.close(data.conn)
    {:stop, reason}
  end

end
