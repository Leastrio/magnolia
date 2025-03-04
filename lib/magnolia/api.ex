defmodule Magnolia.Api do
  import Magnolia.Ratelimiter, only: [request: 2]

  def get_gateway_bot(ctx) do
    {:ok, req} = request(ctx, [method: :get, url: "/gateway/bot"])
    req
  end
  
  def create_message(ctx, channel_id, content) do
    {:ok, req} = request(ctx, [
      method: :post,
      url: "/channels/{channel_id}/messages",
      path_params: [channel_id: channel_id],
      json: %{content: content}
    ])
    req
  end

  def update_presence(pid, status, activity) do
    {idle_since, afk} =
      case status do
        "idle" -> {System.system_time(:millisecond), true}
        _ -> {0, false}
      end

    activity_payload =
      case activity do
        {:playing, name} -> %{"type" => 0, "name" => name}
        {:streaming, name, url} -> %{"type" => 1, "name" => name, "url" => url}
        {:listening, name} -> %{"type" => 2, "name" => name}
        {:watching, name} -> %{"type" => 3, "name" => name}
        {:custom, state} -> %{"type" => 4, "name" => "Custom Status", "state" => state}
        {:competing, name} -> %{"type" => 5, "name" => name}
      end

    payload = Magnolia.Shard.Payload.update_presence_payload(idle_since, activity_payload, status, afk)
    :gen_statem.cast(pid, {:update_presence, payload})
  end
end
