defmodule Breeze.TestSupport.ProcessHelpers do
  @moduledoc false

  def stop_gen_server(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  catch
    :exit, reason ->
      if expected_stop_exit?(reason) do
        :ok
      else
        :erlang.raise(:exit, reason, __STACKTRACE__)
      end
  end

  defp expected_stop_exit?(reason) when reason in [:noproc, :normal, :shutdown], do: true

  defp expected_stop_exit?({reason, {GenServer, :stop, _args}}),
    do: expected_stop_exit?(reason)

  defp expected_stop_exit?({reason, {:sys, :terminate, _args}}),
    do: expected_stop_exit?(reason)

  defp expected_stop_exit?(_reason), do: false
end
