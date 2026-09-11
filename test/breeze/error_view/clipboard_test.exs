defmodule Breeze.ErrorView.ClipboardTest do
  use ExUnit.Case, async: true

  alias Breeze.ErrorView.Clipboard

  test "returns timeout when clipboard command does not finish" do
    assert {:error, :timeout} =
             Clipboard.copy("details",
               os_type: {:unix, :linux},
               timeout: 10,
               run_fun: fn _name, _path, _text ->
                 Process.sleep(1_000)
                 {:ok, "slow-copy"}
               end,
               find_executable: fn "wl-copy" -> "/usr/bin/wl-copy" end
             )
  end

  test "returns unavailable when no clipboard command exists" do
    assert {:error, :unavailable} =
             Clipboard.copy("details", find_executable: fn _name -> nil end)
  end

  test "normalizes unexpected clipboard function results" do
    assert {:error, {:unexpected_result, :ok}} =
             Clipboard.copy("details", copy_fun: fn _text -> :ok end)
  end
end
