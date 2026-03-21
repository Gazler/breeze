defmodule Breeze.InspectorPanel do
  @moduledoc false

  use Breeze.View

  def render(assigns) do
    ~H"""
    <box style={@root_style}>
      <box style={@title_style}>{@title_text}</box>
      <box style={@meta_style}>{@meta_text}</box>
      <box style={@line_style}>{@layout_text}</box>
      <box style={@line_style}>{@box_text}</box>
      <box style={@line_style}>{@class_text}</box>
      <box class="inline width-full" style={@line_style}>
        <box style={@color_text_style}>{@color_text}</box>
        <box :if={@show_fg_swatch? or @show_bg_swatch?} style={@swatch_label_style}>
        </box>
        <box :if={@show_fg_swatch?} style={@fg_swatch_style}>██</box>
        <box :if={@show_fg_swatch? and @show_bg_swatch?} style={@swatch_label_style}>
        </box>
        <box :if={@show_bg_swatch?} style={@bg_swatch_style}>██</box>
      </box>
      <box style={@line_style}>{@focus_text}</box>
      <box style={@line_style}>{@implicit_text}</box>
      <box style={@meta_style}>{@flags_text}</box>
      <box style={@meta_style}>{@fragment_text}</box>
    </box>
    """
  end
end
