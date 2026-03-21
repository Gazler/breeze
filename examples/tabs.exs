defmodule TabsExample do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)

    term =
      term
      |> assign_layout(screen_width, screen_height)
      |> assign(selected_tab: "overview")
      |> focus("tabs")

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen overflow-hidden">
      <box style="bold">Tabs example</box>
      <box>Use left/right arrows while the tabs are focused.</box>
      <box>The tab bar should scroll horizontally to keep the selected tab visible.</box>
      <.tabs
        id="tabs"
        selected={@selected_tab}
        br-change="select_tab"
        style={"width-#{@tabs_width} height-#{@tabs_height} border-rounded focus:border-4"}
      >
        <:tab value="overview" label="Overview">
          <.tab_panel label="Overview" value="overview" height={@panel_height}/>
        </:tab>
        <:tab value="requests" label="Requests">
          <.tab_panel label="Requests" value="requests" height={@panel_height}/>
        </:tab>
        <:tab value="responses" label="Responses">
          <.tab_panel label="Responses" value="responses" height={@panel_height}/>
        </:tab>
        <:tab value="headers" label="Headers">
          <.tab_panel label="Headers" value="headers" height={@panel_height}/>
        </:tab>
        <:tab value="cookies" label="Cookies">
          <.tab_panel label="Cookies" value="cookies" height={@panel_height}/>
        </:tab>
        <:tab value="timeline" label="Timeline">
          <.tab_panel label="Timeline" value="timeline" height={@panel_height}/>
        </:tab>
        <:tab value="inspector" label="Inspector">
          <.tab_panel label="Inspector" value="inspector" height={@panel_height}/>
        </:tab>
        <:tab value="settings" label="Settings">
          <.tab_panel label="Settings" value="settings" height={@panel_height}/>
        </:tab>
        <:tab value="shortcuts" label="Shortcuts">
          <.tab_panel label="Shortcuts" value="shortcuts" height={@panel_height}/>
        </:tab>
        <:tab value="advanced" label="Advanced">
          <.tab_panel label="Advanced" value="advanced" height={@panel_height}/>
        </:tab>
      </.tabs>
    </box>
    """
  end

  attr :height, :integer, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  def tab_panel(assigns) do
    assigns = assign(assigns, lines: panel_lines(assigns.label))

    ~H"""
    <.scroll id={"tabs-panel-#{@value}"} style={"width-full height-#{@height} overflow-scroll"}>
      <box style="bold">{@label}</box>
      <box>Selected tab value: {@value}</box>
      <box>
      </box>
      <box :for={line <- @lines}>{line}</box>
    </.scroll>
    """
  end

  def handle_event("select_tab", %{value: tab}, term) do
    {:noreply, term |> assign(selected_tab: tab)}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(term.terminal)
    {:noreply, assign_layout(term, screen_width, screen_height)}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp assign_layout(term, screen_width, screen_height) do
    tabs_width = max(min(screen_width - 4, 36), 20) + 2
    panel_height = max(screen_height - 9, 6)

    assign(term,
      tabs_width: tabs_width,
      tabs_height: panel_height + 4
    )
    |> assign(panel_height: panel_height)
  end

  defp panel_lines(label) do
    for line <- 1..100 do
      "#{label} panel line #{line}"
    end
  end
end

Breeze.Example.run([view: TabsExample, hide_cursor: true], keep_alive: :infinity)
