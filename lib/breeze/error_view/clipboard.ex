defmodule Breeze.ErrorView.Clipboard do
  @moduledoc false

  # OSC 52 writes to the client terminal's clipboard. The terminal may ignore
  # the request according to its clipboard permissions; there is no write ACK.
  def copy(text, opts \\ []) when is_binary(text) do
    case Keyword.get(opts, :copy_fun) do
      fun when is_function(fun, 1) ->
        copy_with_fun(text, fun, Keyword.get(opts, :timeout, 500))

      _ ->
        {:ok, {:osc52, "\e]52;c;" <> Base.encode64(text) <> "\e\\"}}
    end
  end

  defp copy_with_fun(text, fun, timeout) do
    task = Task.async(fn -> fun.(text) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> normalize_result(result)
      nil -> {:error, :timeout}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp normalize_result({:ok, target}), do: {:ok, target}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(other), do: {:error, {:unexpected_result, other}}
end
