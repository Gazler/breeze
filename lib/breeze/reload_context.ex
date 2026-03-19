defmodule Breeze.ReloadContext do
  @moduledoc false

  @compile_flag {__MODULE__, :compiling?}

  def compiling? do
    Process.get(@compile_flag, false)
  end

  def with_compile(fun) when is_function(fun, 0) do
    previous = Process.get(@compile_flag)
    Process.put(@compile_flag, true)

    try do
      fun.()
    after
      if is_nil(previous) do
        Process.delete(@compile_flag)
      else
        Process.put(@compile_flag, previous)
      end
    end
  end
end
