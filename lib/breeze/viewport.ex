defmodule Breeze.Viewport do
  @moduledoc """
  Helpers for working with scrollable viewport metrics.

  Implicit event payloads include an `%Breeze.Viewport{}` struct in the
  `"element"` key.
  """

  @typedoc "Dimensions and scroll metrics for a rendered viewport."
  @type t :: %__MODULE__{
          left: integer(),
          top: integer(),
          width: non_neg_integer() | nil,
          height: non_neg_integer(),
          viewport_width: non_neg_integer() | nil,
          viewport_height: non_neg_integer(),
          content_width: non_neg_integer() | nil,
          content_height: non_neg_integer()
        }

  defstruct left: 0,
            top: 0,
            width: nil,
            height: 0,
            viewport_width: nil,
            viewport_height: 0,
            content_width: nil,
            content_height: 0

  @doc "Builds viewport metrics from a dimensions map."
  @spec from_dimensions(map() | nil) :: t()
  def from_dimensions(nil), do: %__MODULE__{}

  def from_dimensions(dimensions) when is_map(dimensions) do
    width = normalize_optional_int(Map.get(dimensions, :width))
    height = normalize_int(Map.get(dimensions, :height))

    viewport_width =
      dimensions
      |> Map.get(:viewport_width)
      |> normalize_optional_int(width)

    content_width =
      dimensions
      |> Map.get(:content_width)
      |> normalize_optional_int(width)

    viewport_height =
      dimensions
      |> Map.get(:viewport_height)
      |> normalize_int(height)

    content_height =
      dimensions
      |> Map.get(:content_height)
      |> normalize_int(height)

    %__MODULE__{
      left: normalize_signed_int(Map.get(dimensions, :left)),
      top: normalize_signed_int(Map.get(dimensions, :top)),
      width: width,
      height: height,
      viewport_width: viewport_width,
      viewport_height: viewport_height,
      content_width: content_width,
      content_height: content_height
    }
  end

  @doc "Returns the largest valid vertical scroll offset."
  @spec max_scroll_y(t() | map()) :: non_neg_integer()
  def max_scroll_y(viewport), do: viewport |> to_viewport() |> do_max_scroll_y()

  @doc "Returns the largest valid horizontal scroll offset."
  @spec max_scroll_x(t() | map()) :: non_neg_integer()
  def max_scroll_x(viewport), do: viewport |> to_viewport() |> do_max_scroll_x()

  @doc "Clamps a vertical scroll offset to the viewport's valid range."
  @spec clamp_scroll_y(integer(), t() | map()) :: non_neg_integer()
  def clamp_scroll_y(scroll_y, viewport) when is_integer(scroll_y) do
    viewport = to_viewport(viewport)
    clamp(scroll_y, 0, do_max_scroll_y(viewport))
  end

  @doc "Clamps a horizontal scroll offset to the viewport's valid range."
  @spec clamp_scroll_x(integer(), t() | map()) :: non_neg_integer()
  def clamp_scroll_x(scroll_x, viewport) when is_integer(scroll_x) do
    viewport = to_viewport(viewport)
    clamp(scroll_x, 0, do_max_scroll_x(viewport))
  end

  @doc """
  Returns the vertical scroll offset needed to reveal a range of rows.

  Set `:padding` to keep additional rows visible above and below the range.
  """
  @spec ensure_range_visible(integer(), integer(), integer(), t() | map(), keyword()) ::
          non_neg_integer()
  def ensure_range_visible(scroll_y, first_row, last_row, viewport, opts \\ [])
      when is_integer(scroll_y) and is_integer(first_row) and is_integer(last_row) do
    viewport = to_viewport(viewport)
    padding = opts |> Keyword.get(:padding, 0) |> normalize_int()

    window_top = scroll_y + padding
    window_bottom = scroll_y + viewport.viewport_height - 1 - padding

    next_scroll =
      cond do
        first_row < window_top ->
          first_row - padding

        last_row > window_bottom ->
          last_row - viewport.viewport_height + 1 + padding

        true ->
          scroll_y
      end

    clamp_scroll_y(next_scroll, viewport)
  end

  @doc "Returns the vertical scroll offset needed to reveal a row."
  @spec ensure_row_visible(integer(), integer(), t() | map(), keyword()) :: non_neg_integer()
  def ensure_row_visible(scroll_y, row, viewport, opts \\ [])
      when is_integer(scroll_y) and is_integer(row) do
    ensure_range_visible(scroll_y, row, row, viewport, opts)
  end

  defp to_viewport(%__MODULE__{} = viewport), do: viewport
  defp to_viewport(viewport), do: from_dimensions(viewport)

  defp do_max_scroll_y(%__MODULE__{content_height: content, viewport_height: viewport_height}),
    do: max(content - viewport_height, 0)

  defp do_max_scroll_x(%__MODULE__{content_width: nil}), do: 0

  defp do_max_scroll_x(%__MODULE__{content_width: content, viewport_width: viewport_width}) do
    max(content - (viewport_width || 0), 0)
  end

  defp normalize_int(value, fallback \\ 0)

  defp normalize_int(value, _fallback) when is_integer(value), do: max(value, 0)
  defp normalize_int(_value, fallback), do: max(fallback, 0)

  defp normalize_optional_int(value, fallback \\ nil)

  defp normalize_optional_int(value, _fallback) when is_integer(value), do: max(value, 0)
  defp normalize_optional_int(nil, fallback), do: fallback
  defp normalize_optional_int(_value, fallback), do: fallback

  defp normalize_signed_int(value, fallback \\ 0)
  defp normalize_signed_int(value, _fallback) when is_integer(value), do: value
  defp normalize_signed_int(_value, fallback), do: fallback

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end
end
