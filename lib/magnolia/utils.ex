defmodule Magnolia.Utils do
  def parse_token(token) do
    [id, _, _] = String.split(token, ".")
    Base.decode64!(id, padding: false)
  end

  def module(id, shard), do: :"Magnolia.#{id}.Shard.#{shard}"
end
