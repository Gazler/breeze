defmodule Breeze.Example do
  @moduledoc false

  def run(server_opts, opts \\ []) do
    unless load_only?() or Breeze.ReloadContext.compiling?() do
      case server_opts
           |> Keyword.put_new(:logger, :replace)
           |> start_server() do
        {:ok, _pid} -> keep_alive(Keyword.get(opts, :keep_alive, :infinity))
        {:error, reason} -> raise_start_error(reason)
      end
    end
  end

  def load_only? do
    Application.get_env(:breeze, :example_mode) == :load_only or
      System.get_env("BREEZE_LOAD_EXAMPLES_ONLY") in ["1", "true", "TRUE"]
  end

  defp keep_alive(:infinity) do
    receive do
    end
  end

  defp keep_alive(timeout) when is_integer(timeout) and timeout >= 0 do
    :timer.sleep(timeout)
  end

  defp start_server(server_opts) do
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      Breeze.Server.start_link(server_opts)
    after
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  defp raise_start_error({exception, stacktrace}) when is_list(stacktrace) do
    :erlang.raise(:error, exception, stacktrace)
  end

  defp raise_start_error(reason), do: exit(reason)
end
