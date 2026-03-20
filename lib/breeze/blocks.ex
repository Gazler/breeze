defmodule Breeze.Blocks do
  @moduledoc """
  Reusable built-in components for Breeze views.

  Import this module in your view to use the provided components:

      defmodule MyView do
        use Breeze.View
        import Breeze.Blocks
        ...
      end

  ## Class merging

  All components expose a `class` attribute (and where applicable an
  `item_class` attribute) that are merged with the component's defaults using
  `merge_class/2`. Style tokens are grouped by their *property key*, everything
  before the last `-` segment, so an override of `"width-32"` replaces the
  default `"width-24"` while leaving other properties intact (including `focus:`
  prefixes).
  """

  use Breeze.View

  attr :id, :string, required: true
  attr :loop, :boolean, default: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    assigns =
      assigns
      |> assign(
        class:
          merge_class(
            "border width-24 height-8 overflow-scroll scrollbar-arrows focus:border-primary",
            class_override(assigns)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "selected:bg-primary selected:text width-24",
            class_override(assigns, :item_class, :item_style)
          )
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.List}
      list-loop={@loop}
      list-scroll-padding={1}
      focusable
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box
        :for={item <- @item}
        value={item.value}
        class={@item_class}
        style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
      >
        {render_slot(item, %{})}
      </box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :selected, :string, default: nil
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :menu_class, :string, default: nil
  attr :menu_style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
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
        trigger_class:
          merge_class(
            "bg-primary text bold width-#{width} height-1 focus:inverse",
            class_override(assigns)
          )
      )
      |> assign(menu_class: class_override(assigns, :menu_class, :menu_style))
      |> assign(
        item_class:
          merge_class(
            "width-#{menu_width} text selected:bg-primary selected:text focus:inverse",
            class_override(assigns, :item_class, :item_style)
          )
      )

    assigns =
      assign(assigns,
        item_styles:
          items_with_labels
          |> Enum.with_index()
          |> Enum.map(fn {{item, _label}, index} ->
            {item, index, assigns.item_class}
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
      class={@trigger_class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      {@trigger_content}
      <box
        dropdown-indicator-closed="true"
        class={@trigger_class}
        style={Breeze.Blocks.inline_style(assigns)}
      >
        ▼
      </box>
      <box
        dropdown-indicator-open="true"
        class={@trigger_class}
        style={Breeze.Blocks.inline_style(assigns)}
      >
        ▲
      </box>
      <box
        dropdown-frame="true"
        class={@menu_class}
        style={Breeze.Blocks.inline_style(assigns, :menu_class, :menu_style)}
      >
      </box>
      <box
        :for={{item, index, item_style} <- @item_styles}
        dropdown-item="true"
        dropdown-item-index={index}
        value={item.value}
        class={item_style}
        style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
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
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :item_class, :string, default: nil
  attr :item_style, :any, default: nil
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
        class:
          merge_class(
            "border overflow-hidden focus:border-primary grid grid-cols-1 grid-rows-2",
            class_override(assigns)
          )
      )
      |> assign(
        item_class:
          merge_class(
            "selected:bold selected:text-primary focus:selected:bg-primary focus:selected:text overflow-scroll",
            class_override(assigns, :item_class, :item_style)
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
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      <box class="inline height-1" tab-bar="true">
        <box
          :for={t <- @tab}
          value={t.value}
          tab-label={t.label}
          class={@item_class}
          style={Breeze.Blocks.inline_style(assigns, :item_class, :item_style)}
        >
          {" #{t.label} "}
        </box>
      </box>
      <box class="height-full overflow-hidden">{render_slot(@active)}</box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :"input-value", :string, default: ""
  attr :"input-cursor", :any, default: nil
  attr :"input-placeholder", :string, default: nil
  attr :rest, :global

  slot :inner_block

  def input(assigns) do
    ~H"""
    <box
      id={@id}
      focusable
      implicit={Breeze.Implicit.Input}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      input-value={assigns[:"input-value"]}
      input-cursor={assigns[:"input-cursor"]}
      input-placeholder={assigns[:"input-placeholder"]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </box>
    """
  end

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :width, :integer, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil

  def markdown(assigns) do
    assigns =
      assign(assigns,
        class:
          merge_class(
            "height-full overflow-scroll scrollbar-arrows",
            class_override(assigns)
          )
      )

    ~H"""
    <.scroll id={@id} class={@class} style={Breeze.Blocks.inline_style(assigns)}>
      {Breeze.Markdown.render(@content, @width)}
    </.scroll>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def scroll(assigns) do
    assigns =
      assign(assigns,
        class:
          merge_class(
            "height-full overflow-scroll scrollbar-arrows",
            class_override(assigns)
          )
      )

    ~H"""
    <box
      focusable
      id={@id}
      implicit={Breeze.Implicit.Scroll}
      class={@class}
      style={Breeze.Blocks.inline_style(assigns)}
      {@rest}
    >
      {render_slot(@inner_block)}
    </box>
    """
  end

  attr :id, :string, default: nil
  attr :width, :integer, required: true
  attr :height, :integer, required: true
  attr :scroll, :boolean, default: false
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :title_class, :string, default: nil
  attr :title_style, :any, default: nil
  attr :scroll_class, :string, default: nil
  attr :scroll_style, :any, default: nil
  attr :rest, :global

  slot :title
  slot :inner_block

  def panel(assigns) do
    assigns =
      assigns
      |> assign(
        class: merge_class("border-rounded border-stroke bg-panel", class_override(assigns)),
        title_class: merge_class("bold text", class_override(assigns, :title_class, :title_style))
      )
      |> assign(
        scroll_class:
          merge_class(
            "width-full height-full bg-panel scrollbar-arrows",
            class_override(assigns, :scroll_class, :scroll_style)
          )
      )

    if assigns[:scroll] do
      if is_nil(assigns[:id]) do
        raise ArgumentError, "panel requires an id when scroll: true"
      end

      ~H"""
      <box
        class={"#{@class} width-#{@width} height-#{@height}"}
        style={Breeze.Blocks.inline_style(assigns)}
        {@rest}
      >
        <box
          :if={assigns[:title]}
          class={"absolute left-2 top-0 #{@title_class}"}
          style={Breeze.Blocks.inline_style(assigns, :title_class, :title_style)}
        >
          {render_slot(@title)}
        </box>
        <.scroll
          id={@id}
          class={@scroll_class}
          style={Breeze.Blocks.inline_style(assigns, :scroll_class, :scroll_style)}
        >
          {render_slot(@inner_block)}
        </.scroll>
      </box>
      """
    else
      ~H"""
      <box
        class={"#{@class} width-#{@width} height-#{@height}"}
        style={Breeze.Blocks.inline_style(assigns)}
        {@rest}
      >
        {render_slot(@inner_block)}
        <box
          :if={assigns[:title]}
          class={"absolute left-2 top-0 #{@title_class}"}
          style={Breeze.Blocks.inline_style(assigns, :title_class, :title_style)}
        >
          {render_slot(@title)}
        </box>
      </box>
      """
    end
  end

  attr :id, :string, required: true
  attr :width, :integer, default: nil
  attr :height, :integer, default: nil
  attr :inset, :integer, default: nil
  attr :inset_x, :integer, default: nil
  attr :inset_y, :integer, default: nil
  attr :class, :string, default: nil
  attr :style, :any, default: nil
  attr :frame_class, :string, default: nil
  attr :frame_style, :any, default: nil
  attr :rest, :global

  slot :title
  slot :inner_block

  def modal(assigns) do
    {frame_class, panel_class} =
      case {assigns[:width], assigns[:height], assigns[:inset], assigns[:inset_x],
            assigns[:inset_y]} do
        {width, height, nil, nil, nil} when is_integer(width) and is_integer(height) ->
          {
            merge_class(
              "fixed center width-#{width + 2} height-#{height + 2} bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 top-0 layer-51 width-#{width} height-#{height} border-rounded border-stroke bg-panel",
              class_override(assigns)
            )
          }

        {nil, nil, inset, nil, nil} when is_integer(inset) ->
          {
            merge_class(
              "fixed inset-#{inset} width-screen height-screen bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-stroke bg-panel",
              class_override(assigns)
            )
          }

        {nil, nil, nil, inset_x, inset_y}
        when is_integer(inset_x) and is_integer(inset_y) ->
          {
            merge_class(
              "fixed inset-x-#{inset_x} inset-y-#{inset_y} width-screen height-screen bg layer-50",
              class_override(assigns, :frame_class, :frame_style)
            ),
            merge_class(
              "absolute left-0 right-0 top-0 bottom-0 layer-51 width-full height-full border-rounded border-stroke bg-panel",
              class_override(assigns)
            )
          }

        _ ->
          raise ArgumentError,
                "modal requires either width/height, inset, or inset_x/inset_y"
      end

    assigns =
      assigns
      |> assign(frame_class: frame_class)
      |> assign(panel_class: panel_class)

    ~H"""
    <box
      id={@id}
      focusable
      focus-scope="trap"
      implicit={Breeze.Implicit.Modal}
      class={@frame_class}
      style={Breeze.Blocks.inline_style(assigns, :frame_class, :frame_style)}
      {@rest}
    >
      <box class={@panel_class} style={Breeze.Blocks.inline_style(assigns)}>
        <box :if={assigns[:title]} class="absolute left-2 top-0 bold text">{render_slot(@title)}</box>
        {render_slot(@inner_block)}
      </box>
    </box>
    """
  end

  @doc """
  Merge two class strings, with `override` taking precedence over `default` for
  matching style properties.

  The *property key* for each style token is everything before its final `-`
  segment, so tokens that share the same prefix override one another:

      iex> Breeze.Blocks.merge_class("border width-24 height-8", "width-32")
      "border width-32 height-8"

      iex> Breeze.Blocks.merge_class("overflow-scroll", "overflow-hidden")
      "overflow-hidden"

  Tokens from `override` that do not match any default key are appended:

      iex> Breeze.Blocks.merge_class("border width-24", "bg-4")
      "border width-24 bg-4"

  `nil` or an empty string override returns the default unchanged.
  """
  @spec merge_class(String.t(), String.t() | nil) :: String.t()
  def merge_class(default, override) when override in [nil, ""], do: default

  def merge_class(default, override) do
    default_tokens = String.split(default, " ", trim: true)
    override_tokens = String.split(override, " ", trim: true)

    default_key_set = MapSet.new(default_tokens, &style_key/1)
    override_map = Map.new(override_tokens, fn token -> {style_key(token), token} end)

    merged =
      Enum.map(default_tokens, fn token -> Map.get(override_map, style_key(token), token) end)

    new_tokens = Enum.reject(override_tokens, &MapSet.member?(default_key_set, style_key(&1)))

    Enum.join(merged ++ new_tokens, " ")
  end

  @spec merge_style(String.t(), String.t() | nil) :: String.t()
  def merge_style(default, override), do: merge_class(default, override)

  defp class_override(assigns, class_key \\ :class, style_key \\ :style) do
    cond do
      is_binary(assigns[class_key]) -> assigns[class_key]
      is_binary(assigns[style_key]) -> assigns[style_key]
      true -> nil
    end
  end

  @doc false
  def inline_style(assigns, class_key \\ :class, style_key \\ :style) do
    cond do
      not is_nil(assigns[class_key]) and not is_binary(assigns[class_key]) -> assigns[class_key]
      not is_binary(assigns[style_key]) -> assigns[style_key]
      true -> nil
    end
  end

  defp style_key(token) do
    case String.split(token, "-") do
      [_only] -> token
      parts -> parts |> Enum.drop(-1) |> Enum.join("-")
    end
  end
end
