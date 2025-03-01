WIP lib for making discord bots in elixir

magnolia reaches to be a flexible and scalable library allowing bots of any size and architecture to run

### Features (Planned or already implemented)
- [x] Support to dynamically spawn new bots
- [ ] Adapters to replace the current library behavior of the following:
    - Ratelimiter: Handles how ratelimits are stored
    - Caches: Handles how resources are cached
- [x] REST API only for apps that dont need a full gateway bot


### Installation
Currently, the library is a WIP so the best way to install it is through the repo
```elixir
defp deps do 
  [{:magnolia, github: "Leastrio/magnolia"}]
end
```

### Example

To start the bot you must first start `Magnolia.Bot` under your supervision tree
```elixir
defmodule MyBot.Application do 
  use Application

  def start(_type, _args) do 
    children = [
      {Magnolia.Bot, consumer: MyBot.Consumer, token: System.fetch_env!("BOT_TOKEN"), intents: [:guild_messages]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

To handle events, you must create a module that implements the `Magnolia.Consumer` behavior and then pass that module name to the bot options shown above
```elixir
defmodule MyBot.Consumer do
  @behaviour Magnolia.Consumer

  def handle_event({:READY, _payload}, bot_ctx) do
    Magnolia.Api.update_presence(bot_ctx.shard_pid, :online, {:custom, "Hi!"})
  end

  def handle_event(_, _), do: :noop # A catch all handler is important!
end
```

Using magnolia only for the rest api starts off with starting the ratelimiter under your supervision tree
```elixir
defmodule MyBot.Application do 
  use Application

  def start(_type, _args) do 
    children = [
      {Magnolia.Ratelimiter, bot_id}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

And then to call endpoints you do
```elixir
bot_ctx = Magnolia.Struct.BotContext.new(System.fetch_env!("BOT_TOKEN"))
channel_id = 123456789
Magnolia.Api.create_message(bot_ctx, channel_id, content: "Hi!")
```

#### Acknowledgements
- [Nostrum](https://github.com/Kraigie/nostrum) - A lot of inspiration and reference came from this library
- [Coxir](https://github.com/satom99/coxir) - Used as a reference
