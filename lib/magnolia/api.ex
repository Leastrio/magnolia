defmodule Magnolia.Api do
  @base_url "https://discord.com/api/v10"

  def get_gateway_bot(token) do
    get(token, "/gateway/bot").body
  end

  defp get(token, endpoint) do
    Req.get!(@base_url <> endpoint, headers: [{"Authorization", "Bot #{token}"}])
  end
end
