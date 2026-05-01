defmodule Breeze.Server.Dimensions do
  @moduledoc false

  def translate_live(elements, %{left: left, top: top} = viewport, prefix, child_box)
      when is_map(elements) do
    translated_elements =
      Map.new(elements, fn {id, viewport} ->
        translated_id =
          case id do
            value when is_binary(value) ->
              if String.starts_with?(value, prefix <> "::"),
                do: value,
                else: prefix <> "::" <> value
          end

        {translated_id,
         %{
           left: left + Map.get(viewport, :left, 0),
           top: top + Map.get(viewport, :top, 0),
           width: Map.get(viewport, :width, 0),
           height: Map.get(viewport, :height, 0),
           viewport_width: Map.get(viewport, :viewport_width, 0),
           viewport_height: Map.get(viewport, :viewport_height, 0),
           content_width: Map.get(viewport, :content_width, 0),
           content_height: Map.get(viewport, :content_height, 0)
         }}
      end)

    Map.put(
      translated_elements,
      prefix,
      live_root(translated_elements, viewport, child_box)
    )
  end

  def translate_live(_elements, _viewport, _prefix, _child_box), do: %{}

  def live_child_terminal(terminal, %{width: width, height: height} = viewport) do
    width = live_child_terminal_dimension(width, Map.get(viewport, :viewport_width))
    height = live_child_terminal_dimension(height, Map.get(viewport, :viewport_height))

    if is_integer(width) and width > 0 and is_integer(height) and height > 0 do
      resize_virtual_terminal(terminal, width, height)
    else
      terminal
    end
  end

  def live_child_terminal(terminal, _viewport), do: terminal

  defp live_root(_translated_elements, %{width: width, height: height} = viewport, _child_box)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{
      left: Map.get(viewport, :left, 0),
      top: Map.get(viewport, :top, 0),
      width: width,
      height: height,
      viewport_width: Map.get(viewport, :viewport_width, width),
      viewport_height: Map.get(viewport, :viewport_height, height),
      content_width: Map.get(viewport, :content_width, width),
      content_height: Map.get(viewport, :content_height, height)
    }
  end

  defp live_root(translated_elements, viewport, child_box) do
    case child_root(viewport, child_box) do
      nil -> translated_root(translated_elements, viewport)
      root_dims -> root_dims
    end
  end

  defp translated_root(translated_elements, viewport) do
    translated_elements
    |> Map.values()
    |> Enum.reduce(nil, &merge_bounds/2)
    |> dimensions_from_bounds(viewport)
  end

  defp merge_bounds(dims, nil) do
    left = Map.get(dims, :left, 0)
    top = Map.get(dims, :top, 0)

    %{
      left: left,
      top: top,
      right: left + max(Map.get(dims, :width, 0) - 1, 0),
      bottom: top + max(Map.get(dims, :height, 0) - 1, 0)
    }
  end

  defp merge_bounds(dims, bounds) do
    next = merge_bounds(dims, nil)

    %{
      left: min(bounds.left, next.left),
      top: min(bounds.top, next.top),
      right: max(bounds.right, next.right),
      bottom: max(bounds.bottom, next.bottom)
    }
  end

  defp dimensions_from_bounds(nil, viewport) do
    %{
      left: Map.get(viewport, :left, 0),
      top: Map.get(viewport, :top, 0),
      width: 0,
      height: 0,
      viewport_width: 0,
      viewport_height: 0,
      content_width: 0,
      content_height: 0
    }
  end

  defp dimensions_from_bounds(bounds, _viewport) do
    width = max(bounds.right - bounds.left + 1, 0)
    height = max(bounds.bottom - bounds.top + 1, 0)

    %{
      left: bounds.left,
      top: bounds.top,
      width: width,
      height: height,
      viewport_width: width,
      viewport_height: height,
      content_width: width,
      content_height: height
    }
  end

  defp child_root(%{left: left, top: top}, %{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{
      left: left,
      top: top,
      width: width,
      height: height,
      viewport_width: width,
      viewport_height: height,
      content_width: width,
      content_height: height
    }
  end

  defp child_root(_viewport, _child_box), do: nil

  defp live_child_terminal_dimension(primary, _secondary)
       when is_integer(primary) and primary > 0,
       do: primary

  defp live_child_terminal_dimension(_primary, secondary)
       when is_integer(secondary) and secondary > 0,
       do: secondary

  defp live_child_terminal_dimension(_primary, _secondary), do: nil

  defp resize_virtual_terminal(%Termite.Terminal{} = terminal, width, height) do
    %{terminal | size: %{width: width, height: height}}
  end

  defp resize_virtual_terminal(nil, width, height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end
end
