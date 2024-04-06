defmodule Magnolia.Cluster do
  alias Magnolia.Api
  alias Magnolia.Bot

  use Supervisor

  def start_link(opts) do
    shards = Map.get(opts, :shards)
    total_shards = Map.get(opts, :total_shards)

    shards = cond do
      is_nil(shards) and is_nil(total_shards) -> :auto
      is_nil(shards) and not is_nil(total_shards) -> {:total, total_shards}
      not is_nil(shards) and is_nil(total_shards) -> raise "Total shards not specified in bot options!"
      is_list(shards) -> {shards, total_shards}
      true -> raise "Invalid shard list!"
    end

    gateway = Api.get_gateway_bot(opts.token)

    Supervisor.start_link(__MODULE__, %Bot{opts | shards: shards, gateway: gateway}, name: :"Magnolia.#{opts.id}.Cluster")
  end

  def init(opts) do
    {shards, total} = case opts.shards do
      :auto -> {Enum.to_list(0..(opts.gateway["shards"] - 1)), opts.gateway["shards"]}
      {:total, total} -> {Enum.to_list(0..(total - 1)), total}
      {shards, total} -> {shards, total}
    end
    children = Enum.map(shards, fn s -> create_worker(opts, s, total) end)

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 3, max_seconds: 30)
  end

  defp create_worker(opts, shard_num, total_shards) do
    Supervisor.child_spec({Magnolia.Shard, [opts, shard_num, total_shards]}, id: shard_num)
  end
end
