defmodule Breeze.Server.Inline do
  @moduledoc false

  alias Breeze.Server.Frame
  alias Breeze.Server.Inline.History

  # physical_size governs scrolling; available_size applies the layout override;
  # layout_size/1 additionally caps the view at its requested height.
  defstruct [
    :physical_size,
    :available_size,
    :requested_height,
    top: 0,
    height: 0,
    pending_output: ""
  ]

  # Terminals supporting synchronized output present the complete update at
  # once. Others ignore the private mode and still receive one contiguous write.
  def synchronize(""), do: ""
  def synchronize(payload), do: "\e[?2026h" <> payload <> "\e[?2026l"

  # Kitty/Ghostty can discard a redrawable prompt before resize reflow sends
  # its old rows into scrollback. Terminals without support ignore the hint.
  def live_region, do: "\e]133;A;redraw=1\e\\"
  def history_region, do: "\e]133;C\e\\"

  def validate_options!(opts) do
    unless Keyword.get(opts, :screen, :fullscreen) in [:fullscreen, :inline] do
      raise ArgumentError, ":screen must be :fullscreen or :inline"
    end

    height = Keyword.get(opts, :inline_height, :auto)

    unless height == :auto or (is_integer(height) and height > 0) do
      raise ArgumentError, ":inline_height must be :auto or a positive integer"
    end

    opts
  end

  # CPR coordinates are one-based. Start on a fresh line if the caller left the
  # cursor after existing text. Without CPR, scroll to a known blank row rather
  # than guessing an origin and overwriting the caller's output.
  def open(size, position, requested_height \\ :auto, layout_override \\ nil) do
    {top, payload} =
      case position do
        {row, 1} -> {min(row - 1, size.height - 1), "\r"}
        {row, _col} -> {min(row, size.height - 1), "\r\n"}
        nil -> {size.height - 1, "\r" <> String.duplicate("\n", size.height)}
      end

    inline =
      %__MODULE__{top: top, requested_height: requested_height}
      |> put_geometry(size, layout_override)

    {inline, payload}
  end

  def layout_size(inline) do
    size = inline.available_size

    case inline.requested_height do
      :auto -> size
      height -> %{size | height: min(height, size.height)}
    end
  end

  def pending_output?(nil), do: false
  def pending_output?(inline), do: inline.pending_output != ""

  def take_pending_output(inline),
    do: {%{inline | pending_output: ""}, inline.pending_output}

  def lines(inline, output) do
    lines = :binary.split(output, "\n", [:global])
    height = layout_size(inline).height

    case inline.requested_height do
      :auto -> Enum.take(lines, height)
      _ -> Frame.normalize_lines(output, height)
    end
  end

  def render(inline, previous_lines, lines, previous_overlays, overlays) do
    # Overlays can extend below the text (for example, a live cursor).
    overlay_height =
      Enum.reduce(overlays, 0, fn overlay, height ->
        max(height, overlay.y + Map.get(overlay, :height, 1))
      end)

    height = min(max(length(lines), overlay_height), layout_size(inline).height)
    height = max(height, 1)

    lines =
      lines
      |> Kernel.++(List.duplicate("", height))
      |> Enum.take(height)
      |> Frame.fit_lines(inline.physical_size.width)

    overlays = Enum.filter(overlays, &(&1.y >= 0 and &1.y < height))
    old_height = inline.height
    growth = max(height - max(old_height, 1), 0)
    old_bottom = inline.top + max(old_height - 1, 0)

    reserve =
      if growth > 0, do: position(old_bottom) <> String.duplicate("\r\n", growth), else: ""

    top = max(min(inline.top, inline.physical_size.height - height), 0)
    inline = %{inline | top: top, height: height}

    # Clear rows vacated by a shrinking view, including styled blank rows.
    painted_lines = lines ++ List.duplicate("", max(old_height - height, 0))

    payload =
      Frame.build_payload(
        previous_lines,
        painted_lines,
        previous_overlays,
        overlays,
        inline.physical_size.width,
        row_offset: top,
        clear: false
      )

    {inline, pending_output} = take_pending_output(inline)

    payload =
      if pending_output == "" and reserve == "" and payload == "" do
        ""
      else
        # Reflow can change the height of every row below the origin. Keep the
        # cursor at the origin so a resize can locate it without guessing how
        # many physical rows the old frame now occupies.
        synchronize(
          pending_output <>
            reserve <>
            position(top) <>
            live_region() <>
            payload <> "\e[0m" <> position(top)
        )
      end

    {inline, payload, lines, overlays}
  end

  # The reported cursor must describe the committed frame, not queued history.
  def resize(inline, size, position, layout_override \\ nil)

  def resize(%{pending_output: output}, _size, _position, _layout_override) when output != "",
    do: raise(ArgumentError, "flush pending inline output before resizing")

  def resize(inline, size, nil, layout_override) do
    {inline, payload} = open(size, nil, inline.requested_height, layout_override)
    queue_output(inline, payload)
  end

  def resize(inline, size, {row, _col}, layout_override) do
    top = min(row - 1, size.height - 1)

    # The old frame may have reflowed into extra rows. Erase from its origin
    # down, preserving all output above it, then reserve space for the new frame.
    %{inline | top: top, height: 0}
    |> put_geometry(size, layout_override)
    |> queue_output(position(top) <> "\e[0m\e[J")
  end

  def append(inline, content) do
    # Retain text styles while removing controls that could move the cursor.
    # Wrap by display cells so the physical height is known, including CJK.
    rows = History.rows(content, inline.physical_size.width)

    clear =
      if inline.height > 0 do
        Enum.map_join(0..(inline.height - 1), fn row ->
          position(inline.top + row) <> "\e[0m\e[2K"
        end)
      else
        ""
      end

    payload =
      clear <>
        position(inline.top) <>
        history_region() <> "\e[0m" <> Enum.map_join(rows, &(&1 <> "\r\n"))

    top = min(inline.top + length(rows), inline.physical_size.height - 1)
    queue_output(%{inline | top: top, height: 0}, payload)
  end

  def translate_mouse(nil, event), do: event

  def translate_mouse(inline, %{"y" => y} = event) do
    if y >= inline.top and y < inline.top + inline.height,
      do: Map.put(event, "y", y - inline.top),
      else: nil
  end

  def position(row), do: "\e[#{row + 1};1H"

  defp put_geometry(inline, physical_size, layout_override) do
    available_size =
      if is_function(layout_override, 1), do: layout_override.(physical_size), else: physical_size

    available_size = %{
      width: min(available_size.width, physical_size.width),
      height: min(available_size.height, physical_size.height)
    }

    %{inline | physical_size: physical_size, available_size: available_size}
  end

  defp queue_output(inline, payload),
    do: %{inline | pending_output: inline.pending_output <> payload}
end
