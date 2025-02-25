defmodule Magnolia.Consumer do
  alias Magnolia.Struct  

  @callback handle_event({atom(), struct()}, Struct.BotState.t()) :: any()
end
