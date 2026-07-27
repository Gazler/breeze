defmodule MouseExample do
  use Breeze.View

  @max_events 16

  def mount(_opts, term) do
    term =
      term
      |> assign(
        clicks: 0,
        wheel_up: 0,
        wheel_down: 0,
        event_seq: 0,
        last_event_at: nil,
        events: []
      )
      |> focus("left-panel")

    {:ok, term}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        last_mouse:
          case List.first(assigns.events) do
            nil -> "none"
            event -> event.summary
          end
      )

    ~H"""
    <box class="w-screen h-screen pl-1 pt-1">
      <box class="font-bold">Mouse example</box>
      <box>Left click either panel to focus it. Scroll over a panel to inspect wheel events.</box>
      <box>Press c to clear, q to quit.</box>
      <box>Last mouse event: {@last_mouse}</box>
      <box>Clicks: {@clicks}  Wheel up: {@wheel_up}  Wheel down: {@wheel_down}</box>
      <box>
      </box>
      <box class="inline">
        <box id="left-panel" focusable class="rounded w-24 h-6 focus:border-4">
          <box class="font-bold">Left panel</box>
          <box>Expected target: left-panel</box>
          <box>Wheel here</box>
        </box>
        <box>
        </box>
        <box id="right-panel" focusable class="rounded w-24 h-6 focus:border-4">
          <box class="font-bold">Right panel</box>
          <box>Expected target: right-panel</box>
          <box>Wheel here</box>
        </box>
      </box>
      <box>
      </box>
      <box class="font-bold">Recent events</box>
      <box class="text-muted">
        #    dt   button/action       x,y      row,col  target       repeat  modifiers
      </box>
      <box :for={event <- @events} class="inline w-full overflow-hidden">
        <box class="w-5">{event.seq}</box>
        <box class="w-5">{event.dt}</box>
        <box class="w-20">{event.button_action}</box>
        <box class="w-9">{event.xy}</box>
        <box class="w-9">{event.row_col}</box>
        <box class="w-13">{event.target}</box>
        <box class="w-8">{event.repeat}</box>
        <box>{event.modifiers}</box>
      </box>
    </box>
    """
  end

  def handle_event(_, %{"key" => "c"}, term) do
    {:noreply,
     assign(term,
       clicks: 0,
       wheel_up: 0,
       wheel_down: 0,
       event_seq: 0,
       last_event_at: nil,
       events: []
     )}
  end

  def handle_event(_, %{"mouse" => mouse} = event, term),
    do: {:noreply, record_mouse_event(term, event, mouse)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}

  def handle_event(_, _, term), do: {:noreply, term}

  defp record_mouse_event(term, event, mouse) do
    now = System.monotonic_time(:millisecond)
    dt = event_delta(term.assigns.last_event_at, now)
    seq = term.assigns.event_seq + 1
    target = Map.get(event, "target", "none")
    repeat = Map.get(mouse, "repeat", 1)

    entry = %{
      seq: pad(seq, 4),
      dt: pad(dt, 4),
      button_action: "#{mouse["button"]}/#{mouse["action"]}",
      xy: "#{mouse["x"]},#{mouse["y"]}",
      row_col: "#{Map.get(event, "row", "-")},#{Map.get(event, "col", "-")}",
      target: target,
      repeat: to_string(repeat),
      modifiers: mouse_modifiers(mouse),
      summary:
        "##{seq} +#{dt}ms #{mouse["button"]}/#{mouse["action"]} x=#{mouse["x"]} y=#{mouse["y"]} target=#{target} repeat=#{repeat}"
    }

    term
    |> update_mouse_counts(mouse)
    |> assign(
      event_seq: seq,
      last_event_at: now,
      events: Enum.take([entry | term.assigns.events], @max_events)
    )
  end

  defp update_mouse_counts(term, %{"button" => "left", "action" => "press"}) do
    assign(term, clicks: term.assigns.clicks + 1)
  end

  defp update_mouse_counts(term, %{"button" => "wheel_up"}) do
    assign(term, wheel_up: term.assigns.wheel_up + 1)
  end

  defp update_mouse_counts(term, %{"button" => "wheel_down"}) do
    assign(term, wheel_down: term.assigns.wheel_down + 1)
  end

  defp update_mouse_counts(term, _mouse), do: term

  defp mouse_modifiers(mouse) do
    [{"shiftKey", "shift"}, {"altKey", "alt"}, {"ctrlKey", "ctrl"}]
    |> Enum.filter(fn {key, _label} -> Map.get(mouse, key) == true end)
    |> Enum.map_join("+", &elem(&1, 1))
    |> blank_dash()
  end

  defp event_delta(nil, _now), do: 0
  defp event_delta(last, now), do: max(now - last, 0)

  defp pad(value, width), do: value |> to_string() |> String.pad_leading(width)

  defp blank_dash(""), do: "-"
  defp blank_dash(value), do: value
end

Breeze.Example.run(
  view: MouseExample,
  hide_cursor: true,
  mouse: true,
  global_keybindings: [{"q", "Quit", fn _event, term -> {:stop, term} end}]
)
