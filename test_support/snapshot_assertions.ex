defmodule Breeze.SnapshotAssertions do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      import Breeze.SnapshotAssertions
    end
  end

  defmacro assert_snapshot(actual, relative_path, opts \\ []) do
    caller_file = __CALLER__.file

    quote bind_quoted: [
            actual: actual,
            relative_path: relative_path,
            opts: opts,
            caller_file: caller_file
          ] do
      Breeze.SnapshotAssertions.assert_snapshot!(actual, relative_path, caller_file, opts)
    end
  end

  def assert_snapshot!(actual, relative_path, caller_file, opts \\ [])
      when is_binary(actual) and is_binary(relative_path) and is_binary(caller_file) and
             is_list(opts) do
    path = snapshot_path(relative_path, caller_file, opts)

    cond do
      update_snapshots?() ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, actual)

      not File.exists?(path) ->
        raise ExUnit.AssertionError,
          message:
            "snapshot missing: #{Path.relative_to_cwd(path)}\n" <>
              "Re-run with BREEZE_UPDATE_SNAPSHOTS=1 to create it."

      true ->
        :ok
    end

    expected = File.read!(path)

    if actual != expected do
      actual_path = path <> ".actual"
      File.write!(actual_path, actual)
      diff = diff_summary(expected, actual)

      raise ExUnit.AssertionError,
        message:
          "snapshot mismatch: #{Path.relative_to_cwd(path)}\n" <>
            "actual written to: #{Path.relative_to_cwd(actual_path)}\n" <>
            "Re-run with BREEZE_UPDATE_SNAPSHOTS=1 to accept the new output.\n\n" <>
            "#{diff}\n\n" <>
            "Expected:\n#{expected}\n\n" <>
            "Actual:\n#{actual}"
    end

    :ok
  end

  defp snapshot_path(relative_path, caller_file, opts) do
    snapshot_dir =
      case Keyword.get(opts, :snapshot_dir) do
        nil -> Path.join(Path.dirname(caller_file), "__snapshots__")
        dir -> Path.expand(dir, Path.dirname(caller_file))
      end

    Path.join(snapshot_dir, relative_path)
  end

  defp update_snapshots? do
    System.get_env("BREEZE_UPDATE_SNAPSHOTS") in ["1", "true", "TRUE"]
  end

  defp diff_summary(expected, actual) do
    {line, column, expected_char, actual_char, offset} = first_difference(expected, actual)

    expected_line = line_at(expected, line)
    actual_line = line_at(actual, line)

    """
    First difference at byte #{offset}, line #{line}, column #{column}
    expected char: #{inspect(expected_char)}
    actual char: #{inspect(actual_char)}
    expected bytes: #{byte_size(expected)}
    actual bytes: #{byte_size(actual)}
    expected line: #{inspect(expected_line)}
    actual line: #{inspect(actual_line)}
    """
    |> String.trim()
  end

  defp first_difference(expected, actual) do
    expected_chars = String.to_charlist(expected)
    actual_chars = String.to_charlist(actual)
    locate_difference(expected_chars, actual_chars, 1, 1, 0)
  end

  defp locate_difference([same | expected_rest], [same | actual_rest], line, column, offset) do
    if same == ?\n do
      locate_difference(expected_rest, actual_rest, line + 1, 1, offset + 1)
    else
      locate_difference(expected_rest, actual_rest, line, column + 1, offset + 1)
    end
  end

  defp locate_difference([expected | _], [actual | _], line, column, offset) do
    {line, column, codepoint_to_string(expected), codepoint_to_string(actual), offset}
  end

  defp locate_difference([], [actual | _], line, column, offset) do
    {line, column, :eof, codepoint_to_string(actual), offset}
  end

  defp locate_difference([expected | _], [], line, column, offset) do
    {line, column, codepoint_to_string(expected), :eof, offset}
  end

  defp locate_difference([], [], line, column, offset) do
    {line, column, :eof, :eof, offset}
  end

  defp line_at(content, line_number) do
    content
    |> String.split("\n", trim: false)
    |> Enum.at(line_number - 1)
  end

  defp codepoint_to_string(codepoint) when is_integer(codepoint), do: <<codepoint::utf8>>
end
