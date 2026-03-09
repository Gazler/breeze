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
