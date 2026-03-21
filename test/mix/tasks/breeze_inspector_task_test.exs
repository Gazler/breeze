defmodule Mix.Tasks.BreezeInspectorTaskTest do
  use ExUnit.Case, async: true

  test "run opts enable reload and disable nested inspector" do
    assert Mix.Tasks.Breeze.Inspector.run_opts() == [
             view: Breeze.RemoteInspector.View,
             reload: true,
             mouse: true,
             inspector: false
           ]
  end

  test "normalize_connect_target keeps explicit host" do
    assert Mix.Tasks.Breeze.Inspector.normalize_connect_target("app@host.example") ==
             :"app@host.example"
  end

  test "normalize_connect_target expands short name with current host" do
    host =
      case String.split(to_string(node()), "@", parts: 2) do
        [_name, current_host] when current_host != "" ->
          current_host

        _ ->
          case :inet.gethostname() do
            {:ok, hostname} -> to_string(hostname)
            _ -> "localhost"
          end
      end

    assert Mix.Tasks.Breeze.Inspector.normalize_connect_target("app") ==
             String.to_atom("app@#{host}")
  end
end
