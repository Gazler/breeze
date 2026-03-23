defmodule Breeze.RemoteInspectorTest do
  use ExUnit.Case, async: false

  defmodule InspectorAppView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="button" focusable class="bold">Hello</box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule FakeInspectorServer do
    use GenServer

    def start_link(snapshot) do
      GenServer.start_link(__MODULE__, snapshot)
    end

    def init(snapshot), do: {:ok, snapshot}

    def handle_call(:inspector_snapshot, _from, snapshot) do
      {:reply, snapshot, snapshot}
    end
  end

  test "remote inspector view renders rich snapshot details" do
    theme =
      Breeze.Theme.new(%{
        name: "demo",
        mode: :custom,
        dark: true,
        defaults: %{foreground_color: {1, 2, 3}, background_color: {4, 5, 6}, border_color: 7},
        palette: %{},
        extras: %{}
      })

    snapshot = %{
      root_view: Posting,
      focused: "url",
      last_render_at: 123,
      last_interaction_at: 456,
      theme: theme,
      source: %{node: :app@host, server_pid: self(), view_pid: self()},
      counts: %{elements: 12, focusables: 3, mouse_targets: 9, children: 1},
      focus: %{active_scope: "modal", focusables: ["url"], focus_memory: %{__root__: "url"}},
      selected_id: "url",
      hovered_id: "method",
      selected: %{
        actual_id: "url",
        flags: %{
          :"breeze-component" => "Breeze.Blocks.input",
          focusable: true,
          focused: true,
          class: "input",
          __inspector_idx__: 7
        },
        class: "input",
        component: "Breeze.Blocks.input",
        style_input: "border-rounded",
        style: %{foreground_color: {1, 2, 3}, background_color: {4, 5, 6}},
        viewport: %Breeze.Viewport{
          left: 1,
          top: 2,
          width: 10,
          height: 1,
          viewport_width: 10,
          viewport_height: 1,
          content_width: 10,
          content_height: 1
        },
        bounds: %{left: 1, top: 2, right: 10, bottom: 2},
        content_box: %{left: 1, top: 2, width: 8, height: 1},
        padding: %{top: 0, right: 1, bottom: 0, left: 1},
        scroll: {0, 0},
        focus_meta: %{default_focus: true, focus_scope: :contain, implicit_owner: "form"},
        focus_path: ["form", "url"],
        remembered_focus: %{root: "url"},
        implicit_module: Breeze.Implicit.Input,
        implicit_state: %{cursor: 2, value: "abc", placeholder: "URL"},
        implicit_meta: %{target: "url"},
        fragment_preview: "abc",
        fragment_render: "\e[38;2;1;2;3mabc\e[0m",
        fragment_size: 3
      },
      hovered: %{
        actual_id: "method",
        flags: %{__inspector_idx__: 8}
      }
    }

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            {:app@host, "#PID<0.1.0>"} => %{
              source: %{node: :app@host, pid: self()},
              snapshot: snapshot,
              updated_at: 1_000
            }
          },
          latest_source: {:app@host, "#PID<0.1.0>"},
          screen: %{width: 80, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 80, height: 40}}
      )

    layout_output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            {:app@host, "#PID<0.1.0>"} => %{
              source: %{node: :app@host, pid: self()},
              snapshot: snapshot,
              updated_at: 1_000
            }
          },
          latest_source: {:app@host, "#PID<0.1.0>"},
          panel_tab: "layout",
          screen: %{width: 80, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 80, height: 40}}
      )

    theme_output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            {:app@host, "#PID<0.1.0>"} => %{
              source: %{node: :app@host, pid: self()},
              snapshot: snapshot,
              updated_at: 1_000
            }
          },
          latest_source: {:app@host, "#PID<0.1.0>"},
          panel_tab: "theme",
          screen: %{width: 80, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 80, height: 40}}
      )

    assert output =~ "Remote Inspector"
    assert output =~ "theme=demo mode=custom dark=true"
    assert output =~ "counts=elements=12 focusables=3"
    assert output =~ "mouse_targets=9 children=1"
    assert output =~ "box=viewport=10x1 content=10x1 inner=8x1"
    assert output =~ "padding=0/1/0/1 scroll={0, 0}"
    assert output =~ "component=Breeze.Blocks.input"
    assert output =~ "style_input=\"border-rounded\""
    assert output =~ "fragment_render="
    assert output =~ "\e[38;2;1;2;3mabc\e[0m"
    assert output =~ "FOCUSED"
    assert output =~ "url"
    assert output =~ "(1 focusables)"
    assert layout_output =~ "Attributes"
    assert layout_output =~ "Focus"
    assert layout_output =~ "global"
    assert layout_output =~ "active_scope="
    assert layout_output =~ "selected"
    assert layout_output =~ "focusable=true focused=true"
    assert layout_output =~ "focused: true"
    assert layout_output =~ "class: \"input\""
    assert layout_output =~ "breeze-component"
    assert layout_output =~ "content"
    assert layout_output =~ "8x1"
    assert layout_output =~ "padding"
    assert layout_output =~ "0/1/0/1"
    assert theme_output =~ "Theme"
    assert theme_output =~ "Defaults"
    assert theme_output =~ "background_color #040506"
    assert theme_output =~ "foreground_color #010203"
    assert theme_output =~ "border_color"
    assert theme_output =~ "7"
  end

  test "remote inspector tab changes accept implicit tab payloads" do
    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{panel_tab: "overview"}
    }

    assert {:noreply, %{assigns: %{panel_tab: "layout"}}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{value: "layout"},
               term
             )

    assert {:noreply, %{assigns: %{panel_tab: "focus"}}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{"value" => "focus"},
               term
             )
  end

  test "remote inspector follows the newest live source after a disconnect and reconnect" do
    old_key = {:app@host, "#PID<0.1.0>"}
    new_key = {:app@host, "#PID<0.2.0>"}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          old_key => %{
            source: %{node: :app@host, pid: self()},
            snapshot: %{root_view: InspectorAppView, selected_id: "old"},
            updated_at: 1,
            alive?: false
          },
          new_key => %{
            source: %{node: :app@host, pid: self()},
            snapshot: %{root_view: InspectorAppView, selected_id: "new"},
            updated_at: 2,
            alive?: true
          }
        },
        latest_source: old_key,
        active_source: old_key
      }
    }

    assert {:noreply, %{assigns: %{active_source: ^new_key, latest_source: ^new_key}}} =
             Breeze.RemoteInspector.View.handle_info(
               {:remote_inspector,
                %{
                  snapshots: %{
                    old_key => %{
                      source: %{node: :app@host, pid: self()},
                      snapshot: %{root_view: InspectorAppView, selected_id: "old"},
                      updated_at: 1,
                      alive?: false
                    },
                    new_key => %{
                      source: %{node: :app@host, pid: self()},
                      snapshot: %{root_view: InspectorAppView, selected_id: "new"},
                      updated_at: 2,
                      alive?: true
                    }
                  },
                  latest_source: new_key
                }},
               term
             )
  end

  test "local remote inspector server does not count as a remote delegate" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn ->
      if is_pid(pid) and Process.alive?(pid) and node(pid) == node() do
        GenServer.stop(pid)
      end
    end)

    refute Breeze.RemoteInspector.available?()
  end

  test "publishing to the local server updates subscribers" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    :ok = Breeze.RemoteInspector.subscribe(self())

    snapshot = %{enabled?: true, visible?: true, root_view: Posting, selected_id: "url"}

    Breeze.RemoteInspector.Server.publish(pid, self(), snapshot)

    assert_receive {:remote_inspector, _payload}, 500
    assert_receive {:remote_inspector, %{snapshots: snapshots}}, 500
    assert map_size(snapshots) >= 1
  end

  test "starting the remote inspector server pulls current snapshots from inspector-enabled apps" do
    {:ok, app_pid} =
      FakeInspectorServer.start_link(%{root_view: InspectorAppView, selected_id: "button"})

    :ok = Breeze.RemoteInspector.register_app(app_pid)

    {:ok, inspector_pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn ->
      if Process.alive?(app_pid), do: GenServer.stop(app_pid)

      if Process.alive?(inspector_pid) and node(inspector_pid) == node() do
        GenServer.stop(inspector_pid)
      end
    end)

    Process.sleep(50)

    %{snapshots: snapshots} = Breeze.RemoteInspector.snapshot()

    assert Enum.any?(snapshots, fn {_key, entry} ->
             entry.snapshot.root_view == InspectorAppView
           end)
  end

  test "remote inspector keeps sources and marks them dead when the source pid exits" do
    {:ok, source_pid} =
      FakeInspectorServer.start_link(%{root_view: InspectorAppView, selected_id: "button"})

    {:ok, inspector_pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn ->
      if Process.alive?(source_pid), do: GenServer.stop(source_pid)

      if Process.alive?(inspector_pid) and node(inspector_pid) == node() do
        GenServer.stop(inspector_pid)
      end
    end)

    Breeze.RemoteInspector.Server.publish(
      inspector_pid,
      source_pid,
      %{root_view: InspectorAppView, selected_id: "button"}
    )

    Process.sleep(20)
    GenServer.stop(source_pid)
    Process.sleep(20)

    %{snapshots: snapshots} = Breeze.RemoteInspector.snapshot()
    key = {node(source_pid), inspect(source_pid)}

    assert %{alive?: false, snapshot: %{root_view: InspectorAppView}} = snapshots[key]
  end
end
