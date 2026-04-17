defmodule Breeze.KeybindingsTest do
  use ExUnit.Case, async: true

  alias Breeze.Keybindings

  test "dispatch matches control-style bindings against decoded ctrl events" do
    term = %{handled?: false}

    assert {:noreply, %{handled?: true}} =
             Keybindings.dispatch(
               %{"ctrlKey" => true, "key" => "t"},
               [{"^t", "Method", fn _event, term -> {:noreply, %{term | handled?: true}} end}],
               term
             )
  end

  test "dispatch matches control-style bindings against raw control characters" do
    term = %{handled?: false}

    assert {:noreply, %{handled?: true}} =
             Keybindings.dispatch(
               %{"key" => "\x14"},
               [{"^t", "Method", fn _event, term -> {:noreply, %{term | handled?: true}} end}],
               term
             )
  end

  test "dispatch does not match control-style bindings without ctrl" do
    term = %{handled?: false}

    assert :continue =
             Keybindings.dispatch(
               %{"key" => "t"},
               [{"^t", "Method", fn _event, term -> {:noreply, %{term | handled?: true}} end}],
               term
             )
  end
end
