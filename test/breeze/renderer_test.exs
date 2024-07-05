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
        <box style="bold">Hello <%= @name %></box>
      </.panel>
      """
    end

    slot(:title)
    slot(:inner_block)

    defp panel(assigns) do
      ~H"""
      <box style="border">
        <box :if={assigns[:title]} style="absolute left-1 top-0">
          <%= render_slot(@title) %>
        </box>
        <%= render_slot(@inner_block) %>
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

  describe "parse/2" do
    alias BackBreeze.Box

    test "converts a string to boxes" do
      data =
        Phoenix.HTML.Safe.to_iodata(Example.render(%{name: "world"}))
        |> IO.iodata_to_binary()

      {_, boxes} = Renderer.parse(data)

      assert boxes == %Box{
               style: BackBreeze.Style.border(),
               children: [
                 %Box{
                   children: [
                     %Box{
                       content: "Title",
                       style: BackBreeze.Style.foreground_color(3)
                     }
                   ],
                   position: :absolute,
                   left: 1,
                   top: 0
                 },
                 %Box{content: "Hello world", style: BackBreeze.Style.bold()}
               ]
             }
    end
  end
end
