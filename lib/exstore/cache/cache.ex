defmodule ExStore.Cache.Cache do
  @moduledoc """
  An enhanced GenServer that holds a key-value store in memory with advanced operations.
  """

  use GenServer
  require Logger

  @typedoc "The result of a cache operation"
  @type result ::
          :ok
          | {:ok, any()}
          | :not_found
          | {:error, term()}

  @typedoc "Array operation result"
  @type array_result :: %{
    length: non_neg_integer(),
    element: any()
  }

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
  Sets multiple key-value pairs in a single operation.
  """
  @spec set_many(pid(), data :: [{term(), term()}]) :: :ok
  def set_many(pid, data) do
    GenServer.call(pid, {:set_many, data})
  end

  @doc """
  Retrieves the value associated with `key`.
  """
  @spec get(pid(), key :: term()) :: result()
  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  @doc """
  Retrieves multiple values by their keys.
  """
  @spec get_many(pid(), keys :: [term()]) :: [result()]
  def get_many(pid, keys) do
    GenServer.call(pid, {:get_many, keys})
  end

  @doc """
  Checks if a key exists in the cache.
  """
  @spec has(pid(), key :: term()) :: boolean()
  def has(pid, key) do
    GenServer.call(pid, {:has, key})
  end

  @doc """
  Deletes the key-value pair associated with `key`.
  """
  @spec delete(pid(), key :: term()) :: :ok
  def delete(pid, key) do
    GenServer.call(pid, {:delete, key})
  end

  @doc """
  Deletes multiple keys in a single operation.
  """
  @spec delete_many(pid(), keys :: [term()]) :: :ok
  def delete_many(pid, keys) do
    GenServer.call(pid, {:delete_many, keys})
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

  # Array operations
  @doc """
  Pushes a value to the end of an array stored at the given key.
  """
  @spec push(pid(), key :: term(), value :: any()) :: array_result()
  def push(pid, key, value) do
    GenServer.call(pid, {:push, key, value})
  end

  @doc """
  Pops a value from the end of an array stored at the given key.
  """
  @spec pop(pid(), key :: term()) :: array_result()
  def pop(pid, key) do
    GenServer.call(pid, {:pop, key})
  end

  @doc """
  Shifts a value from the beginning of an array stored at the given key.
  """
  @spec shift(pid(), key :: term()) :: array_result()
  def shift(pid, key) do
    GenServer.call(pid, {:shift, key})
  end

  @doc """
  Unshifts a value to the beginning of an array stored at the given key.
  """
  @spec unshift(pid(), key :: term(), value :: any()) :: array_result()
  def unshift(pid, key, value) do
    GenServer.call(pid, {:unshift, key, value})
  end

  @doc """
  Slices an array stored at the given key.
  """
  @spec slice(pid(), key :: term(), start :: integer(), stop :: integer() | nil) :: [any()] | nil
  def slice(pid, key, start, stop \\ nil) do
    GenServer.call(pid, {:slice, key, start, stop})
  end

  # Server Callbacks
  @impl true
  def init(:ok) do
    table = :ets.new(:cache_table, [:private])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:set, key, value, ttl}, _from, state) do
    :ets.insert(state.table, {key, value})

    if ttl do
      Process.send_after(self(), {:expire, key}, ttl * 1000)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:set_many, data}, _from, state) do
    Enum.each(data, fn {key, value} ->
      :ets.insert(state.table, {key, value})
    end)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    reply =
      case :ets.lookup(state.table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :not_found
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:get_many, keys}, _from, state) do
    replies = Enum.map(keys, fn key ->
      case :ets.lookup(state.table, key) do
        [{^key, value}] -> {:ok, value}
        [] -> :not_found
      end
    end)
    {:reply, replies, state}
  end

  @impl true
  def handle_call({:has, key}, _from, state) do
    reply = case :ets.lookup(state.table, key) do
      [{^key, _value}] -> true
      [] -> false
    end
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :ets.delete(state.table, key)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete_many, keys}, _from, state) do
    Enum.each(keys, fn key ->
      :ets.delete(state.table, key)
    end)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:ttl, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, _value}] ->
        # For simplicity, we don't track TTLs here in this version
        {:reply, :no_ttl, state}

      [] ->
        {:reply, :not_found, state}
    end
  end

  @impl true
  def handle_call(:dump_all, _from, state) do
    all = :ets.tab2list(state.table) |> Enum.into(%{})
    {:reply, all, state}
  end

  # Array operations
  @impl true
  def handle_call({:push, key, value}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, array}] when is_list(array) ->
        new_array = array ++ [value]
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: length(new_array), element: value}, state}

      [] ->
        new_array = [value]
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: 1, element: value}, state}

      _ ->
        # If key exists but value is not a list, treat as new array
        new_array = [value]
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: 1, element: value}, state}
    end
  end

  @impl true
  def handle_call({:pop, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, array}] when is_list(array) and length(array) > 0 ->
        [popped | rest] = Enum.reverse(array)
        new_array = Enum.reverse(rest)
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: length(new_array), element: popped}, state}

      _ ->
        {:reply, %{length: 0, element: nil}, state}
    end
  end

  @impl true
  def handle_call({:shift, key}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, array}] when is_list(array) and length(array) > 0 ->
        [shifted | rest] = array
        :ets.insert(state.table, {key, rest})
        {:reply, %{length: length(rest), element: shifted}, state}

      _ ->
        {:reply, %{length: 0, element: nil}, state}
    end
  end

  @impl true
  def handle_call({:unshift, key, value}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, array}] when is_list(array) ->
        new_array = [value | array]
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: length(new_array), element: value}, state}

      _ ->
        new_array = [value]
        :ets.insert(state.table, {key, new_array})
        {:reply, %{length: 1, element: value}, state}
    end
  end

  @impl true
  def handle_call({:slice, key, start, stop}, _from, state) do
    case :ets.lookup(state.table, key) do
      [{^key, array}] when is_list(array) ->
        result = case stop do
          nil ->
            if start < 0 do
              Enum.slice(array, start..-1//1)
            else
              Enum.slice(array, start..-1//1)
            end
          stop ->
            if start < 0 or stop < 0 do
              Enum.slice(array, start..(stop - 1)//1)
            else
              Enum.slice(array, start..(stop - 1)//1)
            end
        end
        {:reply, result, state}

      _ ->
        {:reply, nil, state}
    end
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
