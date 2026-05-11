defmodule ExCodexEx do
  use Breeze.View
  import Breeze.Blocks

  alias Breeze.Theme

  @initial_prompt ""

  def mount(_opts, term) do
    {:ok,
     term
     |> Breeze.View.put_theme(Theme.builtin(:nebula))
     |> focus("composer")
     |> assign(
       prompt: @initial_prompt,
       prompt_cursor: String.length(@initial_prompt),
       run_count: 0,
       status: "idle",
       screen_height: screen_height(term),
       transcript: initial_transcript()
     )}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        prompt_height: prompt_height(assigns.prompt),
        composer_height: composer_height(assigns.prompt),
        scrollback_height:
          scrollback_height(assigns.screen_height, prompt_height(assigns.prompt)),
        transcript_entries: transcript_entries(assigns.transcript)
      )

    ~H"""
    <box class="width-screen height-screen bg overflow-hidden">
      <.scroll
        id="scrollback"
        scroll-autoscroll="bottom"
        class={"width-full height-#{@scrollback_height} overflow-scroll bg padding-left-2 padding-right-2 padding-top-1 padding-bottom-1"}
      >
        <box :for={entry <- @transcript_entries} class="width-full padding-bottom-1">
          <.textarea
            :if={entry.role == :user}
            id={entry.id}
            textarea-value={entry.text}
            textarea-prefix="› "
            disabled
            class={"width-full height-#{entry.height} bg-surface border-none padding-left-0 padding-top-0 padding-bottom-0"}
          />
          <box :if={entry.role != :user} class={entry.class}>{entry.text}</box>
        </box>
      </.scroll>
      <box
        class={"fixed left-0 bottom-0 width-screen height-#{@prompt_height} bg-panel padding-left-2 padding-right-2 padding-top-1"}
      >
        <.textarea
          id="composer"
          textarea-value={@prompt}
          textarea-cursor={@prompt_cursor}
          textarea-placeholder="Ask ExCodexEx to change the codebase"
          textarea-prefix="› "
          textarea-submit-on-enter
          br-change="prompt_changed"
          br-submit="prompt_submitted"
          class={"width-full height-#{@composer_height} bg-panel border-none padding-left-0 padding-top-0 padding-bottom-0"}
        />
      </box>
    </box>
    """
  end

  def handle_event("prompt_changed", %{value: value, cursor: cursor}, term) do
    {:noreply, assign(term, prompt: value, prompt_cursor: cursor)}
  end

  def handle_event("prompt_submitted", %{value: value}, term) do
    term
    |> assign(prompt: value, prompt_cursor: String.length(value))
    |> run_agent()
  end

  def handle_event(_, %{"key" => "F5"}, term), do: run_agent(term)
  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:finish_run, term) do
    {:noreply,
     assign(term,
       status: "complete",
       transcript:
         term.assigns.transcript ++
           [
             {:agent, "Patched the dashboard focus loop and refreshed the tests."},
             {:system, "Verification passed: mix test test/breeze/agent_dashboard_test.exs"}
           ]
     )}
  end

  def handle_info(:resize, term), do: {:noreply, assign(term, screen_height: screen_height(term))}
  def handle_info(_, term), do: {:noreply, term}

  defp run_agent(term) do
    prompt = String.trim(term.assigns.prompt)

    if prompt == "" do
      {:noreply, focus(term, "composer")}
    else
      start_agent_run(term, prompt)
    end
  end

  defp start_agent_run(term, prompt) do
    Process.send_after(self(), :finish_run, 700)

    {:noreply,
     assign(term,
       run_count: term.assigns.run_count + 1,
       prompt: "",
       prompt_cursor: 0,
       status: "running",
       transcript:
         term.assigns.transcript ++
           [
             {:user, prompt},
             {:agent, "I am reading the dashboard, applying a focused patch, and running tests."}
           ]
     )
     |> focus("composer")}
  end

  defp prompt_height(value) do
    value
    |> String.split("\n", trim: false)
    |> length()
    |> Kernel.+(2)
    |> min(8)
    |> max(4)
  end

  defp composer_height(value), do: max(prompt_height(value) - 1, 3)

  defp scrollback_height(screen_height, prompt_height) do
    max(screen_height - prompt_height, 1)
  end

  defp screen_height(%{terminal: %{size: %{height: height}}}) when is_integer(height), do: height
  defp screen_height(_term), do: 24

  defp transcript_entries([]) do
    [%{id: "empty", role: :system, text: "No messages yet.", class: "text-muted", height: 1}]
  end

  defp transcript_entries(messages) do
    messages
    |> Enum.with_index()
    |> Enum.map(fn {{role, text}, index} ->
      %{
        id: "scrollback-#{role}-#{index}",
        role: role,
        text: text,
        class: transcript_class(role),
        height: transcript_textarea_height(text)
      }
    end)
  end

  defp transcript_class(:system), do: "text-muted"
  defp transcript_class(_role), do: "text"

  defp transcript_textarea_height(text) do
    text
    |> String.split("\n", trim: false)
    |> length()
    |> Kernel.+(2)
    |> min(8)
    |> max(3)
  end

  defp initial_transcript do
    [
      {:system, "ExCodexEx is ready in /workspace/app."},
      {:agent, "Type a task and press Enter."}
    ]
  end
end

server_opts = [
  view: ExCodexEx,
  alt_screen: false,
  reload: true,
  theme: Breeze.Theme.builtin(:nebula),
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
]

Breeze.Example.run(
  server_opts,
  keep_alive: :infinity
)
