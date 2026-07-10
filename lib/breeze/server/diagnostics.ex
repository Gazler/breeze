defmodule Breeze.Server.Diagnostics do
  @moduledoc """
  Developer-facing diagnostics for a running Breeze server.

  Use this module to read the latest rendering statistics or inspector state,
  and to subscribe a process to either stream. Subscribers are monitored and
  automatically removed when they exit.

  Statistics subscribers receive `{:debug_stats, stats}` messages. Inspector
  subscribers receive `{:inspector_snapshot, snapshot}` messages.
  """

  @doc "Returns the latest rendering and interaction statistics for a server."
  @spec stats(pid()) :: map()
  def stats(server) when is_pid(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Subscribes a process to rendering and interaction statistics.

  The subscriber receives `{:debug_stats, stats}` whenever the server publishes
  an updated snapshot. It defaults to the calling process.
  """
  @spec subscribe_stats(pid(), pid()) :: :ok
  def subscribe_stats(server, subscriber \\ self())
      when is_pid(server) and is_pid(subscriber) do
    GenServer.cast(server, {:subscribe_debug, subscriber})
  end

  @doc "Returns the latest inspector snapshot for a server."
  @spec inspector_snapshot(pid()) :: map()
  def inspector_snapshot(server) when is_pid(server) do
    GenServer.call(server, :inspector_snapshot)
  end

  @doc """
  Subscribes a process to inspector snapshots.

  The subscriber receives `{:inspector_snapshot, snapshot}` whenever the server
  publishes an updated snapshot. It defaults to the calling process.
  """
  @spec subscribe_inspector(pid(), pid()) :: :ok
  def subscribe_inspector(server, subscriber \\ self())
      when is_pid(server) and is_pid(subscriber) do
    GenServer.cast(server, {:subscribe_inspector, subscriber})
  end
end
