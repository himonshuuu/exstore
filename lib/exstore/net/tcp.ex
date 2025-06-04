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
      |> String.split()
      |> Enum.map(&String.downcase/1)

    case tokens do
      ["set", key, value] ->
        ExStore.Cache.Cache.set(ExStore.Cache.Cache, key, value)
        "+OK\r\n"

      ["set", key, value, "ex", ttl_str] ->
        case Integer.parse(ttl_str) do
          {ttl, ""} ->
            ExStore.Cache.Cache.set(ExStore.Cache.Cache, key, value, ttl)
            "+OK\r\n"

          _ ->
            "-ERR invalid TTL\r\n"
        end

      ["get", key] ->
        case ExStore.Cache.Cache.get(ExStore.Cache.Cache, key) do
          {:ok, val} -> "$#{byte_size(val)}\r\n#{val}\r\n"
          :not_found -> "$-1\r\n"
        end

      ["del", key] ->
        ExStore.Cache.Cache.delete(ExStore.Cache.Cache, key)
        ":1\r\n"

      ["ttl", key] ->
        case ExStore.Cache.Cache.ttl(ExStore.Cache.Cache, key) do
          :no_ttl -> ":0\r\n"
          :not_found -> ":-2\r\n"
          remaining -> ":#{remaining}\r\n"
        end

      _ ->
        "-ERR unknown command\r\n"
    end
  end
end
