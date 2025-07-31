defmodule ExStore.Persistence do
  @moduledoc """
  Enhanced file-based persistence system with indexing, caching, and debounced writes.
  Similar to the TypeScript CoreDatabase implementation.
  """

  use GenServer
  require Logger

  @max_keys_in_file 100
  @debounce_time 250
  @max_debounce_count 250

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    path = "data"
    File.mkdir_p!(path)

    index_file = "#{path}/index.json"

    # Initialize index file if it doesn't exist
    unless File.exists?(index_file) do
      File.write!(index_file, "{}")
    end

    # Load index
    index = case File.read(index_file) do
      {:ok, content} -> Jason.decode!(content)
      _ -> %{}
    end

    # Load all cached data
    cache = load_cache_data(path, index)

    # Schedule periodic saves
    schedule_save()

    {:ok, %{
      path: path,
      index: index,
      cache: cache,
      write_queue: MapSet.new(),
      is_writing: false,
      debounce_count: 0,
      timer: nil
    }}
  end

  def save(data) do
    GenServer.call(__MODULE__, {:save, data})
  end

  def load() do
    GenServer.call(__MODULE__, :load)
  end

  def set(key, value) do
    GenServer.call(__MODULE__, {:set, key, value})
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def has(key) do
    GenServer.call(__MODULE__, {:has, key})
  end

  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  def all() do
    GenServer.call(__MODULE__, :all)
  end

  def flush() do
    GenServer.call(__MODULE__, :flush)
  end

  # Server callbacks
  @impl true
  def handle_call({:save, data}, _from, state) do
    # Save all data to a JSON file
    filename = "#{state.path}/cache.json"
    File.write!(filename, Jason.encode!(data))
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:load, _from, state) do
    # Load all data from the indexed files
    all_data = state.cache
    |> Map.values()
    |> Enum.reduce(%{}, fn file_data, acc ->
      Map.merge(acc, file_data)
    end)
    {:reply, all_data, state}
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    # Find existing key or get suitable file
    file_name = find_key_file(state.index, key) || get_suitable_file(state)

    # Update index if key is new
    state = if not Map.has_key?(state.index, file_name) do
      put_in(state.index[file_name], [])
    else
      state
    end

    keys_in_file = state.index[file_name] || []
    state = if key not in keys_in_file do
      put_in(state.index[file_name], [key | keys_in_file])
    else
      state
    end

    # Update cache
    file_data = Map.get(state.cache, file_name, %{})
    file_data = Map.put(file_data, key, value)
    state = put_in(state.cache[file_name], file_data)

    # Add to write queue and debounce
    write_queue = MapSet.put(state.write_queue, file_name)
    state = %{state | write_queue: write_queue}

    state = debounced_write(state)

    {:reply, value, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case find_key_file(state.index, key) do
      nil -> {:reply, nil, state}
      file_name ->
        value = get_in(state.cache, [file_name, key])
        {:reply, value, state}
    end
  end

  @impl true
  def handle_call({:has, key}, _from, state) do
    has_key = find_key_file(state.index, key) != nil
    {:reply, has_key, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    case find_key_file(state.index, key) do
      nil -> {:reply, false, state}
      file_name ->
        # Remove from cache
        file_data = Map.get(state.cache, file_name, %{})
        file_data = Map.delete(file_data, key)
        state = put_in(state.cache[file_name], file_data)

        # Remove from index
        keys_in_file = Enum.reject(state.index[file_name], &(&1 == key))
        state = put_in(state.index[file_name], keys_in_file)

        # Add to write queue
        write_queue = MapSet.put(state.write_queue, file_name)
        state = %{state | write_queue: write_queue}

        state = debounced_write(state)

        {:reply, true, state}
    end
  end

  @impl true
  def handle_call(:all, _from, state) do
    all_data = state.cache
    |> Map.values()
    |> Enum.reduce(%{}, fn file_data, acc ->
      Map.merge(acc, file_data)
    end)
    {:reply, all_data, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    state = write_pending_files(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:save, state) do
    # Periodic save of all data
    all_data = state.cache
    |> Map.values()
    |> Enum.reduce(%{}, fn file_data, acc ->
      Map.merge(acc, file_data)
    end)

    filename = "#{state.path}/cache.json"
    File.write!(filename, Jason.encode!(all_data))

    schedule_save()
    {:noreply, state}
  end

  @impl true
  def handle_info(:write, state) do
    state = write_pending_files(state)
    {:noreply, state}
  end

  # Private helper functions
  defp load_cache_data(path, index) do
    # First try to load from indexed files
    cache = index
    |> Map.keys()
    |> Enum.reduce(%{}, fn file_name, acc ->
      file_path = "#{path}/#{file_name}"
      case File.read(file_path) do
        {:ok, content} ->
          try do
            data = Jason.decode!(content)
            Map.put(acc, file_name, data)
          rescue
            _ -> acc
          end
        _ -> acc
      end
    end)

    # If no indexed data, try to load from old cache.dump or cache.json
    if map_size(cache) == 0 do
      # Try cache.json first
      cache_json_path = "#{path}/cache.json"
      case File.read(cache_json_path) do
        {:ok, content} ->
          try do
            data = Jason.decode!(content)
            # Convert to indexed format
            file_name = "data_1.json"
            %{file_name => data}
          rescue
            _ -> %{}
          end
        _ ->
          # Try old binary dump format for backward compatibility
          cache_dump_path = "#{path}/cache.dump"
          case File.read(cache_dump_path) do
            {:ok, binary} ->
              try do
                data = :erlang.binary_to_term(binary)
                # Convert to indexed format
                file_name = "data_1.json"
                %{file_name => data}
              rescue
                _ -> %{}
              end
            _ -> %{}
          end
      end
    else
      cache
    end
  end

  defp find_key_file(index, key) do
    Enum.find_value(index, fn {file_name, keys} ->
      if key in keys, do: file_name, else: nil
    end)
  end

  defp get_suitable_file(state) do
    # Look for a file with space
    spacious_file = Enum.find_value(state.index, fn {file_name, keys} ->
      if length(keys) < @max_keys_in_file, do: file_name, else: nil
    end)

    if spacious_file do
      spacious_file
    else
      # Create new file
      file_count = map_size(state.index)
      new_file_name = "data_#{file_count + 1}.json"
      file_path = "#{state.path}/#{new_file_name}"
      # Ensure the directory exists
      File.mkdir_p!(state.path)
      File.write!(file_path, "{}")
      new_file_name
    end
  end

  defp debounced_write(state) do
    debounce_count = state.debounce_count + 1

    if debounce_count >= @max_debounce_count do
      # Force write immediately
      write_pending_files(%{state | debounce_count: 0})
    else
      # Schedule debounced write
      _timer = if state.timer, do: Process.cancel_timer(state.timer)
      new_timer = Process.send_after(self(), :write, @debounce_time)

      %{state |
        debounce_count: debounce_count,
        timer: new_timer
      }
    end
  end

  defp write_pending_files(state) do
    if state.is_writing do
      # If already writing, schedule another write
      Process.send_after(self(), :write, @debounce_time)
      state
    else
      # Write all pending files
      state = %{state | is_writing: true}

      # Ensure directory exists
      File.mkdir_p!(state.path)

      Enum.each(state.write_queue, fn file_name ->
        file_path = "#{state.path}/#{file_name}"
        file_data = Map.get(state.cache, file_name, %{})
        File.write!(file_path, Jason.encode!(file_data))
      end)

            # Write index
      index_path = "#{state.path}/index.json"
      File.write!(index_path, Jason.encode!(state.index))

      %{state |
        write_queue: MapSet.new(),
        is_writing: false,
        debounce_count: 0,
        timer: nil
      }
    end
  end

  defp schedule_save() do
    Process.send_after(self(), :save, 5_000)  # Every 5 seconds
  end
end
