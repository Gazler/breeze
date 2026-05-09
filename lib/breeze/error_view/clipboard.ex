defmodule Breeze.ErrorView.Clipboard do
  @moduledoc false

  def copy(text, opts \\ []) when is_binary(text) do
    timeout = Keyword.get(opts, :timeout, 500)

    task =
      Task.async(fn ->
        case Keyword.get(opts, :copy_fun) do
          fun when is_function(fun, 1) ->
            fun.(text)

          _ ->
            with {:ok, command} <- command(opts) do
              run_command(command, text, opts)
            end
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> normalize_result(result)
      nil -> {:error, :timeout}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  def command(opts \\ []) do
    os_type = Keyword.get(opts, :os_type, :os.type())
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)

    os_type
    |> candidates()
    |> Enum.find_value(fn name ->
      case find_executable.(name) do
        nil -> nil
        path -> {name, path}
      end
    end)
    |> case do
      nil -> {:error, :unavailable}
      command -> {:ok, command}
    end
  end

  defp candidates({:unix, :darwin}), do: ["pbcopy"]
  defp candidates({:unix, _}), do: ["wl-copy"]
  defp candidates(_), do: []

  defp run_command({name, path}, text, opts) do
    case Keyword.get(opts, :run_fun) do
      fun when is_function(fun, 3) ->
        fun.(name, path, text)

      _ ->
        copy_with_shell(name, path, text)
    end
  end

  defp copy_with_shell(name, path, text) do
    tmp_path =
      Path.join(System.tmp_dir!(), "breeze-clipboard-#{System.unique_integer([:positive])}")

    try do
      with :ok <- File.write(tmp_path, text),
           {:ok, shell} <- find_shell(),
           {output, 0} <- run_shell_copy(shell, tmp_path, path) do
        _ = output
        {:ok, name}
      else
        {:error, reason} ->
          {:error, reason}

        {output, status} ->
          {:error, {:exit_status, status, output}}
      end
    after
      File.rm(tmp_path)
    end
  end

  defp find_shell do
    case System.find_executable("sh") do
      nil -> {:error, :unavailable}
      shell -> {:ok, shell}
    end
  end

  defp run_shell_copy(shell, tmp_path, path) do
    System.cmd(shell, ["-c", "\"$2\" < \"$1\" >/dev/null 2>&1", "breeze-copy", tmp_path, path],
      stderr_to_stdout: true
    )
  end

  defp normalize_result({:ok, command}), do: {:ok, command}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(other), do: {:error, {:unexpected_result, other}}
end
