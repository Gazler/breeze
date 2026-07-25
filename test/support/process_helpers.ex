defmodule Breeze.TestSupport.ProcessHelpers do
  @moduledoc false

  def start_child_server(opts) when is_list(opts) do
    start_supervised(Breeze.ChildServer, :start_link, opts)
  end

  def start_app_server(opts) when is_list(opts) do
    start_supervised(Breeze.Server, :start_app_link, opts)
  end

  def start_server(opts) when is_list(opts) do
    start_supervised(Breeze.Server, :start_link, opts)
  end

  def start_input_router(opts) when is_list(opts) do
    start_supervised(Breeze.InputRouter, :start_link, opts)
  end

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

  defp start_supervised(module, function, opts) do
    ExUnit.Callbacks.start_supervised(%{
      id: {module, make_ref()},
      start: {module, function, [opts]},
      restart: :temporary
    })
  end

  defp expected_stop_exit?(reason) when reason in [:noproc, :normal, :shutdown], do: true

  defp expected_stop_exit?({reason, {GenServer, :stop, _args}}),
    do: expected_stop_exit?(reason)

  defp expected_stop_exit?({reason, {:sys, :terminate, _args}}),
    do: expected_stop_exit?(reason)

  defp expected_stop_exit?(_reason), do: false
end
