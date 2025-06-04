defmodule ExStoreTest do
  use ExUnit.Case

  # start cache server
  setup do
    {:ok, pid} = ExStore.CacheServer.start_link()
    %{pid: pid}
  end

  test "put and get value", %{pid: pid} do
    ExStore.CacheServer.set(pid, "key", "value")
    assert ExStore.CacheServer.get(pid, "key") == {:ok, "value"}
  end

  test "value expires after TTL", %{pid: pid} do
    ExStore.CacheServer.set(pid, "key", "value", 1)
    assert ExStore.CacheServer.get(pid, "key") == {:ok, "value"}
    Process.sleep(1100)
    assert ExStore.CacheServer.get(pid, "key") == :not_found
  end
end
