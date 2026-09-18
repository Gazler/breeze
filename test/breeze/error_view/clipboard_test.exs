defmodule Breeze.ErrorView.ClipboardTest do
  use ExUnit.Case, async: true

  alias Breeze.ErrorView.Clipboard

  test "encodes crash details as an OSC 52 clipboard write" do
    text = "Crash details\nλ\e[31m"
    assert {:ok, {:osc52, sequence}} = Clipboard.copy(text)
    assert sequence == "\e]52;c;" <> Base.encode64(text) <> "\e\\"
  end

  test "returns timeout when an injected clipboard function does not finish" do
    assert {:error, :timeout} =
             Clipboard.copy("details",
               timeout: 10,
               copy_fun: fn _text ->
                 Process.sleep(1_000)
                 {:ok, "slow-copy"}
               end
             )
  end

  test "normalizes unexpected clipboard function results" do
    assert {:error, {:unexpected_result, :ok}} =
             Clipboard.copy("details", copy_fun: fn _text -> :ok end)
  end
end
