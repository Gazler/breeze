defmodule Breeze.RendererTest do
  use ExUnit.Case, async: true
  alias Breeze.Renderer

  defmodule Example do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <.panel>
        <:title>
          <box style="text-3">Title</box>
        </:title>
        <box style="bold">Hello {@name}</box>
      </.panel>
      """
    end

    slot :title
    slot :inner_block

    defp panel(assigns) do
      ~H"""
      <box style="border">
        <box :if={assigns[:title]} style="absolute left-1 top-0">{render_slot(@title)}</box>
        {render_slot(@inner_block)}
      </box>
      """
    end
  end

  defmodule ClassExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="text-3 bold">Hello</box>
      """
    end
  end

  defmodule BackCompatStyleExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="text-3 bold">Hello</box>
      """
    end
  end

  defmodule MapStyleExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style={%{foreground_color: 3, background_color: 0}}>Hello</box>
      """
    end
  end

  defmodule StructStyleExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style={BackBreeze.Style.border_color(3) |> BackBreeze.Style.border(:rounded)}>Hello</box>
      """
    end
  end

  defmodule PanelStyleExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.panel width={7} height={3} class="text-3" style={%{background_color: 0}}>Hello</.panel>
      """
    end
  end

  defmodule FlexiblePanelStyleExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.panel class="width-7 height-3 text-3" style={%{background_color: 0}}>Hello</.panel>
      """
    end
  end

  defmodule ScrollPanelExample do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <.panel id="theme-demo" width={8} height={4} scroll>
        <:title>Demo</:title>
        <box>AAAAAA</box>
        <box>BBBBBB</box>
        <box>CCCCCC</box>
      </.panel>
      """
    end
  end

  defmodule SemanticThemeExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="text-primary bg border border-stroke">Hello</box>
      """
    end
  end

  defmodule ThemeDefaultsExample do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box class="border">Hello</box>
      """
    end
  end

  defmodule ThemeInheritanceExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="bg-surface border">
        <box class="text-primary">Hello</box>
      </box>
      """
    end
  end

  defmodule ScrollImplicit do
    def init(_children, last_state), do: %{offset_y: last_state[:offset_y] || 0, offset_x: 0}

    def handle_event(_, _, state), do: {:noreply, state}

    def handle_modifiers(:root, _flags, state) do
      [scroll_y: state.offset_y, scroll_x: 2]
    end

    def handle_modifiers(:child, _flags, _state), do: []
  end

  defmodule ScrollExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="list" implicit={ScrollImplicit} style="border width-6 height-2 overflow-hidden">
        <box value="a">AAAAAA</box>
        <box value="b">BBBBBB</box>
        <box value="c">CCCCCC</box>
      </box>
      """
    end
  end

  defmodule TabsWidthExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <.tabs id="tabs" selected="overview" style="width-6">
        <:tab value="overview" label="Overview">
          <box>body</box>
        </:tab>
        <:tab value="details" label="Details">
          <box>more</box>
        </:tab>
      </.tabs>
      """
    end
  end

  defmodule FixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed right-0 bottom-0">X</box>
      </box>
      """
    end
  end

  defmodule LiveCounterChild do
    use Breeze.View

    def mount(_opts, term), do: {:ok, assign(term, count: 1)}

    def render(assigns) do
      ~H"""
      <box id="panel">
        <box id="button" focusable>Count: {@count}</box>
      </box>
      """
    end
  end

  defmodule ParentLiveExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box>
        <live id="child" view={LiveCounterChild} start_opts={@start_opts}>
        </live>
      </box>
      """
    end
  end

  defmodule LiveSurfaceChild do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen">
        <box class="fixed right-0 bottom-0">X</box>
      </box>
      """
    end
  end

  defmodule SizedLiveSurfaceExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="width-12 height-5 border">
        <live id="child" view={LiveSurfaceChild} class="width-full height-full">
        </live>
      </box>
      """
    end
  end

  defmodule CenteredFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed center">OK</box>
      </box>
      """
    end
  end

  defmodule InsetFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed inset-1">OK</box>
      </box>
      """
    end
  end

  defmodule FullscreenInsetFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed inset-1 width-screen height-screen border">
        </box>
      </box>
      """
    end
  end

  defmodule CenterXFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed center-x top-0">OK</box>
      </box>
      """
    end
  end

  defmodule CenterYFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="width-screen height-screen">
        <box style="fixed left-0 center-y">OK</box>
      </box>
      """
    end
  end

  defmodule TextAlignmentExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="border width-7 text-center">Hey</box>
      """
    end
  end

  defmodule PaddingBottomExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style="padding-bottom-1">
        <box>Top</box>
      </box>
      """
    end
  end

  defmodule ParentImplicit do
    def init(_children, last_state), do: %{offset_x: last_state[:offset_x] || 0}
    def handle_event(_, _, state), do: {:noreply, state}
    def handle_modifiers(:root, _flags, state), do: [scroll_x: state.offset_x]
    def handle_modifiers(:child, _flags, _state), do: []
  end

  defmodule NestedImplicitExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="parent" implicit={ParentImplicit}>
        <box id="child" implicit={ScrollImplicit} style="border width-8 height-4 overflow-hidden">
          <box>AAAAAA</box>
          <box>BBBBBB</box>
          <box>CCCCCC</box>
        </box>
      </box>
      """
    end
  end

  describe "render_to_string/2" do
    test "converts the boxes to terminal output" do
      assert Renderer.render_to_string(Example, %{name: "world"}) ==
               """
               ┌\e[38;5;3mTitle\e[0m──────┐
               │\e[1mHello world\e[0m│
               └───────────┘\
               """
    end

    test "supports token classes" do
      assert Renderer.render_to_string(ClassExample, %{}) == "\e[1;38;5;3mHello\e[0m"
    end

    test "keeps binary style values backwards compatible" do
      assert Renderer.render_to_string(BackCompatStyleExample, %{}) == "\e[1;38;5;3mHello\e[0m"
    end

    test "accepts inline style maps" do
      assert Renderer.render_to_string(MapStyleExample, %{}) == "\e[48;5;0;38;5;3mHello\e[0m"
    end

    test "accepts BackBreeze.Style structs" do
      assert Renderer.render_to_string(StructStyleExample, %{}) ==
               "\e[38;5;3m╭─────╮\e[0m\n\e[38;5;3m│\e[0mHello\e[38;5;3m│\e[0m\n\e[38;5;3m╰─────╯\e[0m"
    end

    test "forwards inline styles through block components" do
      assert Renderer.render_to_string(PanelStyleExample, %{}) ==
               "\e[48;5;0;38;5;7m╭─────╮\e[0m\n\e[48;5;0;38;5;7m│\e[0m\e[48;5;0;38;5;3mHello\e[0m\e[48;5;0;38;5;7m│\e[0m\n\e[48;5;0;38;5;7m╰─────╯\e[0m"
    end

    test "panel sizing can come from classes" do
      assert Renderer.render_to_string(FlexiblePanelStyleExample, %{}) ==
               "\e[48;5;0;38;5;7m╭─────╮\e[0m\n\e[48;5;0;38;5;7m│\e[0m\e[48;5;0;38;5;3mHello\e[0m\e[48;5;0;38;5;7m│\e[0m\n\e[48;5;0;38;5;7m╰─────╯\e[0m"
    end

    test "resolves semantic tokens against custom themes" do
      theme = Breeze.Theme.new(primary: "#268bd2", background: "#002b36", border: "#586e75")

      {_state, box} = Renderer.render(SemanticThemeExample, %{}, theme: theme)

      assert box.style.foreground_color == {38, 139, 210}
      assert box.style.background_color == {0, 43, 54}
      assert box.style.border_color == {88, 110, 117}
    end

    test "theme: true enables default semantic text, background, and border colors" do
      assert Renderer.render_to_string(ThemeDefaultsExample, %{}, theme: true) ==
               "\e[48;5;0;38;5;7m┌─────┐\e[0m\n\e[48;5;0;38;5;7m│\e[0m\e[48;5;0;38;5;7mHello\e[0m\e[48;5;0;38;5;7m│\e[0m\n\e[48;5;0;38;5;7m└─────┘\e[0m"
    end

    test "theme defaults do not override parent backgrounds on nested content" do
      theme =
        Breeze.Theme.new(
          defaults: %{
            foreground_color: "#d6e7ff",
            background_color: "#0d2137",
            border_color: "#4a9cff"
          },
          palette: %{
            primary: "#4a9cff",
            surface: "#193549"
          }
        )

      assert Renderer.render_to_string(ThemeInheritanceExample, %{}, theme: theme) ==
               "\e[48;2;25;53;73;38;2;74;156;255m┌─────┐\e[0m\n" <>
                 "\e[48;2;25;53;73;38;2;74;156;255m│Hello│\e[0m\n" <>
                 "\e[48;2;25;53;73;38;2;74;156;255m└─────┘\e[0m"
    end

    test "theme: false preserves legacy unthemed defaults" do
      assert Renderer.render_to_string(ThemeDefaultsExample, %{}, theme: false) ==
               "┌─────┐\n│Hello│\n└─────┘"
    end
  end

  describe "render/3" do
    test "scroll panels wire the scroll implicit" do
      {:ok, pid} = Breeze.ChildServer.start(view: ScrollPanelExample, start_opts: [])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)

      {:ok, _acc, initial_box} =
        Breeze.ChildServer.render(pid, focused: "theme-demo", implicit_state: %{})

      assert initial_box.content =~ "AAAAA"
      assert initial_box.content =~ "BBBBB"
      refute initial_box.content =~ "CCCCC"

      assert {:noreply, "theme-demo", true} = Breeze.ChildServer.dispatch_input(pid, "j")

      {:ok, _acc, scrolled_box} =
        Breeze.ChildServer.render(pid, focused: "theme-demo", implicit_state: %{})

      assert scrolled_box.content =~ "BBBBB"
      assert scrolled_box.content =~ "CCCCC"
    end

    test "applies implicit scroll modifiers as structured values" do
      {_, box} =
        Renderer.render(ScrollExample, %{},
          implicit_state: %{"list" => {ScrollImplicit, %{offset_y: 1}}}
        )

      assert box.scroll == {1, 2}
    end

    test "preserves explicit tabs width when labels overflow" do
      {state, _box} = Renderer.render(TabsWidthExample, %{})

      assert hd(state.dimensions).width == 6
      assert hd(state.dimensions).viewport_width == 6
    end

    test "applies nested implicit root modifiers using the nested implicit state" do
      {_state, box} =
        Renderer.render(NestedImplicitExample, %{},
          implicit_state: %{
            "parent" => {ParentImplicit, %{offset_x: 0}},
            "child" => {ScrollImplicit, %{offset_y: 1}}
          }
        )

      assert box.content ==
               """
               ┌──────┐
               │BBBB  │
               │CCCC  │
               └──────┘\
               """
    end

    test "tracks the namespaced live child root element id" do
      {:ok, pid} = Breeze.ChildServer.start(view: LiveCounterChild, start_opts: [])

      {acc, _box} =
        Renderer.render(ParentLiveExample, %{start_opts: []},
          live_view: fn %{id: "child"}, _opts ->
            {:ok, child_acc, child_box} =
              Breeze.ChildServer.render(pid, focused: "button", implicit_state: %{})

            {:rendered, "child", child_acc, child_box}
          end
        )

      assert Enum.any?(acc.elements, fn {_idx, flags} -> Keyword.get(flags, :id) == "child" end)
    end

    test "renders live children against their constrained slot dimensions" do
      {:ok, pid} = Breeze.ChildServer.start(view: LiveSurfaceChild, start_opts: [])

      {_, box} =
        Renderer.render(SizedLiveSurfaceExample, %{},
          terminal: %Termite.Terminal{size: %{width: 30, height: 10}},
          live_view: fn %{id: "child"}, opts ->
            {:ok, _child_acc, child_box} =
              Breeze.ChildServer.render(pid,
                terminal: Keyword.fetch!(opts, :live_terminal)
              )

            {:rendered, "child", %{elements: %{}, ids: [], focusables: [], boxes: %{}}, child_box}
          end
        )

      plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")

      assert plain_content =~
               """
               ┌──────────┐
               │          │
               │          │
               │         X│
               └──────────┘\
               """
    end

    test "supports fixed positioning with right and bottom offsets" do
      {_, box} =
        Renderer.render(FixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 5, height: 3}}
        )

      assert box.content ==
               """
                    
                    
                   X\
               """
    end

    test "supports centered fixed positioning" do
      {_, box} =
        Renderer.render(CenteredFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 10, height: 4}}
        )

      assert box.content ==
               """
                         
                   OK    
                         
                         \
               """
    end

    test "supports inset positioning for fixed boxes" do
      {_, box} =
        Renderer.render(InsetFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 6, height: 4}}
        )

      assert box.content ==
               """
                     
                OK   
                     
                     \
               """
    end

    test "supports inset-constrained fixed screen boxes" do
      {_, box} =
        Renderer.render(FullscreenInsetFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 10, height: 6}}
        )

      assert box.content ==
               """
                         
                ┌──────┐ 
                │      │ 
                │      │ 
                └──────┘ 
                         \
               """
    end

    test "supports centered fixed positioning on the x axis only" do
      {_, box} =
        Renderer.render(CenterXFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 10, height: 4}}
        )

      assert box.content ==
               """
                   OK    
                         
                         
                         \
               """
    end

    test "supports centered fixed positioning on the y axis only" do
      {_, box} =
        Renderer.render(CenterYFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 10, height: 4}}
        )

      assert box.content ==
               """
                         
               OK        
                         
                         \
               """
    end

    test "supports centered text alignment classes" do
      {_, box} = Renderer.render(TextAlignmentExample, %{})

      assert box.content ==
               """
               ┌─────┐
               │ Hey │
               └─────┘\
               """
    end

    test "supports bottom padding classes" do
      {_, box} = Renderer.render(PaddingBottomExample, %{})

      assert box.content ==
               """
               Top
                  \
               """
    end
  end
end
