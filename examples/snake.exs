defmodule Snake do
  use Breeze.View

  @board_width 15
  @board_height 10

  def mount(opts, term) do
    maybe_seed_rand(Keyword.get(opts, :seed))

    size = board_size()
    tick_ms = Keyword.get(opts, :tick_ms, 100)

    {:ok, reset(term, size, tick_ms)}
  end

  def render(assigns) do
    assigns = assign(assigns, size: board_size())

    ~H"""
    <.panel width={@size.width * 2} height={@size.height + 1}>
      <:title>
        <box style="text-3">{score_label(@path, @stopped?)}</box>
      </:title>
      <box :for={{x, y} <- @path} style={"bg-7 absolute left-#{x * 2 - 1} top-#{y + 1}"}>██</box>
      <box style={"absolute left-#{@food.x * 2 - 1} top-#{@food.y + 1}"}>{@food.glyph}</box>
    </.panel>
    """
  end

  attr :width, :integer
  attr :height, :integer

  slot :title
  slot :inner_block

  def panel(assigns) do
    ~H"""
    <box style={"border width-#{@width + 2} height-#{@height + 2}"}>
      <box :if={assigns[:title]} style="absolute left-1 top-0">{render_slot(@title)}</box>
      {render_slot(@inner_block)}
    </box>
    """
  end

  def handle_event(_, %{"key" => "r"}, term), do: {:noreply, restart(term)}
  def handle_event(_, %{"key" => "p"}, term), do: {:noreply, pause(term)}

  def handle_event(_, %{"key" => _key}, %{assigns: %{stopped?: true}} = term) do
    {:noreply, term}
  end

  def handle_event(_, %{"key" => _}, %{assigns: %{paused: true}} = term) do
    term = term |> assign(paused: false) |> schedule_tick()
    {:noreply, term}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term), do: {:noreply, change_dir(term, :up)}
  def handle_event(_, %{"key" => "ArrowDown"}, term), do: {:noreply, change_dir(term, :down)}
  def handle_event(_, %{"key" => "ArrowLeft"}, term), do: {:noreply, change_dir(term, :left)}
  def handle_event(_, %{"key" => "ArrowRight"}, term), do: {:noreply, change_dir(term, :right)}
  def handle_event(_, %{"key" => "k"}, term), do: {:noreply, change_dir(term, :up)}
  def handle_event(_, %{"key" => "j"}, term), do: {:noreply, change_dir(term, :down)}
  def handle_event(_, %{"key" => "h"}, term), do: {:noreply, change_dir(term, :left)}
  def handle_event(_, %{"key" => "l"}, term), do: {:noreply, change_dir(term, :right)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info({:timeout, timer, :tick}, %{assigns: %{tick_timer: timer}} = term) do
    {:noreply, term |> assign(tick_timer: nil) |> tick() |> schedule_tick()}
  end

  def handle_info({:timeout, _timer, :tick}, term), do: {:noreply, term}

  defp tick(%{assigns: %{paused: true}} = term), do: term

  defp tick(term) do
    %{input_buffer: input_buffer, path: path, food: food} = term.assigns
    size = board_size()

    {direction, buffer} =
      case input_buffer do
        [dir | buffer] -> {dir, buffer}
        _ -> {term.assigns.direction, []}
      end

    [{cur_x, cur_y} | _] = Enum.reverse(path)

    {x, y} =
      case direction do
        :right -> {cur_x + 1, cur_y}
        :left -> {cur_x - 1, cur_y}
        :up -> {cur_x, cur_y - 1}
        :down -> {cur_x, cur_y + 1}
      end

    wall_collision? = x == 0 || x == size.width + 1 || y == -1 || y == size.height + 1
    tail_collision? = {x, y} in path

    new_path = path ++ [{x, y}]

    term = assign(term, input_buffer: buffer, direction: direction)

    cond do
      {x, y} == {food.x, food.y} ->
        assign(term, path: new_path, food: random_food(size, new_path))

      wall_collision? || tail_collision? ->
        stop(term)

      true ->
        assign(term, path: tl(path) ++ [{x, y}])
    end
  end

  defp schedule_tick(%{assigns: %{paused: true}} = term), do: term
  defp schedule_tick(%{assigns: %{stopped?: true}} = term), do: term
  defp schedule_tick(%{assigns: %{tick_ms: nil}} = term), do: term
  defp schedule_tick(%{assigns: %{tick_timer: timer}} = term) when is_reference(timer), do: term

  defp schedule_tick(term) do
    timer = :erlang.start_timer(term.assigns.tick_ms, self(), :tick)
    assign(term, tick_timer: timer)
  end

  defp pause(term) do
    case Map.get(term.assigns, :tick_timer) do
      timer when is_reference(timer) -> Process.cancel_timer(timer)
      _other -> :ok
    end

    assign(term, paused: true, tick_timer: nil)
  end

  defp restart(term) do
    term
    |> pause()
    |> reset(board_size(), 100)
  end

  defp stop(term) do
    term
    |> pause()
    |> assign(stopped?: true)
  end

  defp reset(term, size, tick_ms) do
    path = [{1, 1}, {2, 1}, {3, 1}, {4, 1}]

    assign(term, %{
      size: size,
      direction: :right,
      path: path,
      food: random_food(size, path),
      input_buffer: [],
      tick_ms: tick_ms,
      tick_timer: nil,
      paused: true,
      stopped?: false
    })
  end

  defp score_label(path, stopped?) do
    label = "Score: #{length(path) - 4}"

    if stopped?,
      do: label <> " - r to restart",
      else: label
  end

  defp change_dir(term, dir) do
    %{input_buffer: buffer, direction: direction} = term.assigns
    old_dir = if buffer == [], do: direction, else: List.last(buffer)

    {dir, changed?} =
      case {old_dir, dir} do
        {old_dir, :left} when old_dir in [:left, :right] -> {old_dir, false}
        {old_dir, :right} when old_dir in [:left, :right] -> {old_dir, false}
        {old_dir, :up} when old_dir in [:up, :down] -> {old_dir, false}
        {old_dir, :down} when old_dir in [:up, :down] -> {old_dir, false}
        _ -> {dir, true}
      end

    if changed? do
      assign(term, input_buffer: term.assigns.input_buffer ++ [dir])
    else
      term
    end
  end

  defp random_food(size, path) do
    x = :rand.uniform(size.width)
    y = :rand.uniform(size.height) - 1
    color = :rand.uniform(16) + 1
    glyph = Enum.random(["🍇", "🍈", "🍉", "🍍", "🍎", "🍑", "🍒", "🍓"])

    if {x, y} in path,
      do: random_food(size, path),
      else: %{x: x, y: y, color: color, glyph: glyph}
  end

  defp maybe_seed_rand(nil), do: :ok

  defp maybe_seed_rand({a, b, c}) do
    :rand.seed(:exsss, {a, b, c})
  end

  defp board_size, do: %{width: @board_width, height: @board_height}
end

Breeze.Example.run(
  [
    view: Snake,
    hide_cursor: true,
    reload: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
