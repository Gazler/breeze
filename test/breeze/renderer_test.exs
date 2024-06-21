defmodule Breeze.RendererTest do
  use ExUnit.Case, async: true
  alias Breeze.Renderer

  defmodule Example do
    use Breeze.View

    def render(assigns) do
      ~H"""
      <box style={style(%{border: :line})}>
        <box style={style(%{foreground_color: 3, position: :absolute, left: 1, top: 0})}>
          Title
        </box>
        <box style={style(%{bold: true})}>
          Hello <%= @name %>
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

  describe "parse/1" do
    alias BackBreeze.Box

    test "converts a string to boxes" do
      data =
        Phoenix.HTML.Safe.to_iodata(Example.render(%{name: "world"}))
        |> IO.iodata_to_binary()

      boxes = Renderer.parse(data)

      assert boxes == %Box{
               style: BackBreeze.Style.border(),
               children: [
                 %Box{
                   content: "Title",
                   style: BackBreeze.Style.foreground_color(3),
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
