defmodule Breeze.RemoteInspector.LogsTest do
  use ExUnit.Case, async: true

  alias BackBreeze.TextLayout
  alias BackBreeze.VirtualText
  alias Breeze.RemoteInspector.Logs

  test "builds a lazy virtual source and only slices visible wrapped lines" do
    key = {:app@host, "#PID<0.2.0>"}

    logs = %{
      key => %{
        source: %{node: :app@host, pid: self()},
        entries: [
          %{level: :error, line: "abcdefghij"},
          %{level: :warning, line: "warn"}
        ],
        updated_at: 10
      }
    }

    sources = Logs.build_sources(logs)
    assert %VirtualText{cache?: false} = content = Logs.content(sources, key)

    prepared = TextLayout.prepare(content, 4, :scroll, 3)

    assert prepared.raw_line_count == 4

    assert [[{"efgh", %{foreground_color: 1}}], [{"ij", %{foreground_color: 1}}]] =
             TextLayout.visible_lines(prepared, 1, 2)
  end

  test "matches a collector log stream to the selected server node" do
    selected_server = {:app@host, "#PID<0.4.0>"}
    collector = {:app@host, "#PID<0.5.0>"}

    logs = %{
      collector => %{
        source: %{node: :app@host, pid: self()},
        entries: [],
        updated_at: 20
      }
    }

    assert Logs.source(logs, selected_server) == collector
  end

  test "logs panel occupies the inspector body alongside the source sidebar" do
    key = {:app@host, "#PID<0.6.0>"}

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{},
          latest_source: nil,
          panel_tab: "logs",
          logs: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              entries: [%{level: :info, line: "captured log line"}],
              updated_at: 30
            }
          },
          screen: %{width: 60, height: 14}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 60, height: 14}}
      )

    assert output =~ "captured log line"
    assert output =~ "Remote Inspector"
  end
end
