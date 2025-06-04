defmodule ExStore.Persistence do
  @moduledoc """
  Simple module to save/load cache data to disk.
  """

  use GenServer
  @filename "cache.dump"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_save()
    {:ok, %{}}
  end

  def save(data) do
    File.write!(@filename, :erlang.term_to_binary(data))
  end

  def load() do
    if File.exists?(@filename) do
      {:ok, binary} = File.read(@filename)
      :erlang.binary_to_term(binary)
    else
      %{}
    end
  end

  def handle_info(:save, state) do
    data = ExStore.Cache.Cache.dump_all()
    save(data)
    schedule_save()
    {:noreply, state}
  end

  defp schedule_save() do
    Process.send_after(self(), :save, 5_000)  # Every 5 seconds
  end
end