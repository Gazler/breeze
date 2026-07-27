defmodule FormsDemo do
  use Breeze.View
  import Breeze.Blocks

  @fields [
    {"name", "Name"},
    {"email", "Email"},
    {"website", "Website"},
    {"path", "Path"}
  ]

  @website "https://jsonplaceholder.typicode.com/posts/123/comments?include=author,history"
  @path "/Users/demo/projects/breeze_routing/lib/breeze/implicit/input.ex"
  @message "This is a multiline field.\nUse it for longer notes."

  def mount(_opts, term) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(term.terminal)

    {:ok,
     term
     |> focus("name")
     |> assign(
       screen_width: screen_width,
       field_width: default_field_width(screen_width),
       name: "",
       email: "dev@example.com",
       website: @website,
       path: @path,
       message: @message
     )}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        fields:
          Enum.map(@fields, fn {id, label} ->
            value = Map.fetch!(assigns, String.to_atom(id))
            width = field_width(id, assigns.field_width)

            %{
              id: id,
              label: label,
              width: width,
              value: value,
              row_class: row_class(id)
            }
          end),
        message_height: message_height(assigns.message)
      )

    ~H"""
    <box class="w-screen h-screen">
      <box class="font-bold">Forms Demo</box>
      <box class="text-24">Focused example for horizontal input overflow.</box>
      <box class="text-24">Tab between fields. The website field is fixed to 24 cells.</box>
      <box class="text-24">The message field uses the new textarea block.</box>
      <box class="h-1">
      </box>
      <box class="rounded w-72">
        <box class="font-bold">Example Form</box>
        <box class="h-1">
        </box>
        <box :for={field <- @fields} class={field.row_class}>
          <box class="text-4 font-bold">{field.label}</box>
          <.input
            id={field.id}
            input-value={field.value}
            br-change={"#{field.id}_changed"}
            class={"w-#{field.width} focus:inverse"}
          >
            {field.value}
          </.input>
          <box class="text-24">width={field.width} value={field.value}</box>
        </box>
        <box class="h-8">
          <box class="text-4 font-bold">Message</box>
          <.textarea
            id="message"
            textarea-value={@message}
            textarea-placeholder="Add some context"
            br-change="message_changed"
            class={"w-#{@field_width} h-#{@message_height} focus:inverse"}
          />
          <box class="text-24">height={@message_height} value={inspect(@message)}</box>
        </box>
      </box>
    </box>
    """
  end

  def handle_event(event, %{value: value}, term) when is_binary(event) do
    case String.replace_suffix(event, "_changed", "") do
      ^event ->
        {:noreply, term}

      field ->
        {:noreply, assign(term, %{String.to_atom(field) => value})}
    end
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  def handle_info(:resize, term) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(term.terminal)

    {:noreply,
     assign(term, screen_width: screen_width, field_width: default_field_width(screen_width))}
  end

  def handle_info(_, term), do: {:noreply, term}

  defp default_field_width(screen_width), do: min(max(screen_width - 8, 20), 60)

  defp field_width("website", _default_width), do: 24
  defp field_width(_id, default_width), do: default_width

  defp row_class("path"), do: "h-4"
  defp row_class(_id), do: "h-5"

  defp message_height(value) do
    value
    |> String.split("\n", trim: false)
    |> length()
    |> Kernel.+(2)
    |> min(8)
    |> max(4)
  end
end

Breeze.Example.run(
  [
    view: FormsDemo,
    hide_cursor: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
