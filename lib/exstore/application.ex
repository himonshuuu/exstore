defmodule ExStore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ExStore.Supervisor.start_link(name: ExStore.Supervisor)
  end
end
