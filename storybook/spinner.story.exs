defmodule Breeze.Storybook.Stories.Blocks.SpinnerStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "spinner",
      title: "Spinner",
      description:
        "Loading animation for asynchronous work that leaves event handling responsive.",
      variants: [
        %{
          id: "dots",
          label: "Dots",
          source: ~S(<.spinner id="spinner" variant="dots" active={@running?} />),
          notes: [
            "The spinner shows a middle dot while idle.",
            "While asynchronous work is active, it cycles through ten dot frames every 80 ms.",
            "The task runs in a separate process, so the event handler returns immediately."
          ]
        },
        %{
          id: "bars",
          label: "Bars",
          source: ~S(<.spinner id="spinner" variant="bars" active={@running?} />),
          notes: [
            "The spinner shows a middle dot while idle.",
            "While asynchronous work is active, it cycles through |, /, -, and \\ every 120 ms.",
            "The task runs in a separate process, so the event handler returns immediately."
          ]
        }
      ],
      notes: [
        "The spinner shows a middle dot while idle.",
        "Set active while asynchronous work is running.",
        "The block supplies its one-cell layout and panel background automatically."
      ],
      source: ~S(<.spinner id="spinner" active={@running?} />)
    }
  end

  def mount(opts, term) do
    {:ok,
     term
     |> assign(
       completed_runs: 0,
       running?: false,
       task_ref: nil,
       task_fun: Keyword.get(opts, :task_fun, fn -> Process.sleep(2_000) end)
     )
     |> focus("storybook-spinner-run")}
  end

  def render(assigns) do
    assigns =
      assign(assigns, spinner_variant: Map.get(assigns, :__breeze_story_variant__, "dots"))

    ~H"""
    <box class="w-full h-full bg-panel">
      <box class="font-bold">Asynchronous task animation</box>
      <box class="w-full text-muted">
        Press Enter to start background work. The preview remains responsive while it runs.
      </box>
      <box class="pt-1 inline w-full">
        <box>Status:</box>
        <box class="w-1">
        </box>
        <.spinner id="storybook-spinner" variant={@spinner_variant} active={@running?}/>
        <box class="w-1">
        </box>
        <box>Completed runs: {@completed_runs}</box>
      </box>
      <box class="pt-1">
        <.button id="storybook-spinner-run" class="w-22">
          {if @running? do
            "Task running…"
          else
            "Run async task"
          end}
        </.button>
      </box>
    </box>
    """
  end

  def handle_event(
        _,
        %{"key" => key},
        %{focused: "storybook-spinner-run"} = term
      )
      when key in ["Enter", " "] do
    if term.assigns.running? do
      {:noreply, term}
    else
      owner = self()
      task_ref = make_ref()
      task_fun = term.assigns.task_fun

      Task.start(fn ->
        task_fun.()
        send(owner, {__MODULE__, :task_complete, task_ref})
      end)

      {:noreply, assign(term, running?: true, task_ref: task_ref)}
    end
  end

  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info({__MODULE__, :task_complete, task_ref}, term) do
    if term.assigns.task_ref == task_ref do
      {:noreply,
       assign(term,
         running?: false,
         task_ref: nil,
         completed_runs: term.assigns.completed_runs + 1
       )}
    else
      {:noreply, term}
    end
  end

  def handle_info(_, term), do: {:noreply, term}
end
