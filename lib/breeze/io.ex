defmodule Breeze.IO do
  @moduledoc """
  Logger-backed alternatives to `IO.inspect/2` and `IO.puts/1`.

  Alias this module in a view to route temporary debugging output through the
  Breeze logger collector instead of writing over the terminal UI:

      alias Breeze.IO

      IO.puts("mounted settings view")
      IO.inspect(assigns, label: "assigns")

  `inspect/2` returns its input and accepts the usual inspect options. Pretty
  printing and IEx-style syntax colors are enabled by default. Either can be
  overridden with `pretty: false` or `syntax_colors: []`.
  """

  import Kernel, except: [inspect: 1, inspect: 2]
  require Logger

  @doc """
  Pretty-prints a value to the logger and returns the value unchanged.
  """
  @spec inspect(term(), keyword()) :: term()
  def inspect(value, opts \\ []) when is_list(opts) do
    Logger.info(fn -> format_inspect(value, opts) end)
    value
  end

  @doc """
  Pretty-prints a value to the logger and returns the value unchanged.

  The device argument is accepted for compatibility with `IO.inspect/3` and
  is ignored because output is routed to the logger.
  """
  @spec inspect(term(), term(), keyword()) :: term()
  def inspect(_device, value, opts) when is_list(opts), do: inspect(value, opts)

  @doc """
  Writes chardata or a string-convertible value to the logger.
  """
  @spec puts(term()) :: :ok
  def puts(value) do
    Logger.info(fn -> puts_message(value) end)
    :ok
  end

  @doc """
  Writes a value to the logger.

  The device argument is accepted for compatibility with `IO.puts/2` and is
  ignored because output is routed to the logger.
  """
  @spec puts(term(), term()) :: :ok
  def puts(_device, value), do: puts(value)

  defp format_inspect(value, opts) do
    {label, opts} = Keyword.pop(opts, :label)

    opts =
      opts
      |> Keyword.put_new(:pretty, true)
      |> Keyword.put_new_lazy(:syntax_colors, &Elixir.IO.ANSI.syntax_colors/0)

    formatted = Kernel.inspect(value, opts)

    if is_nil(label), do: formatted, else: "#{label}: #{formatted}"
  end

  defp puts_message(value) when is_binary(value), do: value
  defp puts_message(value) when is_list(value), do: Elixir.IO.chardata_to_string(value)
  defp puts_message(value), do: to_string(value)
end
