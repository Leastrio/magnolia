defmodule Magnolia.Struct.BotState do
  use TypedStruct

  @derive {Inspect, except: [:token]}
  typedstruct do
    field :token, String.t()
    field :shard_id, non_neg_integer()
    field :total_shards, non_neg_integer()
  end
end
