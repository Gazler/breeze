defmodule Breeze.Implicit.ScrollTest do
  use ExUnit.Case, async: true

  import Breeze.TestSupport.ProcessHelpers, only: [start_child_server: 1]

  alias BackBreeze.TextSpan
  alias BackBreeze.VirtualText.Source
  alias Breeze.ChildServer
  alias Breeze.Implicit.Scroll
  alias Breeze.Viewport

  defmodule VirtualScrollView do
    use Breeze.View

    def mount(_opts, term) do
      {:ok,
       term
       |> focus("large-scroll")
       |> assign(content: build_content(), header_content: build_header())}
    end

    def render(assigns) do
      ~H"""
      <box
        id="large-scroll"
        implicit={Breeze.Implicit.Scroll}
        focusable
        class="width-screen height-screen border-rounded bg-panel overflow-scroll"
        style={%{scrollbar: %{arrows: true}}}
        content={@content}
      >
        <box
          class="absolute left-0 top-0 width-full height-2 bg-panel"
          style="bold"
          content={@header_content}
        >
        </box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}

    defp build_header do
      [
        TextSpan.new("Header\n", %{bold: true}),
        TextSpan.new("Fixed overlay")
      ]
    end

    defp build_content do
      Source.lazy(
        cache_key: :virtual_scroll_view,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 32 end,
        slice_fn: fn start_line, visible_count, _width ->
          Enum.map(start_line..(start_line + visible_count - 1), fn
            line_no when line_no < 2 ->
              ""

            line_no ->
              index = line_no - 1

              if index <= 30 do
                "Line " <> String.pad_leading(Integer.to_string(index), 2, "0") <> " body"
              else
                ""
              end
          end)
        end
      )
    end
  end

  defmodule NestedGridVirtualScrollView do
    use Breeze.View
    alias BackBreeze.TextSpan
    alias BackBreeze.VirtualText.Source

    def mount(_opts, term) do
      {:ok,
       term
       |> focus("large-scroll-content")
       |> assign(
         header_content: [TextSpan.new("Header", %{background_color: 0})],
         sidebar_content: [TextSpan.new("Sidebar", %{background_color: 0})],
         content: build_content()
       )}
    end

    def render(assigns) do
      ~H"""
      <box class="grid grid-cols-1 grid-rows-2 width-screen height-screen bg-panel">
        <box class="height-2 bg-panel">{@header_content}</box>
        <box class="grid grid-cols-2 width-full height-full bg-panel">
          <box class="width-8 bg-panel">{@sidebar_content}</box>
          <box
            id="large-scroll-content"
            implicit={Breeze.Implicit.Scroll}
            focusable
            class="width-full height-full bg-panel overflow-scroll"
            style={%{scrollbar: %{arrows: true}}}
          >
            {@content}
          </box>
        </box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}

    defp build_content do
      Source.lazy(
        cache_key: :nested_grid_virtual_scroll_view,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 30 end,
        slice_fn: fn start_line, visible_count, _width ->
          Enum.map(start_line..(start_line + visible_count - 1), fn line_no ->
            index = line_no + 1

            if index <= 30 do
              [
                {"Line " <> String.pad_leading(Integer.to_string(index), 2, "0"),
                 %{background_color: 0}}
              ]
            else
              ""
            end
          end)
        end
      )
    end
  end

  describe "init/3" do
    test "carries autoscroll configuration from root attrs" do
      assert {:ok, state, meta} = Scroll.init([], %{"scroll-autoscroll": "bottom"}, %{})

      assert state.offset_y == 0
      assert state.autoscroll == "bottom"
      assert state.pinned_bottom == true
      assert meta[:requires_layout_rerender] == true
    end

    test "preserves prior scroll state" do
      assert {:ok, state, meta} =
               Scroll.init([], %{}, %{offset_y: 4, autoscroll: "bottom", pinned_bottom: false})

      assert state.offset_y == 4
      assert state.autoscroll == "bottom"
      assert state.pinned_bottom == false
      assert meta[:requires_layout_rerender] == true
    end
  end

  describe "handle_event/3" do
    test "updates offset and clears pinned_bottom when user scrolls away" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 8, autoscroll: "bottom", pinned_bottom: true}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :input,
                 %{"key" => "ArrowUp", "element" => viewport},
                 state
               )

      assert next_state.offset_y == 7
      assert next_state.pinned_bottom == false
    end

    test "keeps pinned_bottom when user scrolls to end" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 6, autoscroll: "bottom", pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(:input, %{"key" => "End", "element" => viewport}, state)

      assert next_state.offset_y == 8
      assert next_state.pinned_bottom == true
    end

    test "wheel scroll moves the viewport" do
      viewport = %{viewport_height: 4, content_height: 12, height: 4}
      state = %{offset_y: 3, autoscroll: nil, pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :input,
                 %{"mouse" => %{button: :wheel_down}, "element" => viewport},
                 state
               )

      assert next_state.offset_y == 5
      assert next_state.pinned_bottom == false
    end

    test "wheel scroll respects coalesced repeat counts" do
      viewport = %{viewport_height: 4, content_height: 20, height: 4}
      state = %{offset_y: 3, autoscroll: nil, pinned_bottom: false}

      assert {:noreply, next_state} =
               Scroll.handle_event(
                 :input,
                 %{"mouse" => %{button: :wheel_down, repeat: 3}, "element" => viewport},
                 state
               )

      assert next_state.offset_y == 9
    end
  end

  describe "handle_modifiers/3" do
    test "autoscrolls to bottom when pinned" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 14, height: 5})
      state = %{offset_y: 4, autoscroll: "bottom", pinned_bottom: true}

      assert [scroll_y: 9] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end

    test "does not autoscroll when user has scrolled away" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 14, height: 5})
      state = %{offset_y: 3, autoscroll: "bottom", pinned_bottom: false}

      assert [scroll_y: 3] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end

    test "clamps offset even without autoscroll" do
      viewport = Viewport.from_dimensions(%{viewport_height: 5, content_height: 9, height: 5})
      state = %{offset_y: 20}

      assert [scroll_y: 4] = Scroll.handle_modifiers(:root, [layout_element: viewport], state)
    end
  end

  describe "virtual text integration" do
    test "scrolls root content while keeping absolute overlay children visible" do
      terminal = %Termite.Terminal{size: %{width: 24, height: 8}}

      {:ok, pid} = start_child_server(view: VirtualScrollView, terminal: terminal)
      assert {:ok, _acc, initial_box} = ChildServer.render(pid, terminal: terminal)

      assert initial_box.content =~ "Fixed overlay"
      assert initial_box.content =~ "Line "
      assert initial_box.content =~ "01"

      assert {:noreply, "large-scroll", _consumed} = ChildServer.dispatch_input(pid, "PageDown")
      assert {:ok, _acc, next_box} = ChildServer.render(pid, terminal: terminal)

      assert next_box.content =~ "Fixed overlay"
      refute next_box.content =~ "01"
      assert next_box.content =~ "05"
    end

    test "scrolls nested grid virtual text content" do
      terminal = %Termite.Terminal{size: %{width: 24, height: 8}}

      {:ok, pid} = start_child_server(view: NestedGridVirtualScrollView, terminal: terminal)
      assert {:ok, _acc, initial_box} = ChildServer.render(pid, terminal: terminal)
      assert Breeze.ChildServer.metadata(pid).focused == "large-scroll-content"

      assert initial_box.content =~ "Line 01"

      assert {:noreply, "large-scroll-content", true} =
               ChildServer.dispatch_input(pid, "PageDown")

      assert {:ok, _acc, next_box} = ChildServer.render(pid, terminal: terminal)
      refute next_box.content =~ "Line 01"
      assert next_box.content =~ "Line 06"
    end
  end
end
