defmodule Breeze.RemoteInspectorTest do
  use ExUnit.Case, async: false

  import Breeze.TestSupport.WaitUntil

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

  defmodule CustomInspectorPage do
    @behaviour Breeze.RemoteInspector.Page

    use Breeze.View

    def page, do: [id: "llm", label: "LLM", render_tree: true, note: "module-default"]

    def render(assigns) do
      ~H"""
      <box id="custom-inspector-page" class="width-full height-full">
        page={@id} label={@label} selected={snapshot_selected(@snapshot)} hovered={snapshot_hovered(@snapshot)} config={@config.note} static={@static} tree={tree_selected(@render_tree)}
      </box>
      """
    end

    defp snapshot_selected(%{selected_id: selected_id}), do: selected_id || "-"
    defp snapshot_selected(_snapshot), do: "-"

    defp snapshot_hovered(%{hovered_id: hovered_id}), do: hovered_id || "-"
    defp snapshot_hovered(_snapshot), do: "-"

    defp tree_selected(%{selected_id: selected_id}), do: selected_id || "-"
    defp tree_selected(_render_tree), do: "-"
  end

  defmodule InteractiveInspectorPage do
    @behaviour Breeze.RemoteInspector.Page

    use Breeze.View

    def page, do: [id: "chat", label: "Chat"]

    def render(assigns) do
      assigns =
        Map.merge(%{prompt: "-", info: "-", count: 0, custom_page_error: "-"}, assigns)

      ~H"""
      <box id="interactive-inspector-page" class="width-full height-full">
        prompt={@prompt} info={@info} count={@count} error={@custom_page_error}
      </box>
      """
    end

    def handle_event("interactive_prompt_changed", payload, assigns) do
      value = Map.get(payload, :value) || Map.get(payload, "value")

      {:noreply,
       %{
         prompt: value,
         info: Map.get(assigns, :info, "-"),
         count: Map.get(assigns, :count, 0) + 1
       }}
    end

    def handle_event(_event, _payload, _assigns), do: :noreply

    def handle_info({:done, value}, assigns) do
      {:noreply,
       %{
         prompt: Map.get(assigns, :prompt, "-"),
         info: value,
         count: Map.get(assigns, :count, 0)
       }}
    end
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

  defmodule SelectCaptureServer do
    use GenServer

    def start_link(parent) do
      GenServer.start_link(__MODULE__, parent)
    end

    def init(parent), do: {:ok, parent}

    def handle_cast({:select_inspector, id}, parent) do
      send(parent, {:selected_inspector, id})
      {:noreply, parent}
    end

    def handle_cast({:select_inspector_timeline, selected}, parent) do
      send(parent, {:selected_timeline, selected})
      {:noreply, parent}
    end

    def handle_call({:inspector_render_tree, opts}, _from, parent) do
      send(parent, {:inspector_render_tree, opts})
      kind = Keyword.get(opts, :kind, :rendered)
      child_label = if kind == :code, do: "<Breeze.Blocks.input#child>", else: "<box#child>"

      {:reply,
       %{
         kind: kind,
         nodes: [
           %{
             id: "root",
             label: "<box#root>",
             children: [%{id: "child", label: child_label, children: []}]
           }
         ],
         selected_id: Keyword.get(opts, :selected_id),
         expanded: Keyword.get(opts, :expanded, []),
         limit: Keyword.get(opts, :limit),
         truncated?: false
       }, parent}
    end
  end

  test "remote inspector pages are configurable and reserve built-in page ids" do
    assert [
             %{
               id: "llm",
               label: "Tools",
               module: CustomInspectorPage,
               assigns: %{static: "extra"},
               config: %{note: "config", render_tree: true}
             }
           ] =
             Breeze.RemoteInspector.normalize_pages([
               {CustomInspectorPage,
                id: "llm", label: "Tools", note: "config", assigns: [static: "extra"]},
               {CustomInspectorPage, id: "tree", label: "Reserved"},
               {CustomInspectorPage, id: "llm", label: "Duplicate"}
             ])

    previous = Application.get_env(:breeze, :remote_inspector_pages)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:breeze, :remote_inspector_pages)
        value -> Application.put_env(:breeze, :remote_inspector_pages, value)
      end
    end)

    Application.put_env(:breeze, :remote_inspector_pages, {CustomInspectorPage, id: "agent"})

    assert [%{id: "agent", label: "LLM"}] = Breeze.RemoteInspector.pages()
  end

  test "remote inspector view combines configured and supplied pages" do
    previous = Application.get_env(:breeze, :remote_inspector_pages)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:breeze, :remote_inspector_pages)
        value -> Application.put_env(:breeze, :remote_inspector_pages, value)
      end
    end)

    Application.put_env(
      :breeze,
      :remote_inspector_pages,
      {CustomInspectorPage, id: "configured", label: "Config"}
    )

    key = {:app@host, "#PID<0.1.0>"}

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              snapshot: inspector_snapshot(self(), "button"),
              updated_at: 1_000,
              alive?: true
            }
          },
          latest_source: key,
          active_source: key,
          panel_tab: "llm",
          remote_inspector_pages: [
            {CustomInspectorPage,
             id: "llm", label: "LLM", note: "config", assigns: %{static: "extra"}}
          ],
          render_trees: %{},
          render_tree_expanded: %{},
          timeline_selected: %{},
          screen: %{width: 100, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert output =~ " Config "
    assert output =~ "label=LLM"
    assert output =~ "page=llm"
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
      render_tree: %{
        id: "root",
        label: "<box#root.panel>",
        children: [
          %{
            id: "url",
            label: "<box#url.input> Breeze.Blocks.input",
            label_parts: [
              %{text: "<", token: :punctuation},
              %{text: "box", token: :tag},
              %{text: "#url", token: :id},
              %{text: ".input", token: :class},
              %{text: ".text-primary", token: :class},
              %{
                text: "●",
                token: :swatch,
                role: :foreground,
                foreground_color: {1, 2, 3},
                background_color: nil
              },
              %{text: ".bg-panel", token: :class},
              %{
                text: "●",
                token: :swatch,
                role: :background,
                foreground_color: {4, 5, 6},
                background_color: nil
              },
              %{text: ">", token: :punctuation},
              %{text: " Breeze.Blocks.input", token: :component}
            ],
            children: []
          },
          %{id: "method", label: "<box#method>", children: []}
        ]
      },
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

    tree_output =
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
          panel_tab: "tree",
          screen: %{width: 140, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 140, height: 40}}
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
    assert tree_output =~ "Tree"
    assert tree_output =~ "<box#root.panel>"

    stripped_tree_output = Regex.replace(~r/\e\[[0-9;]*m/, tree_output, "")

    assert stripped_tree_output =~ "<box#url.input.text-primary●.bg-panel●> Breeze.Blocks.input"
    assert tree_output =~ "●"
    assert tree_output =~ "38;2;1;2;3"
    assert tree_output =~ "38;2;4;5;6"
  end

  test "remote inspector view renders custom pages with active snapshot context" do
    key = {:app@host, "#PID<0.1.0>"}

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              snapshot: inspector_snapshot(self(), "button"),
              updated_at: 1_000,
              alive?: true
            }
          },
          latest_source: key,
          active_source: key,
          panel_tab: "llm",
          remote_inspector_pages: [
            {CustomInspectorPage,
             id: "llm", label: "LLM", note: "config", assigns: %{static: "extra"}}
          ],
          render_trees: %{
            key => %{
              nodes: [%{id: "root", label: "<box#root>", children: []}],
              selected_id: "button",
              expanded: [],
              limit: 600,
              truncated?: false
            }
          },
          render_tree_expanded: %{},
          timeline_selected: %{},
          screen: %{width: 100, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert output =~ " LLM "
    assert output =~ "page=llm"
    assert output =~ "label=LLM"
    assert output =~ "selected=button"
    assert output =~ "hovered=hover"
    assert output =~ "config=config"
    assert output =~ "static=extra"
    assert output =~ "tree=button"
  end

  test "remote inspector custom pages can handle events and async messages" do
    key = {:app@host, "#PID<0.1.0>"}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: self()},
            snapshot: inspector_snapshot(self(), "button"),
            updated_at: 1_000,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        panel_tab: "chat",
        remote_inspector_pages: [InteractiveInspectorPage],
        render_tree_kind: "rendered",
        render_trees: %{},
        render_tree_expanded: %{},
        timeline_selected: %{},
        custom_page_states: %{},
        screen: %{width: 100, height: 32}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(
               "interactive_prompt_changed",
               %{value: "hello"},
               term
             )

    assert term.assigns.custom_page_states["chat"].prompt == "hello"
    assert term.assigns.custom_page_states["chat"].count == 1

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_info(
               {:remote_inspector_page, "chat", {:done, "ok"}},
               term
             )

    assert term.assigns.custom_page_states["chat"].prompt == "hello"
    assert term.assigns.custom_page_states["chat"].info == "ok"

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        term.assigns,
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert output =~ " Chat "
    assert output =~ "prompt=hello"
    assert output =~ "info=ok"
    assert output =~ "count=1"
  end

  test "sample LLM page renders active app context" do
    key = {:app@host, "#PID<0.1.0>"}

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              snapshot: inspector_snapshot(self(), "button"),
              updated_at: 1_000,
              alive?: true
            }
          },
          latest_source: key,
          active_source: key,
          panel_tab: "llm",
          remote_inspector_pages: [Breeze.RemoteInspector.Pages.LLM],
          render_trees: %{
            key => %{
              kind: :rendered,
              nodes: [
                %{
                  id: "root",
                  label: "<box#root>",
                  children: [%{id: "button", label: "<box#button>", children: []}]
                }
              ],
              selected_id: "button",
              expanded: ["root"],
              limit: 600,
              truncated?: false
            }
          },
          render_tree_expanded: %{},
          timeline_selected: %{},
          screen: %{width: 100, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert output =~ "LLM Context"
    assert output =~ "root_view=Breeze.RemoteInspectorTest.InspectorAppView"
    assert output =~ "selected=id=button"
    assert output =~ "Render Tree"
    assert output =~ "<box#button>"
  end

  test "remote inspector custom pages can request render tree data" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      stop_process(source_pid)
    end)

    key = {:app@host, inspect(source_pid)}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: source_pid},
            snapshot: inspector_snapshot(source_pid, "child"),
            updated_at: 1,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        panel_tab: "overview",
        remote_inspector_pages: [{CustomInspectorPage, id: "llm", label: "LLM"}],
        render_tree_kind: "rendered",
        render_tree_expanded: %{key => ["root"]},
        render_trees: %{},
        timeline_selected: %{}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event("tab_changed", %{value: "llm"}, term)

    assert term.assigns.panel_tab == "llm"
    assert term.assigns.render_trees[key].selected_id == "child"
    assert_receive {:inspector_render_tree, opts}, 500
    assert Keyword.get(opts, :kind) == :rendered
    assert Keyword.get(opts, :selected_id) == "child"
  end

  test "remote inspector tab changes accept implicit tab payloads" do
    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        panel_tab: "overview",
        snapshots: %{},
        latest_source: nil,
        active_source: nil,
        render_tree_expanded: %{},
        render_trees: %{},
        timeline_selected: %{}
      }
    }

    assert {:noreply, %{assigns: %{panel_tab: "layout"}}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{value: "layout"},
               term
             )

    assert {:noreply, %{assigns: %{panel_tab: "tree"}, local_keybindings: tree_keybindings}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{value: "tree"},
               term
             )

    assert [%{key: "t", label: "Code tree"}] = Breeze.Keybindings.visible(tree_keybindings)

    assert {:noreply, %{assigns: %{panel_tab: "focus"}}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{"value" => "focus"},
               term
             )

    assert {:noreply, %{assigns: %{panel_tab: "layout"}, local_keybindings: []}} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{"value" => "layout"},
               %{term | local_keybindings: tree_keybindings}
             )
  end

  test "remote inspector timeline tab can select a historical snapshot" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      stop_process(source_pid)
    end)

    key = {:app@host, inspect(source_pid)}

    base_snapshot = %{
      root_view: InspectorAppView,
      source: %{node: :app@host, server_pid: source_pid, view_pid: source_pid},
      theme: nil,
      counts: %{elements: 1, focusables: 1, mouse_targets: 1, children: 0},
      focus: %{active_scope: nil, focusables: ["button"], focus_memory: %{}},
      selected: nil,
      hovered: nil,
      selected_id: "live",
      hovered_id: nil,
      focused: "live-focus",
      last_render_at: 1_000,
      last_interaction_at: 900,
      render_tree?: false
    }

    historical_snapshot = %{
      base_snapshot
      | selected_id: "past",
        focused: "past-focus"
    }

    snapshot =
      Map.put(base_snapshot, :timeline, %{
        enabled?: true,
        count: 1,
        next_id: 2,
        frame: %{width: 20, height: 1, lines: ["LIVE FRAME"]},
        entries: [
          %{
            id: 1,
            kind: :input,
            detail: "input: %{focused: \"past\"}",
            frame: %{width: 20, height: 1, lines: ["PAST FRAME"]},
            snapshot: historical_snapshot
          }
        ]
      })

    assigns = %{
      snapshots: %{
        key => %{
          source: %{node: :app@host, pid: source_pid},
          snapshot: snapshot,
          updated_at: 1_000,
          alive?: true
        }
      },
      latest_source: key,
      active_source: key,
      panel_tab: "timeline",
      render_tree_expanded: %{},
      render_trees: %{},
      timeline_selected: %{}
    }

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        Map.put(assigns, :screen, %{width: 100, height: 32}),
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert output =~ "Timeline"
    assert output =~ "timeline=enabled entries=1 selected=latest"
    assert output =~ "#1 input"
    refute output =~ "LIVE FRAME"
    assert timeline_tree_loop_disabled?(assigns)

    term = %Breeze.Term{view: Breeze.RemoteInspector.View, assigns: assigns}

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event("timeline_changed", %{value: "1"}, term)

    assert term.assigns.timeline_selected[key] == "1"
    assert_receive {:selected_timeline, "1"}, 500

    historical_output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        assigns
        |> Map.put(:timeline_selected, %{key => "1"})
        |> Map.put(:screen, %{width: 100, height: 32}),
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 100, height: 40}}
      )

    assert historical_output =~ "past-focus"
    assert historical_output =~ "past"
    assert historical_output =~ "timeline=enabled entries=1 selected=1"
    refute historical_output =~ "PAST FRAME"

    assert {:stop, _term} =
             Breeze.RemoteInspector.View.quit(:quit, %{
               term
               | assigns: Map.put(term.assigns, :timeline_selected, %{key => "1"})
             })

    assert_receive {:selected_timeline, "latest"}, 500
  end

  defp timeline_tree_loop_disabled?(assigns) do
    assigns = Map.put(assigns, :screen, %{width: 100, height: 32})

    Breeze.RemoteInspector.View.render(assigns)
    |> Breeze.Template.render_to_tree(assigns)
    |> tree_with_attrs?(%{"id" => "remote-inspector-timeline", "tree-loop" => "false"})
  end

  defp tree_with_attrs?({tag, _, children}, attrs) when is_atom(tag) do
    node_attrs =
      children
      |> Enum.flat_map(fn
        {:attribute, [key, value]} -> [{key, value}]
        {:attribute_bool, [key]} -> [{key, true}]
        _ -> []
      end)
      |> Map.new()

    attrs_match? =
      Enum.all?(attrs, fn {key, value} ->
        Map.get(node_attrs, key) == value
      end)

    attrs_match? or tree_with_attrs?(children, attrs)
  end

  defp tree_with_attrs?(nodes, attrs) when is_list(nodes) do
    Enum.any?(nodes, &tree_with_attrs?(&1, attrs))
  end

  defp tree_with_attrs?(_node, _attrs), do: false

  defp stop_process(pid) when is_pid(pid) do
    try do
      if Process.alive?(pid), do: GenServer.stop(pid)
    catch
      :exit, _reason -> :ok
    end
  end

  defp stop_process(_pid), do: :ok

  defp stop_local_process(pid) when is_pid(pid) do
    if node(pid) == node(), do: stop_process(pid)
  end

  defp stop_local_process(_pid), do: :ok

  defp inspector_snapshot(pid, selected_id) do
    %{
      root_view: InspectorAppView,
      source: %{node: :app@host, server_pid: pid, view_pid: pid},
      theme: nil,
      counts: %{elements: 1, focusables: 1, mouse_targets: 1, children: 0},
      focus: %{active_scope: nil, focusables: [selected_id], focus_memory: %{}},
      selected: nil,
      hovered: nil,
      selected_id: selected_id,
      hovered_id: "hover",
      focused: selected_id,
      last_render_at: 1_000,
      last_interaction_at: 900,
      render_tree?: true
    }
  end

  test "remote inspector render tree selection updates expansion and delegates selection" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      stop_process(source_pid)
    end)

    key = {:app@host, inspect(source_pid)}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: source_pid},
            snapshot: %{
              source: %{node: :app@host, server_pid: source_pid, view_pid: source_pid},
              selected_id: "root",
              render_tree: %{
                id: "root",
                label: "<box#root>",
                children: [%{id: "child", label: "<box#child>", children: []}]
              }
            },
            updated_at: 1,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        render_tree_expanded: %{},
        render_trees: %{}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(
               "render_tree_changed",
               %{value: "child", expanded: ["root"]},
               term
             )

    assert term.assigns.render_tree_expanded[key] == ["root"]
    assert term.assigns.render_trees[key].selected_id == "child"
    assert_receive {:selected_inspector, "child"}, 500
    assert_receive {:inspector_render_tree, opts}, 500
    assert Keyword.get(opts, :selected_id) == "child"
    assert Keyword.get(opts, :expanded) == ["root"]
    assert Keyword.get(opts, :kind) == :rendered
  end

  test "remote inspector t key toggles the tree between rendered and code modes" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      stop_process(source_pid)
    end)

    key = {:app@host, inspect(source_pid)}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: source_pid},
            snapshot: %{
              source: %{node: :app@host, server_pid: source_pid, view_pid: source_pid},
              selected_id: "child",
              render_tree?: true
            },
            updated_at: 1,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        panel_tab: "tree",
        render_tree_kind: "rendered",
        render_tree_expanded: %{key => ["root"]},
        render_trees: %{}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(:ignored, %{"key" => "t"}, term)

    assert term.assigns.panel_tab == "tree"
    assert term.assigns.render_tree_kind == "code"

    assert %{kind: :code, selected_id: "child", nodes: [%{children: [child]}]} =
             term.assigns.render_trees[{key, "code"}]

    assert child.label == "<Breeze.Blocks.input#child>"

    assert_receive {:inspector_render_tree, opts}, 500
    assert Keyword.get(opts, :kind) == :code
    assert Keyword.get(opts, :selected_id) == "child"
  end

  test "remote inspector render tree scroll changes stay local" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      stop_process(source_pid)
    end)

    key = {:app@host, inspect(source_pid)}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: source_pid},
            snapshot: %{
              source: %{node: :app@host, server_pid: source_pid, view_pid: source_pid},
              selected_id: "child",
              render_tree?: true
            },
            updated_at: 1,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        render_tree_expanded: %{key => ["root"]},
        render_trees: %{
          key => %{
            nodes: [
              %{
                id: "root",
                label: "<box#root>",
                children: [%{id: "child", label: "<box#child>", children: []}]
              }
            ],
            selected_id: "child",
            expanded: ["root"],
            limit: 600,
            truncated?: false
          }
        }
      }
    }

    assert {:noreply, ^term} =
             Breeze.RemoteInspector.View.handle_event(
               "render_tree_changed",
               %{value: "child", expanded: ["root"], offset: 12},
               term
             )

    refute_receive {:selected_inspector, _id}, 50
    refute_receive {:inspector_render_tree, _opts}, 50
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
      stop_local_process(pid)
    end)

    refute Breeze.RemoteInspector.available?()
  end

  test "distribution names default for apps and the remote inspector" do
    assert Breeze.RemoteInspector.default_distribution_name(:inspector) == :inspector
    assert Breeze.RemoteInspector.default_distribution_name(:app, []) == :app

    assert Breeze.RemoteInspector.default_distribution_name(:app,
             view: Breeze.RemoteInspector.View
           ) == :breeze
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
      stop_process(app_pid)
      stop_local_process(inspector_pid)
    end)

    wait_until(fn ->
      %{snapshots: snapshots} = Breeze.RemoteInspector.Server.snapshot(inspector_pid)

      Enum.any?(snapshots, fn {_key, entry} ->
        entry.snapshot.root_view == InspectorAppView
      end)
    end)
  end

  test "remote inspector keeps sources and marks them dead when the source pid exits" do
    {:ok, source_pid} =
      FakeInspectorServer.start_link(%{root_view: InspectorAppView, selected_id: "button"})

    {:ok, inspector_pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn ->
      stop_process(source_pid)
      stop_local_process(inspector_pid)
    end)

    Breeze.RemoteInspector.Server.publish(
      inspector_pid,
      source_pid,
      %{root_view: InspectorAppView, selected_id: "button"}
    )

    key = {node(source_pid), inspect(source_pid)}

    assert %{alive?: true, snapshot: %{root_view: InspectorAppView}} =
             Breeze.RemoteInspector.Server.snapshot(inspector_pid).snapshots[key]

    GenServer.stop(source_pid)

    wait_until(fn ->
      %{snapshots: snapshots} = Breeze.RemoteInspector.Server.snapshot(inspector_pid)

      match?(%{alive?: false, snapshot: %{root_view: InspectorAppView}}, snapshots[key])
    end)
  end
end
