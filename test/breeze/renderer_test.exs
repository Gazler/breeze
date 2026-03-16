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
        <box id="child" implicit={ScrollImplicit} style="border width-6 height-2 overflow-hidden">
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
  end

  describe "render/3" do
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
               ┌───────┐
               │  Hey  │
               └───────┘\
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
