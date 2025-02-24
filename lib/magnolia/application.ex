defmodule Magnolia.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Magnolia.Registry}
    ]

    opts = [strategy: :one_for_one, name: Magnolia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
