defmodule Magnolia.Cluster.Sharder do
  use GenServer
  require Logger

  def start_link(bot_id) do
    GenServer.start_link(__MODULE__, 0, name: :"Magnolia.#{bot_id}.Cluster.Sharder")
  end

  def init(args), do: {:ok, args}

  def block_connect(bot_id) do
    GenServer.call(:"Magnolia.#{bot_id}.Cluster.Sharder", :block_connect, :infinity)
  end

  def handle_call(:block_connect, _from, 0), do: {:reply, :ok, now()}
  def handle_call(:block_connect, _from, last_connect) do
    time = now() - last_connect
    if time >= 5500 do
      {:reply, :ok, now()}
    else
      Logger.info("Waiting #{5500 - time} before next shard connect!")
      Process.sleep(5500 - time)
      {:reply, :ok, now()}
    end
  end

  defp now(), do: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
end
