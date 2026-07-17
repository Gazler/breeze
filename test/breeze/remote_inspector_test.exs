defmodule Breeze.RemoteInspectorTest do
  use ExUnit.Case, async: true

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

  defmodule FakeInspectorServer do
    use GenServer

    def start_link(snapshot) do
      GenServer.start_link(__MODULE__, snapshot)
    end

    def init(snapshot), do: {:ok, snapshot}

    def handle_call(:inspector_snapshot, _from, snapshot) do
      {:reply, snapshot, snapshot}
    end

    def handle_call({:inspector_render_tree, opts}, _from, snapshot) do
      selected_id = Keyword.get(opts, :selected_id, Map.get(snapshot, :selected_id))

      {:reply,
       %{
         kind: Keyword.get(opts, :kind, :rendered),
         nodes: [%{id: "root", label: "<box#root>", children: []}],
         selected_id: selected_id,
         expanded: Keyword.get(opts, :expanded, []),
         limit: Keyword.get(opts, :limit, 600),
         truncated?: false
       }, snapshot}
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

  defmodule SnapshotCaptureServer do
    use GenServer

    def start_link(parent) do
      GenServer.start_link(__MODULE__, parent)
    end

    def init(parent), do: {:ok, parent}

    def handle_cast({:snapshot, source_pid, snapshot}, parent) do
      send(parent, {:captured_snapshot, source_pid, snapshot})
      {:noreply, parent}
    end
  end

  defmodule ThemeTabView do
    use Breeze.View
    import Breeze.RemoteInspector.View, only: [theme_tab: 1]

    def mount(_opts, term) do
      rows =
        Enum.map(1..12, fn index ->
          %{
            class: "width-full",
            style: nil,
            text: if(index == 12, do: "LAST PALETTE SWATCH", else: "palette row #{index}")
          }
        end)

      {:ok, term |> assign(rows: rows) |> focus("theme-scroll")}
    end

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen overflow-hidden">
        <.theme_tab active={true} scroll_id="theme-scroll" active_theme_text="demo" rows={@rows}/>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule CustomInspectorPage do
    use Breeze.RemoteInspector.Page

    def page(_opts),
      do: [label: "Debugger", assigns: [note: "configured", static: "extra"]]

    def render(assigns) do
      snapshot = Breeze.RemoteInspector.Page.request!(assigns, :snapshot)

      render_tree =
        Breeze.RemoteInspector.Page.request!(assigns, :render_tree,
          selected_id: snapshot.selected_id
        )

      lean_context? =
        Enum.all?(
          [:active, :active_source, :snapshot, :selected, :hovered, :snapshots, :render_tree],
          &(not Map.has_key?(assigns, &1))
        )

      assigns =
        Map.merge(assigns, %{
          requested_snapshot: snapshot,
          requested_render_tree: render_tree,
          lean_context?: lean_context?
        })

      ~H"""
      <box id="custom-inspector-page" class="width-full height-full">
        page={@id} selected={selected_id(@requested_snapshot)} note={@note} static={@static} tree={tree_selected(@requested_render_tree)} terminal={@breeze.terminal.height} lean={@lean_context?}
      </box>
      """
    end

    defp selected_id(%{selected_id: selected_id}), do: selected_id || "-"
    defp selected_id(_snapshot), do: "-"
    defp tree_selected(%{selected_id: selected_id}), do: selected_id || "-"
    defp tree_selected(_tree), do: "-"
  end

  defmodule ConfigurableInspectorPage do
    use Breeze.RemoteInspector.Page

    def page(opts) do
      [
        label: Keyword.get(opts, :label, "Configured"),
        assigns: [mode: Keyword.get(opts, :mode, :default)],
        runtime_hooks: Keyword.get(opts, :runtime_hooks, [])
      ]
    end

    def render(assigns), do: ~H"<box>Configured</box>"
  end

  defmodule InteractiveInspectorPage do
    use Breeze.RemoteInspector.Page

    def page(_opts), do: [label: "Chat"]

    def render(assigns) do
      assigns = Map.merge(%{prompt: "-", info: "-", count: 0}, assigns)

      ~H"""
      <box id="interactive-inspector-page">prompt={@prompt} info={@info} count={@count}</box>
      """
    end

    def handle_event("prompt_changed", payload, assigns) do
      value = Map.get(payload, :value) || Map.get(payload, "value")

      {:noreply,
       %{
         prompt: value,
         info: Map.get(assigns, :info, "-"),
         count: Map.get(assigns, :count, 0) + 1
       }}
    end

    def handle_event(event, payload, assigns)
        when event in ["tab_changed", "render_tree_changed"] do
      value = Map.get(payload, :value) || Map.get(payload, "value")

      {:noreply,
       %{
         prompt: "#{event}:#{value}",
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

  defmodule FailingInspectorPage do
    use Breeze.RemoteInspector.Page

    def page(_opts), do: [label: "Failure"]

    def render(_assigns), do: raise("render exploded")

    def handle_event("throw", _payload, _assigns), do: throw(:callback_exploded)
  end

  defmodule InvalidInspectorPage do
    use Breeze.RemoteInspector.Page

    def page(_opts), do: [label: "Invalid", unknown: true]
    def render(assigns), do: ~H"<box>Invalid</box>"
  end

  defmodule MissingPageDeclaration do
    use Breeze.Component

    def render(assigns), do: ~H"<box>Missing declaration</box>"
  end

  defmodule MissingPageLabel do
    use Breeze.RemoteInspector.Page

    def page(_opts), do: [assigns: %{ready?: true}]
    def render(assigns), do: ~H"<box>Missing label</box>"
  end

  test "remote inspector pages use module identity and page-owned metadata" do
    page_id = page_id(CustomInspectorPage)

    assert [
             %{
               id: ^page_id,
               label: "Debugger",
               module: CustomInspectorPage,
               assigns: %{note: "configured", static: "extra"}
             }
           ] =
             Breeze.RemoteInspector.Pages.build([
               CustomInspectorPage,
               CustomInspectorPage
             ])
  end

  test "configured pages contribute runtime hooks without publishing them" do
    configured = [
      {ConfigurableInspectorPage,
       label: "Timeline", mode: :compact, runtime_hooks: [ExampleRuntimeHook]}
    ]

    assert [
             %{
               label: "Timeline",
               module: ConfigurableInspectorPage,
               assigns: %{mode: :compact}
             }
           ] = Breeze.RemoteInspector.Pages.build(configured)

    assert [ExampleRuntimeHook] = Breeze.RemoteInspector.Pages.runtime_hooks(configured)
  end

  test "remote inspector page declarations reject unsupported shapes" do
    assert_raise ArgumentError, ~r/expected :pages to be a list/, fn ->
      Breeze.RemoteInspector.Pages.build(CustomInspectorPage)
    end

    assert_raise ArgumentError, ~r/unknown .*\.page\/1 keys: \[:unknown\]/, fn ->
      Breeze.RemoteInspector.Pages.build([InvalidInspectorPage])
    end

    assert_raise ArgumentError, ~r/expected .* to define page\/1/, fn ->
      Breeze.RemoteInspector.Pages.build([MissingPageDeclaration])
    end

    assert_raise ArgumentError, ~r/page\/1 to define a non-empty :label/, fn ->
      Breeze.RemoteInspector.Pages.build([MissingPageLabel])
    end
  end

  test "page state cannot replace host-owned context" do
    scope = {:app@host, "#PID<0.1.0>"}
    page_id = page_id(CustomInspectorPage)

    page = %{
      id: page_id,
      label: "Tools",
      module: CustomInspectorPage,
      assigns: %{
        source_server_pid: :static_source,
        breeze: :static_breeze,
        id: "static-id",
        page_ref: :static_ref,
        value: :static
      }
    }

    context = %{
      source_server_pid: self(),
      breeze: %{terminal: %{height: 40}},
      page_state_scope: scope,
      page_states: %{
        {scope, page_id} => %{
          source_server_pid: :state_source,
          breeze: :state_breeze,
          id: "state-id",
          label: "State label",
          page: :state_page,
          page_ref: :state_ref,
          value: :state
        }
      }
    }

    assigns = Breeze.RemoteInspector.PageHost.page_assigns(page, context)

    assert assigns.source_server_pid == self()
    assert assigns.breeze == context.breeze
    assert assigns.id == page_id
    assert assigns.label == "Tools"
    assert assigns.page == page
    assert assigns.page_ref == {scope, page_id}
    assert assigns.value == :state
  end

  test "app-discovered pages stay visible when their module is unavailable locally" do
    missing_page = Module.concat([MissingRemoteInspectorPage])
    page_id = page_id(missing_page)

    descriptor = %{
      label: "Timeline",
      module: missing_page,
      assigns: %{}
    }

    assert [
             %{
               id: ^page_id,
               label: "Timeline",
               module: ^missing_page,
               assigns: %{}
             }
           ] = Breeze.RemoteInspector.Pages.validate_discovered([descriptor])

    key = {:app@host, "#PID<0.1.0>"}

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              snapshot:
                inspector_snapshot(self(), "button")
                |> Map.put(:pages, [descriptor]),
              updated_at: 1_000,
              alive?: true
            }
          },
          latest_source: key,
          active_source: key,
          panel_tab: page_id,
          render_tree_kind: "rendered",
          render_trees: %{},
          render_tree_expanded: %{},
          custom_page_states: %{},
          breeze: %{terminal: %{width: 140, height: 40}},
          screen: %{width: 140, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 140, height: 40}}
      )

    assert output =~ "Timeline"
    assert output =~ "is unavailable on this inspector node"
  end

  test "page render and callback failures are isolated and reported" do
    scope = {:app@host, "#PID<0.1.0>"}
    [page] = Breeze.RemoteInspector.Pages.build([FailingInspectorPage])

    active = %{
      snapshot:
        inspector_snapshot(self(), "button")
        |> Map.put(:pages, [page])
    }

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        active_source: scope,
        panel_tab: page.id,
        custom_page_states: %{}
      }
    }

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.PageHost,
        %{
          page: page,
          context: Breeze.RemoteInspector.PageHost.context(term.assigns, active, scope)
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 80, height: 24}}
      )

    assert output =~ "remote inspector page failed: render exploded"

    assert {:noreply, term} =
             Breeze.RemoteInspector.PageHost.delegate_event("throw", %{}, term, active)

    assert term.assigns.custom_page_states[{scope, page.id}].custom_page_error ==
             "remote inspector page failed: {:throw, :callback_exploded}"
  end

  test "app connector retries and publishes the current snapshot without app interaction" do
    snapshot = %{root_view: InspectorAppView, selected_id: "button"}
    {:ok, app_pid} = FakeInspectorServer.start_link(snapshot)
    {:ok, inspector_pid} = SnapshotCaptureServer.start_link(self())
    {:ok, resolver_state} = Agent.start_link(fn -> :retry end)
    {:ok, supervisor} = Breeze.RemoteInspector.Supervisor.start_link()

    {:ok, connector_pid} =
      Breeze.RemoteInspector.Supervisor.start_connector(supervisor, app_pid,
        retry_interval: 5,
        resolver: fn -> Agent.get(resolver_state, & &1) end
      )

    connector_ref = Process.monitor(connector_pid)

    assert connector_pid in supervised_pids(supervisor)

    refute_receive {:captured_snapshot, ^app_pid, _snapshot}, 20

    Agent.update(resolver_state, fn _state -> {:ok, inspector_pid} end)

    assert_receive {:captured_snapshot, ^app_pid, ^snapshot}, 200

    GenServer.stop(app_pid)
    assert_receive {:DOWN, ^connector_ref, :process, ^connector_pid, :normal}, 200

    GenServer.stop(inspector_pid)
    Agent.stop(resolver_state)
    Breeze.RemoteInspector.Supervisor.stop(supervisor)
  end

  test "app connector retries failed initial snapshot reads and publications" do
    snapshot = %{root_view: InspectorAppView, selected_id: "button"}
    {:ok, app_pid} = FakeInspectorServer.start_link(snapshot)
    {:ok, inspector_pid} = SnapshotCaptureServer.start_link(self())
    {:ok, attempts} = Agent.start_link(fn -> %{reads: 0, publications: 0} end)
    {:ok, supervisor} = Breeze.RemoteInspector.Supervisor.start_link()

    snapshot_reader = fn pid ->
      attempt =
        Agent.get_and_update(attempts, fn state ->
          attempt = state.reads + 1
          {attempt, %{state | reads: attempt}}
        end)

      if attempt == 1 do
        exit({:timeout, :inspector_snapshot})
      else
        Breeze.Server.Diagnostics.inspector_snapshot(pid)
      end
    end

    publisher = fn target_pid, source_pid, current_snapshot ->
      attempt =
        Agent.get_and_update(attempts, fn state ->
          attempt = state.publications + 1
          {attempt, %{state | publications: attempt}}
        end)

      if attempt == 1 do
        exit(:publication_failed)
      else
        Breeze.RemoteInspector.Server.publish(target_pid, source_pid, current_snapshot)
      end
    end

    {:ok, connector_pid} =
      Breeze.RemoteInspector.Supervisor.start_connector(supervisor, app_pid,
        retry_interval: 5,
        resolver: fn -> {:ok, inspector_pid} end,
        snapshot_reader: snapshot_reader,
        publisher: publisher
      )

    connector_ref = Process.monitor(connector_pid)

    assert_receive {:captured_snapshot, ^app_pid, ^snapshot}, 200
    assert Agent.get(attempts, & &1) == %{reads: 3, publications: 2}

    GenServer.stop(app_pid)
    assert_receive {:DOWN, ^connector_ref, :process, ^connector_pid, :normal}, 200

    GenServer.stop(inspector_pid)
    Agent.stop(attempts)
    Breeze.RemoteInspector.Supervisor.stop(supervisor)
  end

  test "remote inspector renders registered pages with active snapshot context" do
    {:ok, source_pid} = FakeInspectorServer.start_link(%{selected_id: "button"})
    on_exit(fn -> stop_process(source_pid) end)
    key = {:app@host, inspect(source_pid)}
    pages = Breeze.RemoteInspector.Pages.build([CustomInspectorPage])
    [page] = pages

    output =
      Breeze.Renderer.render_to_string(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: source_pid},
              snapshot:
                inspector_snapshot(source_pid, "button")
                |> Map.put(:pages, pages),
              updated_at: 1_000,
              alive?: true
            }
          },
          latest_source: key,
          active_source: key,
          panel_tab: page.id,
          render_tree_kind: "rendered",
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
          custom_page_states: %{},
          breeze: %{terminal: %{width: 140, height: 40}},
          screen: %{width: 140, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 140, height: 40}}
      )

    assert output =~ "Debugger"
    assert output =~ "page=#{page.id}"
    assert output =~ "selected=button"
    assert output =~ "note=configured"
    assert output =~ "static=extra"
    assert output =~ "tree=button"
    assert output =~ "terminal=40"
    assert output =~ "lean=true"
  end

  test "remote inspector pages can handle events and asynchronous messages" do
    key = {:app@host, "#PID<0.1.0>"}
    other_key = {:other@host, "#PID<0.2.0>"}
    pages = Breeze.RemoteInspector.Pages.build([InteractiveInspectorPage])
    [page] = pages
    page_id = page.id

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          key => %{
            source: %{node: :app@host, pid: self()},
            snapshot:
              inspector_snapshot(self(), "button")
              |> Map.put(:pages, pages),
            updated_at: 1_000,
            alive?: true
          },
          other_key => %{
            source: %{node: :other@host, pid: self()},
            snapshot: inspector_snapshot(self(), "other-button"),
            updated_at: 900,
            alive?: true
          }
        },
        latest_source: key,
        active_source: key,
        panel_tab: page_id,
        render_tree_kind: "rendered",
        render_trees: %{},
        render_tree_expanded: %{},
        custom_page_states: %{},
        screen: %{width: 100, height: 32}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(
               "prompt_changed",
               %{value: "hello"},
               term
             )

    assert term.assigns.custom_page_states[{key, page_id}].prompt == "hello"
    assert term.assigns.custom_page_states[{key, page_id}].count == 1

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(
               "render_tree_changed",
               %{value: "button", expanded: []},
               term
             )

    assert term.assigns.panel_tab == page_id

    assert term.assigns.custom_page_states[{key, page_id}].prompt ==
             "render_tree_changed:button"

    assert term.assigns.custom_page_states[{key, page_id}].count == 2

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_event(
               "tab_changed",
               %{value: "inner"},
               term
             )

    assert term.assigns.panel_tab == page_id
    assert term.assigns.custom_page_states[{key, page_id}].prompt == "tab_changed:inner"
    assert term.assigns.custom_page_states[{key, page_id}].count == 3

    page_assigns =
      Breeze.RemoteInspector.PageHost.page_assigns(
        page,
        Breeze.RemoteInspector.PageHost.context(term.assigns, term.assigns.snapshots[key])
      )

    message = Breeze.RemoteInspector.Page.message(page_assigns, {:done, "ok"})
    term = %{term | assigns: Map.put(term.assigns, :active_source, other_key)}

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_info(message, term)

    assert term.assigns.custom_page_states[{key, page_id}].prompt == "tab_changed:inner"
    assert term.assigns.custom_page_states[{key, page_id}].info == "ok"
    refute Map.has_key?(term.assigns.custom_page_states, {other_key, page_id})
  end

  test "registered pages explicitly request render tree data" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn ->
      if Process.alive?(source_pid), do: GenServer.stop(source_pid)
    end)

    assert {:ok, tree} =
             Breeze.RemoteInspector.Page.request(
               %{source_server_pid: source_pid},
               :render_tree,
               kind: :rendered,
               selected_id: "child",
               expanded: ["root"],
               limit: 200
             )

    assert tree.selected_id == "child"
    assert_receive {:inspector_render_tree, opts}, 500
    assert Keyword.get(opts, :kind) == :rendered
    assert Keyword.get(opts, :selected_id) == "child"
    assert Keyword.get(opts, :expanded) == ["root"]
    assert Keyword.get(opts, :limit) == 200
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
      screen: %{width: 59, height: 24},
      breakpoint: "sm",
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
          screen: %{width: 90, height: 32}
        },
        theme: true,
        terminal: %Termite.Terminal{size: %{width: 90, height: 40}}
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
    assert output =~ "screen=59x24"
    assert output =~ "breakpoint=sm"
    refute output =~ "screen=80x32"
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

  test "remote inspector host events use tagged names" do
    key = {:app@host, inspect(self())}
    terminal = %Termite.Terminal{size: %{width: 100, height: 32}}

    snapshot =
      self()
      |> inspector_snapshot("button")
      |> Map.put(:render_tree, %{id: "root", label: "<box#root>", children: []})

    {acc, _box} =
      Breeze.Renderer.render(
        Breeze.RemoteInspector.View,
        %{
          snapshots: %{
            key => %{
              source: %{node: :app@host, pid: self()},
              snapshot: snapshot,
              updated_at: 1_000,
              alive?: true
            }
          },
          logs: %{},
          log_sources: %{},
          latest_source: key,
          active_source: key,
          panel_tab: "tree",
          render_tree_kind: "rendered",
          render_tree_expanded: %{},
          render_trees: %{},
          custom_page_states: %{},
          screen: terminal.size
        },
        theme: true,
        terminal: terminal
      )

    events = Breeze.RenderState.bootstrap(%Breeze.Term{}, acc).events

    assert events["remote-inspector-tabs"] ==
             %{change: {:breeze_remote_inspector, "tab_changed"}}

    assert events["remote-inspector-render-tree"] ==
             %{change: {:breeze_remote_inspector, "render_tree_changed"}}
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
        render_trees: %{}
      }
    }

    assert {:noreply, %{assigns: %{panel_tab: "layout"}}} =
             Breeze.RemoteInspector.View.handle_event(
               {:breeze_remote_inspector, "tab_changed"},
               %{value: "layout"},
               term
             )

    assert {:noreply, %{assigns: %{panel_tab: "tree"}, local_keybindings: tree_keybindings}} =
             Breeze.RemoteInspector.View.handle_event(
               {:breeze_remote_inspector, "tab_changed"},
               %{value: "tree"},
               term
             )

    assert [%{key: "t", label: "Code tree"}] = Breeze.Keybindings.visible(tree_keybindings)

    assert {:noreply, %{assigns: %{panel_tab: "focus"}}} =
             Breeze.RemoteInspector.View.handle_event(
               {:breeze_remote_inspector, "tab_changed"},
               %{"value" => "focus"},
               term
             )

    assert {:noreply, %{assigns: %{panel_tab: "layout"}, local_keybindings: []}} =
             Breeze.RemoteInspector.View.handle_event(
               {:breeze_remote_inspector, "tab_changed"},
               %{"value" => "layout"},
               %{term | local_keybindings: tree_keybindings}
             )
  end

  test "theme tab can scroll its final palette row fully into view" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 8}}
    {:ok, pid} = Breeze.ChildServer.start(view: ThemeTabView, start_opts: [], terminal: terminal)

    on_exit(fn -> stop_process(pid) end)

    {:ok, _acc, initial_box} =
      Breeze.ChildServer.render(pid,
        focused: "theme-scroll",
        implicit_state: %{},
        terminal: terminal
      )

    refute initial_box.content =~ "LAST PALETTE SWATCH"

    assert {:noreply, "theme-scroll", true} = Breeze.ChildServer.dispatch_input(pid, "End")

    {:ok, _acc, scrolled_box} =
      Breeze.ChildServer.render(pid,
        focused: "theme-scroll",
        implicit_state: %{},
        terminal: terminal
      )

    assert scrolled_box.content =~ "LAST PALETTE SWATCH"
  end

  test "remote inspector render tree selection updates expansion and delegates selection" do
    {:ok, source_pid} = SelectCaptureServer.start_link(self())

    on_exit(fn -> stop_process(source_pid) end)

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
               {:breeze_remote_inspector, "render_tree_changed"},
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

    on_exit(fn -> stop_process(source_pid) end)

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

    on_exit(fn -> stop_process(source_pid) end)

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
               {:breeze_remote_inspector, "render_tree_changed"},
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

  test "remote inspector merges incremental snapshot updates without replacing logs" do
    old_key = {:app@host, "#PID<0.1.0>"}
    new_key = {:app@host, "#PID<0.2.0>"}
    logs = %{old_key => %{entries: [%{level: :info, line: "retained"}]}}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        snapshots: %{
          old_key => %{
            source: %{node: :app@host, pid: self()},
            snapshot: %{root_view: InspectorAppView, selected_id: "old"},
            updated_at: 1,
            alive?: true
          }
        },
        latest_source: old_key,
        active_source: old_key,
        logs: logs
      }
    }

    changed_snapshots = %{
      old_key => %{term.assigns.snapshots[old_key] | alive?: false},
      new_key => %{
        source: %{node: :app@host, pid: self()},
        snapshot: %{root_view: InspectorAppView, selected_id: "new"},
        updated_at: 2,
        alive?: true
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_info(
               {:remote_inspector_snapshots,
                %{snapshots: changed_snapshots, latest_source: new_key}},
               term
             )

    assert term.assigns.active_source == new_key
    assert term.assigns.latest_source == new_key
    assert term.assigns.snapshots[old_key].alive? == false
    assert term.assigns.snapshots[new_key].snapshot.selected_id == "new"
    assert term.assigns.logs == logs
  end

  test "remote inspector removes disconnected log sources incrementally" do
    key = {:app@host, "#PID<0.1.0>"}

    term = %Breeze.Term{
      view: Breeze.RemoteInspector.View,
      assigns: %{
        logs: %{
          key => %{
            source: %{node: :app@host, pid: self()},
            entries: [%{level: :info, line: "removed"}],
            updated_at: 1
          }
        },
        log_sources: %{}
      }
    }

    assert {:noreply, term} =
             Breeze.RemoteInspector.View.handle_info(
               {:remote_inspector_logs, {:delete, key}},
               term
             )

    assert term.assigns.logs == %{}
    assert term.assigns.log_sources == %{}
  end

  test "distribution names default for apps and the remote inspector" do
    assert Breeze.RemoteInspector.default_distribution_name(:inspector) == :inspector
    assert Breeze.RemoteInspector.default_distribution_name(:app, []) == :app

    assert Breeze.RemoteInspector.default_distribution_name(:app,
             view: Breeze.RemoteInspector.View
           ) == :breeze
  end

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
      hovered_id: nil,
      focused: selected_id,
      last_render_at: 1_000,
      last_interaction_at: 900,
      render_tree?: true
    }
  end

  defp page_id(module), do: "page:#{module}"

  defp supervised_pids(supervisor) do
    supervisor
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
  end

  defp stop_process(pid) when is_pid(pid) do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      500 -> Process.demonitor(ref, [:flush])
    end
  end
end

defmodule Breeze.RemoteInspectorSyncTest do
  use ExUnit.Case, async: false

  import Breeze.TestSupport.WaitUntil

  alias Breeze.RemoteInspectorTest.{FakeInspectorServer, InspectorAppView}

  test "local remote inspector server does not count as a remote delegate" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn -> stop_local_process(pid) end)

    refute Breeze.RemoteInspector.available?()
  end

  test "publishing to the local server updates subscribers" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    on_exit(fn -> stop_local_process(pid) end)
    :ok = Breeze.RemoteInspector.subscribe(self())

    assert_receive {:remote_inspector, _payload}
    _state = Breeze.RemoteInspector.Server.snapshot(pid)
    drain_remote_inspector_notifications()

    snapshot = %{enabled?: true, visible?: true, root_view: Posting, selected_id: "url"}

    Breeze.RemoteInspector.Server.publish(pid, self(), snapshot)
    published = Breeze.RemoteInspector.Server.snapshot(pid)
    key = {node(), inspect(self())}

    assert_receive {:remote_inspector_snapshots,
                    %{snapshots: %{^key => entry}, latest_source: ^key}}

    assert entry.snapshot == snapshot
    assert published.snapshots[key] == entry
  end

  test "snapshot broadcasts are coalesced and do not resend logs" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    on_exit(fn -> stop_local_process(pid) end)

    log_entry = %{level: :info, line: String.duplicate("log", 1_000)}
    Breeze.RemoteInspector.Server.publish_logs(pid, self(), [log_entry])
    %{logs: logs} = Breeze.RemoteInspector.Server.snapshot(pid)

    :ok = Breeze.RemoteInspector.subscribe(self())
    assert_receive {:remote_inspector, %{logs: ^logs}}
    drain_remote_inspector_notifications()

    Enum.each(1..20, fn index ->
      Breeze.RemoteInspector.Server.publish(pid, self(), %{selected_id: "item-#{index}"})
    end)

    _state = Breeze.RemoteInspector.Server.snapshot(pid)
    key = {node(), inspect(self())}

    assert_receive {:remote_inspector_snapshots,
                    %{snapshots: %{^key => entry}, latest_source: ^key}}

    assert entry.snapshot.selected_id == "item-20"
    refute_receive {:remote_inspector_snapshots, _update}, 30
  end

  test "incremental logs retain the newest entries in oldest-first order" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    on_exit(fn -> stop_local_process(pid) end)

    Enum.each(1..1_005, fn index ->
      Breeze.RemoteInspector.Server.publish_log_entry(pid, self(), %{
        level: :info,
        line: "entry-#{index}"
      })
    end)

    key = {node(), inspect(self())}
    entries = Breeze.RemoteInspector.Server.snapshot(pid).logs[key].entries

    assert length(entries) == 1_000
    assert hd(entries).line == "entry-6"
    assert List.last(entries).line == "entry-1005"
  end

  test "incremental logs remain bounded by total bytes" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    on_exit(fn -> stop_local_process(pid) end)

    Enum.each(1..21, fn index ->
      line = Integer.to_string(rem(index, 10)) <> String.duplicate("x", 99_999)
      Breeze.RemoteInspector.Server.publish_log_entry(pid, self(), %{level: :info, line: line})
    end)

    key = {node(), inspect(self())}
    entries = Breeze.RemoteInspector.Server.snapshot(pid).logs[key].entries

    assert length(entries) == 20
    assert String.starts_with?(hd(entries).line, "2")
  end

  test "disconnecting a logs-only source sends an incremental deletion" do
    {:ok, pid} = Breeze.RemoteInspector.ensure_server()
    source_pid = spawn(fn -> Process.sleep(:infinity) end)

    on_exit(fn ->
      stop_local_process(source_pid)
      stop_local_process(pid)
    end)

    Breeze.RemoteInspector.Server.publish_logs(pid, source_pid, [
      %{level: :info, line: "temporary"}
    ])

    key = {node(source_pid), inspect(source_pid)}
    assert %{logs: %{^key => _entry}} = Breeze.RemoteInspector.Server.snapshot(pid)

    :ok = Breeze.RemoteInspector.subscribe(self())
    assert_receive {:remote_inspector, %{logs: %{^key => _entry}}}
    drain_remote_inspector_notifications()

    Process.exit(source_pid, :shutdown)

    assert_receive {:remote_inspector_logs, {:delete, ^key}}
    refute Map.has_key?(Breeze.RemoteInspector.Server.snapshot(pid).logs, key)
  end

  test "starting the remote inspector server pulls current snapshots from inspector-enabled apps" do
    {:ok, app_pid} =
      FakeInspectorServer.start_link(%{root_view: InspectorAppView, selected_id: "button"})

    {:ok, supervisor} = Breeze.RemoteInspector.Supervisor.start_link()
    :ok = Breeze.RemoteInspector.register_app(app_pid)
    {:ok, _connector} = Breeze.RemoteInspector.Supervisor.start_connector(supervisor, app_pid)

    {:ok, inspector_pid} = Breeze.RemoteInspector.ensure_server()

    on_exit(fn ->
      stop_local_process(app_pid)
      stop_local_process(inspector_pid)
      Breeze.RemoteInspector.Supervisor.stop(supervisor)
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
      stop_local_process(source_pid)
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

  defp stop_local_process(pid) when is_pid(pid) and node(pid) == node() do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      500 -> Process.demonitor(ref, [:flush])
    end
  end

  defp stop_local_process(_pid), do: :ok

  defp drain_remote_inspector_notifications do
    receive do
      {:remote_inspector, _payload} -> drain_remote_inspector_notifications()
      {:remote_inspector_snapshots, _payload} -> drain_remote_inspector_notifications()
      {:remote_inspector_logs, _payload} -> drain_remote_inspector_notifications()
    after
      0 -> :ok
    end
  end
end
