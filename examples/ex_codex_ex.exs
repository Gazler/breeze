defmodule ExCodexEx do
  use Breeze.View
  import Breeze.Blocks

  alias Breeze.History
  alias Breeze.Theme

  @initial_prompt ""

  def mount(_opts, term) do
    history =
      History.new()
      |> History.append("system-ready", %{
        role: :system,
        text: "ExCodexEx is ready in /workspace/app."
      })
      |> History.append("agent-ready", %{role: :agent, text: "Type a task and press Enter."})

    {:ok,
     term
     |> Breeze.View.put_theme(Theme.builtin(:nebula))
     |> focus("composer")
     |> assign(
       history: history,
       prompt: @initial_prompt,
       prompt_cursor: String.length(@initial_prompt),
       run_count: 0,
       status: "idle"
     )}
  end

  def render(assigns) do
    ~H"""
    <.inline_history id="conversation" history={@history}>
      <:entry>
        <.transcript_entry id={id} entry={entry}/>
      </:entry>
      <:current>
        <box class="width-screen">
          <box class="width-full bg-panel padding-left-2 padding-right-2">
            <.textarea
              id="composer"
              textarea-value={@prompt}
              textarea-cursor={@prompt_cursor}
              textarea-placeholder="Ask ExCodexEx to change the codebase"
              textarea-prefix="› "
              textarea-submit-on-enter
              br-change="prompt_changed"
              br-submit="prompt_submitted"
              class="width-full height-3 bg-panel border-none padding-left-0 padding-top-1 padding-bottom-1"
            />
          </box>
          <box class="width-full height-1 text-muted padding-left-2">
            try: add a retry button to the posting example
          </box>
        </box>
      </:current>
    </.inline_history>
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
     term
     |> append_transcript(:agent, "Patched the dashboard focus loop and refreshed the tests.")
     |> append_transcript(
       :system,
       "Verification passed: mix test test/breeze/agent_dashboard_test.exs"
     )
     |> assign(status: "complete")}
  end

  def handle_info(:resize, term), do: {:noreply, term}
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
     term
     |> append_transcript(:user, prompt)
     |> append_transcript(
       :agent,
       "I am reading the dashboard, applying a focused patch, and running tests."
     )
     |> assign(
       run_count: term.assigns.run_count + 1,
       prompt: "",
       prompt_cursor: 0,
       status: "running"
     )
     |> focus("composer")}
  end

  defp append_transcript(term, role, text) do
    id = "history-#{term.assigns.run_count}-#{role}-#{System.unique_integer([:positive])}"
    entry = %{role: role, text: text}
    history = History.append(term.assigns.history, id, entry)
    assign(term, history: history)
  end

  def transcript_entry(assigns) do
    assigns =
      assign(assigns,
        role: assigns.entry.role,
        text: assigns.entry.text
      )

    ~H"""
    <box class="padding-bottom-1">
      <box :if={@role == :user} class="width-full height-1 bg-terminal">
      </box>
      <.textarea
        :if={@role == :user}
        id={@id}
        textarea-value={@text}
        textarea-prefix="› "
        disabled
        class="width-full height-auto bg border-none padding-left-0 padding-top-1 padding-bottom-1"
      />
      <box :if={@role == :user} class="width-full height-1 bg-terminal">
      </box>
      <box :if={@role == :agent} class="width-full bg-terminal text">{@text}</box>
      <box :if={@role == :system} class="width-full bg-terminal text-muted">{@text}</box>
    </box>
    """
  end
end

server_opts = [
  view: ExCodexEx,
  render_mode: :inline,
  reload: true,
  theme: Breeze.Theme.builtin(:nebula),
  hide_cursor: true,
  global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
]

Breeze.Example.run(
  server_opts,
  keep_alive: :infinity
)
