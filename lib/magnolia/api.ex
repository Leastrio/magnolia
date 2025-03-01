defmodule Magnolia.Api do
  @base_url "https://discord.com/api/v10"

  def get_gateway_bot(ctx) do
    {:ok, req} = get(ctx, "/gateway/bot")
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

  def get(%Magnolia.Struct.BotContext{bot_id: bot_id, token: token}, endpoint) do
    req = Req.new(base_url: @base_url, url: endpoint, headers: [{"Authorization", "Bot #{token}"}], retry: :false)
    Magnolia.Ratelimiter.request(bot_id, req)
  end
end
