defmodule Demo do
  use Breeze.View

  def mount(_opts, term) do
    Process.send_after(self(), :tick, 200)
    {:ok, assign(term, name: "world")}
  end

  def render(assigns) do
    BackBreeze.Style.bold()
    |> BackBreeze.Style.foreground_color(:rand.uniform(8))
    |> BackBreeze.Style.render("hello #{assigns.name}")
  end

  def handle_info(:tick, term) do
    name = if term.assigns.name == "world", do: "elixir", else: "world"
    Process.send_after(self(), :tick, 200)
    {:noreply, assign(term, name: name)}
  end
end

Breeze.Server.start_link(view: Demo)
:timer.sleep(5000)
