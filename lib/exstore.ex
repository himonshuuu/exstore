defmodule ExStore do
  @moduledoc """
  An enhanced in-memory key-value store with file-based persistence, sharding, and advanced operations.
  """

  @server ExStore.Cache.Cache

  @doc """
  Starts the cache server.

  Returns `{:ok, pid}` where `pid` is the PID of the cache server.
  """
  def start do
    {:ok, pid} = ExStore.Cache.Cache.start_link()
    pid
  end

  @doc """
  Sets the value of `key` to `value` with an optional time-to-live (TTL) in seconds.
  """
  def put(key, value, ttl \\ nil) do
    ExStore.RecoveryEngine.record_request(:set, key, value)
    GenServer.call(@server, {:set, key, value, ttl})
  end

  @doc """
  Sets multiple key-value pairs in a single operation.
  """
  def put_many(data) do
    ExStore.RecoveryEngine.record_request(:set_many, nil, data)
    GenServer.call(@server, {:set_many, data})
  end

  @doc """
  Retrieves the value associated with `key`.
  """
  def get(key) do
    ExStore.RecoveryEngine.record_request(:get, key)
    GenServer.call(@server, {:get, key})
  end

  @doc """
  Retrieves multiple values by their keys.
  """
  def get_many(keys) do
    ExStore.RecoveryEngine.record_request(:get_many, keys)
    GenServer.call(@server, {:get_many, keys})
  end

  @doc """
  Checks if a key exists in the cache.
  """
  def has(key) do
    ExStore.RecoveryEngine.record_request(:has, key)
    ExStore.Cache.Cache.has(@server, key)
  end

  @doc """
  Deletes the key-value pair associated with `key`.
  """
  def delete(key) do
    ExStore.RecoveryEngine.record_request(:delete, key)
    GenServer.call(@server, {:delete, key})
  end

  @doc """
  Deletes multiple keys in a single operation.
  """
  def delete_many(keys) do
    ExStore.RecoveryEngine.record_request(:delete_many, keys)
    GenServer.call(@server, {:delete_many, keys})
  end

  @doc """
  Retrieves the TTL associated with `key`, or `-2` if the key does not exist or has no TTL.
  """
  def ttl(key) do
    GenServer.call(@server, {:ttl, key})
  end

  @doc """
  Returns all key-value pairs in the cache.
  """
  def all do
    ExStore.RecoveryEngine.record_request(:all)
    ExStore.Cache.Cache.dump_all()
  end

  # Array operations
  @doc """
  Pushes a value to the end of an array stored at the given key.
  """
  def push(key, value) do
    ExStore.RecoveryEngine.record_request(:set, key, value)
    ExStore.Cache.Cache.push(@server, key, value)
  end

  @doc """
  Pops a value from the end of an array stored at the given key.
  """
  def pop(key) do
    result = ExStore.Cache.Cache.pop(@server, key)
    if result.element != nil do
      ExStore.RecoveryEngine.record_request(:set, key, result)
    end
    result
  end

  @doc """
  Shifts a value from the beginning of an array stored at the given key.
  """
  def shift(key) do
    result = ExStore.Cache.Cache.shift(@server, key)
    if result.element != nil do
      ExStore.RecoveryEngine.record_request(:set, key, result)
    end
    result
  end

  @doc """
  Unshifts a value to the beginning of an array stored at the given key.
  """
  def unshift(key, value) do
    ExStore.RecoveryEngine.record_request(:set, key, value)
    ExStore.Cache.Cache.unshift(@server, key, value)
  end

  @doc """
  Slices an array stored at the given key.
  """
  def slice(key, start, stop \\ nil) do
    ExStore.Cache.Cache.slice(@server, key, start, stop)
  end
end
