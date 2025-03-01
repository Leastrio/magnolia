defmodule Magnolia.Ratelimiter do
  use GenServer
  require Logger

  @ets_opts [
    :named_table,
    :set,
    :public,
    {:write_concurrency, :auto},
    {:decentralized_counters, true}
  ]

  def start_link(bot_id) do
    GenServer.start_link(__MODULE__, :"Magnolia.Ratelimiter.#{bot_id}")
  end

  def init(table_name) do
    :ets.new(table_name, @ets_opts)
    {:ok, table_name}
  end

  def get_bucket(path) do
    case Regex.run(~r/\/?(?:channels|guilds|webhooks)\/(?:\d+)/i, path) do
      [bucket] -> bucket
      _ -> path
    end
  end

  def put(bot_id, {bucket, remaining, reset}) do
    :ets.insert(:"Magnolia.Ratelimiter.#{bot_id}", {bucket, remaining, reset})
  end

  def hit(bot_id, bucket) do
    case :ets.lookup(table_name(bot_id), bucket) do
      [{:global, reset}] -> 
        Logger.warning("Hit a global ratelimit, waiting...")
        {:deny, reset}
      [{_k, _r, reset}] -> check_reset(bot_id, bucket, reset)
      [] -> :allow
    end
  end

  defp check_reset(bot_id, bucket, reset) do
    remaining = :ets.update_counter(table_name(bot_id), bucket, -1)
    if remaining < 0 and System.system_time(:second) < reset do
      {:deny, reset}
    else
      :allow
    end
  end

  defp table_name(bot_id), do: :"Magnolia.Ratelimiter.#{bot_id}"

  defp wait_hit(bot_id, bucket) do
    case hit(bot_id, bucket) do
      :allow -> :ok
      {:deny, reset} -> 
        wait = (reset - System.system_time(:second)) |> :timer.seconds() |> trunc()
        Process.sleep(wait)
        :ok
    end 
  end

  def request(bot_id, request) do
    bucket = get_bucket(request.url.path)
    :ok = wait_hit(bot_id, :global)
    :ok = wait_hit(bot_id, bucket)

    case Req.request(request) do
      {:ok, %{status: 429} = resp} -> 
        limits = parse_limits(bucket, resp)
        put(bot_id, limits)
        request(bot_id, request)
      {:ok, %{status: status} = resp} when status >= 200 and status < 300 -> 
        limits = parse_limits(bucket, resp)
        put(bot_id, limits)
        {:ok, resp.body}
      {:ok, resp} -> 
        {:error, resp}
      {:error, err} -> 
        Logger.error("Error occurred while making request: #{Exception.format(:error, err, [])}")
        {:error, err}
    end
  end

  defp parse_limits(bucket, resp) do
    [remaining] = Req.Response.get_header(resp, "x-ratelimit-remaining")
    [reset] = Req.Response.get_header(resp, "x-ratelimit-reset")

    remaining = String.to_integer(remaining)
    reset = String.to_float(reset)

    if resp.status == 429 do
      [scope] = Req.Response.get_header(resp, "x-ratelimit-scope")
      bucket = if scope == "global", do: :global, else: bucket

      {bucket, remaining, reset}
    else
      {bucket, remaining, reset}
    end
  end
end
