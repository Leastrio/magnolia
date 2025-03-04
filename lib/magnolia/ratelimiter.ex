defmodule Magnolia.Ratelimiter do
  @moduledoc """
  Ratelimiter uses 2 ets tables

  Mappings table maps {method, path} -> bucket hash returned from discord
  Limits table maps {hash, top level resources} -> remaining reqs, rl reset

  """

  # TODO emojis have different ratelimits? need to implement that
  # seems like theres a race condition possibly, managing to hit 429's after a bit

  use GenServer
  require Logger

  @ets_opts [
    :named_table,
    :set,
    :public,
    {:write_concurrency, :auto},
    {:decentralized_counters, true}
  ]

  @cleanup_interval 60_000
  @base_url "https://discord.com/api/v10"

  def start_link(bot_id) do
    GenServer.start_link(__MODULE__, bot_id)
  end

  def init(bot_id) do
    :ets.new(table_name(bot_id, :limits), @ets_opts)
    :ets.new(table_name(bot_id, :mappings), @ets_opts)
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:ok, bot_id}
  end

  # TODO I dont like this, I want a better way to cleanup. 
  # also fix timer if someone decides they wanna cleanup themselves
  # AND currently only the ratelimits are cleaned, however I think I need to clean the mappings too
  def handle_info(:cleanup, bot_id) do
    curr_time = System.system_time(:second)
    match_spec = [
      {
        {{:_, :_}, :_, :"$1"},
        [{:<, :"$1", curr_time}],
        [true]
      },
      {
        {:global, :"$1"},
        [{:<, :"1", curr_time}],
        [true]
      }
    ]
    :ets.select_delete(table_name(bot_id, :limits), match_spec)
    Process.send_after(self(), :cleanup, @cleanup_interval)
    {:noreply, bot_id}
  end

  def put_mapping(bot_id, method, path, bucket) do
    :ets.insert(table_name(bot_id, :mappings), {{method, path}, bucket})
  end

  defp get_mapping(bot_id, method, path) do
    case :ets.lookup(table_name(bot_id, :mappings), {method, path}) do
      [{_route, bucket}] -> bucket
      [] -> nil
    end
  end

  def hit(bot_id, bucket) do
    curr_time = System.system_time(:second)
    case :ets.lookup(table_name(bot_id, :limits), bucket) do
      [{:global, reset}] when curr_time < reset -> 
        Logger.warning("Hit a global ratelimit, waiting...")
        {:deny, reset}
      [{_k, _r, reset}] -> check_reset(bot_id, curr_time, bucket, reset)
      [] -> :allow
    end
  end

  defp check_reset(bot_id, curr_time, bucket, reset) do
    remaining = :ets.update_counter(table_name(bot_id, :limits), bucket, -1)
    if remaining < 0 and curr_time < reset do
      {:deny, reset}
    else
      :allow
    end
  end

  defp table_name(bot_id, :limits), do: :"Magnolia.Ratelimiter.#{bot_id}.Limits"
  defp table_name(bot_id, :mappings), do: :"Magnolia.Ratelimiter.#{bot_id}.Mappings"

  defp wait_hit(bot_id, bucket) do
    case hit(bot_id, bucket) do
      :allow -> :ok
      {:deny, reset} -> 
        wait = (reset - System.system_time(:second)) |> :timer.seconds() |> trunc()
        Process.sleep(wait)
        :ok
    end 
  end

  def request(ctx, opts) when is_list(opts) do
    req = 
      Req.new(
        base_url: @base_url,
        headers: [{"Authorization", "Bot #{ctx.token}"}],
        retry: :false,
        path_params_style: :curly
      )
      |> Req.merge(opts)
    tlr = Keyword.get(opts, :path_params) |> get_tlr()

    request(ctx, req, tlr)
  end

  def request(ctx, req, tlr) do
    bucket = get_mapping(ctx.bot_id, req.method, req.url.path)

    :ok = wait_hit(ctx.bot_id, :global)
    if bucket do
      :ok = wait_hit(ctx.bot_id, {bucket, tlr})
    end

    case Req.request(req) do
      {:ok, %{status: 429} = resp} -> 
        Logger.error("Hit 429")
        handle_limits(ctx.bot_id, bucket, tlr, req, resp)
        request(ctx, req, tlr)
      {:ok, %{status: status} = resp} when status >= 200 and status < 300 -> 
        handle_limits(ctx.bot_id, bucket, tlr, req, resp)
        {:ok, resp.body}
      {:ok, resp} -> 
        {:error, resp}
      {:error, err} -> 
        Logger.error("Error occurred while making request: #{Exception.format(:error, err, [])}")
        {:error, err}
    end
  end

  defp handle_limits(bot_id, curr_bucket, tlr, req, resp) do
    with [remaining] <- Req.Response.get_header(resp, "x-ratelimit-remaining"),
         [reset] <- Req.Response.get_header(resp, "x-ratelimit-reset"),
         [new_bucket] <- Req.Response.get_header(resp, "x-ratelimit-bucket") do
      remaining = String.to_integer(remaining)
      reset = String.to_float(reset)

      cond do 
        is_nil(curr_bucket) -> 
          :ets.insert(table_name(bot_id, :mappings), {{req.method, req.url.path}, new_bucket})
        curr_bucket != new_bucket -> 
          Logger.debug("Bucket for #{req.method} #{req.url.path} updated")
          :ets.insert(table_name(bot_id, :mappings), {{req.method, req.url.path}, new_bucket})
        true -> :noop
      end
      
      if resp.status == 429 do
        [scope] = Req.Response.get_header(resp, "x-ratelimit-scope")
        handle_ratelimited(scope, bot_id, resp, {new_bucket, tlr}, reset)
      else
        :ets.insert(table_name(bot_id, :limits), {{new_bucket, tlr}, remaining, reset})
      end
    end
  end

  defp handle_ratelimited("global", bot_id, resp, _key, _reset) do
    [retry_after] = Req.Response.get_header(resp, "retry-after")
    reset = System.system_time(:second) + retry_after
    :ets.insert(table_name(bot_id, :limits), {:global, reset})
  end

  defp handle_ratelimited(_scope, bot_id, _resp, key, reset) do
    :ets.insert(table_name(bot_id, :limits), {key, 0, reset})
  end
 
  defp get_tlr(nil), do: nil
  defp get_tlr(params) do
    params
    |> Keyword.reject(fn {key, _val} -> 
      key in [:channel_id, :guild_id, :webhook_id, :webhook_token] 
    end)
    |> Enum.sort()
  end
end
