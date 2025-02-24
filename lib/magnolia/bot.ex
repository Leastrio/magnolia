defmodule Magnolia.Bot do
  alias Magnolia.Utils
  alias Magnolia.Api
  alias Magnolia.Struct

  use Supervisor

  defstruct [:token, :intents, :shards, :total_shards, :id, :gateway]

  def start_link(opts) do
    config = struct(__MODULE__, opts)
    bot_id = Utils.parse_token(config.token)
    Supervisor.start_link(__MODULE__, %__MODULE__{config | id: bot_id}, name: {:via, Registry, {Magnolia.Registry, {__MODULE__, bot_id}}})
  end

  def init(opts) do
    gateway_bot = Api.get_gateway_bot(opts.token)

    shard_config = %Magnolia.Shard{
      bot_state: %Struct.BotState{
        token: opts.token,
        shard_id: 0,
        total_shards: 1
      },
      gateway_url: gateway_bot["url"]
    }
    
    children = [
      {Magnolia.Shard, shard_config}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
