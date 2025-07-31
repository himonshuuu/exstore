defmodule ExStore.RecoveryEngine do
  @moduledoc """
  A recovery engine that logs operations and can replay them for data recovery.
  """

  use GenServer
  require Logger

  @request_count 500
  @log_retention_days 7

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    log_file = "data/logs.csv"
    File.mkdir_p!("data")

    if File.exists?(log_file) do
      run_recovery(log_file)
    else
      File.write!(log_file, "timestamp,request_id,method,key,value\n")
    end

    {:ok, %{log_file: log_file}}
  end

  def record_request(method, key \\ nil, value \\ nil, request_id \\ nil) do
    GenServer.cast(__MODULE__, {:record, method, key, value, request_id})
  end

  @impl true
  def handle_cast({:record, method, key, value, request_id}, state) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    request_id = request_id || generate_request_id()

    log_entry = case method do
      :all ->
        "#{timestamp},#{request_id},ALL,,\n"

      :get_many ->
        keys = if is_list(key), do: Enum.join(key, "|"), else: key
        "#{timestamp},#{request_id},GET_MANY,#{keys},\n"

      :delete_many ->
        keys = if is_list(key), do: Enum.join(key, "|"), else: key
        "#{timestamp},#{request_id},DELETE_MANY,#{keys},\n"

      :set_many ->
        data = if is_list(value), do: Enum.map_join(value, "|", &Jason.encode!/1), else: Jason.encode!(value)
        "#{timestamp},#{request_id},SET_MANY,#{key},#{data}\n"

      :get ->
        "#{timestamp},#{request_id},GET,#{key},\n"

      :has ->
        "#{timestamp},#{request_id},HAS,#{key},\n"

      :delete ->
        "#{timestamp},#{request_id},DELETE,#{key},\n"

      :set ->
        encoded_value = if value, do: Jason.encode!(value), else: ""
        "#{timestamp},#{request_id},SET,#{key},#{encoded_value}\n"
    end

    File.write!(state.log_file, log_entry, [:append])
    {:noreply, state}
  end

  defp run_recovery(log_file) do
    Logger.info("Running recovery from log file: #{log_file}")

    requests = File.read!(log_file)
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Skip header
    |> Enum.map(&parse_log_line/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.filter(&(&1.method in [:set, :delete]))
    |> Enum.take(-@request_count)

    Logger.info("Replaying #{length(requests)} operations for recovery")

    Enum.each(requests, fn request ->
      case request.method do
        :set ->
          value = if request.value != "", do: Jason.decode!(request.value), else: nil
          if value, do: ExStore.Cache.Cache.set(ExStore.Cache.Cache, request.key, value)

        :delete ->
          ExStore.Cache.Cache.delete(ExStore.Cache.Cache, request.key)
      end
    end)

    # Clean up old logs
    cleanup_old_logs(log_file)
  end

  defp parse_log_line(line) do
    case String.split(line, ",", parts: 5) do
      [timestamp, request_id, method, key, value] ->
        %{
          timestamp: timestamp,
          request_id: request_id,
          method: String.to_atom(method),
          key: if(key == "", do: nil, else: key),
          value: if(value == "", do: nil, else: value)
        }

      _ ->
        nil
    end
  end

  defp cleanup_old_logs(log_file) do
    threshold = DateTime.utc_now() |> DateTime.add(-@log_retention_days * 24 * 60 * 60, :second)

    requests = File.read!(log_file)
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_log_line/1)
    |> Enum.filter(&(&1 != nil))
    |> Enum.filter(fn request ->
      case DateTime.from_iso8601(request.timestamp) do
        {:ok, timestamp, _} -> DateTime.compare(timestamp, threshold) == :gt
        _ -> false
      end
    end)

    # Rewrite log file with filtered entries
    header = "timestamp,request_id,method,key,value\n"
    entries = Enum.map(requests, fn request ->
      value = if request.value, do: request.value, else: ""
      "#{request.timestamp},#{request.request_id},#{request.method},#{request.key || ""},#{value}"
    end)
    |> Enum.join("\n")

    File.write!(log_file, header <> entries <> "\n")
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
