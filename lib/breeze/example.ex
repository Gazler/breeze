defmodule Breeze.Example do
  @moduledoc false

  def run(server_opts, opts \\ []) do
    unless load_only?() do
      Breeze.Server.start_link(server_opts)
      keep_alive(Keyword.get(opts, :keep_alive, :infinity))
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
end
