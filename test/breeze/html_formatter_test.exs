defmodule Breeze.HTMLFormatterTest do
  use ExUnit.Case, async: true

  alias Breeze.HTMLFormatter

  test "formats nested elements and interpolation" do
    source = "<box><box style=\"bold\">Hello {@name}</box></box>"

    assert HTMLFormatter.format(source, sigil: :H, opening_delimiter: "\"\"\"") ==
             """
             <box>
               <box style="bold">Hello {@name}</box>
             </box>
             """
  end

  test "wraps attributes when a line is too long" do
    source = "<.panel id={@id} class=\"foo bar baz\" br-change=\"change\" />"

    assert HTMLFormatter.format(source,
             sigil: :H,
             opening_delimiter: "\"\"\"",
             line_length: 30
           ) ==
             """
             <.panel
               id={@id}
               class="foo bar baz"
               br-change="change"
             />
             """
  end

  test "keeps :for/:let/:if directives and assign syntax" do
    source =
      "<.table><:col :for={item <- @items} :let={row} :if={@enabled}>{row.value}</:col></.table>"

    assert HTMLFormatter.format(source, sigil: :H, opening_delimiter: "\"\"\"") ==
             """
             <.table>
               <:col :for={item <- @items} :let={row} :if={@enabled}>{row.value}</:col>
             </.table>
             """
  end

  test "formats slot blocks with directives" do
    source = "<.list><:item :for={x <- @items} value={x}><box>{x}</box></:item></.list>"

    assert HTMLFormatter.format(source,
             sigil: :H,
             opening_delimiter: "\"\"\"",
             line_length: 40
           ) ==
             """
             <.list>
               <:item :for={x <- @items} value={x}>
                 <box>{x}</box>
               </:item>
             </.list>
             """
  end

  test "keeps eex expressions and assign syntax" do
    source = "<box><%= String.upcase(@name) %></box>"

    assert HTMLFormatter.format(source, sigil: :H, opening_delimiter: "\"\"\"") ==
             """
             <box><%= String.upcase(@name) %></box>
             """
  end

  test "formats boolean and spread attributes" do
    source = "<box focusable id={@id} {@rest}>x</box>"

    assert HTMLFormatter.format(source,
             sigil: :H,
             opening_delimiter: "\"\"\"",
             line_length: 20
           ) ==
             """
             <box
               focusable
               id={@id}
               {@rest}
             >
               x
             </box>
             """
  end

  test "normalizes blank lines deterministically" do
    source = "\n\n<box><box>a</box></box>\n\n\n"

    formatted =
      HTMLFormatter.format(source,
        sigil: :H,
        opening_delimiter: "\"\"\""
      )

    assert formatted ==
             """
             <box>
               <box>a</box>
             </box>
             """

    assert HTMLFormatter.format(formatted,
             sigil: :H,
             opening_delimiter: "\"\"\""
           ) == formatted
  end

  test "supports ~H\"...\" noformat modifier" do
    source = "<box><box>{@name}</box></box>"
    assert HTMLFormatter.format(source, sigil: :H, modifiers: ~c"noformat") == source
  end
end
