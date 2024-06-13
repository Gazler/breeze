defmodule Snake do
  use Breeze.View

  def mount(_opts, term) do
    path = [{7, 5}, {8, 5}, {9, 5}, {10, 5}]
    size = %{width: 15, height: 10}
    food = random_food(size, path)

    term =
      assign(term, %{size: size, direction: :right, path: path, food: food, input_buffer: []})

    :timer.send_interval(100, self(), :tick)

    {:ok, term}
  end

  def render(assigns) do
    [draw_screen(assigns.size)] ++ draw_snake(assigns.path) ++ [draw_food(assigns.food)]
  end

  defp draw_screen(size) do
    BackBreeze.Style.border()
    |> BackBreeze.Style.width(size.width * 2)
    |> BackBreeze.Style.height(size.height)
    |> BackBreeze.Style.render("")
  end

  defp draw_snake(path) do
    Enum.map(path, fn {x, y} ->
      {x * 2, y + 2, BackBreeze.Style.reverse() |> BackBreeze.Style.render("  ")}
    end)
  end

  defp draw_food({x, y}) do
    {x * 2, y + 2, BackBreeze.Style.foreground_color(2) |> BackBreeze.Style.render("🍏")}
  end

  def handle_event(_, %{"key" => "ArrowUp"}, term), do: {:noreply, change_dir(term, :up)}
  def handle_event(_, %{"key" => "ArrowDown"}, term), do: {:noreply, change_dir(term, :down)}
  def handle_event(_, %{"key" => "ArrowLeft"}, term), do: {:noreply, change_dir(term, :left)}
  def handle_event(_, %{"key" => "ArrowRight"}, term), do: {:noreply, change_dir(term, :right)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    %{input_buffer: input_buffer, path: path, size: size, food: food} = term.assigns

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

    wall_collision? = x == 0 || x == size.width + 1 || y == -1 || y == size.height
    tail_collision? = {x, y} in path

    new_path = path ++ [{x, y}]

    term = assign(term, input_buffer: buffer, direction: direction)

    cond do
      {x, y} == food ->
        {:noreply, assign(term, path: new_path, food: random_food(size, new_path))}

      wall_collision? || tail_collision? ->
        {:stop, term}

      true ->
        {:noreply, assign(term, path: tl(path) ++ [{x, y}])}
    end
  end

  defp change_dir(term, dir) do
    %{input_buffer: buffer, direction: direction} = term.assigns
    old_dir = if buffer == [], do: direction, else: hd(buffer)

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

    if {x, y} in path, do: random_food(size, path), else: {x, y}
  end
end

Breeze.Server.start_link(view: Snake, hide_cursor: true)

receive do
end
