defmodule Breeze.Implicit.TextareaTest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box
  alias Breeze.ChildServer
  alias Breeze.Implicit.Textarea

  defmodule BlockTextareaView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok,
       term
       |> Breeze.View.focus("composer")
       |> Breeze.View.assign(message: "hello")}
    end

    def render(assigns) do
      ~H"""
      <box style="width-16">
        <.textarea
          id="composer"
          textarea-value={@message}
          textarea-placeholder="Ask anything"
          textarea-prefix="› "
          br-change="message_changed"
          style="width-full height-4"
        />
      </box>
      """
    end

    def handle_event("message_changed", %{value: value}, term) do
      {:noreply, Breeze.View.assign(term, message: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SubmitTextareaView do
    use Breeze.View
    import Breeze.Blocks

    def mount(_opts, term) do
      {:ok,
       term
       |> Breeze.View.focus("composer")
       |> Breeze.View.assign(message: "hello", submitted: nil)}
    end

    def render(assigns) do
      ~H"""
      <box>
        <.textarea
          id="composer"
          textarea-value={@message}
          textarea-submit-on-enter
          br-change="message_changed"
          br-submit="message_submitted"
          style="width-16 height-4"
        />
        <box>submitted={@submitted}</box>
      </box>
      """
    end

    def handle_event("message_changed", %{value: value}, term) do
      {:noreply, Breeze.View.assign(term, message: value)}
    end

    def handle_event("message_submitted", %{value: value}, term) do
      {:noreply, Breeze.View.assign(term, submitted: value)}
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule DisabledTextareaView do
    use Breeze.View
    import Breeze.Blocks

    def render(assigns) do
      ~H"""
      <box>
        <.textarea
          id="history-prompt"
          textarea-value="read only"
          textarea-prefix="› "
          disabled
          style="width-20 height-3"
        />
        <.textarea id="composer" textarea-value="" textarea-prefix="› " style="width-20 height-3"/>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  test "init returns normalized state and cursor animation metadata" do
    assert {:ok, %{cursor: 0, value: "", placeholder: nil, preferred_column: nil}, meta} =
             Textarea.init([], %{id: "composer"}, %{})

    assert meta[:rerender_every] == 500
    assert meta[:active_when_focused] == true
    assert meta[:captures_printable_keys] == true
    assert meta[:requires_layout_rerender] == true
  end

  test "init preserves the previous cursor when the same value includes a textarea-cursor hint" do
    assert {:ok, %{value: "hello", cursor: 2, placeholder: nil}, _meta} =
             Textarea.init([], %{:"textarea-value" => "hello", :"textarea-cursor" => 4}, %{
               value: "hello",
               cursor: 2,
               placeholder: nil
             })
  end

  test "enter inserts a newline" do
    assert {{:change, %{value: "hello\n", cursor: 6}},
            %{value: "hello\n", cursor: 6, preferred_column: nil, submit_on_enter?: false}} =
             Textarea.handle_event(nil, %{"key" => "Enter"}, %{
               value: "hello",
               cursor: 5,
               submit_on_enter?: false,
               preferred_column: nil
             })
  end

  test "enter submits when configured and ctrl-j still inserts a newline" do
    state = %{value: "hello", cursor: 5, submit_on_enter?: true, preferred_column: nil}

    assert {{:submit, %{value: "hello", cursor: 5}}, ^state} =
             Textarea.handle_event(nil, %{"key" => "Enter"}, state)

    assert {{:change, %{value: "hello\n", cursor: 6}},
            %{value: "hello\n", cursor: 6, submit_on_enter?: true, preferred_column: nil}} =
             Textarea.handle_event(nil, %{"ctrlKey" => true, "key" => "j"}, state)

    assert {{:change, %{value: "hello\n", cursor: 6}},
            %{value: "hello\n", cursor: 6, submit_on_enter?: true, preferred_column: nil}} =
             Textarea.handle_event(nil, %{"shiftKey" => true, "key" => "Enter"}, state)
  end

  test "arrow up and down move between explicit lines" do
    state = %{value: "alpha\nbeta\ngamma", cursor: 8, preferred_column: nil}

    assert {:noreply, %{cursor: 2, preferred_column: 2}} =
             Textarea.handle_event(nil, %{"key" => "ArrowUp"}, state)

    assert {:noreply, %{cursor: 13, preferred_column: 2}} =
             Textarea.handle_event(nil, %{"key" => "ArrowDown"}, state)
  end

  test "home and end move within the current line" do
    state = %{value: "alpha\nbeta\ngamma", cursor: 8, preferred_column: nil}

    assert {:noreply, %{cursor: 6, preferred_column: nil}} =
             Textarea.handle_event(nil, %{"key" => "Home"}, state)

    assert {:noreply, %{cursor: 10, preferred_column: nil}} =
             Textarea.handle_event(nil, %{"key" => "End"}, state)
  end

  test "ctrl-backspace deletes the previous word for structured key events" do
    state = %{value: "hello world", cursor: 11, preferred_column: nil}

    assert {{:change, %{value: "hello", cursor: 5}},
            %{value: "hello", cursor: 5, preferred_column: nil}} =
             Textarea.handle_event(nil, %{"ctrlKey" => true, "key" => "Backspace"}, state)
  end

  test "renders placeholder content when the value is empty" do
    box = %Box{content: "", style: %BackBreeze.Style{padding_left: 1, padding_top: 1}}

    assert {:ok, %Box{content: "Search docs"},
            overlays: [%{visible?: true, x: 1, y: 1, char: "S"}]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "", cursor: 0, placeholder: "Search docs", preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 14, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "animate wraps long lines and moves the cursor onto the next visual row" do
    box = %Box{content: "", style: %BackBreeze.Style{padding_left: 1, padding_top: 1}}

    assert {:ok, %Box{content: "abcde\nf"}, overlays: [%{x: 2, y: 2, char: " ", visible?: true}]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "abcdef", cursor: 6, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 6, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "animate prefers breaking at whitespace when wrapping" do
    box = %Box{content: "", style: %BackBreeze.Style{padding_left: 1, padding_top: 1}}

    assert {:ok, %Box{content: "hello \nworld"}, overlays: [_]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "hello world", cursor: 6, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 7, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "animate falls back to character wrapping for long words" do
    box = %Box{content: "", style: %BackBreeze.Style{padding_left: 1, padding_top: 1}}

    assert {:ok, %Box{content: "abcdef\ng"}, overlays: [_]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "abcdefg", cursor: 7, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 7, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "animate wraps the cursor to the next visual row when the bordered content width is exactly filled" do
    box =
      %Box{
        content: "",
        style: %BackBreeze.Style{
          padding_left: 1,
          padding_right: 1,
          border: BackBreeze.Border.rounded(),
          width: 10,
          height: 4
        }
      }

    assert {:ok, %Box{content: "123456\n"}, overlays: [%{x: 2, y: 2, char: " ", visible?: true}]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "123456", cursor: 6, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 10, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "borderless textarea height does not subtract border rows" do
    box =
      %Box{
        content: "",
        style: %BackBreeze.Style{
          padding_left: 1,
          padding_right: 1,
          width: 10,
          height: 4
        }
      }

    assert {:ok, %Box{content: "12345678\n9"},
            overlays: [%{x: 2, y: 1, char: " ", visible?: true}]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "123456789", cursor: 9, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 10, viewport_height: 4},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "wrapped prompt-style textarea keeps the cursor aligned in a borderless box" do
    box =
      %Box{
        content: "",
        style: %BackBreeze.Style{
          padding_left: 2,
          padding_right: 1,
          padding_top: 1,
          padding_bottom: 1,
          border: BackBreeze.Border.none(),
          width: 10,
          height: 5
        }
      }

    assert {:ok, %Box{content: "abcdefg\nhij"},
            overlays: [%{x: 5, y: 2, char: " ", visible?: true}]} =
             Textarea.animate(
               :root,
               box,
               [focused: true],
               %{value: "abcdefghij", cursor: 10, placeholder: nil, preferred_column: nil},
               %{
                 layout: %{left: 0, top: 0, viewport_width: 10, viewport_height: 5},
                 now: 0,
                 last_interaction_at: nil
               }
             )
  end

  test "public textarea block updates through br-change" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = ChildServer.start(view: BlockTextareaView, terminal: terminal)

    assert {:ok, _acc, initial_box} = ChildServer.render(pid, terminal: terminal)
    initial_content = Regex.replace(~r/\e\[[0-9;]*m/u, initial_box.content, "")
    assert initial_content =~ "› "
    assert initial_content =~ "hello"

    assert {:noreply, "composer", true} = ChildServer.dispatch_input(pid, "Enter")
    assert {:noreply, "composer", true} = ChildServer.dispatch_input(pid, "w")

    assert {:ok, _acc, box} = ChildServer.render(pid, terminal: terminal)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    lines = String.split(plain_content, "\n")

    assert Enum.any?(lines, &String.contains?(&1, "hello"))
    assert Enum.any?(lines, &String.contains?(&1, "› "))
    assert Enum.any?(lines, &String.contains?(&1, "w"))
  end

  test "public textarea block can submit on enter" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = ChildServer.start(view: SubmitTextareaView, terminal: terminal)

    assert {:ok, _acc, _box} = ChildServer.render(pid, terminal: terminal)
    assert {:noreply, "composer", true} = ChildServer.dispatch_input(pid, "Enter")

    assert %{assigns: %{submitted: "hello", message: "hello"}} = ChildServer.metadata(pid)
  end

  test "disabled public textarea renders without becoming focusable or implicit" do
    terminal = %Termite.Terminal{size: %{width: 40, height: 12}}
    {:ok, pid} = ChildServer.start(view: DisabledTextareaView, terminal: terminal)

    assert {:ok, acc, box} = ChildServer.render(pid, terminal: terminal)
    metadata = ChildServer.metadata(pid)

    refute Map.has_key?(metadata.implicit_state, "history-prompt")
    assert Map.has_key?(metadata.implicit_state, "composer")

    refute Enum.any?(acc.elements, fn {_index, flags} ->
             to_string(Keyword.get(flags, :style)) =~ "absolute" and
               Keyword.get(flags, :breeze_component) == "Breeze.Blocks.textarea"
           end)

    plain_content = Regex.replace(~r/\e\[[0-9;]*m/u, box.content, "")
    assert plain_content =~ "› read only"
    refute plain_content =~ "›\n› read only"
  end
end
