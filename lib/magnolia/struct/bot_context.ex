defmodule Magnolia.Struct.BotContext do
  use TypedStruct

  @derive {Inspect, except: [:token]}
  typedstruct do
    field :token, String.t()
    field :bot_id, non_neg_integer()
    field :shard_id, non_neg_integer()
    field :total_shards, non_neg_integer()
    field :shard_pid, pid()
  end

  def new(token) do
    bot_id = Magnolia.Utils.get_bot_id(token)
    %__MODULE__{token: token, bot_id: bot_id}
  end
end
