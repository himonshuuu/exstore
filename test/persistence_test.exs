defmodule ExStore.PersistenceTest do
  use ExUnit.Case, async: false
  alias ExStore.Persistence

  setup do
    # Clean up test data directory
    try do
      File.rm_rf!("data")
    rescue
      _ -> :ok
    end

    # The persistence module is already started by the supervisor
    # We just need to wait a moment for it to initialize
    Process.sleep(100)

    on_exit(fn ->
      # Clean up after test
      try do
        File.rm_rf!("data")
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

    test "sets and gets values with file-based storage" do
    # Set some values
    Persistence.set("key1", "value1")
    Persistence.set("key2", "value2")
    Persistence.set("key3", "value3")

    # Force a write to disk
    Persistence.flush()
    Process.sleep(100)

    # Verify they can be retrieved
    assert Persistence.get("key1") == "value1"
    assert Persistence.get("key2") == "value2"
    assert Persistence.get("key3") == "value3"

    # Verify file structure was created
    assert File.exists?("data/index.json")
    # Check for any data file (could be data_1.json, data_2.json, etc.)
    data_files = File.ls!("data") |> Enum.filter(&String.starts_with?(&1, "data_"))
    assert length(data_files) > 0
  end

  test "handles key existence checks" do
    Persistence.set("test_key", "test_value")

    assert Persistence.has("test_key") == true
    assert Persistence.has("nonexistent_key") == false
  end

  test "deletes keys properly" do
    Persistence.set("delete_key", "delete_value")
    assert Persistence.has("delete_key") == true

    assert Persistence.delete("delete_key") == true
    assert Persistence.has("delete_key") == false
    assert Persistence.delete("nonexistent_key") == false
  end

    test "returns all data" do
    # Clear any existing data first
    all_existing = Persistence.all()
    Enum.each(Map.keys(all_existing), fn key ->
      Persistence.delete(key)
    end)
    
    Persistence.set("key1", "value1")
    Persistence.set("key2", "value2")
    Persistence.set("key3", "value3")
    
    # Force a write to disk
    Persistence.flush()
    Process.sleep(100)
    
    all_data = Persistence.all()
    
    assert all_data["key1"] == "value1"
    assert all_data["key2"] == "value2"
    assert all_data["key3"] == "value3"
    assert map_size(all_data) == 3
  end

    test "creates multiple files when max keys per file is reached" do
        # Set more than max_keys_in_file (100) keys
    Enum.each(1..105, fn i ->
      Persistence.set("key#{i}", "value#{i}")
    end)

    # Force a write to disk
    Persistence.flush()
    Process.sleep(100)

    # Verify data is accessible
    assert Persistence.get("key1") == "value1"
    assert Persistence.get("key100") == "value100"
    assert Persistence.get("key105") == "value105"

    # Check that multiple files were created
    assert File.exists?("data/index.json")
    index_content = File.read!("data/index.json")
    index = Jason.decode!(index_content)

    # Should have at least 2 files (data_1.json and data_2.json)
    assert map_size(index) >= 2
  end

    test "maintains data across restarts" do
        # Set some data
    Persistence.set("persistent_key", "persistent_value")
    Persistence.set("another_key", "another_value")
    
    # Force a write to disk
    Persistence.flush()
    Process.sleep(100)

    # Verify data is still there
    assert Persistence.get("persistent_key") == "persistent_value"
    assert Persistence.get("another_key") == "another_value"

    # Verify files were created
    assert File.exists?("data/index.json")
    # Check for any data file (could be data_1.json, data_2.json, etc.)
    data_files = File.ls!("data") |> Enum.filter(&String.starts_with?(&1, "data_"))
    assert length(data_files) > 0
  end

  test "handles complex data types" do
    complex_data = %{
      "string" => "hello",
      "number" => 42,
      "list" => [1, 2, 3],
      "map" => %{"nested" => "value"}
    }

    Persistence.set("complex", complex_data)
    retrieved = Persistence.get("complex")

    assert retrieved == complex_data
  end
end
