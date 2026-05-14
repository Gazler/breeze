defmodule Breeze.TemplateTest do
  use ExUnit.Case, async: true

  defmodule InterpolationView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>Hello {@name} <%= String.upcase(@name) %></box>"
    end
  end

  defmodule ConditionalView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>
  <box :if={@show}>yes</box>
</box>"
    end
  end

  defmodule ForView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>
  <box :for={{left, right} <- @pairs}>{left}:{right}</box>
</box>"
    end
  end

  defmodule IgnoreBindingForView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>
  <box :for={{_, right} <- @pairs}>{right}{123}</box>
</box>"
    end
  end

  defmodule MapPatternForView do
    use Breeze.View

    def render(assigns) do
      ~H"<box>
  <box :for={%{label: label} <- @items}>{label}</box>
</box>"
    end
  end

  defmodule AttributeView do
    use Breeze.View

    def render(assigns) do
      ~H"<box id={@id} hidden={@hidden} {@extra}>x</box>"
    end
  end

  defmodule ComponentView do
    use Breeze.View

    attr :rest, :global
    slot :inner_block

    def wrapper(assigns) do
      ~H|<box class="wrapper" {@rest}>{render_slot(@inner_block)}</box>|
    end

    def render(assigns) do
      ~H|<.wrapper br-change="tick">
  <box>inner {@name}</box>
</.wrapper>|
    end
  end

  defmodule SlotView do
    use Breeze.View

    slot :item do
      attr :label, :string
    end

    def list(assigns) do
      ~H|<box>
  <box :for={item <- @item}>{item.label}:{render_slot(item, %{suffix: "!"})}</box>
</box>|
    end

    def render(assigns) do
      ~H"<.list>
  <:item :for={label <- @labels} label={label}>{label}{suffix}</:item>
</.list>"
    end
  end

  defmodule SlotLetView do
    use Breeze.View

    attr :rows, :list, default: []
    slot :col

    def table(assigns) do
      ~H"""
      <box>
        <box :for={row <- @rows}>{render_slot(@col, row)}</box>
      </box>
      """
    end

    def render(assigns) do
      ~H"""
      <.table rows={@rows}>
        <:col :let={row}>{row.name}</:col>
      </.table>
      """
    end
  end

  defmodule PrivateComponentView do
    use Breeze.View

    def render(assigns) do
      ~H"<.secret value={@value}/>"
    end

    defp secret(assigns) do
      ~H"<box>secret {@value}</box>"
    end
  end

  describe "rendering" do
    test "supports @assign interpolation and eex expressions" do
      assert render(InterpolationView, %{name: "world"}) == "<box>Hello world WORLD</box>"
    end

    test "supports :if directive" do
      assert render(ConditionalView, %{show: true}) == "<box><box>yes</box></box>"
      assert render(ConditionalView, %{show: false}) == "<box></box>"
    end

    test "supports :for directive with pattern matching" do
      assert render(ForView, %{pairs: [{1, "a"}, {2, "b"}]}) ==
               "<box><box>1:a</box><box>2:b</box></box>"
    end

    test "supports compiled simple :for patterns with ignored bindings and literals" do
      assert render(IgnoreBindingForView, %{pairs: [{1, "a"}, {2, "b"}]}) ==
               "<box><box>a123</box><box>b123</box></box>"
    end

    test "falls back to eval for unsupported :for patterns" do
      assert render(MapPatternForView, %{items: [%{label: "a"}, %{label: "b"}]}) ==
               "<box><box>a</box><box>b</box></box>"
    end

    test "supports dynamic/boolean/spread attributes" do
      html = render(AttributeView, %{id: "id-1", hidden: false, extra: %{:"br-change" => "go"}})

      assert html == ~s(<box id="id-1" br-change="go">x</box>)
    end

    test "supports components with rest attrs and inner_block" do
      html = render(ComponentView, %{name: "joe"})

      assert html == ~s(<box class="wrapper" br-change="tick"><box>inner joe</box></box>)
    end

    test "supports named slots, :for on slots, and render_slot assigns" do
      assert render(SlotView, %{labels: ["a", "b"]}) ==
               "<box><box>a:a!</box><box>b:b!</box></box>"
    end

    test "supports :let on slots" do
      assert render(SlotLetView, %{rows: [%{name: "Ada"}, %{name: "Grace"}]}) ==
               "<box><box>Ada</box><box>Grace</box></box>"
    end

    test "supports private function components" do
      assert render(PrivateComponentView, %{value: "ok"}) == "<box>secret ok</box>"
    end
  end

  describe "compile errors" do
    test ":if requires an expression" do
      assert_raise RuntimeError, ~r/the :if directive requires an expression/, fn ->
        Breeze.Template.compile!("<box :if=\"true\"></box>", __ENV__)
      end
    end

    test ":for requires an expression" do
      assert_raise RuntimeError, ~r/the :for directive requires an expression/, fn ->
        Breeze.Template.compile!("<box :for=\"item <- @items\"></box>", __ENV__)
      end
    end

    test "invalid :for expression raises" do
      assert_raise RuntimeError, ~r/invalid :for expression/, fn ->
        Breeze.Template.compile!("<box :for={@items}></box>", __ENV__)
      end
    end

    test "missing closing tag raises" do
      assert_raise RuntimeError, ~r/missing closing tag/, fn ->
        Breeze.Template.compile!("<box><box></box>", __ENV__)
      end
    end
  end

  defp render(view, assigns) do
    view.render(assigns)
    |> Breeze.Template.render_to_string(assigns)
  end
end
