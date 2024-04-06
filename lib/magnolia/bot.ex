defmodule Magnolia.Bot do
  alias Magnolia.Utils

  use Supervisor

  defstruct [:token, :intents, :shards, :total_shards, :id, :gateway]

  def start_link(opts) do
    config = struct(__MODULE__, opts)
    bot_id = Utils.parse_token(config.token)
    Supervisor.start_link(__MODULE__, %__MODULE__{config | id: bot_id}, name: :"Magnolia.#{bot_id}")
  end

  def init(opts) do
    children = [
      {Magnolia.Cluster.Sharder, opts.id},
      {Magnolia.Cluster, opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
