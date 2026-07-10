defmodule Breeze.RouterTest do
  use ExUnit.Case, async: true

  alias Breeze.Router
  alias Breeze.Template

  defmodule HomeView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>home</box>"
    end
  end

  defmodule SettingsView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>settings</box>"
    end
  end

  defmodule RouterExample do
    use Breeze.View
    import Breeze.Router

    def render(assigns) do
      ~H"""
      <box>
        <.router routes={@router} id="main"/>
      </box>
      """
    end
  end

  defmodule RouterLifecycleView do
    use Breeze.View

    def mount(opts, term) do
      {:ok, assign(term, name: Keyword.fetch!(opts, :name))}
    end

    def render(assigns) do
      ~H"<box>{@name}</box>"
    end
  end

  defmodule RouterLifecycleRoot do
    use Breeze.View
    import Breeze.Router

    def mount(opts, term) do
      settings_persistence = Keyword.get(opts, :settings_persistence, false)

      routes = [
        home: {RouterLifecycleView, [name: "home"]},
        settings: {RouterLifecycleView, [name: "settings"], persistence: settings_persistence}
      ]

      {:ok, Router.init(term, routes, current: :home)}
    end

    def render(assigns) do
      ~H"""
      <box>
        <.router routes={@router} id="main"/>
      </box>
      """
    end

    def handle_event("navigate", %{"route" => route}, term) do
      {:noreply, Router.navigate(term, String.to_existing_atom(route))}
    end
  end

  defmodule NestedLeafView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>leaf</box>"
    end
  end

  defmodule NestedParentView do
    use Breeze.View
    import Breeze.Router

    def mount(_opts, term) do
      {:ok, Router.init(term, [inner: NestedLeafView], current: :inner)}
    end

    def render(assigns) do
      ~H"""
      <box>
        <.router routes={@router} id="inner"/>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "initializes an opt-in router with a default route" do
    router =
      Router.new(
        home: HomeView,
        settings: {SettingsView, [tab: "general"]}
      )

    assert Router.current(router) == :home
    assert Router.route_names(router) == [:home, :settings]
    assert Router.current_route(router).view == HomeView
  end

  test "navigate switches route and merges params into start opts" do
    router =
      Router.new(
        home: HomeView,
        settings: {SettingsView, [tab: "general"]}
      )

    router = Router.navigate(router, :settings, tab: "advanced", section: "team")

    assert Router.current(router) == :settings
    assert Router.current_route(router).start_opts == [tab: "advanced", section: "team"]
  end

  test "router supports lazy persistence via a third tuple item" do
    [{:box, _, [visible_live]}] =
      RouterExample.render(%{
        router:
          Router.new(
            [
              home: HomeView,
              settings: {SettingsView, [tab: "general"], persistence: true}
            ],
            current: :settings
          )
      })
      |> Template.render_to_tree(%{})

    {:live, attrs} = visible_live
    assert attrs.id == "main:persistent:settings"
    assert attrs.view == SettingsView
    assert attrs.persistent == true
  end

  test "router preloads preload-persistent routes off-screen" do
    [{:box, _, [visible_live, preload_live]}] =
      RouterExample.render(%{
        router:
          Router.new(
            [
              home: HomeView,
              settings: {SettingsView, [tab: "general"], persistence: :preload}
            ],
            current: :home
          )
      })
      |> Template.render_to_tree(%{})

    {:live, visible_attrs} = visible_live
    {:live, preload_attrs} = preload_live

    assert visible_attrs.id == "main:home"
    assert preload_attrs.id == "main:persistent:settings"
    assert preload_attrs.preload_only == true
    assert preload_attrs.persistent == true
  end

  test "router renders a route-specific live id for remounting" do
    [{:box, _, [{:live, attrs}]}] =
      RouterExample.render(%{
        router:
          Router.new(
            [
              home: HomeView,
              settings: SettingsView
            ],
            current: :settings
          )
      })
      |> Template.render_to_tree(%{})

    assert attrs.id == "main:settings"
    assert attrs.view == SettingsView
  end

  test "routing away stops a non-persistent view and routing back remounts it" do
    {:ok, root} = Breeze.ChildServer.start(view: RouterLifecycleRoot, start_opts: [])
    assert {:ok, _acc, _box} = Breeze.ChildServer.render(root, [])

    home = :sys.get_state(root).children["main:home"].pid

    assert {:noreply, _, true} =
             Breeze.ChildServer.dispatch_event(root, "navigate", %{"route" => "settings"})

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(root, [])
    settings = :sys.get_state(root).children["main:settings"].pid

    refute Process.alive?(home)

    assert {:noreply, _, true} =
             Breeze.ChildServer.dispatch_event(root, "navigate", %{"route" => "home"})

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(root, [])
    remounted_home = :sys.get_state(root).children["main:home"].pid

    refute Process.alive?(settings)
    assert remounted_home != home

    GenServer.stop(root, :normal)
  end

  test "preloaded routes stay supervised across navigation" do
    {:ok, root} =
      Breeze.ChildServer.start(
        view: RouterLifecycleRoot,
        start_opts: [settings_persistence: :preload]
      )

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(root, [])
    initial_children = :sys.get_state(root).children
    home = initial_children["main:home"].pid
    settings = initial_children["main:persistent:settings"].pid

    assert Process.alive?(home)
    assert Process.alive?(settings)

    assert {:noreply, _, true} =
             Breeze.ChildServer.dispatch_event(root, "navigate", %{"route" => "settings"})

    assert {:ok, _acc, _box} = Breeze.ChildServer.render(root, [])

    refute Process.alive?(home)
    assert :sys.get_state(root).children["main:persistent:settings"].pid == settings
    assert Process.alive?(settings)

    GenServer.stop(root, :normal)
    refute Process.alive?(settings)
  end

  test "nested routers can emit nested live nodes inside routed views" do
    {:ok, pid} = Breeze.ChildServer.start(view: NestedParentView, start_opts: [])

    {:ok, acc, _box} =
      Breeze.ChildServer.render(pid,
        focused: nil,
        implicit_state: %{},
        live_prefix: "main:parent",
        live_view: fn %{id: "inner:inner", view: NestedLeafView}, _opts ->
          {:rendered, "main:parent::inner:inner", %{elements: %{}, ids: [], focusables: []},
           %BackBreeze.Box{}}
        end
      )

    assert is_map(acc.elements)
  end

  defmodule FocusableLeafView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box id="leaf" focusable style="focus:border-4">leaf</box>
      """
    end
  end

  defmodule FocusableNestedParentView do
    use Breeze.View
    import Breeze.Router

    def mount(_opts, term) do
      {:ok, Router.init(term, [inner: FocusableLeafView], current: :inner)}
    end

    def render(assigns) do
      ~H"""
      <box id="parent" focusable style="focus:border-4">
        <.router routes={@router} id="inner"/>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "nested routed child focusables are exposed in the parent focus list" do
    {:ok, pid} = Breeze.ChildServer.start(view: FocusableNestedParentView, start_opts: [])

    {:ok, acc, _box} =
      Breeze.ChildServer.render(pid,
        focused: nil,
        implicit_state: %{},
        live_view: fn %{id: "inner:inner", view: FocusableLeafView}, _opts ->
          {:ok, child_acc, child_box} =
            Breeze.ChildServer.start(view: FocusableLeafView, start_opts: [])
            |> then(fn {:ok, child_pid} ->
              Breeze.ChildServer.render(child_pid, focused: nil, implicit_state: %{})
            end)

          {:rendered, "inner:inner", child_acc, child_box}
        end
      )

    assert "parent" in acc.focusables
    assert "inner:inner::leaf" in acc.focusables
  end
end
