defmodule Magnolia.Payload do
  alias Magnolia.Utils
  require Logger

  def cast_payload({name, payload}) do
    Logger.warning("Unhandled gateway dispatch event: #{name}")  
    {name, payload}
  end

  def dispatch_event(event, %{bot_state: bot_state} = state) do
    name = Utils.to_via({Magnolia.TaskSupervisors, bot_state.bot_id})
    {:ok, _pid} = Task.Supervisor.start_child(
      {:via, PartitionSupervisor, {name, state.seq}},
      fn -> 
        try do
          state.consumer_module.handle_event(event, bot_state)
        rescue
          e -> Logger.error("Error in event handler: #{Exception.format(:error, e, __STACKTRACE__)}")
        end
      end
    )
  end
end
