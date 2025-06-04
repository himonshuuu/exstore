defmodule ExStore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    {:ok, sup} = ExStore.Supervisor.start_link(name: ExStore.Supervisor)
    # Load persisted data and restore cache
    data = ExStore.Persistence.load()
    ExStore.Cache.Cache.restore(data)
    {:ok, sup}
  end
end