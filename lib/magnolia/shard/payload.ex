defmodule Magnolia.Shard.Payload do
  require Logger

  def identify_payload(data) do
    {os, name} = :os.type()

    %{
      "op" => 2, 
      "d" => %{
        "token" => data.bot_ctx.token, 
        "properties" => %{
          "os" => "#{os} #{name}",
          "browser" => "DiscordBot",
          "device" => "Magnolia"
        },
        "compress" => true,
        "intents" => 33280,
        "shard" => [data.bot_ctx.shard_id, data.bot_ctx.total_shards]
      }
    }
  end

  def resume_payload(data) do
    %{
      "op" => 6,
      "d" => %{
        "token" => data.bot_ctx.token,
        "session_id" => data.session_id,
        "seq" => data.seq
      }
    }
  end

  def update_presence_payload(idle_since, activity, status, afk) do
    %{
      "op" => 3,
      "d" => %{
        "since" => idle_since,
        "activities" => [activity],
        "status" => status,
        "afk" => afk
      }
    }
  end

  def cast_payload({name, payload}) do
    Logger.warning("Unhandled gateway dispatch event: #{name}")  
    {name, payload}
  end
end
