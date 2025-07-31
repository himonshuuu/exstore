defmodule ExStore.EnhancedDatabaseTest do
  use ExUnit.Case
  alias ExStore.Cache.Cache

  setup do
    # Use the already started cache from the application
    %{cache: ExStore.Cache.Cache}
  end

  describe "Basic operations" do
    test "set and get", %{cache: cache} do
      assert :ok = Cache.set(cache, "key1", "value1")
      assert {:ok, "value1"} = Cache.get(cache, "key1")
    end

    test "has method", %{cache: cache} do
      assert Cache.has(cache, "nonexistent") == false
      Cache.set(cache, "exists", "value")
      assert Cache.has(cache, "exists") == true
    end

    test "delete", %{cache: cache} do
      Cache.set(cache, "key2", "value2")
      assert :ok = Cache.delete(cache, "key2")
      assert :not_found = Cache.get(cache, "key2")
    end
  end

  describe "Batch operations" do
    test "set_many", %{cache: cache} do
      data = [{"key1", "value1"}, {"key2", "value2"}, {"key3", "value3"}]
      assert :ok = Cache.set_many(cache, data)

      assert {:ok, "value1"} = Cache.get(cache, "key1")
      assert {:ok, "value2"} = Cache.get(cache, "key2")
      assert {:ok, "value3"} = Cache.get(cache, "key3")
    end

    test "get_many", %{cache: cache} do
      Cache.set(cache, "key1", "value1")
      Cache.set(cache, "key2", "value2")

      results = Cache.get_many(cache, ["key1", "key2", "nonexistent"])
      assert results == [{:ok, "value1"}, {:ok, "value2"}, :not_found]
    end

    test "delete_many", %{cache: cache} do
      Cache.set(cache, "key1", "value1")
      Cache.set(cache, "key2", "value2")
      Cache.set(cache, "key3", "value3")

      assert :ok = Cache.delete_many(cache, ["key1", "key3"])

      assert :not_found = Cache.get(cache, "key1")
      assert {:ok, "value2"} = Cache.get(cache, "key2")
      assert :not_found = Cache.get(cache, "key3")
    end
  end

    describe "Array operations" do
    test "push and pop", %{cache: cache} do
      # Push elements
      assert %{length: 1, element: "first"} = Cache.push(cache, "array1", "first")
      assert %{length: 2, element: "second"} = Cache.push(cache, "array1", "second")
      assert %{length: 3, element: "third"} = Cache.push(cache, "array1", "third")

      # Pop elements (LIFO)
      assert %{length: 2, element: "third"} = Cache.pop(cache, "array1")
      assert %{length: 1, element: "second"} = Cache.pop(cache, "array1")
      assert %{length: 0, element: "first"} = Cache.pop(cache, "array1")
      assert %{length: 0, element: nil} = Cache.pop(cache, "array1")
    end

    test "shift and unshift", %{cache: cache} do
      # Unshift elements
      assert %{length: 1, element: "first"} = Cache.unshift(cache, "array2", "first")
      assert %{length: 2, element: "second"} = Cache.unshift(cache, "array2", "second")
      assert %{length: 3, element: "third"} = Cache.unshift(cache, "array2", "third")

      # Shift elements (FIFO)
      assert %{length: 2, element: "third"} = Cache.shift(cache, "array2")
      assert %{length: 1, element: "second"} = Cache.shift(cache, "array2")
      assert %{length: 0, element: "first"} = Cache.shift(cache, "array2")
      assert %{length: 0, element: nil} = Cache.shift(cache, "array2")
    end

    test "slice", %{cache: cache} do
      # Create an array
      Cache.push(cache, "array3", "a")
      Cache.push(cache, "array3", "b")
      Cache.push(cache, "array3", "c")
      Cache.push(cache, "array3", "d")
      Cache.push(cache, "array3", "e")

      # Test slice operations
      assert ["c", "d", "e"] = Cache.slice(cache, "array3", 2)
      assert ["b", "c"] = Cache.slice(cache, "array3", 1, 3)
      assert ["a", "b", "c", "d", "e"] = Cache.slice(cache, "array3", 0)
      assert Cache.slice(cache, "nonexistent", 0) == nil
    end
  end

      describe "Data persistence" do
    test "data persists in memory", %{cache: cache} do
      # Set some data
      Cache.set(cache, "persistent_key", "persistent_value")
      Cache.set(cache, "another_key", "another_value")

      # Verify data is in memory
      assert {:ok, "persistent_value"} = Cache.get(cache, "persistent_key")
      assert {:ok, "another_value"} = Cache.get(cache, "another_key")
    end
  end

  describe "TTL functionality" do
    test "TTL expiration", %{cache: cache} do
      # Set with 1 second TTL
      Cache.set(cache, "ttl_key", "ttl_value", 1)

      # Should exist immediately
      assert {:ok, "ttl_value"} = Cache.get(cache, "ttl_key")

      # Wait for expiration
      :timer.sleep(1100)

      # Should be expired
      assert :not_found = Cache.get(cache, "ttl_key")
    end
  end

  describe "Complex data types" do
    test "nested maps and lists", %{cache: cache} do
      complex_data = %{
        "user" => %{
          "name" => "John",
          "age" => 30,
          "hobbies" => ["reading", "coding", "gaming"]
        },
        "settings" => %{
          "theme" => "dark",
          "notifications" => true
        }
      }

      Cache.set(cache, "complex", complex_data)
      assert {:ok, ^complex_data} = Cache.get(cache, "complex")
    end
  end
end
