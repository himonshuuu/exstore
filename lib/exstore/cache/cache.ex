defmodule ExStore.Cache.Cache do
  @moduledoc """
  A simple GenServer that holds a key-value store in memory.
  """

  use GenServer

  @typedoc "The result of a cache operation"
  @type result ::
          :ok
          | {:ok, any()}
          | :not_found
          | {:error, term()}

  @doc """
  Starts the cache server.

  Returns `{:ok, pid}` where `pid` is the PID of the cache server.
  """
  @spec start_link(opts :: Keyword.t()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, __MODULE__))
  end

  @doc """
  Sets the value of `key` to `value` with an optional time-to-live (TTL) in seconds.
  """
  @spec set(pid(), key :: term(), value :: term(), ttl :: non_neg_integer() | nil) :: :ok
  def set(pid, key, value, ttl \\ nil) do
    GenServer.call(pid, {:set, key, value, ttl})
  end

  @doc """
  Retrieves the value associated with `key`.
  """
  @spec get(pid(), key :: term()) :: result()
  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  @doc """
  Deletes the key-value pair associated with `key`.
  """
  @spec delete(pid(), key :: term()) :: :ok
  def delete(pid, key) do
    GenServer.call(pid, {:delete, key})
  end

  @doc """
  Retrieves the TTL associated with `key`, or `:no_ttl` if the key does not exist or has no TTL.
  """
  @spec ttl(pid(), key :: term()) :: result()
  def ttl(pid, key) do
    GenServer.call(pid, {:ttl, key})
  end

  @doc """
  Dumps all key-value pairs in the cache as a map.
  """
  def dump_all do
    GenServer.call(__MODULE__, :dump_all)
  end

  @doc """
  Restores the cache from a map of key-value pairs.
  """
  def restore(data) when is_map(data) do
    GenServer.cast(__MODULE__, {:restore, data})
  end

  # Server Callbacks
  @impl true
  def init(:ok) do
    table = :ets.new(:cache_table, [:private])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set, key, value, ttl}, _from, %{table: table} = state) do
    :ets.insert(table, {key, value})

    if ttl do
      Process.send_after(self(), {:expire, key}, ttl * 1000)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, %{table: table} = state) do
    reply =
      case :ets.lookup(table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :not_found
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, %{table: table} = state) do
    :ets.delete(table, key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:ttl, key}, _from, %{table: table} = state) do
    case :ets.lookup(table, key) do
      [{^key, _value}] ->
        # For simplicity, we don't track TTLs here in this version
        {:reply, :no_ttl, state}

      [] ->
        {:reply, :not_found, state}
    end
  end

  @impl true
  def handle_call(:dump_all, _from, %{table: table} = state) do
    all = :ets.tab2list(table) |> Enum.into(%{})
    {:reply, all, state}
  end

  @impl true
  def handle_cast({:restore, data}, %{table: table} = state) do
    :ets.delete_all_objects(table)
    Enum.each(data, fn {k, v} -> :ets.insert(table, {k, v}) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:expire, key}, %{table: table} = state) do
    :ets.delete(table, key)
    {:noreply, state}
  end
end