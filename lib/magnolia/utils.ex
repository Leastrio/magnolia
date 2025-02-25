defmodule Magnolia.Utils do
  require Logger

  def parse_token(token) do
    [id, _, _] = String.split(token, ".")

    Base.decode64!(id, padding: false)
    |> String.to_integer()
  end

  def to_atom_keys(term) do
    case term do
      %{} -> 
        for {key, val} <- term, into: %{}, do: {to_atom(key), to_atom_keys(val)}
      term when is_list(term) -> 
        Enum.map(term, fn i -> to_atom_keys(i) end)
      term -> 
        term
    end
  end

  defp to_atom(term) when is_binary(term) do
    try do
      String.to_existing_atom(term)
    rescue
      _ -> 
        Logger.debug("Converting string to atom: #{term}")
        String.to_atom(term)
    end
  end
  defp to_atom(term), do: term

end
