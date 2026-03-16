defmodule Breeze.Blocks do
  @moduledoc """
  Reusable built-in components for Breeze views.

  Import this module in your view to use the provided components:

      defmodule MyView do
        use Breeze.View
        import Breeze.Blocks
        ...
      end

  ## Style merging

  All components expose a `style` attribute (and where applicable an
  `item_style` attribute) that are merged with the component's defaults using
  `merge_style/2`.  Style tokens are grouped by their *property key*, everything
  before the last `-` segment, so an override of `"width-32"` replaces the
  default `"width-24"` while leaving other properties intact (including `focus:`
  prefixes).
  """

  use Breeze.View

  attr :id, :string, required: true
  attr :loop, :boolean, default: true
  attr :style, :string, default: nil
  attr :item_style, :string, default: nil
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    assigns =
      assigns
      |> assign(
        style:
          merge_style(
            "border width-24 height-8 overflow-scroll scrollbar-arrows focus:border-3",
            assigns[:style]
          )
      )
      |> assign(
        item_style: merge_style("selected:bg-4 selected:text-7 width-24", assigns[:item_style])
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.List}
      list-loop={@loop}
      list-scroll-padding={1}
      focusable
      style={@style}
      {@rest}
    >
      <box :for={item <- @item} value={item.value} style={@item_style}>{render_slot(item, %{})}</box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :style, :string, default: nil
  attr :menu_style, :string, default: nil
  attr :item_style, :string, default: nil
  attr :width, :integer, default: nil
  attr :menu_width, :integer, default: nil
  attr :menu_top, :integer, default: 1
  attr :menu_left, :integer, default: 0
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def dropdown(assigns) do
    items_with_labels =
      Enum.map(assigns.item, fn item ->
        {item, render_slot(item, %{})}
      end)

    selected_label =
      case Enum.find(items_with_labels, fn {item, _label} ->
             Map.get(item, :value) == assigns[:selected]
           end) do
        {_item, label} -> label
        nil -> to_string(assigns[:selected] || "")
      end

    width =
      assigns[:width] ||
        items_with_labels
        |> Enum.map(fn {_item, label} -> String.length(label) + 4 end)
        |> Kernel.++([String.length(selected_label) + 4, 8])
        |> Enum.max()

    menu_width = assigns[:menu_width] || width
    menu_height = max(length(items_with_labels), 1)
    trigger_content = build_dropdown_trigger(selected_label, width)

    assigns =
      assigns
      |> assign(selected_label: selected_label)
      |> assign(width: width)
      |> assign(menu_width: menu_width)
      |> assign(menu_height: menu_height)
      |> assign(trigger_content: trigger_content)
      |> assign(
        trigger_style:
          merge_style(
            "bg-4 text-7 bold width-#{width} height-1 focus:inverse",
            assigns[:style]
          )
      )
      |> assign(menu_style: assigns[:menu_style])
      |> assign(
        item_style:
          merge_style(
            "width-#{menu_width} text-7 selected:bg-4 selected:text-7 focus:inverse",
            assigns[:item_style]
          )
      )

    assigns =
      assign(assigns,
        item_styles:
          items_with_labels
          |> Enum.with_index()
          |> Enum.map(fn {{item, _label}, index} ->
            {item, index, assigns.item_style}
          end)
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Dropdown}
      focusable
      dropdown-selected={@selected}
      dropdown-trigger-width={@width}
      dropdown-menu-width={@menu_width}
      dropdown-menu-height={@menu_height}
      dropdown-menu-top={@menu_top}
      dropdown-menu-left={@menu_left}
      style={@trigger_style}
      {@rest}
    >
      {@trigger_content}
      <box dropdown-indicator-closed="true" style={@trigger_style}>▼</box>
      <box dropdown-indicator-open="true" style={@trigger_style}>▲</box>
      <box dropdown-frame="true" style={@menu_style}>
      </box>
      <box
        :for={{item, index, item_style} <- @item_styles}
        dropdown-item="true"
        dropdown-item-index={index}
        value={item.value}
        style={item_style}
      >
        {render_slot(item, %{})}
      </box>
    </box>
    """
  end

  defp build_dropdown_trigger(label, width) do
    inner_width = max(width - 4, 0)
    padded = String.pad_trailing(to_string(label), inner_width) |> String.slice(0, inner_width)
    " " <> padded <> "   "
  end

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :style, :string, default: nil
  attr :item_style, :string, default: nil
  attr :rest, :global

  slot :tab do
    attr :value, :string, required: true
    attr :label, :string, required: true
  end

  def tabs(assigns) do
    active =
      Enum.find(assigns.tab, List.first(assigns.tab), &(&1.value == assigns[:selected]))

    assigns =
      assigns
      |> assign(active: active)
      |> assign(
        style:
          merge_style(
            "border overflow-hidden focus:border-3 grid grid-cols-1 grid-rows-2",
            assigns[:style]
          )
      )
      |> assign(
        item_style:
          merge_style(
            "selected:bold selected:text-4 focus:selected:bg-4 focus:selected:text-7 overflow-scroll",
            assigns[:item_style]
          )
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.Tabs}
      focusable
      tab-delegate={if @active do
      "#{@id}-panel-#{@active.value}"
    end}
      tab-selected={@active.value}
      style={@style}
      {@rest}
    >
      <box style="inline height-1" tab-bar="true">
        <box :for={t <- @tab} value={t.value} tab-label={t.label} style={@item_style}>
          {" #{t.label} "}
        </box>
      </box>
      <box style="height-full overflow-hidden">{render_slot(@active)}</box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :width, :integer, required: true
  attr :style, :string, default: nil

  def markdown(assigns) do
    assigns =
      assign(assigns,
        style:
          merge_style(
            "height-full overflow-scroll scrollbar-arrows focus:scrollbar-3",
            assigns[:style]
          )
      )

    ~H"""
    <.scroll id={@id} style={@style}>{Breeze.Markdown.render(@content, @width)}</.scroll>
    """
  end

  attr :id, :string, required: true
  attr :style, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def scroll(assigns) do
    assigns =
      assign(assigns,
        style:
          merge_style(
            "height-full overflow-scroll scrollbar-arrows focus:scrollbar-3",
            assigns[:style]
          )
      )

    ~H"""
    <box focusable id={@id} implicit={Breeze.Implicit.Scroll} style={@style} {@rest}>
      {render_slot(@inner_block)}
    </box>
    """
  end

  attr :width, :integer, required: true
  attr :height, :integer, required: true
  attr :style, :string, default: nil
  attr :title_style, :string, default: nil
  attr :rest, :global

  slot :title
  slot :inner_block

  def panel(assigns) do
    assigns =
      assigns
      |> assign(
        style: merge_style("border-rounded border-7 bg-0", assigns[:style]),
        title_style: merge_style("bold bg-0", assigns[:title_style])
      )

    ~H"""
    <box style={"#{@style} width-#{@width} height-#{@height}"} {@rest}>
      {render_slot(@inner_block)}
      <box :if={assigns[:title]} style={"absolute left-2 top-0 #{@title_style}"}>
        {render_slot(@title)}
      </box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :inset, :integer, default: nil
  attr :inset_x, :integer, default: nil
  attr :inset_y, :integer, default: nil
  attr :style, :string, default: nil
  attr :frame_style, :string, default: nil
  attr :rest, :global

  slot :title
  slot :inner_block

  def modal(assigns) do
    {frame_style, panel_style} =
      case {assigns[:width], assigns[:height], assigns[:inset], assigns[:inset_x],
            assigns[:inset_y]} do
        {width, height, nil, nil, nil} when is_integer(width) and is_integer(height) ->
          {
            merge_style(
              "fixed center width-#{width + 2} height-#{height + 2} bg-0 layer-50",
              assigns[:frame_style]
            ),
            merge_style(
              "absolute left-0 top-0 layer-51 width-#{width} height-#{height} border-rounded border-7 bg-0",
              assigns[:style]
            )
          }

        {nil, nil, inset, nil, nil} when is_integer(inset) ->
          {
            merge_style(
              "fixed inset-#{inset} width-screen height-screen bg-0 layer-50",
              assigns[:frame_style]
            ),
            merge_style(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-7 bg-0",
              assigns[:style]
            )
          }

        {nil, nil, nil, inset_x, inset_y}
        when is_integer(inset_x) and is_integer(inset_y) ->
          {
            merge_style(
              "fixed inset-x-#{inset_x} inset-y-#{inset_y} width-screen height-screen bg-0 layer-50",
              assigns[:frame_style]
            ),
            merge_style(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-7 bg-0",
              assigns[:style]
            )
          }

        _ ->
          raise ArgumentError,
                "modal requires either width/height, inset, or inset_x/inset_y"
      end

    assigns =
      assigns
      |> assign(frame_style: frame_style)
      |> assign(panel_style: panel_style)

    ~H"""
    <box
      id={@id}
      focusable
      focus-scope="trap"
      implicit={Breeze.Implicit.Modal}
      style={@frame_style}
      {@rest}
    >
      <box style={@panel_style}>
        <box :if={assigns[:title]} style="absolute left-2 top-0 bold bg-0">{render_slot(@title)}</box>
        {render_slot(@inner_block)}
      </box>
    </box>
    """
  end

  @doc """
  Merge two style strings, with `override` taking precedence over `default` for
  matching style properties.

  The *property key* for each style token is everything before its final `-`
  segment, so tokens that share the same prefix override one another:

      iex> Breeze.Blocks.merge_style("border width-24 height-8", "width-32")
      "border width-32 height-8"

      iex> Breeze.Blocks.merge_style("overflow-scroll", "overflow-hidden")
      "overflow-hidden"

  Tokens from `override` that do not match any default key are appended:

      iex> Breeze.Blocks.merge_style("border width-24", "bg-4")
      "border width-24 bg-4"

  `nil` or an empty string override returns the default unchanged.
  """
  @spec merge_style(String.t(), String.t() | nil) :: String.t()
  def merge_style(default, override) when override in [nil, ""], do: default

  def merge_style(default, override) do
    default_tokens = String.split(default, " ", trim: true)
    override_tokens = String.split(override, " ", trim: true)

    default_key_set = MapSet.new(default_tokens, &style_key/1)
    override_map = Map.new(override_tokens, fn token -> {style_key(token), token} end)

    merged =
      Enum.map(default_tokens, fn token -> Map.get(override_map, style_key(token), token) end)

    new_tokens = Enum.reject(override_tokens, &MapSet.member?(default_key_set, style_key(&1)))

    Enum.join(merged ++ new_tokens, " ")
  end

  defp style_key(token) do
    case String.split(token, "-") do
      [_only] -> token
      parts -> parts |> Enum.drop(-1) |> Enum.join("-")
    end
  end
end
