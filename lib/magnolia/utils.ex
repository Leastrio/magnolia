defmodule Magnolia.Utils do
  def parse_token(token) do
    [id, _, _] = String.split(token, ".")

    Base.decode64!(id, padding: false)
    |> String.to_integer()
  end
end
