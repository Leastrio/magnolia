defmodule Magnolia.Api do
  @base_url "https://discord.com/api/v10"


  def get_gateway_bot(token) do
    Req.get!(@base_url <> "/gateway/bot", headers: [{"Authorization", "Bot #{token}"}]).body
  end
end
