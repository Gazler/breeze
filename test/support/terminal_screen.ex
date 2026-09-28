defmodule Breeze.TestSupport.TerminalScreen do
  @moduledoc false

  # A deliberately small model for ASCII inline-frame tests. Interpret cursor
  # movement, erasure, delayed wrapping and scrolling independently of Inline.
  # Unsupported controls fail rather than silently producing a false assertion.
  defstruct [
    :width,
    :height,
    :redraw_top,
    rows: [],
    scrollback: [],
    row: 0,
    col: 0,
    wrap_pending?: false
  ]

  def new(%{width: width, height: height}, rows \\ []) do
    rows = Enum.take(rows ++ List.duplicate("", height), height)
    rows = Enum.map(rows, &String.pad_trailing(&1, width))
    %__MODULE__{width: width, height: height, rows: rows}
  end

  def rows(screen), do: Enum.map(screen.rows, &String.trim_trailing/1)
  def scrollback(screen), do: Enum.map(screen.scrollback, &String.trim_trailing/1)
  def cursor(screen), do: {screen.row + 1, screen.col + 1}

  # Reflow each hard line independently. Inline tests use ASCII rows without
  # soft wraps, so this also models terminals that simply clip on resize.
  def resize(screen, %{width: width, height: height}, opts \\ []) do
    reflow? = Keyword.get(opts, :reflow, true)

    screen =
      if Keyword.get(opts, :redraw_prompt, false) and screen.redraw_top != nil do
        rows =
          Enum.take(screen.rows, screen.redraw_top) ++
            List.duplicate(String.duplicate(" ", screen.width), screen.height - screen.redraw_top)

        %{screen | rows: rows}
      else
        screen
      end

    chunks =
      Enum.map(screen.rows, fn row ->
        text = if reflow?, do: String.trim_trailing(row), else: String.slice(row, 0, width)
        text = if text == "", do: " ", else: text

        text
        |> String.to_charlist()
        |> Enum.chunk_every(width)
        |> Enum.map(&(to_string(&1) |> String.pad_trailing(width)))
      end)

    row = Enum.take(chunks, screen.row) |> Enum.map(&length/1) |> Enum.sum()
    row = row + if(reflow?, do: div(screen.col, width), else: 0)
    scroll = max(row - height + 1, 0)
    {history, rows} = chunks |> List.flatten() |> Enum.split(scroll)
    rows = Enum.take(rows ++ List.duplicate(String.duplicate(" ", width), height), height)

    %{
      screen
      | width: width,
        height: height,
        rows: rows,
        scrollback: screen.scrollback ++ history,
        row: row - scroll,
        col: if(reflow?, do: rem(screen.col, width), else: min(screen.col, width - 1)),
        wrap_pending?: false
    }
  end

  def write(screen, ""), do: screen

  def write(screen, "\e]133;A;redraw=1\e\\" <> rest),
    do: write(%{screen | redraw_top: screen.row}, rest)

  def write(screen, "\e]133;C\e\\" <> rest),
    do: write(%{screen | redraw_top: nil}, rest)

  def write(screen, <<"\e[", _::binary>> = data) do
    case Regex.run(~r/\A\e\[([0-?]*)([@-~])/, data) do
      [sequence, params, command] ->
        rest = binary_part(data, byte_size(sequence), byte_size(data) - byte_size(sequence))
        screen |> control(params, command) |> write(rest)

      _ ->
        raise ArgumentError, "unsupported terminal sequence: #{inspect(data)}"
    end
  end

  def write(screen, <<"\r", rest::binary>>),
    do: write(%{screen | col: 0, wrap_pending?: false}, rest)

  def write(screen, <<"\n", rest::binary>>), do: screen |> newline() |> write(rest)

  def write(screen, <<char, rest::binary>>) when char in 32..126 do
    screen = if screen.wrap_pending?, do: newline(%{screen | col: 0}), else: screen
    row = Enum.at(screen.rows, screen.row)
    col = screen.col
    <<left::binary-size(^col), _old, right::binary>> = row
    rows = List.replace_at(screen.rows, screen.row, left <> <<char>> <> right)

    write(
      %{
        screen
        | rows: rows,
          col: min(screen.col + 1, screen.width - 1),
          wrap_pending?: screen.col == screen.width - 1
      },
      rest
    )
  end

  def write(_screen, data),
    do: raise(ArgumentError, "unsupported terminal text: #{inspect(data)}")

  defp control(screen, params, "H") do
    [row, col] =
      if params == "", do: [1, 1], else: Enum.map(String.split(params, ";"), &String.to_integer/1)

    %{
      screen
      | row: min(max(row - 1, 0), screen.height - 1),
        col: min(max(col - 1, 0), screen.width - 1),
        wrap_pending?: false
    }
  end

  defp control(screen, params, "K") when params in ["", "0", "2"] do
    start = if params == "2", do: 0, else: screen.col
    row = binary_part(Enum.at(screen.rows, screen.row), 0, start)
    row = row <> String.duplicate(" ", screen.width - start)
    %{screen | rows: List.replace_at(screen.rows, screen.row, row)}
  end

  defp control(screen, "2", "J"),
    do: %{screen | rows: List.duplicate(String.duplicate(" ", screen.width), screen.height)}

  defp control(screen, params, "J") when params in ["", "0"] do
    screen = control(screen, "", "K")

    rows =
      screen.rows
      |> Enum.with_index()
      |> Enum.map(fn {line, row} ->
        if row > screen.row, do: String.duplicate(" ", screen.width), else: line
      end)

    %{screen | rows: rows}
  end

  defp control(screen, "3", "J"), do: %{screen | scrollback: []}
  defp control(screen, _params, "m"), do: screen
  defp control(screen, "?2026", mode) when mode in ["h", "l"], do: screen

  defp control(_screen, params, command),
    do: raise(ArgumentError, "unsupported terminal control: #{inspect(params <> command)}")

  defp newline(%{row: row, height: height} = screen) when row == height - 1 do
    [scrolled | remaining] = screen.rows

    %{
      screen
      | rows: remaining ++ [String.duplicate(" ", screen.width)],
        scrollback: screen.scrollback ++ [scrolled],
        wrap_pending?: false
    }
  end

  defp newline(screen), do: %{screen | row: screen.row + 1, wrap_pending?: false}
end
