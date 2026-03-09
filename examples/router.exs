defmodule RouterHome do
  use Breeze.View

  def mount(opts, term) do
    send(self(), :tick)

    {:ok,
     assign(term,
       message: Keyword.get(opts, :message, "Home screen"),
       ticks: 0,
       interval: Keyword.get(opts, :interval, 900)
     )}
  end

  def render(assigns) do
    ~H"""
    <box id="home" focusable style="border-rounded width-32 height-7 focus:border-4">
      <box style="bold">Home</box>
      <box>{@message}</box>
      <box>Ticks: {@ticks}</box>
      <box>Route opts: [message: "Home screen"]</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, term.assigns.interval)
    {:noreply, assign(term, ticks: term.assigns.ticks + 1)}
  end

  def handle_info(_, term), do: {:noreply, term}
end

defmodule RouterSettings do
  use Breeze.View
  import Breeze.Router

  defmodule SettingsOverview do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, assign(term, label: "Overview child route")}
    end

    def render(assigns) do
      ~H"""
      <box id="settings_overview" focusable style="border-rounded width-30 height-4 focus:border-4">
        <box style="bold">Overview</box>
        <box>{@label}</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  defmodule SettingsAudit do
    use Breeze.View

    def mount(_opts, term) do
      {:ok, assign(term, label: "Audit child route")}
    end

    def render(assigns) do
      ~H"""
      <box id="settings_audit" focusable style="border-rounded width-30 height-4 focus:border-4">
        <box style="bold">Audit</box>
        <box>{@label}</box>
      </box>
      """
    end

    def handle_event(_, _, term), do: {:noreply, term}
    def handle_info(_, term), do: {:noreply, term}
  end

  def mount(opts, term) do
    send(self(), :tick)

    term =
      assign(term,
        section: Keyword.get(opts, :section, "general"),
        ticks: 0,
        interval: Keyword.get(opts, :interval, 350),
        visible?: true,
        hidden_count: 0
      )
      |> focus("settings")

    term =
      Breeze.Router.init(
        term,
        [
          overview: SettingsOverview,
          audit: SettingsAudit
        ],
        current: :overview
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box id="settings" focusable style="border-rounded width-36 height-18 focus:border-4">
      <box style="bold">Settings</box>
      <box>Section: {@section}</box>
      <box>Ticks: {@ticks}</box>
      <box>Visible?: {@visible?}</box>
      <box>Hidden events: {@hidden_count}</box>
      <box>Nested router: a -> overview, b -> audit</box>
      <.router routes={@router} id="nested"/>
    </box>
    """
  end

  def handle_event(_, %{"key" => "a"}, term),
    do: {:noreply, Breeze.Router.navigate(term, :overview)}

  def handle_event(_, %{"key" => "b"}, term), do: {:noreply, Breeze.Router.navigate(term, :audit)}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, term.assigns.interval)
    {:noreply, assign(term, ticks: term.assigns.ticks + 1)}
  end

  def handle_info({:route_visibility, :visible}, term),
    do: {:noreply, assign(term, visible?: true)}

  def handle_info({:route_visibility, :hidden}, term) do
    {:noreply, assign(term, visible?: false, hidden_count: term.assigns.hidden_count + 1)}
  end

  def handle_info(_, term), do: {:noreply, term}
end

defmodule RouterStatus do
  use Breeze.View

  def mount(opts, term) do
    send(self(), :tick)

    {:ok,
     assign(term,
       label: Keyword.get(opts, :label, "Idle"),
       ticks: 0,
       interval: Keyword.get(opts, :interval, 700)
     )}
  end

  def render(assigns) do
    ~H"""
    <box id="status" focusable style="border-rounded width-32 height-7 focus:border-4">
      <box style="bold">Status</box>
      <box>{@label}</box>
      <box>Ticks: {@ticks}</box>
      <box>Route opts set the label text.</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, term.assigns.interval)
    {:noreply, assign(term, ticks: term.assigns.ticks + 1)}
  end

  def handle_info(_, term), do: {:noreply, term}
end

defmodule RouterMetrics do
  use Breeze.View

  def mount(opts, term) do
    send(self(), :tick)

    {:ok,
     assign(term,
       label: Keyword.get(opts, :label, "Metrics"),
       ticks: 0,
       interval: Keyword.get(opts, :interval, 500),
       visible?: false,
       visible_count: 0
     )}
  end

  def render(assigns) do
    ~H"""
    <box id="metrics" focusable style="border-rounded width-34 height-8 focus:border-4">
      <box style="bold">Metrics</box>
      <box>{@label}</box>
      <box>Ticks: {@ticks}</box>
      <box>Visible?: {@visible?}</box>
      <box>Visible events: {@visible_count}</box>
    </box>
    """
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:tick, term) do
    Process.send_after(self(), :tick, term.assigns.interval)
    {:noreply, assign(term, ticks: term.assigns.ticks + 1)}
  end

  def handle_info({:route_visibility, :visible}, term) do
    {:noreply, assign(term, visible?: true, visible_count: term.assigns.visible_count + 1)}
  end

  def handle_info({:route_visibility, :hidden}, term),
    do: {:noreply, assign(term, visible?: false)}

  def handle_info(_, term), do: {:noreply, term}
end

defmodule RouterExample do
  use Breeze.View
  import Breeze.Router

  def mount(_opts, term) do
    term =
      Breeze.Router.init(
        term,
        [
          home: {RouterHome, [message: "Home screen", interval: 900]},
          settings: {RouterSettings, [section: "general", interval: 350], persistence: true},
          status: {RouterStatus, [label: "All systems nominal", interval: 700]},
          metrics:
            {RouterMetrics, [label: "Preloaded route", interval: 500], persistence: :preload}
        ],
        current: :home
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Router example</box>
      <box>Each route has its own ticking counter.</box>
      <box>1 -> home, remounted when revisited</box>
      <box>2 -> settings, persistence: true, includes a nested router</box>
      <box>3 -> status, remounted when revisited</box>
      <box>4 -> metrics, persistence: :preload, already ticking before first visit</box>
      <box>Inside settings: a -> overview, b -> audit. Press q to quit.</box>
      <box style="height-1">
      </box>
      <.router routes={@router} id="main"/>
    </box>
    """
  end

  def handle_event(_, %{"key" => "1"}, term), do: {:noreply, Breeze.Router.navigate(term, :home)}

  def handle_event(_, %{"key" => "2"}, term),
    do: {:noreply, Breeze.Router.navigate(term, :settings, section: "team", interval: 350)}

  def handle_event(_, %{"key" => "3"}, term),
    do:
      {:noreply,
       Breeze.Router.navigate(term, :status, label: "Background jobs healthy", interval: 700)}

  def handle_event(_, %{"key" => "4"}, term),
    do:
      {:noreply, Breeze.Router.navigate(term, :metrics, label: "Preloaded route", interval: 500)}

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}
  def handle_info(_, term), do: {:noreply, term}
end

Breeze.Server.start_link(view: RouterExample, hide_cursor: true)

receive do
end
