defmodule MouseExample do
  use Breeze.View

  def mount(_opts, term) do
    term =
      term
      |> assign(clicks: 0, last_mouse: "none")
      |> focus("left-panel")

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Mouse example</box>
      <box>Left click either panel to focus it. Press q to quit.</box>
      <box>Last mouse event: {@last_mouse}</box>
      <box>Click count: {@clicks}</box>
      <box>
      </box>
      <box style="inline">
        <box id="left-panel" focusable style="border-rounded width-24 height-6 focus:border-4">
          <box style="bold">Left panel</box>
          <box>Expected target: left-panel</box>
        </box>
        <box>
        </box>
        <box id="right-panel" focusable style="border-rounded width-24 height-6 focus:border-4">
          <box style="bold">Right panel</box>
          <box>Expected target: right-panel</box>
        </box>
      </box>
    </box>
    """
  end

  def handle_event(
        _,
        %{"mouse" => %{button: :left, action: :press} = mouse, "target" => target},
        term
      ) do
    summary =
      "#{mouse.button}/#{mouse.action} x=#{mouse.x} y=#{mouse.y} target=#{target}"

    {:noreply,
     assign(term,
       clicks: term.assigns.clicks + 1,
       last_mouse: summary
     )}
  end

  def handle_event(_, %{"mouse" => mouse, "target" => target}, term) do
    summary = "#{mouse.button}/#{mouse.action} x=#{mouse.x} y=#{mouse.y} target=#{target}"
    {:noreply, assign(term, last_mouse: summary)}
  end

  def handle_event(_, %{"mouse" => mouse}, term) do
    summary = "#{mouse.button}/#{mouse.action} x=#{mouse.x} y=#{mouse.y} target=none"
    {:noreply, assign(term, last_mouse: summary)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end

Breeze.Example.run(
  view: MouseExample,
  hide_cursor: true,
  mouse: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
)
