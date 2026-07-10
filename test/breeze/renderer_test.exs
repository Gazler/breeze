defmodule Breeze.RendererTest do
  use ExUnit.Case, async: true
  alias BackBreeze.VirtualText.Source
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

  defmodule ThemeAnimationImplicit do
    @behaviour Breeze.Implicit

    def init(_children, _root_attrs, last_state), do: last_state
    def handle_modifiers(_type, _flags, _state), do: []

    def animate(:root, box, _flags, _state, %{
          phase: :base,
          theme: %Breeze.Theme{name: name}
        }) do
      %{box | content: name}
    end

    def animate(:child, box, _flags, _state, _ctx), do: box
  end

  defmodule ThemeAnimationExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="theme-animation" implicit={ThemeAnimationImplicit}>fallback</box>
      """
    end
  end

  defmodule ScreenDimBackdropExample do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box class="width-12 height-5 bg-surface text">
        <box class="absolute left-1 top-1 text-primary">Hi</box>
        <.modal id="modal" width={4} height={2} dim/>
      </box>
      """
    end
  end

  defmodule ScrollImplicit do
    def init(_children, _root_attrs, last_state),
      do: %{offset_y: last_state[:offset_y] || 0, offset_x: 0}

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

  defmodule VirtualTextChildContentExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="width-12 height-4 border overflow-hidden">{@content}</box>
      """
    end
  end

  defmodule SelectedOwnerImplicit do
    def init(_children, _root_attrs, last_state),
      do: %{selected: last_state[:selected] || "two"}

    def handle_event(_, _, state), do: {:noreply, state}
    def handle_modifiers(:root, _flags, _state), do: []

    def handle_modifiers(:child, flags, state) do
      if state.selected == Keyword.get(flags, :value), do: [selected: true], else: []
    end
  end

  defmodule SelectedWithOwnerExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box id="list" implicit={SelectedOwnerImplicit}>
        <box value="one" class="inline">
          <box class="inline width-1 height-1 overflow-hidden">
            <box selected-with-owner class="hidden selected:width-1 selected:height-1">></box>
            <box selected-with-owner class="width-1 height-1 overflow-hidden selected:hidden">
              {" "}
            </box>
          </box>
          <box class="inline">One</box>
        </box>
        <box value="two" class="inline">
          <box class="inline width-1 height-1 overflow-hidden">
            <box selected-with-owner class="hidden selected:width-1 selected:height-1">></box>
            <box selected-with-owner class="width-1 height-1 overflow-hidden selected:hidden">
              {" "}
            </box>
          </box>
          <box class="inline">Two</box>
        </box>
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

  defmodule NestedCenteredFixedPositionExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="width-screen height-screen overflow-hidden">
        <box class="height-3 width-full overflow-hidden">Header</box>
        <box class="height-1 width-full overflow-hidden">
          <box class="fixed center">OK</box>
        </box>
        <box class="height-1 width-full overflow-hidden">Footer</box>
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
    def init(_children, _root_attrs, last_state), do: %{offset_x: last_state[:offset_x] || 0}
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

  defmodule InlineOverflowExample do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box class="inline bg-panel height-1 overflow-hidden">
        <box class="text-accent bold">Esc</box>
        <box> Close</box>
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

    test "inline overflow-hidden boxes keep their intrinsic width" do
      assert Renderer.render_to_string(InlineOverflowExample, %{}) =~ "Esc"
      assert Renderer.render_to_string(InlineOverflowExample, %{}) =~ "Close"
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

    test "screen dim keeps backdrop text and fill backgrounds consistent" do
      theme = Breeze.Theme.builtin(:nebula)

      {_acc, box} =
        Renderer.render(ScreenDimBackdropExample, %{},
          theme: theme,
          terminal: %Termite.Terminal{size: %{width: 12, height: 5}}
        )

      assert map_size(box.layer_map) < 30
      assert {" ", blank_style} = layer_point(box.layer_map, 1, 0)
      assert {"H", text_style} = layer_point(box.layer_map, 1, 1)
      assert background_rgb(blank_style) == background_rgb(text_style)
    end

    test "theme: false preserves legacy unthemed defaults" do
      assert Renderer.render_to_string(ThemeDefaultsExample, %{}, theme: false) ==
               "┌─────┐\n│Hello│\n└─────┘"
    end
  end

  describe "render/3" do
    test "includes the theme in the base animation context" do
      theme = Breeze.Theme.builtin(:gruvbox)

      {_acc, box} =
        Renderer.render(ThemeAnimationExample, %{},
          theme: theme,
          implicit_state: %{"theme-animation" => {ThemeAnimationImplicit, %{}}}
        )

      assert box.content =~ theme.name
    end

    test "supports virtual text as child content" do
      content =
        Source.lazy(
          cache_key: :renderer_virtual_text_child,
          intrinsic_width: 12,
          line_count_fn: fn _width -> 3 end,
          slice_fn: fn start_line, visible_count, _width ->
            Enum.map(start_line..(start_line + visible_count - 1), fn
              0 -> [{"Alpha", %{bold: true}}]
              1 -> "Beta"
              _ -> ""
            end)
          end
        )

      {_acc, box} =
        Renderer.render(VirtualTextChildContentExample, %{content: content},
          terminal: %Termite.Terminal{size: %{width: 12, height: 4}}
        )

      assert box.content =~ "Alpha"
      assert box.content =~ "Beta"
    end

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

    test "selected-with-owner lets descendants react to implicit child selection" do
      {_state, box} =
        Renderer.render(SelectedWithOwnerExample, %{},
          implicit_state: %{"list" => {SelectedOwnerImplicit, %{selected: "two"}}}
        )

      assert box.content =~ " One"
      assert box.content =~ ">Two"
    end

    test "selected-with-owner also works through child server rerenders" do
      {:ok, pid} = Breeze.ChildServer.start(view: SelectedWithOwnerExample, start_opts: [])

      {:ok, _acc, box} = Breeze.ChildServer.render(pid, focused: "list", implicit_state: %{})

      assert box.content =~ " One"
      assert box.content =~ ">Two"
    end

    test "tracks the namespaced live child root viewport" do
      {:ok, pid} = Breeze.ChildServer.start(view: LiveCounterChild, start_opts: [])

      {acc, _box} =
        Renderer.render(ParentLiveExample, %{start_opts: []},
          live_view: fn %{id: "child"}, _opts ->
            {:ok, child_acc, child_box} =
              Breeze.ChildServer.render(pid, focused: "button", implicit_state: %{})

            child_dimensions = %{
              "child" => %{
                left: 0,
                top: 0,
                width: 10,
                height: 3,
                viewport_width: 10,
                viewport_height: 3,
                content_width: 10,
                content_height: 3
              }
            }

            {:rendered, "child", child_acc, child_box, child_dimensions}
          end
        )

      assert Map.has_key?(acc.live_dimensions, "child")
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

      lines = String.split(box.content, "\n")

      assert length(lines) == 4
      assert Enum.all?(lines, &(String.length(&1) == 10))
      assert lines |> Enum.at(1) |> String.slice(4, 2) == "OK"
    end

    test "keeps nested centered fixed positioning relative to the screen" do
      {_, box} =
        Renderer.render(NestedCenteredFixedPositionExample, %{},
          terminal: %Termite.Terminal{size: %{width: 20, height: 10}}
        )

      plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
      lines = String.split(plain_content, "\n")

      assert lines |> Enum.at(4) |> String.slice(9, 2) == "OK"
      refute lines |> Enum.at(7) |> String.slice(9, 2) == "OK"
      assert lines |> Enum.at(4) |> String.slice(0, 6) == "Footer"
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

  defp background_rgb(style) do
    case Regex.run(~r/48;2;(\d+);(\d+);(\d+)/, style) do
      [_, red, green, blue] ->
        {String.to_integer(red), String.to_integer(green), String.to_integer(blue)}

      _ ->
        nil
    end
  end

  defp layer_point(layer_map, y, x) do
    Map.get(layer_map, {y, x}) || default_fill_at(layer_map, y, x)
  end

  defp default_fill_at(layer_map, y, x) do
    layer_map
    |> Map.get(:__default_fill__)
    |> default_fill_entries()
    |> Enum.find_value(fn
      {{_char, _style} = point, left, top, right, bottom}
      when x >= left and x <= right and y >= top and y <= bottom ->
        point

      _ ->
        nil
    end)
  end

  defp default_fill_entries(nil), do: []
  defp default_fill_entries([]), do: []
  defp default_fill_entries([_ | _] = fills), do: fills
  defp default_fill_entries({_point, _left, _top, _right, _bottom} = fill), do: [fill]
end
