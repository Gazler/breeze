defmodule Breeze.Implicit.InputTest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box
  alias Breeze.ChildServer
  alias Breeze.Implicit.Input

  defmodule InputView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term}

    def render(assigns) do
      ~H"""
      <box
        id="url"
        implicit={Breeze.Implicit.Input}
        input-value="https://jsonplaceholder.typicode.com/posts"
        input-cursor="42"
      >
        {@input_value}
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule NestedInputView do
    use Breeze.View

    def mount(_opts, term), do: {:ok, term |> Breeze.View.focus("url")}

    def render(assigns) do
      ~H"""
      <box style="border">
        <box style="border">
          <box id="url" implicit={Breeze.Implicit.Input} input-value="hello" input-cursor="2" focusable>
            hello
          </box>
        </box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule OverflowInputView do
    use Breeze.View

    @website "https://jsonplaceholder.typicode.com/posts/123/comments?include=author,history"

    def mount(_opts, term) do
      {:ok,
       term
       |> Breeze.View.focus("website")
       |> Breeze.View.assign(
         website: @website,
         website_cursor: String.length(@website)
       )}
    end

    def render(assigns) do
      assigns =
        Breeze.View.assign(assigns,
          website_display: " " <> assigns.website,
          website_cursor_text: Integer.to_string(assigns.website_cursor)
        )

      ~H"""
      <box style="width-40">
        <box style="inline height-1 width-full">
          <box
            id="website"
            implicit={Breeze.Implicit.Input}
            input-value={@website}
            input-cursor={@website_cursor}
            focusable
            br-change="website_changed"
            style="width-24 focus:inverse"
          >
            {@website_display}
          </box>
          <box style="width-4">{@website_cursor_text}</box>
        </box>
      </box>
      """
    end

    def handle_event("website_changed", %{value: value, cursor: cursor}, term) do
      {:noreply, Breeze.View.assign(term, website: value, website_cursor: cursor)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "init returns normalized state and cursor animation metadata" do
    assert {:ok, %{cursor: 1, value: "", placeholder: nil},
            rerender_every: 500, active_when_focused: true} =
             Input.init([], %{id: "input"}, %{})
  end

  test "backspace clamps an out-of-range cursor" do
    state = %{value: "", cursor: 1}

    assert {{:change, %{value: "", cursor: 0}}, %{value: "", cursor: 0}} =
             Input.handle_event(nil, %{"key" => "ArrowLeft"}, state)

    assert {:noreply, %{value: "", cursor: 0}} =
             Input.handle_event(nil, %{"key" => "\x7f"}, %{value: "", cursor: 0})

    assert {:ok, %{value: "", cursor: 1, placeholder: nil},
            rerender_every: 500, active_when_focused: true} =
             Input.init([], %{:"input-value" => "", :"input-cursor" => 4}, %{})
  end

  test "init prefers input attrs over previous implicit state" do
    assert {:ok, %{value: "", cursor: 0, placeholder: nil},
            rerender_every: 500, active_when_focused: true} =
             Input.init([], %{:"input-value" => "", :"input-cursor" => 0}, %{
               value: "stale",
               cursor: 5,
               placeholder: "stale"
             })
  end

  test "renders placeholder content when the value is empty" do
    assert {:ok, %Box{content: " Search docs"}, overlays: [%{visible?: true}]} =
             Input.animate(
               :root,
               %Box{content: "", style: %BackBreeze.Style{}},
               [focused: true],
               %{value: "", cursor: 1, placeholder: "Search docs"},
               %{layout: %{left: 0, top: 0}, now: 0, last_interaction_at: nil}
             )
  end

  test "input modifiers only add runtime placeholder state" do
    assert [] =
             Input.handle_modifiers(:root, [], %{value: "hello", placeholder: nil})

    assert [placeholder: true] =
             Input.handle_modifiers(:root, [], %{value: "", placeholder: "Search docs"})

    assert [placeholder: true] =
             Input.handle_modifiers(:child, [], %{value: "", placeholder: "Search docs"})
  end

  test "animate leaves focused content untouched" do
    assert %Box{content: "hello"} =
             Input.animate(
               :root,
               %Box{content: "hello"},
               [focused: true],
               %{value: "hello", cursor: 2},
               %{}
             )
  end

  test "animate can return geometry-aware overlay data" do
    box = %Box{style: %BackBreeze.Style{border: BackBreeze.Border.line()}}
    theme = Breeze.Theme.Builtin.nebula()

    assert {:ok, %Box{content: " hello"},
            overlays: [
              %{
                x: 15,
                y: 5,
                char: " ",
                foreground_color: {13, 33, 55},
                background_color: {255, 121, 198},
                visible?: true
              }
            ]} =
             Input.animate(:root, box, [focused: true], %{value: "hello", cursor: 7}, %{
               layout: %{left: 6, top: 4},
               now: 0,
               last_interaction_at: nil,
               theme: theme
             })
  end

  test "animate keeps the overlay visible right after interaction" do
    box = %Box{content: "hello", style: %BackBreeze.Style{border: BackBreeze.Border.line()}}

    assert {:ok, %Box{}, overlays: [%{visible?: true}]} =
             Input.animate(:root, box, [focused: true], %{value: "hello", cursor: 5}, %{
               layout: %{left: 6, top: 4},
               now: 500,
               last_interaction_at: 1
             })
  end

  test "animate scrolls overflowing content and pins the cursor to the edge" do
    box = %Box{
      content: " hello world",
      style: %BackBreeze.Style{border: BackBreeze.Border.line()}
    }

    assert {:ok, %Box{content: "world "}, overlays: [%{x: 12, y: 5, char: " ", visible?: true}]} =
             Input.animate(
               :root,
               box,
               [focused: true],
               %{value: "hello world", cursor: 11, viewport_width: 6},
               %{
                 layout: %{left: 6, top: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "animate keeps overflow content stable during async overlay passes" do
    box = %Box{
      content: "istory                  ",
      style: %BackBreeze.Style{border: BackBreeze.Border.line()}
    }

    assert {:ok, %Box{content: "?include=author,history "},
            overlays: [%{x: 30, y: 5, char: " ", visible?: true}]} =
             Input.animate(
               :root,
               box,
               [focused: true],
               %{
                 value:
                   "https://jsonplaceholder.typicode.com/posts/123/comments?include=author,history",
                 cursor: 78,
                 viewport_width: 24
               },
               %{
                 layout: %{left: 6, top: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "arrow right and end stop at the end of the input value" do
    assert {:noreply, %{value: "hello", cursor: 5}} =
             Input.handle_event(nil, %{"key" => "ArrowRight"}, %{value: "hello", cursor: 5})

    assert {{:change, %{value: "hello", cursor: 5}}, %{value: "hello", cursor: 5}} =
             Input.handle_event(nil, %{"key" => "End"}, %{value: "hello", cursor: 2})
  end

  test "control-newline keys are ignored" do
    assert {:noreply, %{value: "hello", cursor: 2}} =
             Input.handle_event(nil, %{"key" => "\n"}, %{value: "hello", cursor: 2})
  end

  test "non-binary keys are ignored" do
    assert {:noreply, %{value: "hello", cursor: 2}} =
             Input.handle_event(nil, %{"key" => %{"key" => "F2"}}, %{value: "hello", cursor: 2})
  end

  test "delete removes the grapheme under the cursor" do
    assert {{:change, %{value: "helo", cursor: 2}}, %{value: "helo", cursor: 2}} =
             Input.handle_event(nil, %{"key" => "Delete"}, %{value: "hello", cursor: 2})
  end

  test "ctrl-w deletes the previous word and surrounding gap" do
    assert {{:change, %{value: "hello", cursor: 5}}, %{value: "hello", cursor: 5}} =
             Input.handle_event(nil, %{"key" => "\x17"}, %{value: "hello   world", cursor: 13})
  end

  test "ctrl-backspace via ctrl-h deletes the previous word and surrounding gap" do
    assert {{:change, %{value: "hello", cursor: 5}}, %{value: "hello", cursor: 5}} =
             Input.handle_event(nil, %{"key" => "\x08"}, %{value: "hello   world", cursor: 13})
  end

  test "ctrl-w is a no-op at the start of the input" do
    assert {:noreply, %{value: "hello", cursor: 0}} =
             Input.handle_event(nil, %{"key" => "\x17"}, %{value: "hello", cursor: 0})
  end

  test "control characters are not treated as insertable input" do
    assert {:noreply, %{value: "hello", cursor: 2}} =
             Input.handle_event(nil, %{"key" => "\x01"}, %{value: "hello", cursor: 2})
  end

  test "animate leaves unfocused content untouched" do
    assert %Box{content: "hello"} =
             Input.animate(:root, %Box{content: "hello"}, [], %{value: "hello", cursor: 2}, %{})
  end

  test "child server accepts implicits that return {:ok, state}" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: InputView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)

    assert %Breeze.Term{
             implicit_state: %{
               "url" => {Breeze.Implicit.Input, %{value: value, cursor: 42}}
             }
           } = :sys.get_state(pid)

    assert value == "https://jsonplaceholder.typicode.com/posts"
  end

  test "nested input layout stores screen-relative coordinates" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 10}}
    {:ok, pid} = ChildServer.start(view: NestedInputView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)

    assert %Breeze.Term{
             elements: %{
               "url" => %Breeze.Viewport{left: 2, top: 2}
             }
           } = :sys.get_state(pid)
  end

  test "child server renders a fixed-width input with a scrolled visible slice" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: OverflowInputView, terminal: terminal)

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)

    assert %Breeze.Term{
             implicit_state: %{
               "website" => {Breeze.Implicit.Input, %{value: _, cursor: 78}}
             }
           } = :sys.get_state(pid)

    assert box.content =~ "?include=author,history "
    refute box.content =~ "https://jsonplaceholder.typicode.com/posts"
  end

  test "child server keeps the cursor pinned when typing at the overflow edge" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: OverflowInputView, terminal: terminal)

    assert {:ok, _acc, initial_box} = ChildServer.render(pid, terminal: terminal)
    assert initial_box.content =~ "?include=author,history "

    assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "!")

    assert %Breeze.Term{
             implicit_state: %{
               "website" => {Breeze.Implicit.Input, %{value: value, cursor: 79}}
             }
           } = :sys.get_state(pid)

    assert String.ends_with?(value, "history!")

    assert {:ok, _acc, next_box} = ChildServer.render(pid, terminal: terminal)

    assert next_box.content =~ "include=author,history! "
    refute next_box.content =~ "comments?include=author,history"
  end

  test "child server scrolls back left after backspace from the overflow edge" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: OverflowInputView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "!")

    assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "\x7f")

    assert %Breeze.Term{
             implicit_state: %{
               "website" => {Breeze.Implicit.Input, %{value: value, cursor: 78}}
             }
           } = :sys.get_state(pid)

    assert String.ends_with?(value, "history")

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)

    assert box.content =~ "?include=author,history "
    refute box.content =~ "include=author,history!"
  end

  test "child server reveals earlier content when moving left out of the overflow edge" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: OverflowInputView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)

    Enum.each(1..12, fn _ ->
      assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "ArrowLeft")
    end)

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)

    assert box.content =~ "23/comments?include=aut "
    refute box.content =~ "?include=author,history "
  end

  test "child server delete updates a scrolled input through the normal key path" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    {:ok, pid} = ChildServer.start(view: OverflowInputView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "ArrowLeft")
    assert {:noreply, "website", true} = ChildServer.dispatch_input(pid, "Delete")

    assert %Breeze.Term{
             implicit_state: %{
               "website" => {Breeze.Implicit.Input, %{value: value, cursor: 77}}
             }
           } = :sys.get_state(pid)

    refute String.contains?(value, "history")
    assert String.ends_with?(value, "histor")
  end

  test "animate can derive viewport width from layout metadata without storing it in state" do
    box = %Box{
      content: " hello world",
      style: %BackBreeze.Style{border: BackBreeze.Border.line()}
    }

    assert {:ok, %Box{content: "world "}, overlays: [%{x: 12, y: 5, char: " ", visible?: true}]} =
             Input.animate(
               :root,
               box,
               [focused: true],
               %{value: "hello world", cursor: 11},
               %{
                 layout: %{left: 6, top: 4, viewport_width: 6},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end
end
