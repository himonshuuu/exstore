defmodule ExStore do
  @moduledoc """
  A simple in-memory key-value store.
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
    GenServer.call(@server, {:set, key, value, ttl})
  end

  @doc """
  Retrieves the value associated with `key`.
  """
  def get(key) do
    GenServer.call(@server, {:get, key})
  end

  @doc """
  Deletes the key-value pair associated with `key`.
  """
  def delete(key) do
    GenServer.call(@server, {:delete, key})
  end

  @doc """
  Retrieves the TTL associated with `key`, or `-2` if the key does not exist or has no TTL.
  """
  def ttl(key) do
    GenServer.call(@server, {:ttl, key})
  end
end

