defmodule Magnolia.Bot do
  alias Magnolia.Utils
  alias Magnolia.Api
  alias Magnolia.Struct
  use TypedStruct

  use Supervisor

  @typedoc """
  * `:token` - Bot token
  * `:intents` - Intents of the bot
  * `:shards` - The shards this bot should start with (defaults to `:auto`)
    * `:auto` - Uses the amount of shards given by discord
    * `{[shard_ids], total_shards}` - Starts up all shards listed in `shard_ids`. `total_shards` should contain the amount of shards your bot has total
  * `:consumer` - The consumer module which will have the event handlers
  """
  typedstruct enforce: true do
    field :token, String.t()
    field :intents, non_neg_integer()
    field :shards, :auto | {[non_neg_integer()], pos_integer()}, default: :auto
    field :consumer, module()
  end

  def start_link(opts) do
    opts = struct(__MODULE__, opts)
    bot_ctx = %Struct.BotContext{
      token: opts.token,
      bot_id: Utils.get_bot_id(opts.token)
    }

    Supervisor.start_link(__MODULE__, {bot_ctx, opts}, name: Utils.to_via({__MODULE__, bot_ctx.bot_id}))
  end

  @doc false
  def init({bot_ctx, opts}) do
    #gateway_bot = Api.get_gateway_bot(bot_ctx)
    gateway_bot = %{"url" => "wss://gateway.discord.gg"}

    shard_config = %Magnolia.Shard{
      bot_ctx: %Struct.BotContext{ 
        bot_ctx |
        shard_id: 0,
        total_shards: 1
      },
      gateway_url: gateway_bot["url"],
      consumer_module: opts.consumer
    }
    
    children = [
      {
        PartitionSupervisor,
        child_spec: Task.Supervisor,
        name: {:via, Registry, {Magnolia.Registry, {Magnolia.TaskSupervisors, bot_ctx.bot_id}}}
      },
      {Magnolia.Ratelimiter, bot_ctx.bot_id},
      {Magnolia.Shard, shard_config}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
