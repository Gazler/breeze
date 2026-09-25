defmodule Breeze.Example do
  @moduledoc false

  def run(server_opts, opts \\ []) do
    unless load_only?() or Breeze.ReloadContext.compiling?() do
      previous_trap_exit = Process.flag(:trap_exit, true)

      try do
        case server_opts |> Keyword.put_new(:logger, :replace) |> Breeze.Server.start_link() do
          {:ok, pid} ->
            timeout = Keyword.get(opts, :keep_alive, :infinity)
            deadline = if timeout == :infinity, do: :infinity, else: now_ms() + timeout
            keep_alive(pid, deadline, previous_trap_exit)

          {:error, reason} ->
            raise_start_error(reason)
        end
      after
        Process.flag(:trap_exit, previous_trap_exit)
      end
    end
  end

  def load_only? do
    Application.get_env(:breeze, :example_mode) == :load_only or
      System.get_env("BREEZE_LOAD_EXAMPLES_ONLY") in ["1", "true", "TRUE"]
  end

  # The startup link observes exits even before start_link/1 returns. Installing
  # a monitor afterwards can lose the exit reason and report only :noproc.
  defp keep_alive(pid, deadline, previously_trapping?) do
    receive do
      {:EXIT, ^pid, reason} ->
        session_result(reason)

      {:EXIT, _other, :normal} when not previously_trapping? ->
        keep_alive(pid, deadline, previously_trapping?)

      {:EXIT, _other, reason} when not previously_trapping? ->
        exit(reason)
    after
      remaining_ms(deadline) ->
        Breeze.Server.stop(pid)
        keep_alive(pid, :infinity, previously_trapping?)
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
  defp remaining_ms(:infinity), do: :infinity
  defp remaining_ms(deadline), do: max(deadline - now_ms(), 0)

  defp session_result(reason) when reason in [:normal, :shutdown], do: :ok
  defp session_result({:shutdown, _reason}), do: :ok
  defp session_result(reason), do: exit(reason)

  defp raise_start_error({exception, stacktrace}) when is_list(stacktrace) do
    :erlang.raise(:error, exception, stacktrace)
  end

  defp raise_start_error(reason), do: exit(reason)
end
