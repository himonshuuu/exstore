defmodule ExStore.Net.TCP do
  @moduledoc """
  A simple TCP server that serves ExStore commands over network.
  """

  require Logger

  def child_spec(port \\ 6380) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [port]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  def start_link(port \\ 6380) do
    Task.start_link(fn -> listen(port) end)
  end

  defp listen(port) when is_integer(port) do
    opts = [:binary, packet: :line, active: false, reuseaddr: true]

    case :gen_tcp.listen(port, opts) do
      {:ok, socket} ->
        Logger.info("ExStore TCP Server running on port #{port}")
        loop_accept(socket)

      {:error, reason} ->
        Logger.error("Failed to start TCP server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp loop_accept(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    Task.start_link(fn -> serve(client) end)
    loop_accept(socket)
  end

  defp serve(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, line} ->
        response = handle_command(line)
        :gen_tcp.send(socket, response)
        serve(socket)

      {:error, :closed} ->
        :ok
    end
  end

  defp handle_command(line) do
    tokens =
      line
      |> binary_part(0, byte_size(line) - 1)
      |> parse_command_line()
      |> Enum.map(fn token ->
        if is_binary(token) do
          String.downcase(token)
        else
          token
        end
      end)

    case tokens do
      ["set", key, value] ->
        ExStore.Cache.Cache.set(ExStore.Cache.Cache, key, value)
        ExStore.Persistence.set(key, value)
        "+OK\r\n"

      ["set", key, value, "ex", ttl_str] ->
        case Integer.parse(ttl_str) do
          {ttl, ""} ->
            ExStore.Cache.Cache.set(ExStore.Cache.Cache, key, value, ttl)
            ExStore.Persistence.set(key, value) # No TTL in persistence
            "+OK\r\n"
          _ ->
            "-ERR invalid TTL\r\n"
        end

      ["setmany"] ++ data ->
        case parse_set_many_data(data) do
          {:ok, key_value_pairs} ->
            ExStore.Cache.Cache.set_many(ExStore.Cache.Cache, key_value_pairs)
            Enum.each(key_value_pairs, fn {k, v} -> ExStore.Persistence.set(k, v) end)
            "+OK\r\n"
          {:error, reason} ->
            "-ERR #{reason}\r\n"
        end

      ["get", key] ->
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, val} when is_binary(val) -> "$#{byte_size(val)}\r\n#{val}\r\n"
          {:ok, val} ->
            encoded = Jason.encode!(val)
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
          :not_found -> "$-1\r\n"
        end

      ["getmany"] ++ keys ->
        case ExStore.Cache.Cache.get_many(ExStore.Cache.Cache, keys) do
          results ->
            response = Enum.map_join(results, "\r\n", fn
              {:ok, val} -> "$#{byte_size(val)}\r\n#{val}"
              :not_found -> "$-1"
            end)
            response <> "\r\n"
        end

      ["has", key] ->
        case ExStore.Cache.Cache.has(ExStore.Cache.Cache, key) do
          true -> ":1\r\n"
          false -> ":0\r\n"
        end

      ["del", key] ->
        ExStore.Cache.Cache.delete(ExStore.Cache.Cache, key)
        ExStore.Persistence.delete(key)
        ":1\r\n"

      ["delmany"] ++ keys ->
        ExStore.Cache.Cache.delete_many(ExStore.Cache.Cache, keys)
        Enum.each(keys, &ExStore.Persistence.delete/1)
        "+OK\r\n"

      ["ttl", key] ->
        case ExStore.Cache.Cache.ttl(ExStore.Cache.Cache, key) do
          :no_ttl -> ":0\r\n"
          :not_found -> ":-2\r\n"
          remaining -> ":#{remaining}\r\n"
        end

      ["all"] ->
        case ExStore.Cache.Cache.dump_all() do
          data ->
            encoded = Jason.encode!(data)
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
        end

      # Array operations
      ["push", key, value] ->
        result = ExStore.Cache.Cache.push(ExStore.Cache.Cache, key, value)
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, v} -> ExStore.Persistence.set(key, v)
          :not_found -> :ok
        end
        case result do
          %{length: length, element: element} ->
            encoded = Jason.encode!(%{length: length, element: element})
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
        end

      ["pop", key] ->
        result = ExStore.Cache.Cache.pop(ExStore.Cache.Cache, key)
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, v} -> ExStore.Persistence.set(key, v)
          :not_found -> :ok
        end
        case result do
          %{length: length, element: element} ->
            encoded = Jason.encode!(%{length: length, element: element})
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
        end

      ["shift", key] ->
        result = ExStore.Cache.Cache.shift(ExStore.Cache.Cache, key)
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, v} -> ExStore.Persistence.set(key, v)
          :not_found -> :ok
        end
        case result do
          %{length: length, element: element} ->
            encoded = Jason.encode!(%{length: length, element: element})
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
        end

      ["unshift", key, value] ->
        result = ExStore.Cache.Cache.unshift(ExStore.Cache.Cache, key, value)
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, v} -> ExStore.Persistence.set(key, v)
          :not_found -> :ok
        end
        case result do
          %{length: length, element: element} ->
            encoded = Jason.encode!(%{length: length, element: element})
            "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
        end

      ["slice", key, start_str, stop_str] ->
        case {Integer.parse(start_str), Integer.parse(stop_str)} do
          {{start, ""}, {stop, ""}} ->
            case ExStore.Cache.Cache.slice(ExStore.Cache.Cache, key, start, stop) do
              nil -> "$-1\r\n"
              result ->
                encoded = Jason.encode!(result)
                "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
            end

          _ ->
            "-ERR invalid slice parameters\r\n"
        end

      ["slice", key, start_str] ->
        case Integer.parse(start_str) do
          {start, ""} ->
            case ExStore.Cache.Cache.slice(ExStore.Cache.Cache, key, start) do
              nil -> "$-1\r\n"
              result ->
                encoded = Jason.encode!(result)
                "$#{byte_size(encoded)}\r\n#{encoded}\r\n"
            end

          _ ->
            "-ERR invalid slice parameter\r\n"
        end

      _ ->
        "-ERR unknown command\r\n"
    end
  end

  defp parse_command_line(line) do
    parse_command_line(line, [], "", false, [])
  end

  defp parse_command_line("", [], "", false, acc) do
    Enum.reverse(acc)
  end

  defp parse_command_line("", [], current, false, acc) do
    Enum.reverse([current | acc])
  end

  defp parse_command_line(" " <> rest, [], "", false, acc) do
    parse_command_line(rest, [], "", false, acc)
  end

  defp parse_command_line(" " <> rest, [], current, false, acc) do
    parse_command_line(rest, [], "", false, [current | acc])
  end

  defp parse_command_line("\"" <> rest, [], "", false, acc) do
    parse_command_line(rest, [], "", true, acc)
  end

  defp parse_command_line("\"" <> rest, [], current, true, acc) do
    parse_command_line(rest, [], "", false, [current | acc])
  end

  defp parse_command_line("\\\"" <> rest, [], current, true, acc) do
    parse_command_line(rest, [], current <> "\"", true, acc)
  end

  defp parse_command_line(<<char::utf8>> <> rest, [], current, true, acc) do
    parse_command_line(rest, [], current <> <<char::utf8>>, true, acc)
  end

  defp parse_command_line(<<char::utf8>> <> rest, [], current, false, acc) do
    parse_command_line(rest, [], current <> <<char::utf8>>, false, acc)
  end

  defp parse_set_many_data(data) when length(data) < 2 do
    {:error, "insufficient data for SETMANY"}
  end

  defp parse_set_many_data(data) when rem(length(data), 2) != 0 do
    {:error, "odd number of arguments for SETMANY"}
  end

  defp parse_set_many_data(data) do
    key_value_pairs = data
    |> Enum.chunk_every(2)
    |> Enum.map(fn [key, value] -> {key, value} end)

    {:ok, key_value_pairs}
  end
end
