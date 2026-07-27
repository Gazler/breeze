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
              row_style: row_style(id)
            }
          end),
        message_height: message_height(assigns.message)
      )

    ~H"""
    <box style="width-screen height-screen">
      <box style="bold">Forms Demo</box>
      <box style="text-24">Focused example for horizontal input overflow.</box>
      <box style="text-24">Tab between fields. The website field is fixed to 24 cells.</box>
      <box style="text-24">The message field uses the new textarea block.</box>
      <box style="height-1">
      </box>
      <box style="border-rounded width-72">
        <box style="bold">Example Form</box>
        <box style="height-1">
        </box>
        <box :for={field <- @fields} style={field.row_style}>
          <box style="text-4 bold">{field.label}</box>
          <.input
            id={field.id}
            input-value={field.value}
            br-change={"#{field.id}_changed"}
            style={"width-#{field.width} focus:inverse"}
          >
            {field.value}
          </.input>
          <box style="text-24">width={field.width} value={field.value}</box>
        </box>
        <box style="height-8">
          <box style="text-4 bold">Message</box>
          <.textarea
            id="message"
            textarea-value={@message}
            textarea-placeholder="Add some context"
            br-change="message_changed"
            style={"width-#{@field_width} height-#{@message_height} focus:inverse"}
          />
          <box style="text-24">height={@message_height} value={inspect(@message)}</box>
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

  defp row_style("path"), do: "height-4"
  defp row_style(_id), do: "height-5"

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
