defmodule Magnolia.Struct.BotState do
  use TypedStruct

  @derive {Inspect, except: [:token]}
  typedstruct enforce: true do
    field :token, String.t()
    field :bot_id, non_neg_integer()
    field :shard_id, non_neg_integer()
    field :total_shards, non_neg_integer()
  end
end
